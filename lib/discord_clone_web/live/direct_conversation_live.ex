defmodule DiscordCloneWeb.DirectConversationLive do
  @moduledoc false

  use DiscordCloneWeb, :live_view

  alias DiscordClone.{Chat, Workspaces}
  alias DiscordCloneWeb.DirectMessagesLive.Shell, as: DirectMessagesShell

  @reaction_palette ["👍", "❤️", "😂", "🎉", "👀"]

  @impl true
  def mount(%{"direct_conversation_id" => direct_conversation_id}, _session, socket) do
    with {:ok, destination} <-
           Chat.get_direct_conversation(socket.assigns.current_scope, direct_conversation_id),
         :ok <- subscribe_to_messages(socket, direct_conversation_id),
         {:ok, messages} <-
           Chat.list_direct_messages(socket.assigns.current_scope, direct_conversation_id),
         {:ok, reaction_summaries} <-
           Chat.list_reaction_summaries(socket.assigns.current_scope, Enum.map(messages, & &1.id)),
         {:ok, destinations} <-
           Chat.list_direct_conversation_destinations(socket.assigns.current_scope),
         {:ok, workspaces} <- Workspaces.list_workspaces(socket.assigns.current_scope) do
      {:ok,
       socket
       |> assign(:direct_conversation, destination.direct_conversation)
       |> assign(:other_participant, destination.other_participant)
       |> assign(:message_form, message_form())
       |> assign(:reply_target, nil)
       |> assign(:reaction_summaries, reaction_summaries)
       |> assign(:writable?, destination_writable?(destinations, direct_conversation_id))
       |> assign(:direct_messages_empty?, messages == [])
       |> stream(:workspaces, workspaces)
       |> stream_configure(:direct_messages, dom_id: &"direct-message-#{&1.id}")
       |> stream(:direct_messages, messages)}
    else
      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Direct Conversation not found.")
         |> push_navigate(to: ~p"/friends")}
    end
  end

  @impl true
  def handle_event("send_direct_message", %{"message" => message_params}, socket) do
    message_params = put_reply_target(message_params, socket.assigns.reply_target)

    case Chat.send_direct_message(
           socket.assigns.current_scope,
           socket.assigns.direct_conversation.id,
           message_params
         ) do
      {:ok, _message} ->
        {:noreply,
         socket
         |> assign(:message_form, message_form())
         |> assign(:reply_target, nil)}

      {:error, :invalid_message, changeset} ->
        {:noreply,
         socket
         |> assign(:message_form, to_form(changeset, as: :message, action: :insert))
         |> recover_invalid_reply_target(changeset)}

      {:error, :not_friends} ->
        {:noreply, put_flash(socket, :error, "You can only message current Friends.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Direct Message could not be sent.")}
    end
  end

  def handle_event("begin_direct_reply", %{"message-id" => message_id}, socket) do
    with true <- socket.assigns.writable?,
         {:ok, message} <-
           Chat.fetch_direct_message(
             socket.assigns.current_scope,
             socket.assigns.direct_conversation.id,
             message_id
           ),
         false <- message_deleted?(message) do
      {:noreply, assign(socket, :reply_target, message)}
    else
      _invalid ->
        {:noreply, put_flash(socket, :error, "That message is no longer available to reply to.")}
    end
  end

  def handle_event("cancel_direct_reply", _params, socket) do
    {:noreply, assign(socket, :reply_target, nil)}
  end

  def handle_event(
        "toggle_direct_reaction",
        %{"message-id" => message_id, "emoji" => emoji},
        socket
      ) do
    case Chat.toggle_reaction(socket.assigns.current_scope, message_id, emoji) do
      {:ok, _reaction} ->
        {:noreply, reload_messages(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Reaction could not be saved.")}

      {:error, _reason, _detail} ->
        {:noreply, put_flash(socket, :error, "Reaction could not be saved.")}
    end
  end

  def handle_event("delete_direct_message", %{"message-id" => message_id}, socket) do
    case Chat.delete_message(socket.assigns.current_scope, message_id) do
      {:ok, _message} -> {:noreply, reload_messages(socket)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, "Message could not be deleted.")}
    end
  end

  @impl true
  def handle_info(
        {:direct_message_created, %{conversation_id: conversation_id}},
        %{assigns: %{direct_conversation: %{id: conversation_id}}} = socket
      ) do
    {:noreply, reload_messages(socket)}
  end

  def handle_info(
        {:message_deleted, %{conversation_id: conversation_id}},
        %{assigns: %{direct_conversation: %{id: conversation_id}}} = socket
      ) do
    {:noreply, reload_messages(socket)}
  end

  def handle_info({:reaction_changed, _payload}, socket) do
    {:noreply, reload_messages(socket)}
  end

  def handle_info({:friendships_changed, _payload}, socket) do
    {:noreply, refresh_writable_capability(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <DirectMessagesShell.app
        workspace_stream={@streams.workspaces}
        conversation_stream={@streams.direct_conversation_destinations}
        incoming_request_count={@incoming_friend_request_count}
        direct_message_unread_count={@direct_message_unread_count}
        selected_conversation_id={@direct_conversation.id}
      >
        <main
          id="direct-conversation"
          class={[
            "min-h-screen bg-base-200/45 px-5 py-10 sm:px-8",
            "transition-colors duration-300"
          ]}
        >
          <div class={["mx-auto flex min-h-[70vh] w-full max-w-4xl flex-col"]}>
            <header class={[
              "flex items-center gap-4 rounded-3xl border border-base-300 bg-base-100",
              "px-5 py-4 shadow-sm sm:px-6"
            ]}>
              <.link
                id="direct-conversation-back"
                navigate={~p"/friends"}
                aria-label="Back to Friends"
                class={[
                  "inline-flex size-10 items-center justify-center rounded-xl text-base-content/55",
                  "transition hover:bg-base-200 hover:text-base-content focus-visible:outline-none",
                  "focus-visible:ring-2 focus-visible:ring-primary"
                ]}
              >
                <.icon name="hero-arrow-left" class="size-5" />
              </.link>

              <div class={[
                "flex size-11 items-center justify-center rounded-full bg-primary/10",
                "text-base font-bold text-primary"
              ]}>
                {@other_participant.username |> String.first() |> String.upcase()}
              </div>

              <div id={"direct-conversation-participant-#{@other_participant.id}"} class={["min-w-0"]}>
                <p class={["truncate font-semibold text-base-content"]}>
                  {@other_participant.username}
                </p>
                <p class={["text-xs text-base-content/50"]}>Direct Conversation</p>
              </div>
            </header>

            <section class={[
              "relative mt-5 flex min-h-0 flex-1 flex-col overflow-hidden rounded-3xl border",
              "border-base-300 bg-base-100 shadow-sm"
            ]}>
              <div
                :if={@direct_messages_empty?}
                id="direct-conversation-empty"
                class={[
                  "flex flex-1 flex-col items-center justify-center p-8 text-center"
                ]}
              >
                <div class={[
                  "mx-auto flex size-14 items-center justify-center rounded-2xl",
                  "bg-primary/10 text-primary"
                ]}>
                  <.icon name="hero-chat-bubble-left-right" class="size-7" />
                </div>
                <h1 class={["mt-5 text-xl font-bold tracking-tight text-base-content"]}>
                  Start your conversation
                </h1>
                <p class={["mt-2 text-sm leading-6 text-base-content/55"]}>
                  This Direct Conversation with @{@other_participant.username} is empty and ready for your first message.
                </p>
              </div>

              <div
                id="direct-messages"
                phx-update="stream"
                class="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto px-5 py-6 sm:px-7"
              >
                <article
                  :for={{dom_id, message} <- @streams.direct_messages}
                  id={dom_id}
                  data-message-seq={message.seq}
                  class={[
                    "group relative flex gap-3 rounded-2xl px-3 py-2 transition duration-200",
                    "hover:bg-base-200/60"
                  ]}
                >
                  <div class={[
                    "flex size-10 shrink-0 items-center justify-center rounded-xl bg-primary/10",
                    "text-sm font-bold text-primary ring-1 ring-primary/15"
                  ]}>
                    {message.user.username |> String.first() |> String.upcase()}
                  </div>
                  <div class="min-w-0 flex-1 pr-24">
                    <div
                      :if={!message_deleted?(message)}
                      class="absolute right-3 top-2 flex items-center gap-1"
                    >
                      <button
                        :if={@writable?}
                        id={"#{dom_id}-reply"}
                        type="button"
                        phx-click="begin_direct_reply"
                        phx-value-message-id={message.id}
                        aria-label={"Reply to message from #{message.user.username}"}
                        class="flex size-8 items-center justify-center rounded-lg text-base-content/45 opacity-0 transition hover:bg-base-300 hover:text-base-content group-hover:opacity-100 focus:opacity-100 focus:outline-none focus:ring-2 focus:ring-primary/30"
                      >
                        <.icon name="hero-arrow-uturn-left" class="size-4" />
                      </button>
                      <div
                        :if={@writable?}
                        id={"#{dom_id}-reaction-palette"}
                        class="flex items-center rounded-lg bg-base-100/95 p-0.5 opacity-0 shadow-sm ring-1 ring-base-300 transition group-hover:opacity-100"
                      >
                        <button
                          :for={{emoji, index} <- Enum.with_index(reaction_palette())}
                          id={"#{dom_id}-reaction-option-#{index}"}
                          type="button"
                          phx-click="toggle_direct_reaction"
                          phx-value-message-id={message.id}
                          phx-value-emoji={emoji}
                          aria-label={"React with #{emoji} to message"}
                          class="flex size-7 items-center justify-center rounded-md text-sm transition hover:bg-base-200 focus:outline-none focus:ring-2 focus:ring-primary/30"
                        >
                          {emoji}
                        </button>
                      </div>
                      <button
                        :if={message.user_id == @current_scope.user.id}
                        id={"#{dom_id}-delete"}
                        type="button"
                        phx-click="delete_direct_message"
                        phx-value-message-id={message.id}
                        aria-label="Delete Direct Message"
                        class="flex size-8 items-center justify-center rounded-lg text-base-content/45 opacity-0 transition hover:bg-error/10 hover:text-error group-hover:opacity-100 focus:opacity-100 focus:outline-none focus:ring-2 focus:ring-error/30"
                      >
                        <.icon name="hero-trash" class="size-4" />
                      </button>
                    </div>
                    <button
                      :if={
                        !is_nil(message.reply_to_message_id) &&
                          !message_deleted?(message.reply_to_message)
                      }
                      id={"#{dom_id}-reply-preview"}
                      type="button"
                      phx-click="begin_direct_reply"
                      phx-value-message-id={message.reply_to_message_id}
                      class="mb-1.5 flex max-w-full items-center gap-2 border-l-2 border-primary/35 pl-2 text-left text-xs text-base-content/55"
                    >
                      <span class="shrink-0 font-semibold text-primary/85">
                        {message.reply_to_message.user.username}
                      </span>
                      <span class="truncate">
                        {truncate_reply_content(message.reply_to_message.content)}
                      </span>
                    </button>
                    <div
                      :if={
                        !is_nil(message.reply_to_message_id) &&
                          message_deleted?(message.reply_to_message)
                      }
                      id={"#{dom_id}-deleted-reply-preview"}
                      class="mb-1.5 flex items-center gap-2 border-l-2 border-base-content/20 pl-2 text-xs italic text-base-content/45"
                    >
                      <.icon name="hero-no-symbol" class="size-3.5" />
                      <span>Message deleted</span>
                    </div>
                    <div class="flex flex-wrap items-baseline gap-2">
                      <span class="text-sm font-semibold text-base-content">
                        {message.user.username}
                      </span>
                      <time
                        datetime={DateTime.to_iso8601(message.inserted_at)}
                        class="text-xs text-base-content/45"
                      >
                        {Calendar.strftime(message.inserted_at, "%H:%M")}
                      </time>
                    </div>
                    <p
                      :if={!message_deleted?(message)}
                      data-direct-message-content
                      class="mt-1 whitespace-pre-wrap break-words text-sm leading-6 text-base-content/80"
                    >
                      {message.content}
                    </p>
                    <p
                      :if={message_deleted?(message)}
                      id={"#{dom_id}-deleted"}
                      class="mt-1 flex items-center gap-2 text-sm italic text-base-content/45"
                    >
                      <.icon name="hero-no-symbol" class="size-4" /> Message deleted
                    </p>
                    <div
                      :if={
                        !message_deleted?(message) &&
                          reaction_summaries_for(@reaction_summaries, message.id) != []
                      }
                      id={"#{dom_id}-reactions"}
                      class="mt-2 flex flex-wrap gap-1.5"
                    >
                      <button
                        :for={
                          {summary, index} <-
                            Enum.with_index(reaction_summaries_for(@reaction_summaries, message.id))
                        }
                        id={"#{dom_id}-reaction-#{index}"}
                        type="button"
                        disabled={!@writable? && !summary.reacted?}
                        phx-click="toggle_direct_reaction"
                        phx-value-message-id={message.id}
                        phx-value-emoji={summary.emoji}
                        data-current-user-reacted={to_string(summary.reacted?)}
                        aria-label={reaction_label(summary)}
                        class={[
                          "inline-flex items-center gap-1 rounded-lg px-2 py-1 text-xs font-semibold ring-1 transition",
                          summary.reacted? &&
                            "bg-primary/10 text-primary ring-primary/30 hover:bg-primary/15",
                          !summary.reacted? && "bg-base-200 text-base-content/60 ring-base-300",
                          !@writable? && !summary.reacted? && "cursor-default opacity-70"
                        ]}
                      >
                        <span>{summary.emoji}</span><span>{summary.count}</span>
                      </button>
                    </div>
                  </div>
                </article>
              </div>

              <div :if={@writable?} class="border-t border-base-300/70 bg-base-100 p-4 sm:p-5">
                <div
                  :if={!is_nil(@reply_target)}
                  id="direct-message-reply-target"
                  data-message-id={@reply_target && @reply_target.id}
                  class="mb-2 flex items-center gap-3 rounded-xl border border-primary/20 bg-primary/5 px-3 py-2"
                >
                  <p class="min-w-0 flex-1 truncate text-xs text-base-content/60">
                    Replying to <span class="font-semibold text-primary">{@reply_target.user.username}</span>: {@reply_target.content}
                  </p>
                  <button
                    id="cancel-direct-message-reply"
                    type="button"
                    phx-click="cancel_direct_reply"
                    aria-label="Cancel reply"
                    class="text-base-content/45 hover:text-base-content"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
                <.form
                  for={@message_form}
                  id="direct-message-form"
                  phx-submit="send_direct_message"
                  class="flex items-end gap-3"
                >
                  <.input
                    field={@message_form[:content]}
                    type="text"
                    placeholder={"Message @#{@other_participant.username}"}
                    autocomplete="off"
                    class="min-h-11 w-full rounded-2xl border border-base-300 bg-base-200/65 px-4 py-3 text-sm text-base-content outline-none transition placeholder:text-base-content/40 focus:border-primary/35 focus:bg-base-100 focus:ring-2 focus:ring-primary/15"
                  />
                  <button
                    id="direct-message-send"
                    type="submit"
                    aria-label="Send Direct Message"
                    phx-disable-with="Sending…"
                    class={[
                      "inline-flex size-11 shrink-0 items-center justify-center rounded-2xl",
                      "bg-primary text-primary-content shadow-sm transition duration-200",
                      "hover:-translate-y-0.5 hover:bg-primary/90 focus-visible:outline-none",
                      "focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2"
                    ]}
                  >
                    <.icon name="hero-paper-airplane" class="size-5" />
                  </button>
                </.form>
              </div>
              <div
                :if={!@writable?}
                id="direct-conversation-read-only"
                class="border-t border-base-300/70 bg-base-200/55 px-5 py-4 text-center text-sm text-base-content/55"
              >
                This Direct Conversation is read-only because you are no longer Friends.
              </div>
            </section>
          </div>
        </main>
      </DirectMessagesShell.app>
    </Layouts.app>
    """
  end

  defp subscribe_to_messages(socket, direct_conversation_id) do
    if connected?(socket) do
      with :ok <-
             Chat.subscribe_to_direct_messages(
               socket.assigns.current_scope,
               direct_conversation_id
             ) do
        Chat.subscribe_to_direct_reactions(socket.assigns.current_scope, direct_conversation_id)
      end
    else
      :ok
    end
  end

  defp reload_messages(socket) do
    case Chat.list_direct_messages(
           socket.assigns.current_scope,
           socket.assigns.direct_conversation.id
         ) do
      {:ok, messages} ->
        {:ok, reaction_summaries} =
          Chat.list_reaction_summaries(socket.assigns.current_scope, Enum.map(messages, & &1.id))

        socket
        |> assign(:direct_messages_empty?, messages == [])
        |> assign(:reaction_summaries, reaction_summaries)
        |> clear_deleted_reply_target(messages)
        |> stream(:direct_messages, messages, reset: true)

      {:error, _reason} ->
        socket
    end
  end

  defp message_form do
    %{}
    |> Chat.change_message()
    |> to_form(as: :message)
  end

  defp put_reply_target(message_params, nil), do: message_params

  defp put_reply_target(message_params, reply_target),
    do: Map.put(message_params, "reply_to_message_id", reply_target.id)

  defp recover_invalid_reply_target(%{assigns: %{reply_target: nil}} = socket, _changeset),
    do: socket

  defp recover_invalid_reply_target(socket, changeset) do
    if Keyword.has_key?(changeset.errors, :reply_to_message_id) do
      socket
      |> assign(:reply_target, nil)
      |> put_flash(:error, "That message is no longer available to reply to.")
    else
      socket
    end
  end

  defp refresh_writable_capability(socket) do
    {:ok, destinations} = Chat.list_direct_conversation_destinations(socket.assigns.current_scope)
    writable? = destination_writable?(destinations, socket.assigns.direct_conversation.id)

    socket
    |> assign(:writable?, writable?)
    |> then(fn socket -> if writable?, do: socket, else: assign(socket, :reply_target, nil) end)
    |> reload_messages()
  end

  defp destination_writable?(destinations, direct_conversation_id) do
    Enum.any?(destinations, fn destination ->
      destination.direct_conversation.id == direct_conversation_id && destination.writable?
    end)
  end

  defp clear_deleted_reply_target(%{assigns: %{reply_target: nil}} = socket, _messages),
    do: socket

  defp clear_deleted_reply_target(socket, messages) do
    target_id = socket.assigns.reply_target.id

    if Enum.any?(messages, &(&1.id == target_id && is_nil(&1.deleted_at))) do
      socket
    else
      socket
      |> assign(:reply_target, nil)
      |> put_flash(:error, "That reply target was deleted.")
    end
  end

  defp reaction_summaries_for(summaries, message_id), do: Map.get(summaries, message_id, [])
  defp reaction_palette, do: @reaction_palette
  defp message_deleted?(%{deleted_at: %DateTime{}}), do: true
  defp message_deleted?(_message), do: false

  defp truncate_reply_content(content) do
    if String.length(content) > 80, do: String.slice(content, 0, 77) <> "…", else: content
  end

  defp reaction_label(summary) do
    count_label = if summary.count == 1, do: "1 reaction", else: "#{summary.count} reactions"
    "#{summary.emoji} reaction, #{count_label}"
  end
end
