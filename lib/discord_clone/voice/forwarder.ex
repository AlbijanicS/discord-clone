defmodule DiscordClone.Voice.Forwarder do
  @moduledoc false

  use GenServer

  alias DiscordClone.Voice.{AdmissionServer, RoomRegistry}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    voice_channel_id = Keyword.fetch!(opts, :voice_channel_id)

    GenServer.start_link(__MODULE__, opts,
      name: {:via, Registry, {RoomRegistry, {:forwarder, voice_channel_id}}}
    )
  end

  @impl true
  def init(opts) do
    voice_channel_id = Keyword.fetch!(opts, :voice_channel_id)
    room_server = room_server(voice_channel_id)

    AdmissionServer.forwarder_started(voice_channel_id, self(), room_server)

    {:ok, %{voice_channel_id: voice_channel_id, room_server: room_server}}
  end

  defp room_server(voice_channel_id) do
    case Registry.lookup(RoomRegistry, {:room, voice_channel_id}) do
      [{pid, _value}] when is_pid(pid) -> pid
      _missing_or_stopped -> nil
    end
  end
end
