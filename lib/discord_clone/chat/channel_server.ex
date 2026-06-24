defmodule DiscordClone.Chat.ChannelServer do
  @moduledoc false

  use GenServer

  alias DiscordClone.Chat.ChannelRegistry

  def start_link(channel_id) do
    GenServer.start_link(__MODULE__, channel_id, name: via_tuple(channel_id))
  end

  def whereis(channel_id) do
    case Registry.lookup(ChannelRegistry, channel_id) do
      [{pid, _value}] -> if Process.alive?(pid), do: pid
      [] -> nil
    end
  end

  @impl true
  def init(channel_id) do
    {:ok, %{channel_id: channel_id}}
  end

  defp via_tuple(channel_id) do
    {:via, Registry, {ChannelRegistry, channel_id}}
  end
end
