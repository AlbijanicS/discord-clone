defmodule DiscordClone.Voice do
  @moduledoc """
  Starts and observes ephemeral Voice Channel room runtimes.

  Durable authorization remains the responsibility of `DiscordClone.Workspaces`.
  This boundary owns only the lifecycle of a room keyed by an already-authorized
  Voice Channel ID.
  """

  alias DiscordClone.UUIDIdentifier
  alias DiscordClone.Voice.{RoomRegistry, RoomServer, RoomSupervisor}

  @spec ensure_room(term()) :: :ok | {:error, :not_found | term()}
  def ensure_room(voice_channel_id) do
    UUIDIdentifier.cast_or(voice_channel_id, {:error, :not_found}, &ensure_room_id/1)
  end

  @spec room_running?(term()) :: boolean()
  def room_running?(voice_channel_id) do
    UUIDIdentifier.cast_or(voice_channel_id, false, &room_running/1)
  end

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

  defp room_running(voice_channel_id) do
    is_pid(room_server(voice_channel_id))
  end

  defp room_server(voice_channel_id) do
    case Registry.lookup(RoomRegistry, {:room, voice_channel_id}) do
      [{pid, _value}] when is_pid(pid) -> if(Process.alive?(pid), do: pid)
      _missing_or_stopped -> nil
    end
  end
end
