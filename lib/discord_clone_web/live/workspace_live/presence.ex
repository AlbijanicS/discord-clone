defmodule DiscordCloneWeb.WorkspaceLive.Presence do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1]

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
end
