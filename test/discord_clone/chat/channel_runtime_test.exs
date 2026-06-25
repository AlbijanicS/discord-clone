defmodule DiscordClone.Chat.ChannelRuntimeTest do
  use DiscordClone.DataCase, async: false

  alias DiscordClone.Chat.{ChannelServer, ChannelSupervisor, Message}
  alias DiscordClone.{Repo, Workspaces}

  import DiscordClone.AccountsFixtures

  describe "channel runtime supervision" do
    test "application starts the channel registry and supervisor" do
      assert is_pid(Process.whereis(DiscordClone.Chat.ChannelRegistry))
      assert is_pid(Process.whereis(DiscordClone.Chat.ChannelSupervisor))
    end

    test "starts and finds a channel runtime by durable channel ID" do
      channel_id = System.unique_integer([:positive])

      assert {:ok, pid} = ChannelSupervisor.start_channel(channel_id)

      assert ChannelServer.whereis(channel_id) == pid
      assert %{channel_id: ^channel_id} = :sys.get_state(pid)
    end

    test "starts with a bounded recent message cache for rendering" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      base_time = ~U[2026-06-19 10:00:00Z]

      messages =
        for index <- 1..55 do
          insert_message!(
            workspace.default_channel_id,
            scope.user.id,
            "message #{index}",
            DateTime.add(base_time, index, :second)
          )
        end

      assert {:ok, pid} = ChannelSupervisor.start_channel(workspace.default_channel_id)
      assert {:ok, cached_messages} = ChannelServer.list_recent_messages(pid)

      assert Enum.map(cached_messages, & &1.id) == messages |> Enum.drop(5) |> Enum.map(& &1.id)
      assert Enum.map(cached_messages, & &1.content) == Enum.map(6..55, &"message #{&1}")
      assert Enum.all?(cached_messages, &Ecto.assoc_loaded?(&1.user))
      assert Enum.all?(cached_messages, &(&1.user.username == scope.user.username))
    end

    test "stops idle channel runtimes and removes their registration" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id

      put_channel_runtime_timeout(0)

      assert {:ok, pid} = DiscordClone.Chat.ensure_channel_runtime(scope, channel_id)
      ref = Process.monitor(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      assert ChannelServer.whereis(channel_id) == nil
    end

    test "restarts after idle shutdown and reloads recent persisted messages" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id

      first_message =
        insert_message!(channel_id, scope.user.id, "before idle", ~U[2026-06-19 10:00:00Z])

      put_channel_runtime_timeout(0)

      assert {:ok, first_pid} = DiscordClone.Chat.ensure_channel_runtime(scope, channel_id)
      ref = Process.monitor(first_pid)
      assert_receive {:DOWN, ^ref, :process, ^first_pid, :normal}
      assert ChannelServer.whereis(channel_id) == nil

      Application.put_env(
        :discord_clone,
        :channel_runtime_inactivity_timeout_ms,
        :timer.minutes(15)
      )

      second_message =
        insert_message!(channel_id, scope.user.id, "after idle", ~U[2026-06-19 10:01:00Z])

      assert {:ok, recent_messages} = DiscordClone.Chat.list_recent_messages(scope, channel_id)
      assert Enum.map(recent_messages, & &1.id) == [first_message.id, second_message.id]

      assert {:ok, second_pid} = DiscordClone.Chat.ensure_channel_runtime(scope, channel_id)
      assert second_pid != first_pid
      assert %{channel_id: ^channel_id} = :sys.get_state(second_pid)
    end

    test "stores typing state as user IDs mapped to deadlines and refreshes activity" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id
      user_id = scope.user.id

      assert {:ok, pid} = DiscordClone.Chat.ensure_channel_runtime(scope, channel_id)
      %{last_activity_at: initial_activity_at} = :sys.get_state(pid)

      assert :ok = DiscordClone.Chat.user_started_typing(scope, channel_id)

      state = :sys.get_state(pid)
      assert %{^user_id => deadline} = state.typing_users
      assert is_integer(deadline)
      refute match?(%{^user_id => %{id: _id}}, state.typing_users)
      assert state.last_activity_at >= initial_activity_at
    end
  end

  defp insert_message!(channel_id, user_id, content, inserted_at) do
    Repo.insert!(%Message{
      channel_id: channel_id,
      user_id: user_id,
      content: content,
      inserted_at: inserted_at,
      updated_at: inserted_at
    })
  end

  defp put_channel_runtime_timeout(timeout_ms) do
    previous = Application.get_env(:discord_clone, :channel_runtime_inactivity_timeout_ms)
    Application.put_env(:discord_clone, :channel_runtime_inactivity_timeout_ms, timeout_ms)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:discord_clone, :channel_runtime_inactivity_timeout_ms)
      else
        Application.put_env(:discord_clone, :channel_runtime_inactivity_timeout_ms, previous)
      end
    end)
  end
end
