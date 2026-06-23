defmodule DiscordClone.Chat.WorkspaceServer do
  @moduledoc false

  use GenServer

  alias DiscordClone.Chat.WorkspaceRegistry

  def start_link(workspace_id) do
    GenServer.start_link(__MODULE__, workspace_id, name: via_tuple(workspace_id))
  end

  def whereis(workspace_id) do
    case Registry.lookup(WorkspaceRegistry, workspace_id) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  @impl true
  def init(workspace_id) do
    {:ok, %{workspace_id: workspace_id}}
  end

  defp via_tuple(workspace_id) do
    {:via, Registry, {WorkspaceRegistry, workspace_id}}
  end
end
