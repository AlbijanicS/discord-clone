defmodule DiscordClone.Voice.SessionSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias DiscordClone.Voice.RoomRegistry

  @spec start_link(keyword()) :: DynamicSupervisor.on_start()
  def start_link(opts) do
    voice_channel_id = Keyword.fetch!(opts, :voice_channel_id)
    DynamicSupervisor.start_link(__MODULE__, opts, name: name(voice_channel_id))
  end

  @spec name(Ecto.UUID.t()) :: {:via, Registry, {module(), term()}}
  def name(voice_channel_id),
    do: {:via, Registry, {DiscordClone.Voice.RoomRegistry, {:sessions, voice_channel_id}}}

  @impl true
  def init(opts) do
    voice_channel_id = Keyword.fetch!(opts, :voice_channel_id)

    case Registry.lookup(RoomRegistry, {:room, voice_channel_id}) do
      [{room_server, _value}] when is_pid(room_server) ->
        send(room_server, {:session_supervisor_started, self()})

      _missing_or_stopped ->
        :ok
    end

    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
