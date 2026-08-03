defmodule DiscordClone.Voice.RoomServer do
  @moduledoc false

  use GenServer

  @idle_timeout_ms :timer.seconds(30)

  alias DiscordClone.Voice.{AdmissionServer, RoomRegistry, Session, SessionSupervisor}

  @capacity 5

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    voice_channel_id = Keyword.fetch!(opts, :voice_channel_id)

    GenServer.start_link(__MODULE__, opts,
      name: {:via, Registry, {RoomRegistry, {:room, voice_channel_id}}}
    )
  end

  @spec mark_in_use(GenServer.server()) :: :ok
  def mark_in_use(server), do: GenServer.call(server, :mark_in_use)

  @doc false
  @spec shutdown(GenServer.server()) :: :ok
  def shutdown(server), do: GenServer.cast(server, :shutdown_runtime)

  @spec mark_empty(GenServer.server(), keyword()) :: :ok
  def mark_empty(server, opts \\ []), do: GenServer.call(server, {:mark_empty, opts})

  @spec admit(GenServer.server(), Ecto.UUID.t(), binary(), pid()) ::
          {:ok, map()} | {:error, map() | :unavailable}
  def admit(server, user_id, signaling_session_id, signaling_channel) do
    GenServer.call(server, {:admit, user_id, signaling_session_id, signaling_channel})
  end

  @spec leave(GenServer.server(), Ecto.UUID.t()) :: :ok
  def leave(server, voice_session_id), do: GenServer.call(server, {:leave, voice_session_id})

  @spec occupancy(GenServer.server()) ::
          {:ok, %{occupancy: non_neg_integer(), capacity: pos_integer()}}
  def occupancy(server), do: GenServer.call(server, :occupancy)

  @spec await_empty(GenServer.server()) :: :ok
  def await_empty(server), do: GenServer.call(server, :await_empty)

  @spec crash_session(GenServer.server(), Ecto.UUID.t()) :: :ok
  def crash_session(server, voice_session_id),
    do: GenServer.call(server, {:crash_session, voice_session_id})

  @impl true
  def init(opts) do
    voice_channel_id = Keyword.fetch!(opts, :voice_channel_id)
    AdmissionServer.room_server_started(voice_channel_id, self())

    {:ok,
     %{
       room_supervisor: Keyword.fetch!(opts, :room_supervisor),
       voice_channel_id: voice_channel_id,
       idle_timer: schedule_idle_shutdown(),
       memberships: %{},
       session_by_signaling: %{},
       session_by_monitor: %{},
       session_supervisor: nil,
       pending_admissions: [],
       empty_waiters: []
     }}
  end

  @impl true
  def handle_call(:mark_in_use, _from, state) do
    {:reply, :ok, %{state | idle_timer: cancel_idle_shutdown(state.idle_timer)}}
  end

  def handle_call({:mark_empty, opts}, _from, state) do
    if map_size(state.memberships) == 0 do
      idle_timeout = Keyword.get(opts, :idle_timeout, @idle_timeout_ms)
      _ = cancel_idle_shutdown(state.idle_timer)

      {:reply, :ok, %{state | idle_timer: schedule_idle_shutdown(idle_timeout)}}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call({:admit, user_id, signaling_session_id, signaling_channel}, from, state) do
    if session_supervisor_ready?(state) do
      admit_request(state, user_id, signaling_session_id, signaling_channel)
    else
      {:noreply,
       %{
         state
         | pending_admissions: [
             {from, user_id, signaling_session_id, signaling_channel} | state.pending_admissions
           ]
       }}
    end
  end

  def handle_call({:leave, voice_session_id}, _from, state) do
    {:reply, :ok, remove_membership(state, voice_session_id)}
  end

  def handle_call(:occupancy, _from, state),
    do: {:reply, {:ok, membership_occupancy(state)}, state}

  def handle_call(:await_empty, from, state) do
    if map_size(state.memberships) == 0 do
      {:reply, :ok, state}
    else
      {:noreply, %{state | empty_waiters: [from | state.empty_waiters]}}
    end
  end

  def handle_call({:crash_session, voice_session_id}, _from, state) do
    case state.memberships do
      %{^voice_session_id => %{session_pid: session_pid}} -> Session.crash(session_pid)
      _missing -> :ok
    end

    session_monitor =
      case state.memberships do
        %{^voice_session_id => %{session_monitor: session_monitor}} -> session_monitor
        _missing -> nil
      end

    state = wait_for_session_crash(state, session_monitor)
    {:reply, :ok, remove_membership(state, voice_session_id, terminate_session?: false)}
  end

  @impl true
  def handle_info({:session_supervisor_started, session_supervisor}, state) do
    state = %{state | session_supervisor: session_supervisor}
    pending_admissions = Enum.reverse(state.pending_admissions)

    state =
      Enum.reduce(pending_admissions, state, fn {from, user_id, signaling_session_id,
                                                 signaling_channel},
                                                state ->
        {:reply, reply, state} =
          admit_request(state, user_id, signaling_session_id, signaling_channel)

        GenServer.reply(from, reply)
        state
      end)

    {:noreply, %{state | pending_admissions: []}}
  end

  def handle_info({:idle_shutdown, idle_timer}, %{idle_timer: {_timer_ref, idle_timer}} = state) do
    Process.exit(state.room_supervisor, :shutdown)
    {:stop, :normal, state}
  end

  def handle_info({:idle_shutdown, _stale_idle_timer}, state), do: {:noreply, state}

  def handle_info({:DOWN, session_monitor, :process, _session, _reason}, state) do
    case Map.pop(state.session_by_monitor, session_monitor) do
      {nil, _session_by_monitor} ->
        {:noreply, state}

      {voice_session_id, _session_by_monitor} ->
        {:noreply, remove_membership(state, voice_session_id, terminate_session?: false)}
    end
  end

  @impl true
  def handle_cast({:signaling_channel_down, voice_session_id}, state) do
    {:noreply, remove_membership(state, voice_session_id)}
  end

  def handle_cast(:shutdown_runtime, state) do
    state = remove_all_memberships(state)
    Process.exit(state.room_supervisor, :shutdown)
    {:noreply, state}
  end

  defp admit_request(state, user_id, signaling_session_id, signaling_channel) do
    case Map.fetch(state.session_by_signaling, signaling_session_id) do
      {:ok, voice_session_id} ->
        {:reply, {:ok, admission(state.memberships[voice_session_id], state)}, state}

      :error when map_size(state.memberships) >= @capacity ->
        {:reply, {:error, room_full(state)}, state}

      :error ->
        admit_new_session(state, user_id, signaling_session_id, signaling_channel)
    end
  end

  defp session_supervisor_ready?(state) do
    is_pid(state.session_supervisor) and Process.alive?(state.session_supervisor)
  end

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

  defp admit_new_session(state, user_id, signaling_session_id, signaling_channel) do
    voice_session_id = Ecto.UUID.generate()

    with {:ok, session_pid} <- start_session(state, voice_session_id, signaling_channel) do
      session_monitor = Process.monitor(session_pid)

      membership = %{
        voice_session_id: voice_session_id,
        user_id: user_id,
        signaling_session_id: signaling_session_id,
        session_pid: session_pid,
        session_monitor: session_monitor
      }

      state =
        state
        |> put_in([:memberships, voice_session_id], membership)
        |> put_in([:session_by_signaling, signaling_session_id], voice_session_id)
        |> put_in([:session_by_monitor, session_monitor], voice_session_id)
        |> Map.put(:idle_timer, cancel_idle_shutdown(state.idle_timer))

      {:reply, {:ok, admission(membership, state)}, state}
    else
      {:error, _reason} -> {:reply, {:error, :unavailable}, state}
    end
  end

  defp remove_membership(state, voice_session_id, opts \\ []) do
    case Map.pop(state.memberships, voice_session_id) do
      {nil, _memberships} ->
        state

      {%{
         session_pid: session_pid,
         session_monitor: session_monitor,
         signaling_session_id: signaling_session_id,
         user_id: user_id
       }, memberships} ->
        if Keyword.get(opts, :terminate_session?, true) and Process.alive?(session_pid) do
          _ =
            DynamicSupervisor.terminate_child(
              SessionSupervisor.name(state.voice_channel_id),
              session_pid
            )
        end

        _ = Process.demonitor(session_monitor, [:flush])

        state = %{
          state
          | memberships: memberships,
            session_by_signaling: Map.delete(state.session_by_signaling, signaling_session_id),
            session_by_monitor: Map.delete(state.session_by_monitor, session_monitor)
        }

        :ok = AdmissionServer.session_removed(user_id, voice_session_id)

        if map_size(memberships) == 0 do
          state =
            if Keyword.get(opts, :schedule_idle?, true) do
              %{state | idle_timer: schedule_idle_shutdown()}
            else
              state
            end

          reply_empty_waiters(state)
        else
          state
        end
    end
  end

  defp start_session(state, voice_session_id, signaling_channel) do
    session_supervisor = SessionSupervisor.name(state.voice_channel_id)

    if is_pid(GenServer.whereis(session_supervisor)) do
      try do
        DynamicSupervisor.start_child(
          session_supervisor,
          {Session,
           room_server: self(),
           voice_session_id: voice_session_id,
           signaling_channel: signaling_channel}
        )
      catch
        :exit, _session_supervisor_stopped -> {:error, :unavailable}
      end
    else
      {:error, :unavailable}
    end
  end

  defp wait_for_session_crash(state, nil), do: state

  defp wait_for_session_crash(state, session_monitor) do
    receive do
      {:DOWN, ^session_monitor, :process, _session, _reason} ->
        %{state | session_by_monitor: Map.delete(state.session_by_monitor, session_monitor)}
    end
  end

  defp remove_all_memberships(state) do
    Enum.reduce(Map.keys(state.memberships), state, fn voice_session_id, state ->
      remove_membership(state, voice_session_id, schedule_idle?: false)
    end)
  end

  defp reply_empty_waiters(state) do
    Enum.each(state.empty_waiters, &GenServer.reply(&1, :ok))
    %{state | empty_waiters: []}
  end

  defp admission(%{voice_session_id: voice_session_id}, state) do
    %{voice_session_id: voice_session_id} |> Map.merge(membership_occupancy(state))
  end

  defp membership_occupancy(state),
    do: %{occupancy: map_size(state.memberships), capacity: @capacity}

  defp room_full(state), do: %{reason: :room_full} |> Map.merge(membership_occupancy(state))
end
