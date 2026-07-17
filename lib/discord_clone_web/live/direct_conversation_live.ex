defmodule DiscordCloneWeb.DirectConversationLive do
  @moduledoc false

  use DiscordCloneWeb, :live_view

  alias DiscordClone.Chat

  @impl true
  def mount(%{"direct_conversation_id" => direct_conversation_id}, _session, socket) do
    case Chat.get_direct_conversation(socket.assigns.current_scope, direct_conversation_id) do
      {:ok, destination} ->
        {:ok,
         socket
         |> assign(:direct_conversation, destination.direct_conversation)
         |> assign(:other_participant, destination.other_participant)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Direct Conversation not found.")
         |> push_navigate(to: ~p"/friends")}
    end
  end

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
            "mt-5 flex flex-1 items-center justify-center rounded-3xl border border-dashed",
            "border-base-300 bg-base-100/70 p-8 text-center"
          ]}>
            <div id="direct-conversation-empty" class={["max-w-sm"]}>
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
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end
end
