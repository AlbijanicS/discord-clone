defmodule DiscordCloneWeb.WorkspaceLive.Shell do
  use DiscordCloneWeb, :html

  alias DiscordClone.Workspaces

  attr :workspace_stream, :any, required: true
  attr :channel_stream, :any, default: nil
  attr :selected_workspace, :any, default: nil
  attr :selected_channel, :any, default: nil
  attr :workspace_form, :any, default: nil
  attr :show_workspace_form?, :boolean, default: false
  attr :workspace_action_menu_id, :integer, default: nil
  attr :renaming_workspace_id, :integer, default: nil
  attr :workspace_rename_form, :any, default: nil
  attr :channel_form, :any, default: nil
  attr :show_channel_form?, :boolean, default: false
  attr :channel_action_menu_id, :integer, default: nil
  attr :renaming_channel_id, :integer, default: nil
  attr :channel_rename_form, :any, default: nil
  attr :context_menu_position, :map, default: nil
  attr :current_scope, :any, default: nil
  attr :main_state, :atom, default: :no_workspace
  attr :invite_form, :any, default: nil
  attr :invite_url, :string, default: nil

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
            phx-hook={selected_workspace?(workspace, @selected_workspace) && "ContextMenu"}
            class={[
              "flex min-h-11 w-full shrink-0 items-center rounded px-3 text-sm font-semibold shadow-sm ring-1 transition hover:-translate-y-0.5",
              selected_workspace?(workspace, @selected_workspace) &&
                "bg-primary text-primary-content ring-primary",
              !selected_workspace?(workspace, @selected_workspace) &&
                "bg-base-100 ring-base-300 hover:bg-primary hover:text-primary-content"
            ]}
            data-stream-id={dom_id}
            data-context-menu-type="workspace"
            data-context-menu-id={workspace.id}
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
              <div class="relative flex items-center justify-between gap-2">
                <%= if @renaming_workspace_id == @selected_workspace.id && @workspace_rename_form do %>
                  <.form
                    for={@workspace_rename_form}
                    id={"workspace-#{@selected_workspace.id}-rename-form"}
                    phx-submit="rename_workspace"
                    phx-value-workspace_id={@selected_workspace.id}
                    class="min-w-0 flex-1"
                  >
                    <.input
                      field={@workspace_rename_form[:name]}
                      type="text"
                      label="Workspace name"
                      autocomplete="off"
                    />
                  </.form>
                <% else %>
                  <p id="selected-workspace-name" class="min-w-0 truncate text-sm font-semibold">
                    {@selected_workspace.name}
                  </p>
                <% end %>
                <.link
                  :if={can_create_workspace_invite?(@selected_workspace, @current_scope)}
                  id={"workspace-#{@selected_workspace.id}-invite-new"}
                  navigate={~p"/workspaces/#{@selected_workspace.id}/invites/new"}
                  class="btn btn-square btn-xs btn-ghost shrink-0 transition hover:scale-105"
                  aria-label={"Create invite for #{@selected_workspace.name}"}
                >
                  <.icon name="hero-user-plus" class="size-4" />
                </.link>
                <button
                  id={"workspace-#{@selected_workspace.id}-actions"}
                  type="button"
                  class="btn btn-square btn-xs btn-ghost shrink-0 transition hover:scale-105"
                  phx-click="open_workspace_actions"
                  phx-value-workspace_id={@selected_workspace.id}
                  aria-label={"Open #{@selected_workspace.name} workspace actions"}
                >
                  <.icon name="hero-ellipsis-horizontal" class="size-4" />
                </button>
                <div
                  :if={@workspace_action_menu_id == @selected_workspace.id}
                  id={"workspace-#{@selected_workspace.id}-menu"}
                  style={context_menu_style(@context_menu_position)}
                  class={menu_class(@context_menu_position, "absolute right-0 top-8", "w-40")}
                  phx-click-away="close_context_menu"
                  phx-window-keydown="close_context_menu"
                  phx-key="escape"
                >
                  <button
                    id={"workspace-#{@selected_workspace.id}-rename"}
                    type="button"
                    class="block w-full rounded px-3 py-2 text-left text-sm transition hover:bg-base-200"
                    phx-click="begin_workspace_rename"
                    phx-value-workspace_id={@selected_workspace.id}
                  >
                    Rename
                  </button>
                  <button
                    :if={workspace_owner?(@selected_workspace, @current_scope)}
                    id={"workspace-#{@selected_workspace.id}-delete"}
                    type="button"
                    class="block w-full rounded px-3 py-2 text-left text-sm text-error transition hover:bg-error/10"
                    phx-click="delete_workspace"
                    phx-value-workspace_id={@selected_workspace.id}
                    phx-confirm="Delete this workspace? The workspace and all contained channels/messages will be removed."
                  >
                    Delete workspace
                  </button>
                  <button
                    :if={!workspace_owner?(@selected_workspace, @current_scope)}
                    id={"workspace-#{@selected_workspace.id}-leave"}
                    type="button"
                    class="block w-full rounded px-3 py-2 text-left text-sm text-error transition hover:bg-error/10"
                    phx-click="leave_workspace"
                    phx-value-workspace_id={@selected_workspace.id}
                    phx-confirm="Leave this workspace? You will lose access and need a new invite to return."
                  >
                    Leave workspace
                  </button>
                </div>
              </div>
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
              <div :for={{dom_id, channel} <- @channel_stream} id={dom_id}>
                <div
                  id={"channel-#{channel.id}"}
                  aria-current={selected_channel_aria(channel, @selected_channel)}
                  phx-hook="ContextMenu"
                  data-context-menu-type="channel"
                  data-context-menu-id={channel.id}
                  class={[
                    "group relative flex items-center gap-1 rounded text-sm transition",
                    selected_channel?(channel, @selected_channel) &&
                      "bg-base-300 font-semibold text-base-content",
                    !selected_channel?(channel, @selected_channel) &&
                      "text-base-content/70 hover:bg-base-300 hover:text-base-content"
                  ]}
                >
                  <%= if @renaming_channel_id == channel.id && @channel_rename_form do %>
                    <.form
                      for={@channel_rename_form}
                      id={"channel-#{channel.id}-rename-form"}
                      phx-submit="rename_channel"
                      phx-value-channel_id={channel.id}
                      class="min-w-0 flex-1 px-2 py-1"
                    >
                      <.input
                        field={@channel_rename_form[:name]}
                        type="text"
                        label="Channel name"
                        autocomplete="off"
                      />
                    </.form>
                  <% else %>
                    <.link
                      navigate={~p"/workspaces/#{@selected_workspace.id}/channels/#{channel.id}"}
                      class="min-w-0 flex-1 truncate px-3 py-2"
                    >
                      # {channel.name}
                    </.link>
                  <% end %>
                  <button
                    id={"channel-#{channel.id}-actions"}
                    type="button"
                    class="btn btn-square btn-xs btn-ghost mr-1 opacity-80 transition hover:opacity-100"
                    phx-click="open_channel_actions"
                    phx-value-channel_id={channel.id}
                    aria-label={"Open #{channel.name} channel actions"}
                  >
                    <.icon name="hero-ellipsis-horizontal" class="size-4" />
                  </button>
                  <div
                    :if={@channel_action_menu_id == channel.id}
                    id={"channel-#{channel.id}-menu"}
                    style={context_menu_style(@context_menu_position)}
                    class={menu_class(@context_menu_position, "absolute mt-10 ml-8", "w-36")}
                    phx-click-away="close_context_menu"
                    phx-window-keydown="close_context_menu"
                    phx-key="escape"
                  >
                    <button
                      id={"channel-#{channel.id}-rename"}
                      type="button"
                      class="block w-full rounded px-3 py-2 text-left text-sm transition hover:bg-base-200"
                      phx-click="begin_channel_rename"
                      phx-value-channel_id={channel.id}
                    >
                      Rename
                    </button>
                    <button
                      :if={@selected_workspace.default_channel_id != channel.id}
                      id={"channel-#{channel.id}-delete"}
                      type="button"
                      class="block w-full rounded px-3 py-2 text-left text-sm text-error transition hover:bg-error/10"
                      phx-click="delete_channel"
                      phx-value-channel_id={channel.id}
                      phx-confirm="Delete this channel? The channel and future messages in it will be removed."
                    >
                      Delete
                    </button>
                  </div>
                </div>
              </div>
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
              <p id="selected-channel-title" class="text-sm font-semibold">
                # {@selected_channel.name}
              </p>
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
          <% :invite -> %>
            <section
              id="workspace-invite-main"
              class="mx-auto flex min-h-full w-full max-w-2xl items-center"
            >
              <div class="w-full rounded border border-base-300 bg-base-100 p-6 shadow-sm">
                <p class="text-xs font-semibold uppercase tracking-wide text-primary">
                  Invite people
                </p>
                <h1 class="mt-2 text-2xl font-semibold tracking-tight">
                  Create an invite for {@selected_workspace.name}
                </h1>
                <p class="mt-2 text-sm text-base-content/60">
                  Generate a fresh link that expires in 30 minutes.
                </p>

                <.form
                  for={@invite_form}
                  id="workspace-invite-create-form"
                  phx-submit="create_workspace_invite"
                  class="mt-6"
                >
                  <.button type="submit" class="btn btn-primary">
                    Create invite link
                  </.button>
                </.form>

                <div :if={@invite_url} id="workspace-invite-result" class="mt-6 space-y-2">
                  <label
                    for="workspace-invite-url"
                    class="text-xs font-semibold uppercase tracking-wide text-base-content/50"
                  >
                    Invite link
                  </label>
                  <div class="flex gap-2">
                    <input
                      id="workspace-invite-url"
                      type="text"
                      value={@invite_url}
                      readonly
                      class="input input-bordered min-w-0 flex-1 select-text font-mono text-sm"
                    />
                    <button
                      id="workspace-invite-copy"
                      type="button"
                      class="btn btn-square btn-outline"
                      aria-label="Copy invite link"
                      phx-hook="ClipboardCopy"
                      phx-update="ignore"
                      data-copy-target="workspace-invite-url"
                    >
                      <.icon name="hero-clipboard-document" class="size-4" />
                    </button>
                  </div>
                </div>
              </div>
            </section>
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

  defp workspace_owner?(workspace, current_scope) do
    current_scope && current_scope.user && workspace.owner_id == current_scope.user.id
  end

  defp can_create_workspace_invite?(workspace, current_scope) do
    Workspaces.can_create_workspace_invite?(current_scope, workspace)
  end

  defp context_menu_style(%{x: x, y: y}), do: "left: #{x}px; top: #{y}px;"
  defp context_menu_style(_position), do: nil

  defp menu_class(nil, anchor_class, width_class),
    do: [
      anchor_class,
      "z-20",
      width_class,
      "rounded border border-base-300 bg-base-100 p-1 shadow-lg"
    ]

  defp menu_class(_position, _anchor_class, width_class),
    do: ["fixed z-50", width_class, "rounded border border-base-300 bg-base-100 p-1 shadow-lg"]

  defp user_initial(user) do
    user.username
    |> String.first()
    |> String.upcase()
  end

  defp main_class(:channel), do: "flex min-h-0 flex-col bg-base-100"
  defp main_class(_state), do: "min-h-0 overflow-auto bg-base-100 p-6"
end
