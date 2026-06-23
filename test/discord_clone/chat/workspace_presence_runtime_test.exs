defmodule DiscordClone.Chat.WorkspacePresenceRuntimeTest do
  use DiscordClone.DataCase, async: false

  alias DiscordClone.Chat.{WorkspacePresence, WorkspaceServer, WorkspaceSupervisor}

  describe "workspace presence runtime supervision" do
    test "application starts the workspace presence registry and supervisor" do
      assert is_pid(Process.whereis(DiscordClone.Chat.WorkspaceRegistry))
      assert is_pid(Process.whereis(DiscordClone.Chat.WorkspaceSupervisor))
    end

    test "starts and finds a workspace presence runtime by durable workspace ID" do
      workspace_id = System.unique_integer([:positive])

      assert {:ok, pid} = WorkspaceSupervisor.start_workspace(workspace_id)
      assert WorkspaceServer.whereis(workspace_id) == pid
      assert WorkspaceServer.online_user_ids(pid) == []
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
      assert WorkspaceServer.online_user_ids(restarted_pid) == []
    end
  end

  describe "workspace presence connections" do
    test "joining presence for a user and pid records that user as online" do
      workspace_id = System.unique_integer([:positive])
      user_id = System.unique_integer([:positive])
      live_view_pid = self()

      assert {:ok, workspace_pid} = WorkspaceSupervisor.start_workspace(workspace_id)

      assert :ok = WorkspaceServer.join(workspace_pid, user_id, live_view_pid)
      assert WorkspaceServer.online_user_ids(workspace_pid) == [user_id]
    end

    test "joining presence for the same user and same pid is idempotent" do
      workspace_id = System.unique_integer([:positive])
      user_id = System.unique_integer([:positive])
      live_view_pid = self()

      assert {:ok, workspace_pid} = WorkspaceSupervisor.start_workspace(workspace_id)

      assert :ok = WorkspaceServer.join(workspace_pid, user_id, live_view_pid)
      assert :ok = WorkspaceServer.join(workspace_pid, user_id, live_view_pid)

      assert WorkspaceServer.online_user_ids(workspace_pid) == [user_id]
    end

    test "joining presence for the same user from multiple pids keeps one online user id" do
      workspace_id = System.unique_integer([:positive])
      user_id = System.unique_integer([:positive])
      first_live_view_pid = self()
      second_live_view_pid = start_live_view_process()

      assert {:ok, workspace_pid} = WorkspaceSupervisor.start_workspace(workspace_id)

      assert :ok = WorkspaceServer.join(workspace_pid, user_id, first_live_view_pid)
      assert :ok = WorkspaceServer.join(workspace_pid, user_id, second_live_view_pid)

      assert WorkspaceServer.online_user_ids(workspace_pid) == [user_id]
    end

    test "joining presence for different users tracks each user independently" do
      workspace_id = System.unique_integer([:positive])
      first_user_id = System.unique_integer([:positive])
      second_user_id = System.unique_integer([:positive])
      first_live_view_pid = self()
      second_live_view_pid = start_live_view_process()

      assert {:ok, workspace_pid} = WorkspaceSupervisor.start_workspace(workspace_id)

      assert :ok = WorkspaceServer.join(workspace_pid, second_user_id, second_live_view_pid)
      assert :ok = WorkspaceServer.join(workspace_pid, first_user_id, first_live_view_pid)

      assert WorkspaceServer.online_user_ids(workspace_pid) ==
               Enum.sort([first_user_id, second_user_id])
    end

    test "when the last pid for a user exits the user is removed from online state" do
      workspace_id = System.unique_integer([:positive])
      user_id = System.unique_integer([:positive])
      live_view_pid = start_live_view_process()

      assert {:ok, workspace_pid} = WorkspaceSupervisor.start_workspace(workspace_id)
      assert :ok = WorkspaceServer.join(workspace_pid, user_id, live_view_pid)
      assert WorkspaceServer.online_user_ids(workspace_pid) == [user_id]

      ref = Process.monitor(live_view_pid)
      send(live_view_pid, :stop)

      assert_receive {:DOWN, ^ref, :process, ^live_view_pid, :normal}
      _ = :sys.get_state(workspace_pid)

      assert WorkspaceServer.online_user_ids(workspace_pid) == []
    end

    test "when one of several pids for a user exits the user remains online" do
      workspace_id = System.unique_integer([:positive])
      user_id = System.unique_integer([:positive])
      first_live_view_pid = start_live_view_process()
      second_live_view_pid = start_live_view_process()

      assert {:ok, workspace_pid} = WorkspaceSupervisor.start_workspace(workspace_id)
      assert :ok = WorkspaceServer.join(workspace_pid, user_id, first_live_view_pid)
      assert :ok = WorkspaceServer.join(workspace_pid, user_id, second_live_view_pid)
      assert WorkspaceServer.online_user_ids(workspace_pid) == [user_id]

      ref = Process.monitor(first_live_view_pid)
      send(first_live_view_pid, :stop)

      assert_receive {:DOWN, ^ref, :process, ^first_live_view_pid, :normal}
      _ = :sys.get_state(workspace_pid)

      assert WorkspaceServer.online_user_ids(workspace_pid) == [user_id]
    end

    test "listing online user ids does not change runtime state" do
      workspace_id = System.unique_integer([:positive])
      user_id = System.unique_integer([:positive])
      live_view_pid = self()

      assert {:ok, workspace_pid} = WorkspaceSupervisor.start_workspace(workspace_id)
      assert :ok = WorkspaceServer.join(workspace_pid, user_id, live_view_pid)

      assert WorkspaceServer.online_user_ids(workspace_pid) == [user_id]
      assert WorkspaceServer.online_user_ids(workspace_pid) == [user_id]
    end
  end

  describe "workspace presence broadcasts" do
    test "first connection for a user broadcasts that workspace user joined" do
      workspace_id = System.unique_integer([:positive])
      user_id = System.unique_integer([:positive])
      live_view_pid = self()

      assert {:ok, workspace_pid} = WorkspaceSupervisor.start_workspace(workspace_id)
      assert :ok = WorkspacePresence.subscribe(workspace_id)

      assert :ok = WorkspaceServer.join(workspace_pid, user_id, live_view_pid)

      assert_receive {:workspace_user_joined,
                      %{workspace_id: ^workspace_id, user_id: ^user_id} = payload}

      refute Map.has_key?(payload, :user)
      refute Map.has_key?(payload, :members)
    end

    test "duplicate connection for an already-online user does not broadcast another joined event" do
      workspace_id = System.unique_integer([:positive])
      user_id = System.unique_integer([:positive])
      live_view_pid = self()

      assert {:ok, workspace_pid} = WorkspaceSupervisor.start_workspace(workspace_id)
      assert :ok = WorkspacePresence.subscribe(workspace_id)
      assert :ok = WorkspaceServer.join(workspace_pid, user_id, live_view_pid)
      assert_receive {:workspace_user_joined, %{workspace_id: ^workspace_id, user_id: ^user_id}}

      assert :ok = WorkspaceServer.join(workspace_pid, user_id, live_view_pid)

      refute_receive {:workspace_user_joined, _payload}, 50
    end

    test "additional connection for an already-online user does not broadcast another joined event" do
      workspace_id = System.unique_integer([:positive])
      user_id = System.unique_integer([:positive])
      first_live_view_pid = self()
      second_live_view_pid = start_live_view_process()

      assert {:ok, workspace_pid} = WorkspaceSupervisor.start_workspace(workspace_id)
      assert :ok = WorkspacePresence.subscribe(workspace_id)
      assert :ok = WorkspaceServer.join(workspace_pid, user_id, first_live_view_pid)
      assert_receive {:workspace_user_joined, %{workspace_id: ^workspace_id, user_id: ^user_id}}

      assert :ok = WorkspaceServer.join(workspace_pid, user_id, second_live_view_pid)

      refute_receive {:workspace_user_joined, _payload}, 50
    end

    test "last disconnect for a user broadcasts that workspace user left" do
      workspace_id = System.unique_integer([:positive])
      user_id = System.unique_integer([:positive])
      live_view_pid = start_live_view_process()

      assert {:ok, workspace_pid} = WorkspaceSupervisor.start_workspace(workspace_id)
      assert :ok = WorkspacePresence.subscribe(workspace_id)
      assert :ok = WorkspaceServer.join(workspace_pid, user_id, live_view_pid)
      assert_receive {:workspace_user_joined, %{workspace_id: ^workspace_id, user_id: ^user_id}}

      ref = Process.monitor(live_view_pid)
      send(live_view_pid, :stop)

      assert_receive {:DOWN, ^ref, :process, ^live_view_pid, :normal}
      _ = :sys.get_state(workspace_pid)

      assert_receive {:workspace_user_left,
                      %{workspace_id: ^workspace_id, user_id: ^user_id} = payload}

      refute Map.has_key?(payload, :user)
      refute Map.has_key?(payload, :members)
    end

    test "non-last disconnect for a user does not broadcast that workspace user left" do
      workspace_id = System.unique_integer([:positive])
      user_id = System.unique_integer([:positive])
      first_live_view_pid = start_live_view_process()
      second_live_view_pid = start_live_view_process()

      assert {:ok, workspace_pid} = WorkspaceSupervisor.start_workspace(workspace_id)
      assert :ok = WorkspacePresence.subscribe(workspace_id)
      assert :ok = WorkspaceServer.join(workspace_pid, user_id, first_live_view_pid)
      assert_receive {:workspace_user_joined, %{workspace_id: ^workspace_id, user_id: ^user_id}}
      assert :ok = WorkspaceServer.join(workspace_pid, user_id, second_live_view_pid)

      ref = Process.monitor(first_live_view_pid)
      send(first_live_view_pid, :stop)

      assert_receive {:DOWN, ^ref, :process, ^first_live_view_pid, :normal}
      _ = :sys.get_state(workspace_pid)

      refute_receive {:workspace_user_left, _payload}, 50
    end
  end

  defp start_live_view_process do
    start_supervised!(%{
      id: System.unique_integer([:positive]),
      start:
        {Task, :start_link,
         [
           fn ->
             receive do
               :stop -> :ok
             end
           end
         ]}
    })
  end
end
