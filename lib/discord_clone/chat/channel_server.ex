defmodule DiscordClone.Chat.ChannelServer do
  @moduledoc false

  use GenServer

  alias DiscordClone.Chat.ChannelRegistry

  def list_recent_messages(pid) when is_pid(pid) do
    GenServer.call(pid, :list_recent_messages)
  end

  def put_recent_message(pid, message) when is_pid(pid) do
    GenServer.call(pid, {:put_recent_message, message})
  end

  def child_spec(arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [arg]},
      restart: :temporary
    }
  end

  @spec start_link({any(), any()}) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link({channel_id, recent_messages}) do
    GenServer.start_link(__MODULE__, {channel_id, recent_messages}, name: via_tuple(channel_id))
  end

  def whereis(channel_id) do
    case Registry.lookup(ChannelRegistry, channel_id) do
      [{pid, _value}] -> if Process.alive?(pid), do: pid
      [] -> nil
    end
  end

  @impl true
  def init({channel_id, recent_messages}) do
    {:ok, %{channel_id: channel_id, recent_messages: recent_messages}}
  end

  @impl true
  def handle_call(:list_recent_messages, _from, state) do
    {:reply, {:ok, state.recent_messages}, state}
  end

  def handle_call({:put_recent_message, message}, _from, state) do
    recent_messages =
      state.recent_messages
      |> Enum.reject(&(&1.id == message.id))
      |> Kernel.++([message])
      |> Enum.take(-50)

    {:reply, :ok, %{state | recent_messages: recent_messages}}
  end

  defp via_tuple(channel_id) do
    {:via, Registry, {ChannelRegistry, channel_id}}
  end
end
