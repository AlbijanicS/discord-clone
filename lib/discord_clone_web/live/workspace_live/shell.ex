defmodule DiscordCloneWeb.WorkspaceLive.Shell do
  use DiscordCloneWeb, :html

  attr :workspace_stream, :any, required: true
  attr :channel_stream, :any, default: nil
  attr :selected_workspace, :any, default: nil
  attr :selected_channel, :any, default: nil
  attr :workspace_form, :any, default: nil
  attr :show_workspace_form?, :boolean, default: false
  attr :channel_form, :any, default: nil
  attr :show_channel_form?, :boolean, default: false
  attr :current_scope, :any, default: nil
  attr :main_state, :atom, default: :no_workspace

  def app(assigns) do
    ~H"""
    <div
      id="workspace-app-shell"
      class="fixed inset-0 grid min-h-screen overflow-hidden bg-base-100 lg:grid-cols-[14rem_18rem_minmax(0,1fr)]"
    >
      <aside
        id="workspace-sidebar"
        class="flex min-h-0 flex-col border-b border-base-300 bg-base-300 p-3 lg:border-b-0 lg:border-r"
      >
        <div class="mb-3 flex items-center justify-between gap-2">
          <p class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
            Workspaces
          </p>
          <button
            :if={@workspace_form && !@show_workspace_form?}
            id="workspace-create-toggle"
            type="button"
            class="btn btn-square btn-sm btn-ghost transition hover:scale-105"
            phx-click="show_workspace_form"
            aria-label="Create workspace"
          >
            <.icon name="hero-plus" class="size-4" />
          </button>
        </div>

        <div
          id="workspaces"
          phx-update="stream"
          class="flex min-h-0 gap-2 overflow-x-auto lg:flex-col lg:overflow-y-auto"
        >
          <div id="workspace-empty-state" class="hidden only:block text-sm text-base-content/60">
            Create a workspace to start.
          </div>
          <.link
            :for={{dom_id, workspace} <- @workspace_stream}
            id={workspace_dom_id(dom_id, workspace, @selected_workspace)}
            navigate={~p"/workspaces/#{workspace.id}"}
            aria-current={selected_workspace_aria(workspace, @selected_workspace)}
            class={[
              "flex min-h-11 w-full shrink-0 items-center rounded px-3 text-sm font-semibold shadow-sm ring-1 transition hover:-translate-y-0.5",
              selected_workspace?(workspace, @selected_workspace) &&
                "bg-primary text-primary-content ring-primary",
              !selected_workspace?(workspace, @selected_workspace) &&
                "bg-base-100 ring-base-300 hover:bg-primary hover:text-primary-content"
            ]}
            data-stream-id={dom_id}
            aria-label={"Open #{workspace.name}"}
          >
            <span class="truncate">{workspace.name}</span>
          </.link>
        </div>

        <.form
          :if={@workspace_form && @show_workspace_form?}
          for={@workspace_form}
          id="workspace-create-form"
          phx-submit="create_workspace"
          class="mt-4 space-y-2"
        >
          <.input
            field={@workspace_form[:name]}
            type="text"
            label="Workspace name"
            placeholder="Design guild"
            autocomplete="off"
          />
          <.button type="submit" class="btn btn-primary btn-sm w-full">
            Create
          </.button>
        </.form>
      </aside>

      <aside
        id="channel-sidebar"
        class="hidden min-h-0 flex-col border-r border-base-300 bg-base-200 lg:flex"
      >
        <div class="min-h-0 flex-1 overflow-y-auto p-4">
          <%= if @selected_workspace do %>
            <div class="mb-4">
              <p class="text-sm font-semibold">{@selected_workspace.name}</p>
              <div class="mt-1 flex items-center justify-between gap-2">
                <p class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
                  Channels
                </p>
                <button
                  :if={@channel_form && !@show_channel_form?}
                  id="channel-create-toggle"
                  type="button"
                  class="btn btn-square btn-xs btn-ghost transition hover:scale-105"
                  phx-click="show_channel_form"
                  aria-label="Create channel"
                >
                  <.icon name="hero-plus" class="size-3.5" />
                </button>
              </div>
            </div>

            <div id="channels" phx-update="stream" class="space-y-1">
              <div id="channel-empty-state" class="hidden only:block text-sm text-base-content/60">
                No channels yet.
              </div>
              <.link
                :for={{dom_id, channel} <- @channel_stream}
                id={"channel-#{channel.id}"}
                navigate={~p"/workspaces/#{@selected_workspace.id}/channels/#{channel.id}"}
                aria-current={selected_channel_aria(channel, @selected_channel)}
                class={[
                  "block rounded px-3 py-2 text-sm transition",
                  selected_channel?(channel, @selected_channel) &&
                    "bg-base-300 font-semibold text-base-content",
                  !selected_channel?(channel, @selected_channel) &&
                    "text-base-content/70 hover:bg-base-300 hover:text-base-content"
                ]}
                data-stream-id={dom_id}
              >
                # {channel.name}
              </.link>
            </div>

            <.form
              :if={@channel_form && @show_channel_form?}
              for={@channel_form}
              id="channel-create-form"
              phx-submit="create_channel"
              class="mt-4 space-y-2"
            >
              <.input
                field={@channel_form[:name]}
                type="text"
                label="Channel name"
                placeholder="planning"
                autocomplete="off"
              />
              <.button type="submit" class="btn btn-primary btn-sm w-full">
                Create
              </.button>
            </.form>
          <% else %>
            <div class="mb-4">
              <p class="text-sm font-semibold">No workspace selected</p>
              <p class="mt-1 text-sm text-base-content/60">Choose a workspace to see channels.</p>
            </div>
          <% end %>
        </div>

        <div
          :if={@current_scope && @current_scope.user}
          class="border-t border-base-300 bg-base-300/70 p-3"
        >
          <div class="flex items-center gap-3">
            <div class="flex size-9 shrink-0 items-center justify-center rounded bg-primary text-sm font-semibold text-primary-content">
              {user_initial(@current_scope.user)}
            </div>
            <div class="min-w-0 flex-1">
              <p class="truncate text-sm font-semibold">{@current_scope.user.username}</p>
              <p class="truncate text-xs text-base-content/50">{@current_scope.user.email}</p>
            </div>
            <.link
              href={~p"/users/settings"}
              class="btn btn-square btn-xs btn-ghost"
              aria-label="Settings"
            >
              <.icon name="hero-cog-6-tooth" class="size-4" />
            </.link>
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="btn btn-square btn-xs btn-ghost"
              aria-label="Log out"
            >
              <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
            </.link>
          </div>
        </div>
      </aside>

      <main id="workspace-main" class={main_class(@main_state)}>
        <%= case @main_state do %>
          <% :channel -> %>
            <header class="border-b border-base-300 px-6 py-4">
              <p class="text-sm font-semibold"># {@selected_channel.name}</p>
            </header>
            <div id="channel-main" class="min-h-0 flex-1 p-6">
              <div class="flex h-full items-center justify-center text-center">
                <div>
                  <p class="text-lg font-semibold">Messages are coming soon</p>
                  <p class="mt-2 text-sm text-base-content/60">
                    This channel is ready for the future chat surface.
                  </p>
                </div>
              </div>
            </div>
            <div class="border-t border-base-300 p-4">
              <input
                id="message-composer-placeholder"
                type="text"
                class="input input-bordered w-full"
                placeholder={"Message ##{@selected_channel.name}"}
                disabled
              />
            </div>
          <% :empty_channel -> %>
            <div
              id="workspace-main-empty-channel"
              class="flex h-full items-center justify-center text-center"
            >
              <div>
                <p class="text-lg font-semibold">No channels yet</p>
                <p class="mt-2 text-sm text-base-content/60">
                  Create a channel to start shaping this workspace.
                </p>
              </div>
            </div>
          <% :no_workspace -> %>
            <div class="flex h-full items-center justify-center text-center">
              <div>
                <p class="text-lg font-semibold">Select a workspace to continue</p>
                <p class="mt-2 text-sm text-base-content/60">
                  Your workspace channels will appear here once you enter one.
                </p>
              </div>
            </div>
        <% end %>
      </main>
    </div>
    """
  end

  defp workspace_dom_id(_dom_id, workspace, selected_workspace)
       when not is_nil(selected_workspace) and workspace.id == selected_workspace.id,
       do: "workspace-#{workspace.id}"

  defp workspace_dom_id(dom_id, _workspace, _selected_workspace), do: dom_id

  defp selected_workspace?(workspace, selected_workspace),
    do: selected_workspace && workspace.id == selected_workspace.id

  defp selected_channel?(channel, selected_channel),
    do: selected_channel && channel.id == selected_channel.id

  defp selected_workspace_aria(workspace, selected_workspace) do
    if selected_workspace?(workspace, selected_workspace), do: "page"
  end

  defp selected_channel_aria(channel, selected_channel) do
    if selected_channel?(channel, selected_channel), do: "page"
  end

  defp user_initial(user) do
    user.username
    |> String.first()
    |> String.upcase()
  end

  defp main_class(:channel), do: "flex min-h-0 flex-col bg-base-100"
  defp main_class(_state), do: "min-h-0 overflow-auto bg-base-100 p-6"
end
