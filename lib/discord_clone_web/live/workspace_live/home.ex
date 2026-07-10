defmodule DiscordCloneWeb.WorkspaceLive.Home do
  use DiscordCloneWeb, :live_view

  alias DiscordClone.Workspaces
  alias DiscordCloneWeb.WorkspaceLive.Shell

  @impl true
  def mount(_params, _session, socket) do
    {:ok, workspaces} = Workspaces.list_workspaces(socket.assigns.current_scope)

    socket =
      socket
      |> assign(:workspace_form, workspace_form(socket.assigns.current_scope))
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
        main_state={:no_workspace}
      />
    </Layouts.app>
    """
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
        {:ok, workspaces} = Workspaces.list_workspaces(socket.assigns.current_scope)

        socket =
          socket
          |> assign(:workspace_form, workspace_form(socket.assigns.current_scope))
          |> assign(:show_workspace_form?, workspaces == [])
          |> stream(:workspaces, workspaces, reset: true)

        {:noreply, push_navigate(socket, to: ~p"/workspaces/#{workspace.id}")}

      {:error, :invalid_workspace, changeset} ->
        {:noreply,
         socket
         |> assign(:show_workspace_form?, true)
         |> assign(:workspace_form, to_form(changeset, as: :workspace, action: :insert))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Workspace could not be created.")}
    end
  end

  defp workspace_form(scope, attrs \\ %{}) do
    scope
    |> Workspaces.change_workspace(attrs)
    |> to_form(as: :workspace)
  end
end
