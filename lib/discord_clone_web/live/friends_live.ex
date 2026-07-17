defmodule DiscordCloneWeb.FriendsLive do
  @moduledoc false

  use DiscordCloneWeb, :live_view

  alias DiscordClone.Friendships

  @empty_form %{"username" => ""}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, incoming_requests} =
      Friendships.list_incoming_requests(socket.assigns.current_scope)

    {:ok, outgoing_requests} =
      Friendships.list_outgoing_requests(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:form, to_form(@empty_form, as: :friend_request))
     |> assign(:request_outcome, nil)
     |> stream_configure(:incoming_requests,
       dom_id: &"incoming-request-#{&1.relationship.id}"
     )
     |> stream(:incoming_requests, incoming_requests)
     |> stream_configure(:outgoing_requests,
       dom_id: &"outgoing-request-#{&1.relationship.id}"
     )
     |> stream(:outgoing_requests, outgoing_requests)}
  end

  @impl true
  def handle_event("send_friend_request", %{"friend_request" => params}, socket) do
    case Friendships.send_friend_request(socket.assigns.current_scope, params) do
      {:ok, result} ->
        outcome =
          if result.relationship.status == :accepted do
            {:success, "You and @#{result.user.username} are now friends."}
          else
            {:success, "Friend Request sent to @#{result.user.username}."}
          end

        {:noreply,
         socket
         |> assign(:form, to_form(@empty_form, as: :friend_request))
         |> assign(:request_outcome, outcome)
         |> refresh_request_streams()}

      {:error, :unknown_user} ->
        {:noreply, assign(socket, :request_outcome, {:error, "No User has that exact username."})}

      {:error, :self_request} ->
        {:noreply,
         assign(socket, :request_outcome, {:error, "You cannot send yourself a Friend Request."})}

      {:error, :invalid_username} ->
        {:noreply, assign(socket, :request_outcome, {:error, "Enter an exact username."})}

      {:error, _reason} ->
        {:noreply,
         assign(socket, :request_outcome, {:error, "Friend Request could not be sent."})}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="friends-home" class={["min-h-screen bg-base-200/45 px-5 py-10 sm:px-8"]}>
        <div class={["mx-auto w-full max-w-5xl"]}>
          <header class={["mb-8 flex flex-col gap-3"]}>
            <div class={["flex items-center gap-2 text-primary"]}>
              <.icon name="hero-user-group" class="size-5" />
              <span class={["text-xs font-bold uppercase tracking-[0.2em]"]}>Friends</span>
            </div>
            <h1 class={["text-3xl font-bold tracking-tight text-base-content sm:text-4xl"]}>
              Find your people, precisely.
            </h1>
            <p class={["max-w-2xl text-sm leading-6 text-base-content/60"]}>
              Send a private Friend Request with an exact global username. There is no public directory.
            </p>
          </header>

          <section class={["rounded-3xl border border-base-300 bg-base-100 p-5 shadow-sm sm:p-7"]}>
            <div class={["flex items-center gap-3"]}>
              <div class={[
                "flex size-10 items-center justify-center rounded-2xl bg-primary/10 text-primary"
              ]}>
                <.icon name="hero-user-plus" class="size-5" />
              </div>
              <div>
                <h2 class={["font-semibold text-base-content"]}>Send a Friend Request</h2>
                <p class={["text-xs text-base-content/55"]}>Exact username matching only</p>
              </div>
            </div>

            <.form
              for={@form}
              id="friend-request-form"
              phx-submit="send_friend_request"
              class={["mt-5 flex flex-col gap-3 sm:flex-row sm:items-end"]}
            >
              <div class={["min-w-0 flex-1"]}>
                <.input
                  field={@form[:username]}
                  type="text"
                  label="Global username"
                  placeholder="exact_username"
                  autocomplete="off"
                  required
                />
              </div>
              <button
                id="send-friend-request-button"
                type="submit"
                class={[
                  "inline-flex h-11 items-center justify-center gap-2 rounded-xl bg-primary px-5",
                  "text-sm font-semibold text-primary-content shadow-sm transition duration-200",
                  "hover:-translate-y-0.5 hover:shadow-md focus-visible:outline-none",
                  "focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2"
                ]}
              >
                <.icon name="hero-paper-airplane" class="size-4" /> Send request
              </button>
            </.form>

            <%= if @request_outcome do %>
              <div
                id="friend-request-outcome"
                data-kind={elem(@request_outcome, 0)}
                class={[
                  "mt-4 rounded-xl border px-4 py-3 text-sm",
                  elem(@request_outcome, 0) == :success &&
                    "border-success/25 bg-success/10 text-success",
                  elem(@request_outcome, 0) == :error &&
                    "border-error/25 bg-error/10 text-error"
                ]}
              >
                {elem(@request_outcome, 1)}
              </div>
            <% end %>
          </section>

          <div class={["mt-7 grid gap-6 lg:grid-cols-2"]}>
            <.request_panel
              id="incoming-requests"
              title="Incoming"
              subtitle="Friend Requests waiting for you"
              empty="No incoming requests"
              icon="hero-inbox-arrow-down"
              stream={@streams.incoming_requests}
              direction={:incoming}
            />
            <.request_panel
              id="outgoing-requests"
              title="Outgoing"
              subtitle="Friend Requests you have sent"
              empty="No outgoing requests"
              icon="hero-paper-airplane"
              stream={@streams.outgoing_requests}
              direction={:outgoing}
            />
          </div>
        </div>
      </main>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :empty, :string, required: true
  attr :icon, :string, required: true
  attr :stream, :any, required: true
  attr :direction, :atom, required: true

  defp request_panel(assigns) do
    ~H"""
    <section class={["overflow-hidden rounded-3xl border border-base-300 bg-base-100 shadow-sm"]}>
      <header class={["flex items-center gap-3 border-b border-base-300 px-5 py-4"]}>
        <div class={[
          "flex size-9 items-center justify-center rounded-xl bg-base-200 text-base-content/60"
        ]}>
          <.icon name={@icon} class="size-4" />
        </div>
        <div>
          <h2 class={["text-sm font-semibold text-base-content"]}>{@title}</h2>
          <p class={["text-xs text-base-content/50"]}>{@subtitle}</p>
        </div>
      </header>
      <div id={@id} phx-update="stream" class={["divide-y divide-base-300"]}>
        <div
          id={"#{@id}-empty-state"}
          class={[
            "hidden only:flex items-center justify-center px-5 py-12 text-sm text-base-content/45"
          ]}
        >
          {@empty}
        </div>
        <article
          :for={{dom_id, request} <- @stream}
          id={dom_id}
          class={["group flex items-center gap-3 px-5 py-4 transition hover:bg-base-200/50"]}
        >
          <div class={[
            "flex size-10 items-center justify-center rounded-full bg-primary/10 font-bold text-primary"
          ]}>
            {request.user.username |> String.first() |> String.upcase()}
          </div>
          <div class={["min-w-0 flex-1"]}>
            <p class={["truncate text-sm font-semibold text-base-content"]}>
              @{request.user.username}
            </p>
            <p class={["text-xs text-base-content/45"]}>
              {if @direction == :incoming, do: "Wants to be friends", else: "Request pending"}
            </p>
          </div>
          <span class={["size-2 rounded-full bg-warning ring-4 ring-warning/10"]} />
        </article>
      </div>
    </section>
    """
  end

  defp refresh_request_streams(socket) do
    {:ok, incoming_requests} = Friendships.list_incoming_requests(socket.assigns.current_scope)
    {:ok, outgoing_requests} = Friendships.list_outgoing_requests(socket.assigns.current_scope)

    socket
    |> stream(:incoming_requests, incoming_requests, reset: true)
    |> stream(:outgoing_requests, outgoing_requests, reset: true)
  end
end
