defmodule DiscordCloneWeb.ChannelLive.Show do
  use DiscordCloneWeb, :live_view

  alias DiscordClone.Workspaces
  alias DiscordCloneWeb.WorkspaceLive.Shell

  @impl true
  def mount(%{"workspace_id" => workspace_id, "channel_id" => channel_id}, _session, socket) do
    with {:ok, workspace} <-
           Workspaces.fetch_workspace(socket.assigns.current_scope, workspace_id),
         {:ok, channel} <-
           Workspaces.fetch_channel(socket.assigns.current_scope, workspace_id, channel_id),
         {:ok, workspaces} <- Workspaces.list_workspaces(socket.assigns.current_scope),
         {:ok, channels} <- Workspaces.list_channels(socket.assigns.current_scope, workspace_id) do
      socket =
        socket
        |> assign(:selected_workspace, workspace)
        |> assign(:selected_channel, channel)
        |> assign(:channel_form, channel_form(workspace.id))
        |> assign(:show_channel_form?, false)
        |> stream(:workspaces, workspaces)
        |> stream(:channels, channels)

      {:ok, socket}
    else
      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Channel not found or you do not have access.")
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
        selected_channel={@selected_channel}
        channel_form={@channel_form}
        show_channel_form?={@show_channel_form?}
        current_scope={@current_scope}
        main_state={:channel}
      />
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("show_channel_form", _params, socket) do
    {:noreply, assign(socket, :show_channel_form?, true)}
  end

  def handle_event("create_channel", %{"channel" => channel_params}, socket) do
    workspace_id = socket.assigns.selected_workspace.id

    case Workspaces.create_channel(socket.assigns.current_scope, workspace_id, channel_params) do
      {:ok, channel} ->
        {:ok, channels} = Workspaces.list_channels(socket.assigns.current_scope, workspace_id)

        socket =
          socket
          |> assign(:channel_form, channel_form(workspace_id))
          |> assign(:show_channel_form?, false)
          |> stream(:channels, channels, reset: true)

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

  defp channel_form(workspace_id, attrs \\ %{}) do
    workspace_id
    |> Workspaces.change_channel(attrs)
    |> to_form(as: :channel)
  end
end
