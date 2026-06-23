defmodule DiscordCloneWeb.WorkspaceLive.Presence do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1, stream: 4]

  alias DiscordClone.Chat

  def join_workspace(socket, workspace_id) do
    if connected?(socket) do
      with :ok <- Chat.subscribe_to_workspace_presence(socket.assigns.current_scope, workspace_id),
           :ok <- Chat.join_workspace_presence(socket.assigns.current_scope, workspace_id),
           {:ok, online_user_ids} <-
             Chat.list_online_workspace_user_ids(socket.assigns.current_scope, workspace_id) do
        assign(socket, :online_user_ids, MapSet.new(online_user_ids))
      else
        {:error, _reason} -> assign(socket, :online_user_ids, MapSet.new())
      end
    else
      assign(socket, :online_user_ids, MapSet.new())
    end
  end

  def user_joined(socket, payload), do: update_online_user_ids(socket, payload, :join)
  def user_left(socket, payload), do: update_online_user_ids(socket, payload, :leave)

  defp update_online_user_ids(socket, %{workspace_id: workspace_id, user_id: user_id}, event)
       when event in [:join, :leave] do
    if selected_workspace_id(socket) == workspace_id do
      online_user_ids = Map.get(socket.assigns, :online_user_ids, MapSet.new())

      socket
      |> assign(:online_user_ids, update_user_id(online_user_ids, user_id, event))
      |> refresh_workspace_members()
    else
      socket
    end
  end

  defp update_online_user_ids(socket, _payload, _event), do: socket

  defp update_user_id(online_user_ids, user_id, :join), do: MapSet.put(online_user_ids, user_id)

  defp update_user_id(online_user_ids, user_id, :leave),
    do: MapSet.delete(online_user_ids, user_id)

  defp refresh_workspace_members(%{assigns: %{workspace_members: members}} = socket) do
    stream(socket, :workspace_members, members, reset: true)
  end

  defp refresh_workspace_members(socket), do: socket

  defp selected_workspace_id(%{assigns: %{selected_workspace: %{id: workspace_id}}}) do
    workspace_id
  end

  defp selected_workspace_id(_socket), do: nil
end
