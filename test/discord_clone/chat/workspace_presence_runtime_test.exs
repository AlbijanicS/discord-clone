defmodule DiscordClone.Chat.WorkspacePresenceRuntimeTest do
  use DiscordClone.DataCase, async: false

  alias DiscordClone.Chat.{WorkspaceServer, WorkspaceSupervisor}

  describe "workspace presence runtime supervision" do
    test "application starts the workspace presence registry and supervisor" do
      assert is_pid(Process.whereis(DiscordClone.Chat.WorkspaceRegistry))
      assert is_pid(Process.whereis(DiscordClone.Chat.WorkspaceSupervisor))
    end

    test "starts and finds a workspace presence runtime by durable workspace ID" do
      workspace_id = System.unique_integer([:positive])

      assert {:ok, pid} = WorkspaceSupervisor.start_workspace(workspace_id)
      assert WorkspaceServer.whereis(workspace_id) == pid
      assert :sys.get_state(pid) == %{workspace_id: workspace_id}
    end

    test "starting the same workspace runtime twice returns the active process" do
      workspace_id = System.unique_integer([:positive])

      assert {:ok, first_pid} = WorkspaceSupervisor.start_workspace(workspace_id)
      assert {:ok, second_pid} = WorkspaceSupervisor.start_workspace(workspace_id)

      assert second_pid == first_pid
      assert WorkspaceServer.whereis(workspace_id) == first_pid
    end

    test "supervision restarts a workspace runtime under the same workspace ID" do
      workspace_id = System.unique_integer([:positive])
      assert {:ok, pid} = WorkspaceSupervisor.start_workspace(workspace_id)

      ref = Process.monitor(pid)
      Process.exit(pid, :kill)

      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
      _ = :sys.get_state(DiscordClone.Chat.WorkspaceSupervisor)

      restarted_pid = WorkspaceServer.whereis(workspace_id)
      assert is_pid(restarted_pid)
      assert restarted_pid != pid
      assert :sys.get_state(restarted_pid) == %{workspace_id: workspace_id}
    end
  end
end
