defmodule DiscordClone.Voice.RoomServer do
  @moduledoc false

  use GenServer

  @idle_timeout_ms :timer.seconds(30)

  alias DiscordClone.Voice.RoomRegistry

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    voice_channel_id = Keyword.fetch!(opts, :voice_channel_id)

    GenServer.start_link(__MODULE__, opts,
      name: {:via, Registry, {RoomRegistry, {:room, voice_channel_id}}}
    )
  end

  @spec mark_in_use(GenServer.server()) :: :ok
  def mark_in_use(server), do: GenServer.call(server, :mark_in_use)

  @spec mark_empty(GenServer.server(), keyword()) :: :ok
  def mark_empty(server, opts \\ []), do: GenServer.call(server, {:mark_empty, opts})

  @impl true
  def init(opts) do
    {:ok,
     %{
       room_supervisor: Keyword.fetch!(opts, :room_supervisor),
       idle_timer: schedule_idle_shutdown()
     }}
  end

  @impl true
  def handle_call(:mark_in_use, _from, state) do
    {:reply, :ok, %{state | idle_timer: cancel_idle_shutdown(state.idle_timer)}}
  end

  def handle_call({:mark_empty, opts}, _from, state) do
    idle_timeout = Keyword.get(opts, :idle_timeout, @idle_timeout_ms)
    _ = cancel_idle_shutdown(state.idle_timer)

    {:reply, :ok, %{state | idle_timer: schedule_idle_shutdown(idle_timeout)}}
  end

  @impl true
  def handle_info({:idle_shutdown, idle_timer}, %{idle_timer: {_timer_ref, idle_timer}} = state) do
    Process.exit(state.room_supervisor, :shutdown)
    {:stop, :normal, state}
  end

  def handle_info({:idle_shutdown, _stale_idle_timer}, state), do: {:noreply, state}

  defp schedule_idle_shutdown(timeout \\ @idle_timeout_ms)
       when is_integer(timeout) and timeout >= 0 do
    idle_timer = make_ref()
    timer_ref = Process.send_after(self(), {:idle_shutdown, idle_timer}, timeout)
    {timer_ref, idle_timer}
  end

  defp cancel_idle_shutdown(nil), do: nil

  defp cancel_idle_shutdown({timer_ref, _idle_timer}) do
    _ = Process.cancel_timer(timer_ref)
    nil
  end
end
