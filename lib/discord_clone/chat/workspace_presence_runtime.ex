defmodule DiscordClone.Chat.WorkspacePresenceRuntime do
  @moduledoc false

  alias DiscordClone.Chat.{WorkspaceServer, WorkspaceSupervisor}

  def whereis(workspace_id), do: WorkspaceServer.whereis(workspace_id)

  def start_workspace(workspace_id), do: WorkspaceSupervisor.start_workspace(workspace_id)

  def online_user_ids(workspace_id) do
    case whereis(workspace_id) do
      nil -> []
      pid -> WorkspaceServer.online_user_ids(pid)
    end
  end

  def join(workspace_id, user_id, live_view_pid) when is_pid(live_view_pid) do
    with {:ok, workspace_pid} <- start_workspace(workspace_id) do
      WorkspaceServer.join(workspace_pid, user_id, live_view_pid)
    end
  end

  def stop_workspace(workspace_id) do
    case whereis(workspace_id) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(WorkspaceSupervisor, pid)
    end
  end
end
