defmodule DiscordClone.Chat.WorkspaceSupervisor do
  @moduledoc false

  alias DiscordClone.Chat.WorkspaceServer

  def start_workspace(workspace_id) do
    case DynamicSupervisor.start_child(__MODULE__, {WorkspaceServer, workspace_id}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end
end
