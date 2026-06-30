defmodule DiscordCloneWeb.ChannelLive.Show do
  use DiscordCloneWeb, :live_view

  alias DiscordClone.{Chat, Workspaces}
  alias DiscordClone.Chat.Emoji
  alias DiscordClone.Chat.WorkspacePresence, as: PresenceEvents
  alias DiscordCloneWeb.ChannelLive.MessageRows
  alias DiscordCloneWeb.WorkspaceLive.Presence
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
         {:ok, members} <- Workspaces.list_members(socket.assigns.current_scope, workspace_id),
         :ok <- mark_selected_channel_read(socket, channel.id),
         {:ok, channel_unread_counts} <- load_channel_unread_counts(socket, workspace.id),
         {:ok, messages} <- load_recent_messages(socket, channel.id),
         {:ok, reaction_summaries} <- load_reaction_summaries(socket, messages),
         {:ok, channel_runtime_monitor_ref} <- monitor_channel_runtime(socket, channel.id),
         :ok <- subscribe_to_channel_messages(socket, channel.id),
         :ok <- subscribe_to_workspace_messages(socket, workspace.id),
         :ok <- subscribe_to_channel_typing(socket, channel.id) do
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
        |> assign(:latest_message, List.last(messages))
        |> assign(:has_older_messages?, length(messages) == @message_page_size)
        |> assign(:workspace_action_menu_id, nil)
        |> assign(:renaming_workspace_id, nil)
        |> assign(:workspace_rename_form, nil)
        |> assign(:channel_action_menu_id, nil)
        |> assign(:renaming_channel_id, nil)
        |> assign(:channel_rename_form, nil)
        |> assign(:context_menu_position, nil)
        |> assign(:typing_user_ids, MapSet.new())
        |> assign(:channel_runtime_monitor_ref, channel_runtime_monitor_ref)
        |> assign(:channel_unread_counts, channel_unread_counts)
        |> assign(:reaction_summaries, reaction_summaries)
        |> stream_configure(:messages, dom_id: &"message-#{&1.id}")
        |> stream(:workspaces, workspaces)
        |> stream(:channels, channels)
        |> stream(:messages, MessageRows.annotate(messages))
        |> Presence.prepare_workspace(workspace.id, members)

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
        member_stream={@streams.workspace_members}
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
        online_user_ids={@online_user_ids}
        channel_unread_counts={@channel_unread_counts}
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
          <div
            id="channel-messages"
            phx-update="stream"
            phx-hook="ChannelMessages"
            class="min-h-0 flex-1 scroll-pb-6 overflow-y-auto px-5 py-6"
          >
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
              :for={{dom_id, row} <- @streams.messages}
              id={dom_id}
              data-message-row={row_kind(row)}
              data-hover-surface="message-row"
              class={[
                "group grid grid-cols-[2.75rem_minmax(0,1fr)] gap-3 rounded-md px-3 transition-colors duration-150 hover:bg-base-200/75 focus-within:bg-base-200/75",
                if(row.row_kind == :compact, do: "py-1", else: "py-2.5")
              ]}
            >
              <div
                :if={row.row_kind == :full}
                id={"#{dom_id}-avatar"}
                class="flex size-9 shrink-0 items-center justify-center rounded-md bg-primary/10 text-sm font-semibold text-primary ring-1 ring-primary/10 transition group-hover:bg-primary/15"
                aria-hidden="true"
              >
                {user_initial(row.message.user)}
              </div>
              <div :if={row.row_kind == :compact} id={"#{dom_id}-spacer"} aria-hidden="true"></div>
              <div id={"#{dom_id}-body"} class="min-w-0">
                <div
                  :if={row.row_kind == :full}
                  id={"#{dom_id}-header"}
                  class="flex flex-wrap items-baseline gap-2"
                >
                  <span id={"#{dom_id}-author"} class="font-semibold">
                    {row.message.user.username}
                  </span>
                  <time
                    id={"#{dom_id}-timestamp"}
                    datetime={DateTime.to_iso8601(row.message.inserted_at)}
                    class="text-xs text-base-content/50"
                  >
                    {compact_time(row.message.inserted_at)}
                  </time>
                </div>
                <p
                  id={"#{dom_id}-content"}
                  class={[
                    "whitespace-pre-wrap break-words text-sm leading-6 text-base-content/90 [overflow-wrap:anywhere]",
                    row.row_kind == :full && "mt-1"
                  ]}
                >
                  {Emoji.render_shortcodes(row.message.content)}
                </p>
              </div>
            </article>
          </div>
          <div
            id="channel-typing-indicator"
            class="min-h-6 border-t border-base-300/50 px-6 py-2 text-xs font-medium text-base-content/60"
            aria-live="polite"
          >
            <span
              :for={
                member <- typing_members(@workspace_members, @typing_user_ids, @current_scope.user.id)
              }
              data-typing-user-id={member.user.id}
            >
              {member.user.username} is typing...
            </span>
          </div>
          <div
            id="message-composer-panel"
            class="border-t border-base-300/70 bg-base-100/95 px-5 pb-5 pt-3"
          >
            <.form
              for={@message_form}
              id="message-composer-form"
              phx-change="message_typing"
              phx-submit="send_message"
              phx-hook="MessageComposer"
              class="flex items-start gap-3"
            >
              <div
                id="message-composer-shell"
                class="min-w-0 flex-1 rounded-lg border border-base-300/80 bg-base-200/45 px-3 py-2 shadow-sm transition focus-within:border-primary/45 focus-within:bg-base-100 focus-within:ring-2 focus-within:ring-primary/15"
              >
                <.input
                  field={@message_form[:content]}
                  type="text"
                  placeholder={"Message ##{@selected_channel.name}"}
                  autocomplete="off"
                  phx-throttle="3000"
                  class="w-full rounded-md border border-transparent bg-transparent px-1 py-2.5 text-sm text-base-content outline-none transition placeholder:text-base-content/40 focus:border-transparent focus:ring-0"
                />
              </div>
              <button
                id="message-composer-submit"
                type="submit"
                class="rounded-md bg-primary px-4 py-3 text-sm font-semibold text-primary-content shadow-sm transition hover:-translate-y-0.5 hover:bg-primary/90 focus:outline-none focus:ring-2 focus:ring-primary/30"
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
    row = MessageRows.annotate_next(socket.assigns.latest_message, message)

    {:noreply,
     socket
     |> assign(:latest_message, message)
     |> stream_insert(:messages, row)
     |> push_event("scroll_channel_messages_to_bottom", %{container_id: "channel-messages"})}
  end

  def handle_info({:workspace_message_created, %{workspace_id: workspace_id} = payload}, socket) do
    if socket.assigns.selected_workspace.id == workspace_id do
      {:noreply, refresh_channel_unread_counts_for_message(socket, payload)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:typing_started, %{channel_id: channel_id, user_id: user_id}}, socket) do
    if socket.assigns.selected_channel.id == channel_id do
      typing_user_ids = MapSet.put(socket.assigns.typing_user_ids, user_id)

      {:noreply,
       socket
       |> assign(:typing_user_ids, typing_user_ids)
       |> monitor_current_channel_runtime()}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:typing_stopped, %{channel_id: channel_id, user_id: user_id}}, socket) do
    if socket.assigns.selected_channel.id == channel_id do
      typing_user_ids = MapSet.delete(socket.assigns.typing_user_ids, user_id)

      {:noreply, assign(socket, :typing_user_ids, typing_user_ids)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {:DOWN, monitor_ref, :process, _pid, _reason},
        %{assigns: %{channel_runtime_monitor_ref: monitor_ref}} = socket
      ) do
    {:noreply,
     socket
     |> assign(:typing_user_ids, MapSet.new())
     |> assign(:channel_runtime_monitor_ref, nil)}
  end

  def handle_info(event, socket) do
    case PresenceEvents.to_presence_event(event) do
      {:ok, :user_joined, payload} -> {:noreply, Presence.user_joined(socket, payload)}
      {:ok, :user_left, payload} -> {:noreply, Presence.user_left(socket, payload)}
      :error -> {:noreply, socket}
    end
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
          |> prepend_older_message_rows(socket)
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
        row = MessageRows.annotate_next(socket.assigns.latest_message, message)

        {:noreply,
         socket
         |> assign(:message_form, message_form())
         |> assign(:latest_message, message)
         |> push_event("clear_message_composer", %{input_id: "message_content"})
         |> push_event("scroll_channel_messages_to_bottom", %{container_id: "channel-messages"})
         |> stream_insert(:messages, row)}

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

  def handle_event("message_typing", %{"message" => %{"content" => content}}, socket)
      when is_binary(content) do
    if String.trim(content) == "" do
      stop_typing(socket)
    else
      start_typing(socket)
    end
  end

  def handle_event("message_typing", _params, socket) do
    start_typing(socket)
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
      |> refresh_channel_sidebar(workspace_id, channels)

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
      |> refresh_channel_sidebar(workspace_id, channels)

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
      |> refresh_channel_sidebar(workspace_id)

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
        |> refresh_channel_sidebar(workspace_id, channels)

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
          |> refresh_channel_sidebar(workspace_id, channels)

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
          |> refresh_channel_sidebar(workspace_id, channels)

        {:noreply, socket}

      {:error, :invalid_channel, changeset} ->
        {:noreply,
         socket
         |> assign(:renaming_channel_id, String.to_integer(channel_id))
         |> assign(:channel_rename_form, to_form(changeset, as: :channel, action: :insert))
         |> assign(:channel_action_menu_id, nil)
         |> refresh_channel_sidebar(workspace_id)}

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
        {:ok, channels} = Workspaces.list_channels(socket.assigns.current_scope, workspace_id)

        {:noreply,
         socket
         |> assign(:channel_action_menu_id, nil)
         |> refresh_channel_sidebar(workspace_id, channels)}

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

  defp prepend_older_message_rows([], socket), do: socket

  defp prepend_older_message_rows(older_messages, socket) do
    boundary_row =
      MessageRows.annotate_next(List.last(older_messages), socket.assigns.oldest_message)

    older_messages
    |> MessageRows.annotate()
    |> Enum.reverse()
    |> Enum.reduce(socket, fn row, socket ->
      stream_insert(socket, :messages, row, at: 0)
    end)
    |> stream_insert(:messages, boundary_row)
  end

  defp subscribe_to_channel_messages(socket, channel_id) do
    if connected?(socket) do
      Chat.subscribe_to_channel_messages(socket.assigns.current_scope, channel_id)
    else
      :ok
    end
  end

  defp subscribe_to_workspace_messages(socket, workspace_id) do
    if connected?(socket) do
      Chat.subscribe_to_workspace_messages(socket.assigns.current_scope, workspace_id)
    else
      :ok
    end
  end

  defp subscribe_to_channel_typing(_socket, _channel_id), do: :ok

  defp monitor_channel_runtime(socket, channel_id) do
    if connected?(socket) do
      case Chat.ensure_channel_runtime(socket.assigns.current_scope, channel_id) do
        {:ok, pid} -> {:ok, Process.monitor(pid)}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, nil}
    end
  end

  defp monitor_current_channel_runtime(
         %{assigns: %{channel_runtime_monitor_ref: monitor_ref}} = socket
       )
       when is_reference(monitor_ref) do
    socket
  end

  defp monitor_current_channel_runtime(socket) do
    case Chat.ensure_channel_runtime(
           socket.assigns.current_scope,
           socket.assigns.selected_channel.id
         ) do
      {:ok, pid} -> assign(socket, :channel_runtime_monitor_ref, Process.monitor(pid))
      {:error, _reason} -> socket
    end
  end

  defp load_recent_messages(socket, channel_id) do
    if connected?(socket) do
      Chat.list_recent_messages(socket.assigns.current_scope, channel_id)
    else
      {:ok, []}
    end
  end

  defp load_reaction_summaries(socket, messages) do
    if connected?(socket) do
      message_ids = Enum.map(messages, & &1.id)

      Chat.list_reaction_summaries(socket.assigns.current_scope, message_ids)
    else
      {:ok, %{}}
    end
  end

  defp mark_selected_channel_read(socket, channel_id) do
    if connected?(socket) do
      Chat.mark_channel_read(socket.assigns.current_scope, channel_id)
    else
      :ok
    end
  end

  defp load_channel_unread_counts(socket, workspace_id) do
    if connected?(socket) do
      Chat.list_unread_counts(socket.assigns.current_scope, workspace_id)
    else
      {:ok, %{}}
    end
  end

  defp refresh_channel_unread_counts_for_message(socket, %{channel_id: channel_id})
       when channel_id == socket.assigns.selected_channel.id do
    with :ok <- Chat.mark_channel_read(socket.assigns.current_scope, channel_id) do
      refresh_channel_sidebar(socket, socket.assigns.selected_workspace.id)
    else
      {:error, _reason} -> socket
    end
  end

  defp refresh_channel_unread_counts_for_message(socket, _payload) do
    refresh_channel_sidebar(socket, socket.assigns.selected_workspace.id)
  end

  defp start_typing(socket) do
    case Chat.user_started_typing(
           socket.assigns.current_scope,
           socket.assigns.selected_channel.id
         ) do
      :ok ->
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Channel not found or you do not have access.")
         |> push_navigate(to: ~p"/workspaces")}
    end
  end

  defp stop_typing(socket) do
    case Chat.user_stopped_typing(
           socket.assigns.current_scope,
           socket.assigns.selected_channel.id
         ) do
      :ok ->
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Channel not found or you do not have access.")
         |> push_navigate(to: ~p"/workspaces")}
    end
  end

  defp restream_workspaces(socket) do
    {:ok, workspaces} = Workspaces.list_workspaces(socket.assigns.current_scope)
    stream(socket, :workspaces, workspaces, reset: true)
  end

  defp refresh_channel_sidebar(socket, workspace_id) do
    {:ok, channels} = Workspaces.list_channels(socket.assigns.current_scope, workspace_id)
    refresh_channel_sidebar(socket, workspace_id, channels)
  end

  defp refresh_channel_sidebar(socket, workspace_id, channels) do
    socket =
      case Chat.list_unread_counts(socket.assigns.current_scope, workspace_id) do
        {:ok, channel_unread_counts} ->
          assign(socket, :channel_unread_counts, channel_unread_counts)

        {:error, _reason} ->
          socket
      end

    stream(socket, :channels, channels, reset: true)
  end

  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_binary(value), do: String.to_integer(value)

  defp compact_time(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%H:%M")

  defp row_kind(%{row_kind: row_kind}), do: Atom.to_string(row_kind)

  defp user_initial(%{username: username}) when is_binary(username) do
    username
    |> String.first()
    |> String.upcase()
  end

  defp typing_members(members, typing_user_ids, current_user_id) do
    members
    |> Enum.filter(&MapSet.member?(typing_user_ids, &1.user.id))
    |> Enum.reject(&(&1.user.id == current_user_id))
  end
end
