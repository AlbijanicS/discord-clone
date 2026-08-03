defmodule DiscordClone.Voice.SessionSupervisor do
  @moduledoc false

  use DynamicSupervisor

  @spec start_link(keyword()) :: DynamicSupervisor.on_start()
  def start_link(opts) do
    voice_channel_id = Keyword.fetch!(opts, :voice_channel_id)
    DynamicSupervisor.start_link(__MODULE__, :ok, name: name(voice_channel_id))
  end

  @spec name(Ecto.UUID.t()) :: {:via, Registry, {module(), term()}}
  def name(voice_channel_id),
    do: {:via, Registry, {DiscordClone.Voice.RoomRegistry, {:sessions, voice_channel_id}}}

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)
end
