defmodule DiscordClone.Voice.AdmissionServer do
  @moduledoc false

  use GenServer

  alias DiscordClone.Voice
  alias DiscordClone.Voice.RoomServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, :ok, opts)

  @spec admit(Ecto.UUID.t(), Ecto.UUID.t(), binary(), pid()) :: {:ok, map()} | {:error, term()}
  def admit(voice_channel_id, user_id, signaling_session_id, signaling_channel) do
    GenServer.call(
      __MODULE__,
      {:admit, voice_channel_id, user_id, signaling_session_id, signaling_channel}
    )
  end

  @spec leave(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def leave(voice_channel_id, voice_session_id) do
    GenServer.call(__MODULE__, {:leave, voice_channel_id, voice_session_id})
  end

  @doc false
  @spec await_ready() :: :ok
  def await_ready, do: GenServer.call(__MODULE__, :await_ready, :infinity)

  @doc false
  @spec room_server_started(Ecto.UUID.t(), pid()) :: :ok
  def room_server_started(voice_channel_id, room_server) do
    GenServer.cast(__MODULE__, {:room_server_started, voice_channel_id, room_server})
  end

  @doc false
  @spec forwarder_started(Ecto.UUID.t(), pid(), pid() | nil) :: :ok
  def forwarder_started(voice_channel_id, forwarder, room_server) do
    GenServer.cast(__MODULE__, {:forwarder_started, voice_channel_id, forwarder, room_server})
  end

  @spec session_removed(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def session_removed(user_id, voice_session_id) do
    GenServer.cast(__MODULE__, {:session_removed, user_id, voice_session_id})
  end

  @impl true
  def init(:ok) do
    room_servers = Voice.running_room_servers()
    recovery_pending = MapSet.new(Enum.map(room_servers, fn {_voice_channel_id, pid} -> pid end))

    state = %{
      admission_status: if(room_servers == [], do: :ready, else: :recovering),
      sessions_by_user: %{},
      rooms_by_channel: %{},
      monitors: %{},
      recovery_pending: recovery_pending,
      recovery_waiters: []
    }

    state =
      Enum.reduce(room_servers, state, fn {voice_channel_id, room_server}, state ->
        track_room_server(state, voice_channel_id, room_server)
      end)

    Enum.each(room_servers, fn {_voice_channel_id, room_server} ->
      RoomServer.shutdown(room_server)
    end)

    {:ok, state}
  end

  @impl true
  def handle_call(:await_ready, from, %{admission_status: :recovering} = state) do
    {:noreply, %{state | recovery_waiters: [from | state.recovery_waiters]}}
  end

  def handle_call(:await_ready, _from, state), do: {:reply, :ok, state}

  def handle_call(
        {:admit, _voice_channel_id, _user_id, _signaling_session_id, _signaling_channel},
        _from,
        %{admission_status: :recovering} = state
      ) do
    {:reply, {:error, :recovering}, state}
  end

  def handle_call(
        {:admit, voice_channel_id, user_id, signaling_session_id, signaling_channel},
        _from,
        state
      ) do
    case Map.get(state.sessions_by_user, user_id) do
      nil ->
        admit_new_session(
          state,
          voice_channel_id,
          user_id,
          signaling_session_id,
          signaling_channel
        )

      %{voice_channel_id: ^voice_channel_id, signaling_session_id: ^signaling_session_id} ->
        admit_existing_session(
          state,
          voice_channel_id,
          user_id,
          signaling_session_id,
          signaling_channel
        )

      current_session ->
        move_session(
          state,
          current_session,
          voice_channel_id,
          user_id,
          signaling_session_id,
          signaling_channel
        )
    end
  end

  def handle_call({:leave, voice_channel_id, voice_session_id}, _from, state) do
    :ok = Voice.leave_room(voice_channel_id, voice_session_id)

    {:reply, :ok,
     %{
       state
       | sessions_by_user:
           remove_session(state.sessions_by_user, voice_channel_id, voice_session_id)
     }}
  end

  @impl true
  def handle_cast({:room_server_started, voice_channel_id, room_server}, state) do
    state = track_room_server(state, voice_channel_id, room_server)

    if state.admission_status == :recovering do
      RoomServer.shutdown(room_server)
    end

    {:noreply, maybe_finish_recovery(state)}
  end

  def handle_cast(
        {:forwarder_started, voice_channel_id, forwarder, room_server},
        state
      ) do
    state = track_forwarder(state, voice_channel_id, forwarder, room_server)
    {:noreply, maybe_finish_recovery(state)}
  end

  def handle_cast({:session_removed, user_id, voice_session_id}, state) do
    sessions_by_user =
      case Map.get(state.sessions_by_user, user_id) do
        %{voice_session_id: ^voice_session_id} -> Map.delete(state.sessions_by_user, user_id)
        _current_or_missing -> state.sessions_by_user
      end

    {:noreply, %{state | sessions_by_user: sessions_by_user}}
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, _pid, reason}, state) do
    case Map.pop(state.monitors, monitor) do
      {nil, _monitors} ->
        {:noreply, state}

      {component, monitors} ->
        state = %{state | monitors: monitors}
        state = drop_component_if_current(state, component)
        state = remove_recovery_pending(state, component)

        state =
          if room_failure?(reason) do
            invalidate_runtime(state, component.voice_channel_id, component.room_server_pid)
          else
            state
          end

        {:noreply, maybe_finish_recovery(state)}
    end
  end

  defp admit_existing_session(
         state,
         voice_channel_id,
         user_id,
         signaling_session_id,
         signaling_channel
       ) do
    case Voice.admit_room(voice_channel_id, user_id, signaling_session_id, signaling_channel) do
      {:ok, admission, room_server} ->
        state =
          put_session(
            state,
            voice_channel_id,
            user_id,
            signaling_session_id,
            admission,
            room_server
          )

        {:reply, {:ok, admission}, state}

      {:error, :unavailable} ->
        admit_new_session(
          remove_user(state, user_id),
          voice_channel_id,
          user_id,
          signaling_session_id,
          signaling_channel
        )

      error ->
        {:reply, error, state}
    end
  end

  defp move_session(
         state,
         %{
           voice_channel_id: current_voice_channel_id,
           voice_session_id: current_voice_session_id
         },
         voice_channel_id,
         user_id,
         signaling_session_id,
         signaling_channel
       ) do
    with :ok <- target_available?(voice_channel_id, current_voice_channel_id),
         :ok <- Voice.leave_room(current_voice_channel_id, current_voice_session_id) do
      admit_new_session(
        remove_user(state, user_id),
        voice_channel_id,
        user_id,
        signaling_session_id,
        signaling_channel
      )
    else
      {:error, %{reason: :room_full} = room_full} -> {:reply, {:error, room_full}, state}
      error -> {:reply, error, state}
    end
  end

  defp target_available?(voice_channel_id, voice_channel_id), do: :ok

  defp target_available?(voice_channel_id, _current_voice_channel_id) do
    with :ok <- Voice.ensure_room(voice_channel_id),
         {:ok, %{occupancy: occupancy, capacity: capacity}} <-
           Voice.room_occupancy(voice_channel_id) do
      if occupancy < capacity do
        :ok
      else
        {:error, %{reason: :room_full, occupancy: occupancy, capacity: capacity}}
      end
    end
  end

  defp admit_new_session(
         state,
         voice_channel_id,
         user_id,
         signaling_session_id,
         signaling_channel
       ) do
    case Voice.admit_room(voice_channel_id, user_id, signaling_session_id, signaling_channel) do
      {:ok, %{voice_session_id: _voice_session_id} = admission, room_server} ->
        state =
          put_session(
            state,
            voice_channel_id,
            user_id,
            signaling_session_id,
            admission,
            room_server
          )

        {:reply, {:ok, admission}, state}

      error ->
        {:reply, error, state}
    end
  end

  defp put_session(
         state,
         voice_channel_id,
         user_id,
         signaling_session_id,
         %{voice_session_id: voice_session_id},
         room_server
       ) do
    session = %{
      voice_channel_id: voice_channel_id,
      voice_session_id: voice_session_id,
      signaling_session_id: signaling_session_id,
      room_server_pid: room_server
    }

    put_in(state.sessions_by_user[user_id], session)
  end

  defp remove_user(state, user_id),
    do: %{state | sessions_by_user: Map.delete(state.sessions_by_user, user_id)}

  defp remove_session(sessions_by_user, voice_channel_id, voice_session_id) do
    Enum.reduce(sessions_by_user, sessions_by_user, fn {user_id, session}, sessions_by_user ->
      if session.voice_channel_id == voice_channel_id and
           session.voice_session_id == voice_session_id do
        Map.delete(sessions_by_user, user_id)
      else
        sessions_by_user
      end
    end)
  end

  defp track_room_server(state, voice_channel_id, room_server) do
    existing = get_in(state.rooms_by_channel, [voice_channel_id, :room_server])

    if existing && existing.pid == room_server do
      state
    else
      state =
        if existing do
          state
          |> invalidate_runtime(voice_channel_id, existing.pid)
          |> remove_component(voice_channel_id, :room_server)
          |> remove_recovery_pending(existing.pid)
        else
          invalidate_other_runtime_sessions(state, voice_channel_id, room_server)
        end

      monitor = Process.monitor(room_server)

      state
      |> put_component(voice_channel_id, :room_server, room_server, monitor, room_server)
      |> add_recovery_pending(room_server)
    end
  end

  defp track_forwarder(state, voice_channel_id, forwarder, room_server) do
    room_server =
      room_server || get_in(state.rooms_by_channel, [voice_channel_id, :room_server, :pid])

    existing = get_in(state.rooms_by_channel, [voice_channel_id, :forwarder])

    if existing && existing.pid == forwarder do
      state
    else
      state =
        if existing do
          state
          |> invalidate_runtime(voice_channel_id, existing.room_server_pid)
          |> remove_component(voice_channel_id, :forwarder)
        else
          invalidate_other_runtime_sessions(state, voice_channel_id, room_server)
        end

      monitor = Process.monitor(forwarder)

      state
      |> put_component(voice_channel_id, :forwarder, forwarder, monitor, room_server)
    end
  end

  defp put_component(state, voice_channel_id, component_name, pid, monitor, room_server_pid) do
    component = %{
      voice_channel_id: voice_channel_id,
      component: component_name,
      pid: pid,
      monitor: monitor,
      room_server_pid: room_server_pid
    }

    room = Map.get(state.rooms_by_channel, voice_channel_id, %{})

    %{
      state
      | rooms_by_channel:
          Map.put(
            state.rooms_by_channel,
            voice_channel_id,
            Map.put(room, component_name, %{
              pid: pid,
              monitor: monitor,
              room_server_pid: room_server_pid
            })
          ),
        monitors: Map.put(state.monitors, monitor, component)
    }
  end

  defp remove_component(state, voice_channel_id, component_name) do
    case get_in(state.rooms_by_channel, [voice_channel_id, component_name]) do
      %{monitor: monitor} ->
        Process.demonitor(monitor, [:flush])

        state
        |> update_in([:rooms_by_channel, voice_channel_id], &Map.delete(&1, component_name))
        |> update_in([:monitors], &Map.delete(&1, monitor))

      nil ->
        state
    end
  end

  defp drop_component_if_current(state, %{voice_channel_id: voice_channel_id} = component) do
    pid = component.pid
    monitor = component.monitor

    case get_in(state.rooms_by_channel, [voice_channel_id, component.component]) do
      %{pid: ^pid, monitor: ^monitor} ->
        update_in(
          state,
          [:rooms_by_channel, voice_channel_id],
          &Map.delete(&1, component.component)
        )

      _replacement_or_missing ->
        state
    end
  end

  defp add_recovery_pending(%{admission_status: :recovering} = state, room_server) do
    Map.update!(state, :recovery_pending, &MapSet.put(&1, room_server))
  end

  defp add_recovery_pending(state, _room_server), do: state

  defp remove_recovery_pending(state, %{component: :room_server, pid: room_server}) do
    Map.update!(state, :recovery_pending, &MapSet.delete(&1, room_server))
  end

  defp remove_recovery_pending(state, room_server) when is_pid(room_server) do
    Map.update!(state, :recovery_pending, &MapSet.delete(&1, room_server))
  end

  defp remove_recovery_pending(state, _component), do: state

  defp invalidate_runtime(state, _voice_channel_id, nil), do: state

  defp invalidate_runtime(state, voice_channel_id, room_server) do
    sessions_by_user =
      Enum.reduce(state.sessions_by_user, state.sessions_by_user, fn {user_id, session},
                                                                     sessions ->
        if session.voice_channel_id == voice_channel_id and
             session.room_server_pid == room_server do
          Map.delete(sessions, user_id)
        else
          sessions
        end
      end)

    %{state | sessions_by_user: sessions_by_user}
  end

  defp invalidate_other_runtime_sessions(state, _voice_channel_id, nil), do: state

  defp invalidate_other_runtime_sessions(state, voice_channel_id, room_server) do
    sessions_by_user =
      Enum.reduce(state.sessions_by_user, state.sessions_by_user, fn {user_id, session},
                                                                     sessions ->
        if session.voice_channel_id == voice_channel_id and
             session.room_server_pid != room_server do
          Map.delete(sessions, user_id)
        else
          sessions
        end
      end)

    %{state | sessions_by_user: sessions_by_user}
  end

  defp room_failure?(:normal), do: false
  defp room_failure?(_reason), do: true

  defp maybe_finish_recovery(%{admission_status: :recovering, recovery_pending: pending} = state) do
    if MapSet.size(pending) == 0 do
      Enum.each(state.recovery_waiters, &GenServer.reply(&1, :ok))
      %{state | admission_status: :ready, recovery_waiters: []}
    else
      state
    end
  end

  defp maybe_finish_recovery(state), do: state
end
