defmodule DiscordClone.Chat.WorkspacePresence do
  @moduledoc false

  def subscribe(workspace_id) do
    Phoenix.PubSub.subscribe(DiscordClone.PubSub, topic(workspace_id))
  end

  def broadcast_user_joined(workspace_id, user_id) do
    broadcast(workspace_id, {:workspace_user_joined, payload(workspace_id, user_id)})
  end

  def broadcast_user_left(workspace_id, user_id) do
    broadcast(workspace_id, {:workspace_user_left, payload(workspace_id, user_id)})
  end

  defp broadcast(workspace_id, event) do
    Phoenix.PubSub.broadcast(DiscordClone.PubSub, topic(workspace_id), event)
  end

  defp payload(workspace_id, user_id) do
    %{workspace_id: workspace_id, user_id: user_id}
  end

  defp topic(workspace_id), do: "chat:workspace_presence:#{workspace_id}"
end
