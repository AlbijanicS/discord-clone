defmodule DiscordClone.Chat.ChannelRuntimeTest do
  use DiscordClone.DataCase, async: false

  alias DiscordClone.Chat.{ChannelServer, ChannelSupervisor}

  describe "channel runtime supervision" do
    test "application starts the channel registry and supervisor" do
      assert is_pid(Process.whereis(DiscordClone.Chat.ChannelRegistry))
      assert is_pid(Process.whereis(DiscordClone.Chat.ChannelSupervisor))
    end

    test "starts and finds a channel runtime by durable channel ID" do
      channel_id = System.unique_integer([:positive])

      assert {:ok, pid} = ChannelSupervisor.start_channel(channel_id)

      assert ChannelServer.whereis(channel_id) == pid
      assert :sys.get_state(pid) == %{channel_id: channel_id}
    end
  end
end
