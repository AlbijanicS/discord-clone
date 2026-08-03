defmodule DiscordClone.Voice.Session do
  @moduledoc false

  use GenServer, restart: :temporary

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @spec crash(pid()) :: :ok
  def crash(session) do
    Process.exit(session, :kill)
    :ok
  end

  @impl true
  def init(opts) do
    signaling_channel = Keyword.fetch!(opts, :signaling_channel)

    {:ok,
     %{
       room_server: Keyword.fetch!(opts, :room_server),
       voice_session_id: Keyword.fetch!(opts, :voice_session_id),
       signaling_channel_monitor: Process.monitor(signaling_channel)
     }}
  end

  @impl true
  def handle_info(
        {:DOWN, signaling_channel_monitor, :process, _signaling_channel, _reason},
        %{signaling_channel_monitor: signaling_channel_monitor} = state
      ) do
    GenServer.cast(state.room_server, {:signaling_channel_down, state.voice_session_id})
    {:stop, :normal, state}
  end

  def handle_info(_message, state), do: {:noreply, state}
end
