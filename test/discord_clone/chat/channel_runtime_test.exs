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
end
