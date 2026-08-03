defmodule DiscordClone.Voice.AdmissionServer do
  @moduledoc false

  use GenServer

  alias DiscordClone.Voice

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

  @spec session_removed(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def session_removed(user_id, voice_session_id) do
    GenServer.cast(__MODULE__, {:session_removed, user_id, voice_session_id})
  end

  @impl true
  def init(:ok), do: {:ok, %{sessions_by_user: %{}}}

  @impl true
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
  def handle_cast({:session_removed, user_id, voice_session_id}, state) do
    sessions_by_user =
      case Map.get(state.sessions_by_user, user_id) do
        %{voice_session_id: ^voice_session_id} -> Map.delete(state.sessions_by_user, user_id)
        _current_or_missing -> state.sessions_by_user
      end

    {:noreply, %{state | sessions_by_user: sessions_by_user}}
  end

  defp admit_existing_session(
         state,
         voice_channel_id,
         user_id,
         signaling_session_id,
         signaling_channel
       ) do
    case Voice.admit_room(voice_channel_id, user_id, signaling_session_id, signaling_channel) do
      {:ok, admission} ->
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
      {:ok, %{voice_session_id: voice_session_id} = admission} ->
        session = %{
          voice_channel_id: voice_channel_id,
          voice_session_id: voice_session_id,
          signaling_session_id: signaling_session_id
        }

        {:reply, {:ok, admission}, put_in(state.sessions_by_user[user_id], session)}

      error ->
        {:reply, error, state}
    end
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
end
