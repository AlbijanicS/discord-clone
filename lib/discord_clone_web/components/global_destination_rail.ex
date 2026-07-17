defmodule DiscordCloneWeb.GlobalDestinationRail do
  @moduledoc false

  use DiscordCloneWeb, :html

  attr :workspace_stream, :any, required: true
  attr :selected_workspace, :any, default: nil
  attr :workspace_form, :any, default: nil
  attr :show_workspace_form?, :boolean, default: false
  attr :direct_message_unread_count, :integer, default: 0

  def rail(assigns) do
    ~H"""
    <div id="global-destination-rail" class="contents">
      <aside
        id="workspace-sidebar"
        aria-label="Global destinations"
        class="flex min-h-0 flex-col items-center bg-base-300 p-3 shadow-[inset_-1px_0_0_rgb(255_255_255/0.03)]"
      >
        <.link
          id="global-direct-messages-destination"
          navigate={~p"/direct-messages"}
          aria-label="Direct Messages"
          title="Direct Messages"
          class={[
            "relative mb-3 flex size-12 shrink-0 items-center justify-center rounded-2xl",
            "bg-primary text-primary-content shadow-sm ring-1 ring-primary/40 transition duration-200",
            "hover:-translate-y-0.5 hover:rounded-xl hover:shadow-md focus-visible:outline-none",
            "focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-base-300",
            "phx-click-loading:pointer-events-none phx-click-loading:animate-pulse"
          ]}
        >
          <.icon name="hero-chat-bubble-left-right" class="size-6" />
          <span
            :if={@direct_message_unread_count > 0}
            id="direct-messages-unread-count"
            aria-label={direct_message_unread_label(@direct_message_unread_count)}
            class="absolute -right-1.5 -top-1.5 flex min-w-5 items-center justify-center rounded-full bg-error px-1.5 text-[0.6875rem] font-bold leading-5 text-error-content shadow-sm ring-2 ring-base-300"
          >
            {@direct_message_unread_count}
          </span>
        </.link>

        <div class="mb-3 h-px w-8 shrink-0 bg-base-content/15" aria-hidden="true"></div>

        <button
          :if={@workspace_form && !@show_workspace_form?}
          id="workspace-create-toggle"
          type="button"
          class={[
            "mb-3 inline-flex size-9 shrink-0 items-center justify-center rounded-xl",
            "text-base-content/60 transition duration-150 hover:scale-105 hover:bg-base-100",
            "hover:text-base-content focus-visible:outline-none focus-visible:ring-2",
            "focus-visible:ring-primary/60"
          ]}
          phx-click="show_workspace_form"
          aria-label="Create workspace"
          title="Create workspace"
        >
          <.icon name="hero-plus" class="size-4" />
        </button>

        <div
          id="workspaces"
          phx-update="stream"
          class="flex min-h-0 w-full justify-center gap-2 overflow-x-auto lg:flex-col lg:items-center lg:overflow-y-auto"
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
            title={workspace.name}
            class={[
              "flex size-12 shrink-0 items-center justify-center rounded-lg text-base font-bold shadow-sm ring-1 transition hover:-translate-y-0.5",
              selected_workspace?(workspace, @selected_workspace) &&
                "bg-primary text-primary-content ring-primary",
              !selected_workspace?(workspace, @selected_workspace) &&
                "bg-base-100 ring-base-300 hover:bg-primary hover:text-primary-content"
            ]}
            data-stream-id={dom_id}
            data-workspace-id={workspace.id}
            data-context-menu-type="workspace"
            data-context-menu-id={workspace.id}
            aria-label={"Open #{workspace.name}"}
          >
            <span aria-hidden="true">{workspace_initial(workspace)}</span>
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
          <div class="grid grid-cols-2 gap-2">
            <button
              id="workspace-create-cancel"
              type="button"
              class={[
                "inline-flex h-9 items-center justify-center rounded-lg px-3 text-xs font-semibold",
                "text-base-content/65 transition hover:bg-base-100 hover:text-base-content",
                "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/60"
              ]}
              phx-click="cancel_workspace_form"
            >
              Cancel
            </button>
            <.button
              type="submit"
              class={[
                "inline-flex h-9 items-center justify-center rounded-lg bg-primary px-3",
                "text-xs font-semibold text-primary-content shadow-sm transition",
                "hover:-translate-y-0.5 hover:bg-primary/90 focus-visible:outline-none",
                "focus-visible:ring-2 focus-visible:ring-primary/60"
              ]}
            >
              Create
            </.button>
          </div>
        </.form>
      </aside>
    </div>
    """
  end

  defp workspace_dom_id(_dom_id, workspace, selected_workspace)
       when not is_nil(selected_workspace) and workspace.id == selected_workspace.id,
       do: "workspace-#{workspace.id}"

  defp workspace_dom_id(dom_id, _workspace, _selected_workspace), do: dom_id

  defp selected_workspace?(workspace, selected_workspace),
    do: selected_workspace && workspace.id == selected_workspace.id

  defp selected_workspace_aria(workspace, selected_workspace) do
    if selected_workspace?(workspace, selected_workspace), do: "page"
  end

  defp workspace_initial(workspace) do
    workspace.name
    |> String.trim()
    |> String.first()
    |> case do
      nil -> "?"
      initial -> String.upcase(initial)
    end
  end

  defp direct_message_unread_label(1), do: "1 unread Direct Message"
  defp direct_message_unread_label(count), do: "#{count} unread Direct Messages"
end
