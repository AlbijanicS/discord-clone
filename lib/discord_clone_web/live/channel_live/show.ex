defmodule DiscordCloneWeb.ChannelLive.Show do
  use DiscordCloneWeb, :live_view

  alias DiscordClone.{Chat, Workspaces}
  alias DiscordCloneWeb.WorkspaceLive.Shell

  @message_page_size 50

  @impl true
  def mount(%{"workspace_id" => workspace_id, "channel_id" => channel_id}, _session, socket) do
    with {:ok, workspace} <-
           Workspaces.fetch_workspace(socket.assigns.current_scope, workspace_id),
         {:ok, channel} <-
           Workspaces.fetch_channel(socket.assigns.current_scope, workspace_id, channel_id),
         {:ok, workspaces} <- Workspaces.list_workspaces(socket.assigns.current_scope),
         {:ok, channels} <- Workspaces.list_channels(socket.assigns.current_scope, workspace_id),
         {:ok, messages} <- Chat.list_recent_messages(socket.assigns.current_scope, channel.id),
         :ok <- subscribe_to_channel_messages(socket, channel.id) do
      socket =
        socket
        |> assign(:selected_workspace, workspace)
        |> assign(:selected_channel, channel)
        |> assign(:workspace_form, workspace_form(socket.assigns.current_scope))
        |> assign(:show_workspace_form?, false)
        |> assign(:channel_form, channel_form(workspace.id))
        |> assign(:show_channel_form?, false)
        |> assign(:message_form, message_form())
        |> assign(:oldest_message, List.first(messages))
        |> assign(:has_older_messages?, length(messages) == @message_page_size)
        |> assign(:workspace_action_menu_id, nil)
        |> assign(:renaming_workspace_id, nil)
        |> assign(:workspace_rename_form, nil)
        |> assign(:channel_action_menu_id, nil)
        |> assign(:renaming_channel_id, nil)
        |> assign(:channel_rename_form, nil)
        |> assign(:context_menu_position, nil)
        |> stream_configure(:messages, dom_id: &"message-#{&1.id}")
        |> stream(:workspaces, workspaces)
        |> stream(:channels, channels)
        |> stream(:messages, messages)

      {:ok, socket}
    else
      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Channel not found or you do not have access.")
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Shell.app
        workspace_stream={@streams.workspaces}
        channel_stream={@streams.channels}
        selected_workspace={@selected_workspace}
        selected_channel={@selected_channel}
        workspace_form={@workspace_form}
        show_workspace_form?={@show_workspace_form?}
        channel_form={@channel_form}
        show_channel_form?={@show_channel_form?}
        workspace_action_menu_id={@workspace_action_menu_id}
        renaming_workspace_id={@renaming_workspace_id}
        workspace_rename_form={@workspace_rename_form}
        channel_action_menu_id={@channel_action_menu_id}
        renaming_channel_id={@renaming_channel_id}
        channel_rename_form={@channel_rename_form}
        context_menu_position={@context_menu_position}
        current_scope={@current_scope}
        main_state={:channel}
      >
        <section
          id="channel-message-surface"
          class="flex h-full min-h-0 flex-col bg-base-100"
          aria-label={"Messages in #{@selected_channel.name}"}
        >
          <div :if={@has_older_messages?} class="border-b border-base-300/60 px-6 py-3 text-center">
            <button
              id="load-older-messages"
              type="button"
              phx-click="load_older_messages"
              class="rounded border border-base-300 bg-base-100 px-4 py-2 text-sm font-semibold text-base-content/70 transition hover:-translate-y-0.5 hover:border-primary/40 hover:text-base-content focus:outline-none focus:ring-2 focus:ring-primary/20"
            >
              Load older
            </button>
          </div>
          <div id="channel-messages" phx-update="stream" class="min-h-0 flex-1 overflow-y-auto p-6">
            <div
              id="channel-empty-state"
              class="hidden only:flex h-full items-center justify-center text-center"
            >
              <div>
                <p class="text-lg font-semibold">No messages yet</p>
                <p class="mt-2 text-sm text-base-content/60">
                  This channel is quiet for now.
                </p>
              </div>
            </div>
            <article
              :for={{dom_id, message} <- @streams.messages}
              id={dom_id}
              class="group flex gap-3 rounded px-2 py-2 transition hover:bg-base-200/70"
            >
              <div class="flex size-9 shrink-0 items-center justify-center rounded bg-primary/10 text-sm font-semibold text-primary">
                {user_initial(message.user)}
              </div>
              <div class="min-w-0 flex-1">
                <div class="flex flex-wrap items-baseline gap-2">
                  <span id={"#{dom_id}-author"} class="font-semibold">
                    {message.user.username}
                  </span>
                  <time
                    datetime={DateTime.to_iso8601(message.inserted_at)}
                    class="text-xs text-base-content/50"
                  >
                    {compact_time(message.inserted_at)}
                  </time>
                </div>
                <p id={"#{dom_id}-content"} class="mt-1 whitespace-pre-wrap break-words text-sm">
                  {message.content}
                </p>
              </div>
            </article>
          </div>
          <div class="border-t border-base-300/70 bg-base-100 px-5 py-4">
            <.form
              for={@message_form}
              id="message-composer-form"
              phx-submit="send_message"
              phx-hook="MessageComposer"
              class="flex items-start gap-3"
            >
              <div class="min-w-0 flex-1">
                <.input
                  field={@message_form[:content]}
                  type="text"
                  placeholder={"Message ##{@selected_channel.name}"}
                  autocomplete="off"
                  class="w-full rounded border border-base-300 bg-base-200/70 px-4 py-3 text-sm text-base-content outline-none transition placeholder:text-base-content/40 focus:border-primary focus:bg-base-100 focus:ring-2 focus:ring-primary/20"
                />
              </div>
              <button
                id="message-composer-submit"
                type="submit"
                class="rounded bg-primary px-4 py-3 text-sm font-semibold text-primary-content transition hover:bg-primary/90 focus:outline-none focus:ring-2 focus:ring-primary/30"
              >
                Send
              </button>
            </.form>
          </div>
        </section>
      </Shell.app>
    </Layouts.app>
    """
  end

  @impl true
  def handle_info({:message_created, message}, socket) do
    {:noreply, stream_insert(socket, :messages, message)}
  end

  @impl true
  def handle_event("show_workspace_form", _params, socket) do
    {:noreply, assign(socket, :show_workspace_form?, true)}
  end

  def handle_event("cancel_workspace_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_workspace_form?, false)
     |> assign(:workspace_form, workspace_form(socket.assigns.current_scope))}
  end

  def handle_event("create_workspace", %{"workspace" => workspace_params}, socket) do
    case Workspaces.create_workspace(socket.assigns.current_scope, workspace_params) do
      {:ok, workspace} ->
        {:noreply, push_navigate(socket, to: ~p"/workspaces/#{workspace.id}")}

      {:error, :invalid_workspace, changeset} ->
        {:noreply,
         socket
         |> assign(:show_workspace_form?, true)
         |> assign(:workspace_form, to_form(changeset, as: :workspace, action: :insert))}
    end
  end

  def handle_event("show_channel_form", _params, socket) do
    {:noreply, assign(socket, :show_channel_form?, true)}
  end

  def handle_event("cancel_channel_form", _params, socket) do
    workspace_id = socket.assigns.selected_workspace.id

    {:noreply,
     socket
     |> assign(:show_channel_form?, false)
     |> assign(:channel_form, channel_form(workspace_id))}
  end

  def handle_event("load_older_messages", _params, %{assigns: %{oldest_message: nil}} = socket) do
    {:noreply, assign(socket, :has_older_messages?, false)}
  end

  def handle_event("load_older_messages", _params, socket) do
    case Chat.list_older_messages(
           socket.assigns.current_scope,
           socket.assigns.selected_channel.id,
           socket.assigns.oldest_message
         ) do
      {:ok, older_messages} ->
        socket =
          older_messages
          |> Enum.reverse()
          |> Enum.reduce(socket, fn message, socket ->
            stream_insert(socket, :messages, message, at: 0)
          end)
          |> assign(:oldest_message, List.first(older_messages) || socket.assigns.oldest_message)
          |> assign(:has_older_messages?, length(older_messages) == @message_page_size)

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Channel not found or you do not have access.")
         |> push_navigate(to: ~p"/workspaces")}
    end
  end

  def handle_event("send_message", %{"message" => message_params}, socket) do
    case Chat.send_message(
           socket.assigns.current_scope,
           socket.assigns.selected_channel.id,
           message_params
         ) do
      {:ok, message} ->
        {:noreply,
         socket
         |> assign(:message_form, message_form())
         |> push_event("clear_message_composer", %{input_id: "message_content"})
         |> stream_insert(:messages, message)}

      {:error, :invalid_message, changeset} ->
        {:noreply,
         assign(socket, :message_form, to_form(changeset, as: :message, action: :insert))}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Channel not found or you do not have access.")
         |> push_navigate(to: ~p"/workspaces")}
    end
  end

  def handle_event("open_workspace_actions", %{"workspace_id" => workspace_id}, socket) do
    {:noreply,
     socket
     |> assign(:workspace_action_menu_id, String.to_integer(workspace_id))
     |> assign(:channel_action_menu_id, nil)
     |> assign(:context_menu_position, nil)}
  end

  def handle_event("begin_workspace_rename", %{"workspace_id" => workspace_id}, socket) do
    with {:ok, workspace} <-
           Workspaces.fetch_workspace(socket.assigns.current_scope, workspace_id),
         {:ok, workspaces} <- Workspaces.list_workspaces(socket.assigns.current_scope) do
      socket =
        socket
        |> assign(:workspace_action_menu_id, nil)
        |> assign(:renaming_workspace_id, workspace.id)
        |> assign(
          :workspace_rename_form,
          workspace_form(socket.assigns.current_scope, %{
            name: workspace.name
          })
        )
        |> stream(:workspaces, workspaces, reset: true)

      {:noreply, socket}
    else
      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Workspace could not be renamed.")
         |> push_navigate(to: ~p"/workspaces")}
    end
  end

  def handle_event(
        "rename_workspace",
        %{"workspace_id" => workspace_id, "workspace" => workspace_params},
        socket
      ) do
    case Workspaces.rename_workspace(socket.assigns.current_scope, workspace_id, workspace_params) do
      {:ok, workspace} ->
        {:ok, workspaces} = Workspaces.list_workspaces(socket.assigns.current_scope)

        selected_workspace =
          if socket.assigns.selected_workspace.id == workspace.id,
            do: workspace,
            else: socket.assigns.selected_workspace

        socket =
          socket
          |> assign(:selected_workspace, selected_workspace)
          |> assign(:renaming_workspace_id, nil)
          |> assign(:workspace_rename_form, nil)
          |> assign(:workspace_action_menu_id, nil)
          |> stream(:workspaces, workspaces, reset: true)

        {:noreply, socket}

      {:error, :invalid_workspace, changeset} ->
        {:noreply,
         socket
         |> assign(:renaming_workspace_id, String.to_integer(workspace_id))
         |> assign(:workspace_rename_form, to_form(changeset, as: :workspace, action: :insert))
         |> assign(:workspace_action_menu_id, nil)
         |> restream_workspaces()}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Workspace could not be renamed.")
         |> push_navigate(to: ~p"/workspaces")}
    end
  end

  def handle_event("delete_workspace", %{"workspace_id" => workspace_id}, socket) do
    case Workspaces.delete_workspace(socket.assigns.current_scope, workspace_id) do
      {:ok, _workspace} ->
        {:noreply, push_navigate(socket, to: ~p"/workspaces")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Workspace could not be deleted.")
         |> push_navigate(to: ~p"/workspaces")}
    end
  end

  def handle_event("leave_workspace", %{"workspace_id" => workspace_id}, socket) do
    case Workspaces.leave_workspace(socket.assigns.current_scope, workspace_id) do
      {:ok, _membership} ->
        {:noreply, push_navigate(socket, to: ~p"/workspaces")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Workspace could not be left.")
         |> push_navigate(to: ~p"/workspaces")}
    end
  end

  def handle_event("open_channel_actions", %{"channel_id" => channel_id}, socket) do
    workspace_id = socket.assigns.selected_workspace.id
    {:ok, channels} = Workspaces.list_channels(socket.assigns.current_scope, workspace_id)

    socket =
      socket
      |> assign(:channel_action_menu_id, String.to_integer(channel_id))
      |> assign(:workspace_action_menu_id, nil)
      |> assign(:context_menu_position, nil)
      |> stream(:channels, channels, reset: true)

    {:noreply, socket}
  end

  def handle_event(
        "open_context_menu",
        %{"type" => "channel", "id" => channel_id, "x" => x, "y" => y},
        socket
      ) do
    workspace_id = socket.assigns.selected_workspace.id
    {:ok, channels} = Workspaces.list_channels(socket.assigns.current_scope, workspace_id)

    socket =
      socket
      |> assign(:channel_action_menu_id, to_integer(channel_id))
      |> assign(:workspace_action_menu_id, nil)
      |> assign(:context_menu_position, %{x: to_integer(x), y: to_integer(y)})
      |> stream(:channels, channels, reset: true)

    {:noreply, socket}
  end

  def handle_event(
        "open_context_menu",
        %{"type" => "workspace", "id" => workspace_id, "x" => x, "y" => y},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:workspace_action_menu_id, to_integer(workspace_id))
     |> assign(:channel_action_menu_id, nil)
     |> assign(:context_menu_position, %{x: to_integer(x), y: to_integer(y)})}
  end

  def handle_event("close_context_menu", _params, socket) do
    workspace_id = socket.assigns.selected_workspace.id

    socket =
      socket
      |> assign(:workspace_action_menu_id, nil)
      |> assign(:channel_action_menu_id, nil)
      |> assign(:context_menu_position, nil)
      |> restream_channels(workspace_id)

    {:noreply, socket}
  end

  def handle_event("begin_channel_rename", %{"channel_id" => channel_id}, socket) do
    workspace_id = socket.assigns.selected_workspace.id

    with {:ok, channel} <-
           Workspaces.fetch_channel(socket.assigns.current_scope, workspace_id, channel_id),
         {:ok, channels} <- Workspaces.list_channels(socket.assigns.current_scope, workspace_id) do
      socket =
        socket
        |> assign(:channel_action_menu_id, nil)
        |> assign(:renaming_channel_id, channel.id)
        |> assign(:channel_rename_form, channel_form(workspace_id, %{name: channel.name}))
        |> stream(:channels, channels, reset: true)

      {:noreply, socket}
    else
      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Channel could not be renamed.")
         |> push_navigate(to: ~p"/workspaces")}
    end
  end

  def handle_event("create_channel", %{"channel" => channel_params}, socket) do
    workspace_id = socket.assigns.selected_workspace.id

    case Workspaces.create_channel(socket.assigns.current_scope, workspace_id, channel_params) do
      {:ok, channel} ->
        {:ok, channels} = Workspaces.list_channels(socket.assigns.current_scope, workspace_id)

        socket =
          socket
          |> assign(:channel_form, channel_form(workspace_id))
          |> assign(:show_channel_form?, false)
          |> stream(:channels, channels, reset: true)

        {:noreply,
         push_navigate(socket, to: ~p"/workspaces/#{workspace_id}/channels/#{channel.id}")}

      {:error, :invalid_channel, changeset} ->
        {:noreply,
         socket
         |> assign(:show_channel_form?, true)
         |> assign(:channel_form, to_form(changeset, as: :channel, action: :insert))}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Channel could not be created.")
         |> push_navigate(to: ~p"/workspaces")}
    end
  end

  def handle_event(
        "rename_channel",
        %{"channel_id" => channel_id, "channel" => channel_params},
        socket
      ) do
    workspace_id = socket.assigns.selected_workspace.id

    case Workspaces.rename_channel(
           socket.assigns.current_scope,
           workspace_id,
           channel_id,
           channel_params
         ) do
      {:ok, channel} ->
        {:ok, channels} = Workspaces.list_channels(socket.assigns.current_scope, workspace_id)

        selected_channel =
          if socket.assigns.selected_channel.id == channel.id,
            do: channel,
            else: socket.assigns.selected_channel

        socket =
          socket
          |> assign(:selected_channel, selected_channel)
          |> assign(:renaming_channel_id, nil)
          |> assign(:channel_rename_form, nil)
          |> assign(:channel_action_menu_id, nil)
          |> stream(:channels, channels, reset: true)

        {:noreply, socket}

      {:error, :invalid_channel, changeset} ->
        {:noreply,
         socket
         |> assign(:renaming_channel_id, String.to_integer(channel_id))
         |> assign(:channel_rename_form, to_form(changeset, as: :channel, action: :insert))
         |> assign(:channel_action_menu_id, nil)
         |> restream_channels(workspace_id)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Channel could not be renamed.")
         |> push_navigate(to: ~p"/workspaces")}
    end
  end

  def handle_event("delete_channel", %{"channel_id" => channel_id}, socket) do
    workspace_id = socket.assigns.selected_workspace.id

    deleting_current_channel? =
      socket.assigns.selected_channel.id == String.to_integer(channel_id)

    case Workspaces.delete_channel(socket.assigns.current_scope, workspace_id, channel_id) do
      {:ok, _channel} when deleting_current_channel? ->
        {:noreply, push_navigate(socket, to: ~p"/workspaces/#{workspace_id}")}

      {:ok, _channel} ->
        {:noreply,
         socket
         |> assign(:channel_action_menu_id, nil)
         |> restream_channels(workspace_id)}

      {:error, :landing_channel_required} ->
        {:noreply, put_flash(socket, :error, "The landing channel cannot be deleted.")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Channel could not be deleted.")
         |> push_navigate(to: ~p"/workspaces")}
    end
  end

  defp channel_form(workspace_id, attrs \\ %{}) do
    workspace_id
    |> Workspaces.change_channel(attrs)
    |> to_form(as: :channel)
  end

  defp workspace_form(scope, attrs \\ %{}) do
    scope
    |> Workspaces.change_workspace(attrs)
    |> to_form(as: :workspace)
  end

  defp message_form(attrs \\ %{}) do
    attrs
    |> Chat.change_message()
    |> to_form(as: :message)
  end

  defp subscribe_to_channel_messages(socket, channel_id) do
    if connected?(socket) do
      Chat.subscribe_to_channel_messages(socket.assigns.current_scope, channel_id)
    else
      :ok
    end
  end

  defp restream_workspaces(socket) do
    {:ok, workspaces} = Workspaces.list_workspaces(socket.assigns.current_scope)
    stream(socket, :workspaces, workspaces, reset: true)
  end

  defp restream_channels(socket, workspace_id) do
    {:ok, channels} = Workspaces.list_channels(socket.assigns.current_scope, workspace_id)
    stream(socket, :channels, channels, reset: true)
  end

  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_binary(value), do: String.to_integer(value)

  defp compact_time(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%H:%M")

  defp user_initial(%{username: username}) when is_binary(username) do
    username
    |> String.first()
    |> String.upcase()
  end
end
