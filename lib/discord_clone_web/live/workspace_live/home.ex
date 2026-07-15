defmodule DiscordCloneWeb.WorkspaceLive.Home do
  use DiscordCloneWeb, :live_view

  alias DiscordClone.Workspaces
  alias DiscordCloneWeb.WorkspaceLive.Shell
  alias DiscordCloneWeb.WorkspaceLive.WorkspaceManagementEvents

  @impl true
  def mount(_params, _session, socket) do
    {:ok, workspaces} = Workspaces.list_workspaces(socket.assigns.current_scope)

    socket =
      socket
      |> assign(
        :workspace_form,
        WorkspaceManagementEvents.workspace_form(socket.assigns.current_scope)
      )
      |> assign(:show_workspace_form?, workspaces == [])
      |> stream(:workspaces, workspaces)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Shell.app
        workspace_stream={@streams.workspaces}
        workspace_form={@workspace_form}
        show_workspace_form?={@show_workspace_form?}
        current_scope={@current_scope}
        unread_activity_count={@unread_activity_count}
        main_state={:no_workspace}
      />
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("show_workspace_form", _params, socket) do
    WorkspaceManagementEvents.show_workspace_form(socket)
  end

  def handle_event("cancel_workspace_form", _params, socket) do
    WorkspaceManagementEvents.cancel_workspace_form(socket)
  end

  def handle_event("create_workspace", params, socket) do
    WorkspaceManagementEvents.create_workspace(socket, params)
  end
end
