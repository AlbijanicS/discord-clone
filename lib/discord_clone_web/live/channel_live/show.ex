defmodule DiscordCloneWeb.ChannelLive.Show do
  use DiscordCloneWeb, :live_view

  alias DiscordClone.{Chat, Workspaces}
  alias DiscordClone.Chat.Emoji
  alias DiscordClone.Chat.WorkspacePresence, as: PresenceEvents
  alias DiscordCloneWeb.ChannelLive.MessageRows
  alias DiscordCloneWeb.WorkspaceLive.Presence
  alias DiscordCloneWeb.WorkspaceLive.Shell

  @reaction_palette [
    {"👍", "React with 👍 to message"},
    {"❤️", "React with ❤️ to message"},
    {"😂", "React with 😂 to message"},
    {"🎉", "React with 🎉 to message"},
    {"👀", "React with 👀 to message"}
  ]

  @rendered_message_limit 300

  @impl true
  def mount(%{"workspace_id" => workspace_id, "channel_id" => channel_id}, _session, socket) do
    with {:ok, workspace} <-
           Workspaces.fetch_workspace(socket.assigns.current_scope, workspace_id),
         {:ok, channel} <-
           Workspaces.fetch_channel(socket.assigns.current_scope, workspace_id, channel_id),
         {:ok, workspaces} <- Workspaces.list_workspaces(socket.assigns.current_scope),
         {:ok, channels} <- Workspaces.list_channels(socket.assigns.current_scope, workspace_id),
         {:ok, members} <- Workspaces.list_members(socket.assigns.current_scope, workspace_id),
         {:ok, message_window} <- open_channel_message_window(socket, channel.id),
         {:ok, channel_unread_counts} <- load_channel_unread_counts(socket, workspace.id),
         {:ok, selected_channel_read_summary} <-
           load_channel_read_summary(socket, workspace.id, channel.id),
         messages = message_window.messages,
         {:ok, reaction_summaries} <- load_reaction_summaries(socket, messages),
         {:ok, channel_runtime_monitor_ref} <- monitor_channel_runtime(socket, channel.id),
         :ok <- subscribe_to_channel_messages(socket, channel.id),
         :ok <- subscribe_to_channel_reactions(socket, channel.id),
         :ok <- subscribe_to_workspace_messages(socket, workspace.id),
         :ok <- subscribe_to_channel_typing(socket, channel.id) do
      message_rows = MessageRows.annotate(messages)

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
        |> assign(:message_window_meta, message_window.meta)
        |> assign(:has_older_messages?, message_window.meta.has_older?)
        |> assign(:loading_older_messages?, false)
        |> assign(:loading_newer_messages?, false)
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
        |> assign(:selected_channel_read_summary, selected_channel_read_summary)
        |> assign(:unread_divider_seq, unread_divider_seq(selected_channel_read_summary))
        |> assign(:reaction_summaries, reaction_summaries)
        |> assign(:message_rows_by_id, message_rows_by_id(message_rows))
        |> stream_configure(:messages, dom_id: &"message-#{&1.id}")
        |> stream(:workspaces, workspaces)
        |> stream(:channels, channels)
        |> stream(:messages, message_rows)
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
          <div
            :if={
              sticky_unread_actions?(
                @channel_unread_counts,
                @selected_channel,
                @unread_divider_seq,
                @message_rows_by_id
              )
            }
            id="selected-channel-unread-actions"
            class="flex flex-wrap items-center justify-center gap-2 border-b border-base-300/60 bg-base-200/55 px-5 py-2.5 text-sm"
          >
            <button
              id="jump-to-oldest-unread"
              type="button"
              phx-click="jump_to_oldest_unread"
              class="rounded bg-base-100 px-3 py-1.5 font-semibold text-base-content/80 shadow-sm ring-1 ring-base-300 transition hover:-translate-y-0.5 hover:text-base-content focus:outline-none focus:ring-2 focus:ring-primary/25"
            >
              Jump to oldest unread
            </button>
            <button
              id="mark-channel-read"
              type="button"
              phx-click="mark_channel_read"
              class="rounded bg-base-100 px-3 py-1.5 font-semibold text-base-content/80 shadow-sm ring-1 ring-base-300 transition hover:-translate-y-0.5 hover:text-base-content focus:outline-none focus:ring-2 focus:ring-primary/25"
            >
              Mark as read
            </button>
            <button
              id="skip-to-latest"
              type="button"
              phx-click="skip_to_latest"
              aria-label="Skip to latest and mark unread messages read"
              class="rounded bg-primary px-3 py-1.5 font-semibold text-primary-content shadow-sm transition hover:-translate-y-0.5 hover:bg-primary/90 focus:outline-none focus:ring-2 focus:ring-primary/25"
            >
              Skip to latest
            </button>
          </div>
          <div
            :if={
              skip_to_latest_action?(@message_window_meta) and
                not sticky_unread_actions?(
                  @channel_unread_counts,
                  @selected_channel,
                  @unread_divider_seq,
                  @message_rows_by_id
                )
            }
            id="selected-channel-latest-actions"
            class="flex justify-center border-b border-base-300/60 bg-base-100/90 px-5 py-2.5 text-sm"
          >
            <button
              id="skip-to-latest"
              type="button"
              phx-click="skip_to_latest"
              aria-label="Skip to latest and mark unread messages read"
              class="rounded bg-primary px-3 py-1.5 font-semibold text-primary-content shadow-sm transition hover:-translate-y-0.5 hover:bg-primary/90 focus:outline-none focus:ring-2 focus:ring-primary/25"
            >
              Skip to latest
            </button>
          </div>
          <div
            id="channel-messages"
            phx-update="stream"
            phx-hook="ChannelMessages"
            data-has-older-messages={to_string(@has_older_messages?)}
            data-has-newer-messages={to_string(@message_window_meta.has_newer?)}
            data-loading-older={to_string(@loading_older_messages?)}
            data-loading-newer={to_string(@loading_newer_messages?)}
            class="min-h-0 flex-1 scroll-pb-6 overflow-y-auto px-5 py-6"
          >
            <div
              id="older-messages-loading"
              data-loading={to_string(@loading_older_messages?)}
              aria-live="polite"
              class={[
                "py-2 text-center text-xs font-semibold uppercase tracking-wide text-base-content/45",
                !@loading_older_messages? && "sr-only"
              ]}
            >
              Loading older messages
            </div>
            <div
              :if={is_nil(@oldest_message)}
              id="channel-empty-state"
              class="flex h-full items-center justify-center text-center"
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
              data-message-id={row.message.id}
              data-message-seq={row.message.seq}
              data-visible-read-observe="true"
              data-hover-surface="message-row"
              class={[
                "group relative grid w-full grid-cols-[2.75rem_minmax(0,1fr)] gap-x-3 rounded-md px-3 transition-colors duration-150 hover:bg-base-200/70 focus-within:bg-base-200/70",
                if(row.row_kind == :compact, do: "py-0.5", else: "py-1.5")
              ]}
            >
              <div
                :if={row.message.seq == @unread_divider_seq}
                id="channel-unread-divider"
                data-unread-divider-seq={row.message.seq}
                class="col-span-2 mb-2 flex items-center gap-3 text-xs font-semibold uppercase tracking-wide text-primary"
              >
                <span class="h-px flex-1 bg-primary/30"></span>
                <span
                  id="channel-unread-divider-marker"
                  data-message-id={row.message.id}
                  class="rounded bg-primary/10 px-2 py-1 ring-1 ring-primary/20"
                >
                  New messages
                </span>
                <span class="h-px flex-1 bg-primary/30"></span>
              </div>
              <div
                :if={row.row_kind == :full}
                id={"#{dom_id}-avatar"}
                class="mt-0.5 flex size-10 shrink-0 items-center justify-center rounded-lg bg-primary/15 text-sm font-semibold text-primary ring-1 ring-primary/20 transition group-hover:bg-primary/20"
                aria-hidden="true"
              >
                {user_initial(row.message.user)}
              </div>
              <div :if={row.row_kind == :compact} id={"#{dom_id}-spacer"} aria-hidden="true"></div>
              <div id={"#{dom_id}-body"} class="relative min-w-0 pr-40">
                <div
                  id={"#{dom_id}-reaction-palette"}
                  class={[
                    "pointer-events-none absolute right-0 z-10 flex items-center gap-0.5 rounded-md bg-base-100/95 p-0.5 opacity-0 shadow-lg shadow-base-300/20 ring-1 ring-base-content/10 transition duration-150 group-hover:pointer-events-auto group-hover:opacity-100",
                    if(row.row_kind == :compact, do: "top-0", else: "top-0.5")
                  ]}
                  aria-label="Reaction palette"
                >
                  <button
                    :for={{{emoji, label}, index} <- Enum.with_index(reaction_palette())}
                    id={reaction_option_id(row.message.id, index)}
                    type="button"
                    phx-click="toggle_reaction"
                    phx-value-message-id={row.message.id}
                    phx-value-emoji={emoji}
                    class="flex size-7 items-center justify-center rounded text-sm transition hover:bg-base-200 focus:outline-none focus:ring-2 focus:ring-primary/25"
                    aria-label={label}
                    title={label}
                  >
                    <span aria-hidden="true">{emoji}</span>
                  </button>
                </div>
                <div
                  :if={row.row_kind == :full}
                  id={"#{dom_id}-header"}
                  class="flex min-h-5 flex-wrap items-baseline gap-2 pr-40"
                >
                  <span
                    id={"#{dom_id}-author"}
                    class="text-sm font-semibold leading-5 text-base-content"
                  >
                    {row.message.user.username}
                  </span>
                  <time
                    id={"#{dom_id}-timestamp"}
                    datetime={DateTime.to_iso8601(row.message.inserted_at)}
                    class="text-xs font-medium leading-5 text-base-content/50"
                  >
                    {compact_time(row.message.inserted_at)}
                  </time>
                </div>
                {message_content(row, dom_id)}
                <%= if reaction_summaries_for(@reaction_summaries, row.message.id) != [] do %>
                  <div
                    id={"#{dom_id}-reactions"}
                    class="mt-1.5 flex flex-wrap items-center gap-1.5"
                    aria-label="Message reactions"
                  >
                    <span
                      :for={
                        {summary, index} <-
                          Enum.with_index(reaction_summaries_for(@reaction_summaries, row.message.id))
                      }
                      id={reaction_pill_id(row.message.id, index)}
                      data-current-user-reacted={to_string(summary.reacted?)}
                      class={reaction_pill_class(summary)}
                      aria-label={reaction_pill_label(summary)}
                    >
                      <span aria-hidden="true">{summary.emoji}</span>
                      <span>{summary.count}</span>
                    </span>
                  </div>
                <% end %>
              </div>
            </article>
            <div
              id="newer-messages-loading"
              data-loading={to_string(@loading_newer_messages?)}
              aria-live="polite"
              class={[
                "py-2 text-center text-xs font-semibold uppercase tracking-wide text-base-content/45",
                !@loading_newer_messages? && "sr-only"
              ]}
            >
              Loading newer messages
            </div>
          </div>
          <div
            id="channel-typing-indicator"
            class="min-h-6 px-6 py-2 text-xs font-medium text-base-content/60 shadow-[0_-1px_0_rgb(255_255_255/0.035)]"
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
            class="bg-base-100/95 px-5 pb-4 pt-3 shadow-[0_-12px_28px_rgb(0_0_0/0.10),0_-1px_0_rgb(255_255_255/0.04)]"
          >
            <.form
              for={@message_form}
              id="message-composer-form"
              phx-change="message_typing"
              phx-submit="send_message"
              phx-hook="MessageComposer"
              class="flex items-end"
            >
              <div
                id="message-composer-shell"
                class="min-w-0 flex-1 rounded-lg bg-base-200/80 px-3 py-2 shadow-inner shadow-base-300/30 ring-1 ring-base-300/60 transition focus-within:bg-base-200 focus-within:ring-primary/35"
              >
                <.input
                  field={@message_form[:content]}
                  type="text"
                  placeholder={"Message ##{@selected_channel.name}"}
                  autocomplete="off"
                  phx-throttle="3000"
                  class="w-full appearance-none border-0 bg-transparent px-1 py-2 text-sm leading-5 text-base-content outline-none ring-0 transition placeholder:text-base-content/40 focus:border-0 focus:outline-none focus:ring-0"
                  error_class="input-error border-0 ring-0"
                />
              </div>
            </.form>
          </div>
        </section>
      </Shell.app>
    </Layouts.app>
    """
  end

  @impl true
  def handle_info({:message_created, message}, socket) do
    if append_selected_channel_message?(socket) do
      row = MessageRows.annotate_next(socket.assigns.latest_message, message)

      {:noreply,
       socket
       |> assign(:latest_message, message)
       |> assign(
         :message_window_meta,
         latest_window_meta(socket.assigns.message_window_meta, message)
       )
       |> put_message_row(row)
       |> stream_insert(:messages, row)
       |> trim_rendered_message_window(:older)
       |> push_event("scroll_channel_messages_to_bottom", %{container_id: "channel-messages"})}
    else
      {:noreply,
       assign(
         socket,
         :message_window_meta,
         newer_available_meta(socket.assigns.message_window_meta, message)
       )}
    end
  end

  def handle_info({:workspace_message_created, %{workspace_id: workspace_id} = payload}, socket) do
    if socket.assigns.selected_workspace.id == workspace_id do
      {:noreply, refresh_channel_unread_counts_for_message(socket, payload)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:reaction_changed, %{message_id: message_id}}, socket) do
    {:noreply, refresh_reaction_summary(socket, message_id)}
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

  def handle_event(
        "load_older_messages",
        _params,
        %{assigns: %{loading_older_messages?: true}} = socket
      ) do
    {:noreply, socket}
  end

  def handle_event("load_older_messages", _params, %{assigns: %{oldest_message: nil}} = socket) do
    {:noreply,
     socket
     |> assign(:has_older_messages?, false)
     |> assign(:loading_older_messages?, false)}
  end

  def handle_event("load_older_messages", params, socket) do
    case Chat.load_older_message_window(
           socket.assigns.current_scope,
           socket.assigns.selected_channel.id,
           socket.assigns.oldest_message.seq
         ) do
      {:ok, %{messages: older_messages, meta: meta}} ->
        socket =
          older_messages
          |> prepend_older_message_rows(socket)
          |> assign(:oldest_message, List.first(older_messages) || socket.assigns.oldest_message)
          |> assign(:loading_older_messages?, false)
          |> assign(
            :message_window_meta,
            merge_older_window_meta(socket.assigns.message_window_meta, meta)
          )
          |> assign(:has_older_messages?, meta.has_older?)
          |> trim_rendered_message_window(:newer)
          |> preserve_scroll_after_older_load(params)

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Channel not found or you do not have access.")
         |> push_navigate(to: ~p"/workspaces")}
    end
  end

  def handle_event(
        "load_newer_messages",
        _params,
        %{assigns: %{loading_newer_messages?: true}} = socket
      ) do
    {:noreply, socket}
  end

  def handle_event(
        "load_newer_messages",
        _params,
        %{assigns: %{latest_message: nil}} = socket
      ) do
    {:noreply, assign(socket, :loading_newer_messages?, false)}
  end

  def handle_event("load_newer_messages", _params, socket) do
    if socket.assigns.message_window_meta.has_newer? do
      case Chat.load_newer_message_window(
             socket.assigns.current_scope,
             socket.assigns.selected_channel.id,
             socket.assigns.latest_message.seq
           ) do
        {:ok, %{messages: newer_messages, meta: meta}} ->
          socket =
            newer_messages
            |> append_newer_message_rows(socket)
            |> assign(:latest_message, List.last(newer_messages) || socket.assigns.latest_message)
            |> assign(:loading_newer_messages?, false)
            |> assign(
              :message_window_meta,
              merge_newer_window_meta(socket.assigns.message_window_meta, meta)
            )
            |> trim_rendered_message_window(:older)

          {:noreply, socket}

        {:error, _reason} ->
          {:noreply,
           socket
           |> put_flash(:error, "Channel not found or you do not have access.")
           |> push_navigate(to: ~p"/workspaces")}
      end
    else
      {:noreply, assign(socket, :loading_newer_messages?, false)}
    end
  end

  def handle_event("jump_to_oldest_unread", _params, socket) do
    case Chat.jump_to_oldest_unread(
           socket.assigns.current_scope,
           socket.assigns.selected_channel.id
         ) do
      {:ok, message_window} ->
        {:noreply, replace_message_window(socket, message_window)}

      {:error, :no_unread_messages} ->
        {:noreply, refresh_channel_sidebar(socket, socket.assigns.selected_workspace.id)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Channel not found or you do not have access.")
         |> push_navigate(to: ~p"/workspaces")}
    end
  end

  def handle_event("mark_channel_read", _params, socket) do
    case Chat.mark_channel_read(socket.assigns.current_scope, socket.assigns.selected_channel.id) do
      :ok ->
        {:noreply,
         socket
         |> clear_selected_channel_unread_ui()
         |> refresh_channel_sidebar(socket.assigns.selected_workspace.id)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Channel not found or you do not have access.")
         |> push_navigate(to: ~p"/workspaces")}
    end
  end

  def handle_event("mark_sidebar_channel_read", %{"channel_id" => channel_id}, socket) do
    channel_id = to_integer(channel_id)

    case Chat.mark_channel_read(socket.assigns.current_scope, channel_id) do
      :ok ->
        socket =
          socket
          |> assign(:channel_action_menu_id, nil)
          |> assign(:context_menu_position, nil)
          |> maybe_clear_selected_channel_unread_ui(channel_id)
          |> refresh_channel_sidebar(socket.assigns.selected_workspace.id)

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Channel not found or you do not have access.")
         |> push_navigate(to: ~p"/workspaces")}
    end
  end

  def handle_event("skip_to_latest", _params, socket) do
    case Chat.jump_to_latest(socket.assigns.current_scope, socket.assigns.selected_channel.id) do
      {:ok, message_window} ->
        socket =
          socket
          |> replace_message_window(message_window)
          |> refresh_channel_sidebar(socket.assigns.selected_workspace.id)
          |> push_event("scroll_channel_messages_to_bottom", %{container_id: "channel-messages"})

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Channel not found or you do not have access.")
         |> push_navigate(to: ~p"/workspaces")}
    end
  end

  def handle_event("visible_read_observed", %{"ranges" => ranges}, socket) when is_list(ranges) do
    ranges = parse_visible_read_ranges(ranges)

    socket =
      if valid_visible_read_ranges?(socket, ranges) do
        apply_visible_read_ranges(socket, ranges)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("visible_read_observed", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("scroll_anchor_observed", %{"seq" => seq}, socket) do
    socket =
      with {:ok, seq} <- parse_integer(seq),
           true <- rendered_message_seq?(socket, seq),
           {:ok, _read_state} <-
             Chat.persist_channel_anchor(
               socket.assigns.current_scope,
               socket.assigns.selected_channel.id,
               seq
             ) do
        socket
      else
        _ignored -> socket
      end

    {:noreply, socket}
  end

  def handle_event("scroll_anchor_observed", _params, socket) do
    {:noreply, socket}
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
         |> put_message_row(row)
         |> push_event("clear_message_composer", %{input_id: "message_content"})
         |> push_event("scroll_channel_messages_to_bottom", %{container_id: "channel-messages"})
         |> stream_insert(:messages, row)
         |> trim_rendered_message_window(:older)}

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

  def handle_event("toggle_reaction", %{"message-id" => message_id, "emoji" => emoji}, socket) do
    message_id = to_integer(message_id)

    case Chat.toggle_reaction(socket.assigns.current_scope, message_id, emoji) do
      {:ok, _reaction_or_deleted_reaction} ->
        {:noreply, refresh_reaction_summary(socket, message_id)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Reaction could not be saved.")}

      {:error, _reason, _detail} ->
        {:noreply, put_flash(socket, :error, "Reaction could not be saved.")}
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

  defp reaction_summaries_for(reaction_summaries, message_id) do
    Map.get(reaction_summaries, message_id, [])
  end

  defp refresh_reaction_summary(socket, message_id) do
    socket =
      case Chat.list_reaction_summaries(socket.assigns.current_scope, [message_id]) do
        {:ok, %{^message_id => summaries}} ->
          reaction_summaries =
            Map.put(socket.assigns.reaction_summaries, message_id, summaries)

          assign(socket, :reaction_summaries, reaction_summaries)

        {:ok, %{}} ->
          assign(
            socket,
            :reaction_summaries,
            Map.delete(socket.assigns.reaction_summaries, message_id)
          )

        {:error, _reason} ->
          put_flash(socket, :error, "Reaction summary could not be refreshed.")
      end

    restream_message_row(socket, message_id)
  end

  defp reaction_palette, do: @reaction_palette

  defp reaction_option_id(message_id, index), do: "message-#{message_id}-reaction-option-#{index}"

  defp reaction_pill_id(message_id, index), do: "message-#{message_id}-reaction-#{index}"

  defp reaction_pill_label(%{emoji: emoji, count: count, reacted?: reacted?}) do
    reacted_label = if reacted?, do: "you reacted", else: "you have not reacted"

    "#{emoji} reaction, #{count} #{reaction_count_label(count)}, #{reacted_label}"
  end

  defp reaction_count_label(1), do: "reaction"
  defp reaction_count_label(_count), do: "reactions"

  defp reaction_pill_class(%{reacted?: true}) do
    "inline-flex items-center gap-1 rounded-full border border-primary/35 bg-primary/10 px-2 py-0.5 text-xs font-semibold text-primary shadow-sm transition"
  end

  defp reaction_pill_class(_summary) do
    "inline-flex items-center gap-1 rounded-full border border-base-300 bg-base-200/70 px-2 py-0.5 text-xs font-semibold text-base-content/75 transition"
  end

  defp message_content(row, dom_id) do
    {:safe, attrs} =
      Phoenix.HTML.attributes_escape(
        id: "#{dom_id}-content",
        class: [
          "whitespace-pre-wrap break-words text-sm leading-5 text-base-content/90 [overflow-wrap:anywhere]",
          row.row_kind == :full && "mt-0.5"
        ]
      )

    {:safe, content} =
      row.message.content
      |> Emoji.render_shortcodes()
      |> Phoenix.HTML.html_escape()

    {:safe, ["<p", attrs, ">", content, "</p>"]}
  end

  defp prepend_older_message_rows([], socket), do: socket

  defp prepend_older_message_rows(older_messages, socket) do
    boundary_row =
      MessageRows.annotate_next(List.last(older_messages), socket.assigns.oldest_message)

    older_rows = MessageRows.annotate(older_messages)

    older_rows
    |> Enum.reverse()
    |> Enum.reduce(put_message_rows(socket, [boundary_row | older_rows]), fn row, socket ->
      stream_insert(socket, :messages, row, at: 0)
    end)
    |> stream_insert(:messages, boundary_row)
  end

  defp append_newer_message_rows([], socket), do: socket

  defp append_newer_message_rows(newer_messages, socket) do
    {newer_rows, _previous_message} =
      Enum.map_reduce(newer_messages, socket.assigns.latest_message, fn message,
                                                                        previous_message ->
        {MessageRows.annotate_next(previous_message, message), message}
      end)

    newer_rows
    |> Enum.reduce(put_message_rows(socket, newer_rows), fn row, socket ->
      stream_insert(socket, :messages, row)
    end)
  end

  defp trim_rendered_message_window(socket, trim_side) do
    rows = visible_message_rows(socket)
    overage = length(rows) - @rendered_message_limit

    if overage > 0 do
      {removed_rows, kept_rows} = split_trimmed_rows(rows, overage, trim_side)
      removed_message_ids = Enum.map(removed_rows, & &1.message.id)

      socket
      |> delete_message_rows(removed_rows)
      |> prune_message_state(removed_message_ids)
      |> assign_visible_boundaries(kept_rows, trim_side)
      |> push_removed_message_rows(removed_rows)
    else
      socket
    end
  end

  defp visible_message_rows(socket) do
    socket.assigns.message_rows_by_id
    |> Map.values()
    |> Enum.sort_by(& &1.message.seq)
  end

  defp parse_visible_read_ranges(ranges) do
    Enum.reduce_while(ranges, [], fn
      %{"from_seq" => from_seq, "to_seq" => to_seq}, parsed_ranges ->
        case {parse_integer(from_seq), parse_integer(to_seq)} do
          {{:ok, from_seq}, {:ok, to_seq}} ->
            {:cont, [{from_seq, to_seq} | parsed_ranges]}

          _invalid ->
            {:halt, :invalid}
        end

      _invalid, _parsed_ranges ->
        {:halt, :invalid}
    end)
    |> case do
      :invalid -> :invalid
      parsed_ranges -> Enum.reverse(parsed_ranges)
    end
  end

  defp valid_visible_read_ranges?(_socket, :invalid), do: false
  defp valid_visible_read_ranges?(_socket, []), do: false

  defp valid_visible_read_ranges?(socket, ranges) do
    rendered_seqs =
      socket
      |> visible_message_rows()
      |> MapSet.new(& &1.message.seq)

    ranges_ordered?(ranges) and
      Enum.all?(ranges, fn {from_seq, to_seq} ->
        from_seq >= 1 and from_seq <= to_seq and to_seq - from_seq + 1 <= 50 and
          Enum.all?(from_seq..to_seq, &MapSet.member?(rendered_seqs, &1))
      end)
  end

  defp rendered_message_seq?(socket, seq) when is_integer(seq) do
    socket
    |> visible_message_rows()
    |> Enum.any?(&(&1.message.seq == seq))
  end

  defp ranges_ordered?(ranges) do
    ranges
    |> Enum.reduce_while(nil, fn {from_seq, to_seq}, previous_to_seq ->
      if is_nil(previous_to_seq) or from_seq > previous_to_seq do
        {:cont, to_seq}
      else
        {:halt, false}
      end
    end)
    |> then(&(&1 != false))
  end

  defp apply_visible_read_ranges(socket, ranges) do
    changed? =
      Enum.reduce(ranges, false, fn {from_seq, to_seq}, changed? ->
        case Chat.subtract_visible_read_range(
               socket.assigns.current_scope,
               socket.assigns.selected_channel.id,
               from_seq,
               to_seq
             ) do
          {:ok, _read_state} -> true
          {:error, _reason} -> changed?
        end
      end)

    if changed? do
      socket
      |> clear_selected_channel_unread_ui_if_read()
      |> refresh_channel_sidebar(socket.assigns.selected_workspace.id)
    else
      socket
    end
  end

  defp split_trimmed_rows(rows, overage, :newer) do
    Enum.split(rows, length(rows) - overage)
    |> then(fn {kept_rows, removed_rows} -> {removed_rows, kept_rows} end)
  end

  defp split_trimmed_rows(rows, overage, :older) do
    Enum.split(rows, overage)
  end

  defp delete_message_rows(socket, removed_rows) do
    Enum.reduce(removed_rows, socket, fn row, socket ->
      stream_delete(socket, :messages, row)
    end)
  end

  defp prune_message_state(socket, message_ids) do
    socket
    |> assign(:message_rows_by_id, Map.drop(socket.assigns.message_rows_by_id, message_ids))
    |> assign(:reaction_summaries, Map.drop(socket.assigns.reaction_summaries, message_ids))
  end

  defp assign_visible_boundaries(socket, [] = _kept_rows, _trim_side) do
    socket
    |> assign(:oldest_message, nil)
    |> assign(:latest_message, nil)
    |> assign(:has_older_messages?, false)
  end

  defp assign_visible_boundaries(socket, kept_rows, trim_side) do
    oldest_message = kept_rows |> List.first() |> Map.fetch!(:message)
    latest_message = kept_rows |> List.last() |> Map.fetch!(:message)

    socket
    |> assign(:oldest_message, oldest_message)
    |> assign(:latest_message, latest_message)
    |> assign(
      :message_window_meta,
      trimmed_window_meta(
        socket.assigns.message_window_meta,
        oldest_message,
        latest_message,
        trim_side
      )
    )
    |> assign(
      :has_older_messages?,
      trimmed_has_older?(socket.assigns.message_window_meta, trim_side)
    )
  end

  defp trimmed_window_meta(meta, oldest_message, latest_message, trim_side) do
    meta
    |> Map.put(:oldest_seq, oldest_message.seq)
    |> Map.put(:newest_seq, latest_message.seq)
    |> Map.put(:has_older?, trimmed_has_older?(meta, trim_side))
    |> Map.put(:has_newer?, trimmed_has_newer?(meta, trim_side))
    |> Map.put(:at_latest?, trimmed_at_latest?(meta, latest_message, trim_side))
    |> Map.put(:at_or_near_latest?, trimmed_at_or_near_latest?(meta, latest_message, trim_side))
  end

  defp trimmed_has_older?(_meta, :older), do: true
  defp trimmed_has_older?(meta, :newer), do: meta.has_older?

  defp trimmed_has_newer?(_meta, :newer), do: true
  defp trimmed_has_newer?(meta, :older), do: meta.has_newer?

  defp trimmed_at_latest?(_meta, _latest_message, :newer), do: false
  defp trimmed_at_latest?(meta, latest_message, :older), do: latest_message.seq == meta.latest_seq

  defp trimmed_at_or_near_latest?(_meta, _latest_message, :newer), do: false

  defp trimmed_at_or_near_latest?(meta, latest_message, :older) do
    meta.latest_seq - latest_message.seq <= 50
  end

  defp push_removed_message_rows(socket, []), do: socket

  defp push_removed_message_rows(socket, removed_rows) do
    push_event(socket, "remove_channel_message_rows", %{
      container_id: "channel-messages",
      message_ids: Enum.map(removed_rows, & &1.message.id),
      row_ids: Enum.map(removed_rows, &"message-#{&1.message.id}")
    })
  end

  defp replace_message_window(socket, %{messages: messages, meta: meta}) do
    rows = MessageRows.annotate(messages)

    socket
    |> assign(:oldest_message, List.first(messages))
    |> assign(:latest_message, List.last(messages))
    |> assign(:message_window_meta, meta)
    |> assign(:has_older_messages?, meta.has_older?)
    |> assign(:loading_older_messages?, false)
    |> assign(:loading_newer_messages?, false)
    |> assign(:reaction_summaries, reaction_summaries_for_window(socket, messages))
    |> assign(:message_rows_by_id, message_rows_by_id(rows))
    |> recalculate_selected_channel_unread_ui()
    |> stream(:messages, rows, reset: true)
  end

  defp reaction_summaries_for_window(socket, messages) do
    message_ids = Enum.map(messages, & &1.id)

    case Chat.list_reaction_summaries(socket.assigns.current_scope, message_ids) do
      {:ok, reaction_summaries} -> reaction_summaries
      {:error, _reason} -> %{}
    end
  end

  defp message_rows_by_id(rows) do
    Map.new(rows, fn row -> {row.message.id, row} end)
  end

  defp put_message_row(socket, row), do: put_message_rows(socket, [row])

  defp put_message_rows(socket, rows) do
    message_rows_by_id = Map.merge(socket.assigns.message_rows_by_id, message_rows_by_id(rows))
    assign(socket, :message_rows_by_id, message_rows_by_id)
  end

  defp restream_message_row(socket, message_id) do
    case Map.fetch(socket.assigns.message_rows_by_id, message_id) do
      {:ok, row} -> stream_insert(socket, :messages, row)
      :error -> socket
    end
  end

  defp restream_visible_message_rows(socket) do
    stream(socket, :messages, visible_message_rows(socket), reset: true)
  end

  defp append_selected_channel_message?(socket) do
    socket.assigns.message_window_meta.at_or_near_latest?
  end

  defp latest_window_meta(meta, message) do
    latest_seq = max(meta.latest_seq || 0, message.seq)

    meta
    |> Map.put(:newest_seq, message.seq)
    |> Map.put(:latest_seq, latest_seq)
    |> Map.put(:has_newer?, false)
    |> Map.put(:at_latest?, true)
    |> Map.put(:at_or_near_latest?, true)
  end

  defp newer_available_meta(meta, message) do
    latest_seq = max(meta.latest_seq || 0, message.seq)

    meta
    |> Map.put(:latest_seq, latest_seq)
    |> Map.put(:has_newer?, true)
    |> Map.put(:at_latest?, false)
    |> Map.put(:at_or_near_latest?, false)
  end

  defp merge_older_window_meta(current_meta, older_meta) do
    current_meta
    |> Map.put(:oldest_seq, older_meta.oldest_seq || current_meta.oldest_seq)
    |> Map.put(:latest_seq, max(current_meta.latest_seq || 0, older_meta.latest_seq || 0))
    |> Map.put(:has_older?, older_meta.has_older?)
  end

  defp merge_newer_window_meta(current_meta, newer_meta) do
    current_meta
    |> Map.put(:newest_seq, newer_meta.newest_seq || current_meta.newest_seq)
    |> Map.put(:latest_seq, max(current_meta.latest_seq || 0, newer_meta.latest_seq || 0))
    |> Map.put(:has_newer?, newer_meta.has_newer?)
    |> Map.put(:at_latest?, newer_meta.at_latest?)
    |> Map.put(:at_or_near_latest?, newer_meta.at_or_near_latest?)
  end

  defp preserve_scroll_after_older_load(socket, %{
         "container_id" => container_id,
         "scroll_height" => scroll_height,
         "scroll_top" => scroll_top
       }) do
    push_event(socket, "preserve_channel_messages_scroll", %{
      container_id: container_id,
      previous_scroll_height: to_integer(scroll_height),
      previous_scroll_top: to_integer(scroll_top)
    })
  end

  defp preserve_scroll_after_older_load(socket, _params), do: socket

  defp subscribe_to_channel_messages(socket, channel_id) do
    if connected?(socket) do
      Chat.subscribe_to_channel_messages(socket.assigns.current_scope, channel_id)
    else
      :ok
    end
  end

  defp subscribe_to_channel_reactions(socket, channel_id) do
    if connected?(socket) do
      Chat.subscribe_to_channel_reactions(socket.assigns.current_scope, channel_id)
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

  defp open_channel_message_window(socket, channel_id) do
    if connected?(socket) do
      with {:ok, %{landing: landing}} <-
             Chat.open_channel(socket.assigns.current_scope, channel_id) do
        load_landing_message_window(socket, channel_id, landing)
      end
    else
      {:ok,
       %{
         messages: [],
         meta: %{
           oldest_seq: nil,
           newest_seq: nil,
           latest_seq: 0,
           has_older?: false,
           has_newer?: false,
           at_latest?: true,
           at_or_near_latest?: true
         }
       }}
    end
  end

  defp load_landing_message_window(socket, channel_id, %{type: :latest}) do
    Chat.load_latest_message_window(socket.assigns.current_scope, channel_id)
  end

  defp load_landing_message_window(socket, channel_id, %{type: :sequence, target_seq: target_seq}) do
    Chat.load_message_window_around(socket.assigns.current_scope, channel_id, target_seq)
  end

  defp load_reaction_summaries(socket, messages) do
    if connected?(socket) do
      message_ids = Enum.map(messages, & &1.id)

      Chat.list_reaction_summaries(socket.assigns.current_scope, message_ids)
    else
      {:ok, %{}}
    end
  end

  defp load_channel_unread_counts(socket, workspace_id) do
    if connected?(socket) do
      Chat.list_unread_counts(socket.assigns.current_scope, workspace_id)
    else
      {:ok, %{}}
    end
  end

  defp load_channel_read_summary(socket, workspace_id, channel_id) do
    if connected?(socket) do
      with {:ok, summaries} <-
             Chat.list_channel_read_summaries(socket.assigns.current_scope, workspace_id) do
        {:ok, Enum.find(summaries, &(&1.channel_id == channel_id))}
      end
    else
      {:ok, nil}
    end
  end

  defp unread_divider_seq(%{unread_count: unread_count, first_unread_seq: first_unread_seq})
       when unread_count > 0 do
    first_unread_seq
  end

  defp unread_divider_seq(_summary), do: nil

  defp clear_selected_channel_unread_ui(socket) do
    socket
    |> assign(:selected_channel_read_summary, nil)
    |> assign(:unread_divider_seq, nil)
    |> restream_visible_message_rows()
  end

  defp maybe_clear_selected_channel_unread_ui(socket, channel_id) do
    if socket.assigns.selected_channel.id == channel_id do
      clear_selected_channel_unread_ui(socket)
    else
      socket
    end
  end

  defp clear_selected_channel_unread_ui_if_read(socket) do
    case load_channel_read_summary(
           socket,
           socket.assigns.selected_workspace.id,
           socket.assigns.selected_channel.id
         ) do
      {:ok, nil} ->
        clear_selected_channel_unread_ui(socket)

      {:ok, %{unread_count: 0}} ->
        clear_selected_channel_unread_ui(socket)

      {:ok, _summary} ->
        socket

      {:error, _reason} ->
        socket
    end
  end

  defp recalculate_selected_channel_unread_ui(socket) do
    case load_channel_read_summary(
           socket,
           socket.assigns.selected_workspace.id,
           socket.assigns.selected_channel.id
         ) do
      {:ok, selected_channel_read_summary} ->
        socket
        |> assign(:selected_channel_read_summary, selected_channel_read_summary)
        |> assign(:unread_divider_seq, unread_divider_seq(selected_channel_read_summary))

      {:error, _reason} ->
        socket
    end
  end

  defp refresh_channel_unread_counts_for_message(socket, %{channel_id: channel_id})
       when channel_id == socket.assigns.selected_channel.id do
    refresh_channel_sidebar(socket, socket.assigns.selected_workspace.id)
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

  defp selected_channel_unread_count(channel_unread_counts, selected_channel) do
    Map.get(channel_unread_counts, selected_channel.id, 0)
  end

  defp sticky_unread_actions?(
         channel_unread_counts,
         selected_channel,
         unread_divider_seq,
         message_rows_by_id
       ) do
    selected_channel_unread_count(channel_unread_counts, selected_channel) > 0 and
      not rendered_unread_divider?(unread_divider_seq, message_rows_by_id)
  end

  defp rendered_unread_divider?(nil, _message_rows_by_id), do: false

  defp rendered_unread_divider?(unread_divider_seq, message_rows_by_id) do
    Enum.any?(message_rows_by_id, fn {_message_id, row} ->
      row.message.seq == unread_divider_seq
    end)
  end

  defp skip_to_latest_action?(%{has_newer?: has_newer?}), do: has_newer?
  defp skip_to_latest_action?(_meta), do: false

  defp parse_integer(value) when is_integer(value), do: {:ok, value}

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _invalid -> :error
    end
  end

  defp parse_integer(_value), do: :error

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
