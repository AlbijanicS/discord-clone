defmodule DiscordClone.Voice do
  @moduledoc """
  Starts and observes ephemeral Voice Channel room runtimes.

  Durable authorization remains the responsibility of `DiscordClone.Workspaces`.
  This boundary owns only the lifecycle of a room keyed by an already-authorized
  Voice Channel ID.
  """

  alias DiscordClone.UUIDIdentifier
  alias DiscordClone.Voice.{AdmissionServer, RoomRegistry, RoomServer, RoomSupervisor}

  @spec ensure_room(term()) :: :ok | {:error, :not_found | term()}
  def ensure_room(voice_channel_id) do
    UUIDIdentifier.cast_or(voice_channel_id, {:error, :not_found}, &ensure_room_id/1)
  end

  @spec room_running?(term()) :: boolean()
  def room_running?(voice_channel_id) do
    UUIDIdentifier.cast_or(voice_channel_id, false, &room_running/1)
  end

  @spec admit(term(), term(), binary(), pid()) :: {:ok, map()} | {:error, term()}
  def admit(voice_channel_id, user_id, signaling_session_id, signaling_channel)
      when is_binary(signaling_session_id) and is_pid(signaling_channel) do
    with true <- Process.alive?(signaling_channel),
         {:ok, [voice_channel_id, user_id]} <-
           UUIDIdentifier.cast_all([voice_channel_id, user_id]) do
      safe_admit(voice_channel_id, user_id, signaling_session_id, signaling_channel)
    else
      false -> {:error, :invalid_admission}
      :error -> {:error, :not_found}
    end
  end

  def admit(_voice_channel_id, _user_id, _signaling_session_id, _signaling_channel),
    do: {:error, :invalid_admission}

  @spec leave(term(), term()) :: :ok | {:error, :not_found | term()}
  def leave(voice_channel_id, voice_session_id) do
    with {:ok, [voice_channel_id, voice_session_id]} <-
           UUIDIdentifier.cast_all([voice_channel_id, voice_session_id]) do
      safe_leave(voice_channel_id, voice_session_id)
    else
      :error -> {:error, :not_found}
    end
  end

  @spec room_occupancy(term()) ::
          {:ok, %{occupancy: non_neg_integer(), capacity: pos_integer()}} | {:error, :not_found}
  def room_occupancy(voice_channel_id) do
    UUIDIdentifier.cast_or(voice_channel_id, {:error, :not_found}, fn voice_channel_id ->
      case room_server(voice_channel_id) do
        nil -> {:error, :not_found}
        room_server -> safe_room_occupancy(room_server)
      end
    end)
  end

  @doc false
  @spec crash_session(term(), term()) :: :ok | {:error, :not_found}
  def crash_session(voice_channel_id, voice_session_id) do
    with {:ok, [voice_channel_id, voice_session_id]} <-
           UUIDIdentifier.cast_all([voice_channel_id, voice_session_id]) do
      case room_server(voice_channel_id) do
        nil -> :ok
        room_server -> RoomServer.crash_session(room_server, voice_session_id)
      end
    else
      :error -> {:error, :not_found}
    end
  end

  @doc false
  @spec await_empty_room(term()) :: :ok | {:error, :not_found}
  def await_empty_room(voice_channel_id) do
    UUIDIdentifier.cast_or(voice_channel_id, {:error, :not_found}, fn voice_channel_id ->
      case room_server(voice_channel_id) do
        nil -> :ok
        room_server -> RoomServer.await_empty(room_server)
      end
    end)
  end

  @doc false
  @spec expire_idle_room(term()) :: :ok | {:error, :not_found}
  def expire_idle_room(voice_channel_id) do
    UUIDIdentifier.cast_or(voice_channel_id, {:error, :not_found}, fn voice_channel_id ->
      case room_server(voice_channel_id) do
        nil -> :ok
        room_server -> await_room_shutdown(room_server)
      end
    end)
  end

  @doc false
  @spec crash_admission_server() :: :ok | {:error, :not_running}
  def crash_admission_server do
    case Process.whereis(AdmissionServer) do
      admission_server when is_pid(admission_server) ->
        Process.exit(admission_server, :kill)
        :ok

      nil ->
        {:error, :not_running}
    end
  end

  @doc false
  @spec crash_forwarder(term()) :: :ok | {:error, :not_found}
  def crash_forwarder(voice_channel_id) do
    UUIDIdentifier.cast_or(voice_channel_id, {:error, :not_found}, fn voice_channel_id ->
      case Registry.lookup(RoomRegistry, {:forwarder, voice_channel_id}) do
        [{forwarder, _value}] when is_pid(forwarder) ->
          monitor = Process.monitor(forwarder)
          Process.exit(forwarder, :kill)

          receive do
            {:DOWN, ^monitor, :process, ^forwarder, _reason} -> :ok
          end

        _missing_or_stopped ->
          :ok
      end
    end)
  end

  @doc false
  @spec await_admission_recovery() :: :ok | {:error, :recovery_timeout}
  def await_admission_recovery, do: AdmissionServer.await_ready()

  @doc false
  @spec mark_room_in_use(term()) :: :ok | {:error, :not_found | :not_running | term()}
  def mark_room_in_use(voice_channel_id) do
    case UUIDIdentifier.cast(voice_channel_id) do
      {:ok, voice_channel_id} -> mark_room_in_use(voice_channel_id, 2)
      :error -> {:error, :not_found}
    end
  end

  @doc false
  @spec mark_room_empty(term(), keyword()) :: :ok | {:error, :not_found | term()}
  def mark_room_empty(voice_channel_id, opts \\ []) do
    UUIDIdentifier.cast_or(voice_channel_id, {:error, :not_found}, fn voice_channel_id ->
      case room_server(voice_channel_id) do
        nil -> :ok
        room_server -> RoomServer.mark_empty(room_server, opts)
      end
    end)
  end

  @doc false
  @spec admit_room(Ecto.UUID.t(), Ecto.UUID.t(), binary(), pid()) ::
          {:ok, map(), pid()} | {:error, term()}
  def admit_room(voice_channel_id, user_id, signaling_session_id, signaling_channel) do
    admit_room(voice_channel_id, user_id, signaling_session_id, signaling_channel, 2)
  end

  @doc false
  @spec leave_room(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def leave_room(voice_channel_id, voice_session_id) do
    case room_server(voice_channel_id) do
      nil -> :ok
      room_server -> safe_room_leave(room_server, voice_session_id)
    end
  end

  @doc false
  @spec running_room_servers() :: [{Ecto.UUID.t(), pid()}]
  def running_room_servers do
    Registry.select(RoomRegistry, [
      {{{:room, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
  end

  defp ensure_room_id(voice_channel_id) do
    if room_running(voice_channel_id) do
      :ok
    else
      case DynamicSupervisor.start_child(RoomSupervisor, {RoomSupervisor, voice_channel_id}) do
        {:ok, _room_supervisor} ->
          :ok

        {:error, {:already_started, _room_supervisor}} ->
          :ok

        {:error, reason} ->
          if room_running(voice_channel_id), do: :ok, else: {:error, reason}
      end
    end
  end

  defp mark_room_in_use(voice_channel_id, attempts_left) do
    with :ok <- ensure_room_id(voice_channel_id),
         room_server when is_pid(room_server) <- room_server(voice_channel_id) do
      RoomServer.mark_in_use(room_server)
    else
      nil when attempts_left > 0 -> mark_room_in_use(voice_channel_id, attempts_left - 1)
      nil -> {:error, :not_running}
      error -> error
    end
  catch
    :exit, _room_stopped when attempts_left > 0 ->
      mark_room_in_use(voice_channel_id, attempts_left - 1)

    :exit, _room_stopped ->
      {:error, :not_running}
  end

  defp admit_room(
         voice_channel_id,
         user_id,
         signaling_session_id,
         signaling_channel,
         attempts_left
       ) do
    with :ok <- ensure_room_id(voice_channel_id),
         room_server when is_pid(room_server) <- room_server(voice_channel_id) do
      case RoomServer.admit(room_server, user_id, signaling_session_id, signaling_channel) do
        {:ok, admission} ->
          {:ok, admission, room_server}

        {:error, :unavailable} when attempts_left > 0 ->
          admit_room(
            voice_channel_id,
            user_id,
            signaling_session_id,
            signaling_channel,
            attempts_left - 1
          )

        result ->
          result
      end
    else
      nil when attempts_left > 0 ->
        admit_room(
          voice_channel_id,
          user_id,
          signaling_session_id,
          signaling_channel,
          attempts_left - 1
        )

      nil ->
        {:error, :not_found}

      {:error, _room_starting} when attempts_left > 0 ->
        admit_room(
          voice_channel_id,
          user_id,
          signaling_session_id,
          signaling_channel,
          attempts_left - 1
        )

      error ->
        error
    end
  catch
    :exit, _room_stopped when attempts_left > 0 ->
      admit_room(
        voice_channel_id,
        user_id,
        signaling_session_id,
        signaling_channel,
        attempts_left - 1
      )

    :exit, _room_stopped ->
      {:error, :not_found}
  end

  defp room_running(voice_channel_id) do
    is_pid(room_server(voice_channel_id))
  end

  defp room_server(voice_channel_id) do
    case Registry.lookup(RoomRegistry, {:room, voice_channel_id}) do
      [{pid, _value}] when is_pid(pid) -> if(Process.alive?(pid), do: pid)
      _missing_or_stopped -> nil
    end
  end

  defp safe_room_leave(room_server, voice_session_id) do
    RoomServer.leave(room_server, voice_session_id)
  catch
    :exit, _room_stopped -> :ok
  end

  defp safe_admit(voice_channel_id, user_id, signaling_session_id, signaling_channel) do
    AdmissionServer.admit(voice_channel_id, user_id, signaling_session_id, signaling_channel)
  catch
    :exit, _admission_server_unavailable -> {:error, :recovering}
  end

  defp safe_leave(voice_channel_id, voice_session_id) do
    AdmissionServer.leave(voice_channel_id, voice_session_id)
  catch
    :exit, _admission_server_unavailable -> :ok
  end

  defp safe_room_occupancy(room_server) do
    RoomServer.occupancy(room_server)
  catch
    :exit, _room_stopped -> {:error, :not_found}
  end

  defp await_room_shutdown(room_server) do
    room_monitor = Process.monitor(room_server)
    :ok = RoomServer.mark_empty(room_server, idle_timeout: 0)

    receive do
      {:DOWN, ^room_monitor, :process, ^room_server, :normal} -> :ok
    end
  end
end
