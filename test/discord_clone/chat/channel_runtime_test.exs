defmodule DiscordClone.Chat.ChannelRuntimeTest do
  use DiscordClone.DataCase, async: false

  alias DiscordClone.Chat.{Message, Runtime}
  alias DiscordClone.{Repo, Workspaces}
  alias DiscordClone.Workspaces.Channel

  import DiscordClone.AccountsFixtures

  describe "channel runtime supervision" do
    test "starts and finds a channel runtime by durable channel ID" do
      channel_id = Ecto.UUID.generate()

      assert {:ok, pid} = Runtime.ensure_channel(channel_id)

      assert Runtime.channel_pid(channel_id) == pid
      assert Runtime.list_recent_messages(channel_id) == {:ok, []}
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

      assert {:ok, _pid} = Runtime.ensure_channel(workspace.default_channel_id)
      assert {:ok, cached_messages} = Runtime.list_recent_messages(workspace.default_channel_id)

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
      assert Runtime.channel_pid(channel_id) == nil
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
      assert Runtime.channel_pid(channel_id) == nil

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
      assert Runtime.channel_pid(channel_id) == second_pid
    end

    test "tracks typing user IDs and broadcasts typing started" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id
      user_id = scope.user.id

      assert :ok = DiscordClone.Chat.subscribe_to_channel_typing(scope, channel_id)

      assert :ok = DiscordClone.Chat.user_started_typing(scope, channel_id)
      assert {:ok, [^user_id]} = DiscordClone.Chat.list_typing_user_ids(scope, channel_id)

      assert_receive {:typing_started, %{channel_id: ^channel_id, user_id: ^user_id}}
    end

    test "repeated typing starts keep one typing user and do not rebroadcast started" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id
      user_id = scope.user.id

      put_channel_typing_timeout(1_000)

      assert :ok = DiscordClone.Chat.subscribe_to_channel_typing(scope, channel_id)
      assert :ok = DiscordClone.Chat.user_started_typing(scope, channel_id)
      assert_receive {:typing_started, %{channel_id: ^channel_id, user_id: ^user_id}}

      assert :ok = DiscordClone.Chat.user_started_typing(scope, channel_id)

      assert {:ok, [^user_id]} = DiscordClone.Chat.list_typing_user_ids(scope, channel_id)
      refute_receive {:typing_started, _payload}, 50
    end
  end

  defp insert_message!(channel_id, user_id, content, inserted_at) do
    inserted_at = %{inserted_at | microsecond: {elem(inserted_at.microsecond, 0), 6}}

    {:ok, message} =
      Repo.transaction(fn ->
        channel =
          Repo.one!(
            from channel in Channel,
              where: channel.id == ^channel_id,
              lock: "FOR UPDATE"
          )

        seq = channel.last_message_seq + 1

        message =
          Repo.insert!(%Message{
            channel_id: channel_id,
            user_id: user_id,
            content: content,
            seq: seq,
            inserted_at: inserted_at,
            updated_at: inserted_at
          })

        channel
        |> Ecto.Changeset.change(last_message_seq: seq)
        |> Repo.update!()

        message
      end)

    message
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

  defp put_channel_typing_timeout(timeout_ms) do
    previous = Application.get_env(:discord_clone, :channel_runtime_typing_timeout_ms)
    Application.put_env(:discord_clone, :channel_runtime_typing_timeout_ms, timeout_ms)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:discord_clone, :channel_runtime_typing_timeout_ms)
      else
        Application.put_env(:discord_clone, :channel_runtime_typing_timeout_ms, previous)
      end
    end)
  end
end
