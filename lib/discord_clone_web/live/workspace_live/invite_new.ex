defmodule DiscordCloneWeb.WorkspaceLive.InviteNew do
  use DiscordCloneWeb, :live_view

  alias DiscordClone.Workspaces
  alias DiscordCloneWeb.WorkspaceLive.Shell

  @impl true
  def mount(%{"workspace_id" => workspace_id}, _session, socket) do
    with {:ok, workspace} <-
           Workspaces.fetch_workspace(socket.assigns.current_scope, workspace_id),
         {:ok, workspaces} <- Workspaces.list_workspaces(socket.assigns.current_scope),
         {:ok, channels} <- Workspaces.list_channels(socket.assigns.current_scope, workspace_id) do
      socket =
        socket
        |> assign(:selected_workspace, workspace)
        |> assign(:workspace_form, workspace_form(socket.assigns.current_scope))
        |> assign(:show_workspace_form?, false)
        |> assign(:workspace_action_menu_id, nil)
        |> assign(:renaming_workspace_id, nil)
        |> assign(:workspace_rename_form, nil)
        |> assign(:channel_form, channel_form(workspace.id))
        |> assign(:show_channel_form?, false)
        |> assign(:context_menu_position, nil)
        |> assign(:invite_form, invite_form())
        |> assign(:invite_url, nil)
        |> stream(:workspaces, workspaces)
        |> stream(:channels, channels)

      {:ok, socket}
    else
      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Workspace not found or you do not have access.")
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
        workspace_form={@workspace_form}
        show_workspace_form?={@show_workspace_form?}
        workspace_action_menu_id={@workspace_action_menu_id}
        renaming_workspace_id={@renaming_workspace_id}
        workspace_rename_form={@workspace_rename_form}
        channel_form={@channel_form}
        show_channel_form?={@show_channel_form?}
        context_menu_position={@context_menu_position}
        current_scope={@current_scope}
        invite_form={@invite_form}
        invite_url={@invite_url}
        main_state={:invite}
      />
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("show_workspace_form", _params, socket) do
    {:noreply, assign(socket, :show_workspace_form?, true)}
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

  def handle_event("create_channel", %{"channel" => channel_params}, socket) do
    workspace_id = socket.assigns.selected_workspace.id

    case Workspaces.create_channel(socket.assigns.current_scope, workspace_id, channel_params) do
      {:ok, channel} ->
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

  def handle_event("create_workspace_invite", params, socket) do
    invite_params = Map.get(params, "invite", %{})
    workspace_id = socket.assigns.selected_workspace.id

    case Workspaces.create_workspace_invite(
           socket.assigns.current_scope,
           workspace_id,
           invite_params
         ) do
      {:ok, invite} ->
        {:noreply,
         socket
         |> assign(:invite_form, invite_form())
         |> assign(:invite_url, invite_url(invite))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Invite link could not be created.")}
    end
  end

  def handle_event("open_workspace_actions", %{"workspace_id" => workspace_id}, socket) do
    {:noreply,
     socket
     |> assign(:workspace_action_menu_id, String.to_integer(workspace_id))
     |> assign(:context_menu_position, nil)}
  end

  def handle_event("close_context_menu", _params, socket) do
    {:noreply,
     socket
     |> assign(:workspace_action_menu_id, nil)
     |> assign(:context_menu_position, nil)}
  end

  defp workspace_form(scope, attrs \\ %{}) do
    scope
    |> Workspaces.change_workspace(attrs)
    |> to_form(as: :workspace)
  end

  defp channel_form(workspace_id, attrs \\ %{}) do
    workspace_id
    |> Workspaces.change_channel(attrs)
    |> to_form(as: :channel)
  end

  defp invite_form(attrs \\ %{}) do
    attrs
    |> Workspaces.change_workspace_invite()
    |> to_form(as: :invite)
  end

  defp invite_url(invite) do
    DiscordCloneWeb.Endpoint.url() <> "/invites/#{invite.code}"
  end
end
