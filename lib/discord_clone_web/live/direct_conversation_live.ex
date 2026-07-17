defmodule DiscordCloneWeb.DirectConversationLive do
  @moduledoc false

  use DiscordCloneWeb, :live_view

  alias DiscordClone.Chat

  @impl true
  def mount(%{"direct_conversation_id" => direct_conversation_id}, _session, socket) do
    with {:ok, destination} <-
           Chat.get_direct_conversation(socket.assigns.current_scope, direct_conversation_id),
         :ok <- subscribe_to_messages(socket, direct_conversation_id),
         {:ok, messages} <-
           Chat.list_direct_messages(socket.assigns.current_scope, direct_conversation_id) do
      {:ok,
       socket
       |> assign(:direct_conversation, destination.direct_conversation)
       |> assign(:other_participant, destination.other_participant)
       |> assign(:message_form, message_form())
       |> assign(:direct_messages_empty?, messages == [])
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
    case Chat.send_direct_message(
           socket.assigns.current_scope,
           socket.assigns.direct_conversation.id,
           message_params
         ) do
      {:ok, _message} ->
        {:noreply, assign(socket, :message_form, message_form())}

      {:error, :invalid_message, changeset} ->
        {:noreply,
         assign(socket, :message_form, to_form(changeset, as: :message, action: :insert))}

      {:error, :not_friends} ->
        {:noreply, put_flash(socket, :error, "You can only message current Friends.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Direct Message could not be sent.")}
    end
  end

  @impl true
  def handle_info(
        {:direct_message_created, %{conversation_id: conversation_id}},
        %{assigns: %{direct_conversation: %{id: conversation_id}}} = socket
      ) do
    {:noreply, reload_messages(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
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
                  "group flex gap-3 rounded-2xl px-3 py-2 transition duration-200",
                  "hover:bg-base-200/60"
                ]}
              >
                <div class={[
                  "flex size-10 shrink-0 items-center justify-center rounded-xl bg-primary/10",
                  "text-sm font-bold text-primary ring-1 ring-primary/15"
                ]}>
                  {message.user.username |> String.first() |> String.upcase()}
                </div>
                <div class="min-w-0 flex-1">
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
                    data-direct-message-content
                    class="mt-1 whitespace-pre-wrap break-words text-sm leading-6 text-base-content/80"
                  >
                    {message.content}
                  </p>
                </div>
              </article>
            </div>

            <div class="border-t border-base-300/70 bg-base-100 p-4 sm:p-5">
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
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp subscribe_to_messages(socket, direct_conversation_id) do
    if connected?(socket) do
      Chat.subscribe_to_direct_messages(socket.assigns.current_scope, direct_conversation_id)
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
        socket
        |> assign(:direct_messages_empty?, messages == [])
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
end
