defmodule DiscordClone.Chat.ChannelSupervisor do
  @moduledoc false

  alias DiscordClone.Chat.ChannelServer

  def start_channel(channel_id) do
    case DynamicSupervisor.start_child(__MODULE__, {ChannelServer, channel_id}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end
end
