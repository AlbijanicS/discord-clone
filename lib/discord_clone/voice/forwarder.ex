defmodule DiscordClone.Voice.Forwarder do
  @moduledoc false

  use GenServer

  alias DiscordClone.Voice.{Diagnostics, RoomRegistry, Session, SessionCoordinator}

  @first_audio_output_slot 0

  @type voice_session_id :: Ecto.UUID.t()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    voice_channel_id = Keyword.fetch!(opts, :voice_channel_id)

    GenServer.start_link(__MODULE__, opts,
      name: {:via, Registry, {RoomRegistry, {:forwarder, voice_channel_id}}}
    )
  end

  @spec session_started(pid() | nil, voice_session_id(), pid()) :: :ok
  def session_started(forwarder, voice_session_id, session) when is_pid(forwarder) do
    GenServer.call(forwarder, {:session_started, voice_session_id, session})
  end

  def session_started(_missing_forwarder, _voice_session_id, _session), do: :ok

  @spec receive_ready(pid() | nil, voice_session_id(), pid(), :opus) :: :ok
  def receive_ready(forwarder, voice_session_id, session, :opus) when is_pid(forwarder) do
    GenServer.cast(forwarder, {:receive_ready, voice_session_id, session, :opus})
  end

  def receive_ready(_missing_forwarder, _voice_session_id, _session, :opus), do: :ok

  @spec send_ready(pid() | nil, voice_session_id(), pid(), integer(), :opus) :: :ok
  def send_ready(forwarder, voice_session_id, session, inbound_track_id, :opus)
      when is_pid(forwarder) do
    GenServer.cast(
      forwarder,
      {:send_ready, voice_session_id, session, inbound_track_id, :opus}
    )
  end

  def send_ready(_missing_forwarder, _voice_session_id, _session, _inbound_track_id, :opus),
    do: :ok

  @spec source_ended(pid() | nil, voice_session_id(), pid(), integer()) :: :ok
  def source_ended(forwarder, voice_session_id, session, inbound_track_id)
      when is_pid(forwarder) do
    GenServer.cast(forwarder, {:source_ended, voice_session_id, session, inbound_track_id})
  end

  def source_ended(_missing_forwarder, _voice_session_id, _session, _inbound_track_id), do: :ok

  @spec session_removed(pid() | nil, voice_session_id()) :: :ok
  def session_removed(forwarder, voice_session_id) when is_pid(forwarder) do
    GenServer.call(forwarder, {:session_removed, voice_session_id})
  end

  def session_removed(_missing_forwarder, _voice_session_id), do: :ok

  @spec forward_rtp(pid() | nil, voice_session_id(), integer(), ExRTP.Packet.t()) :: :ok
  def forward_rtp(forwarder, voice_session_id, inbound_track_id, packet)
      when is_pid(forwarder) do
    GenServer.cast(forwarder, {:forward_rtp, voice_session_id, inbound_track_id, packet})
  end

  def forward_rtp(_missing_forwarder, _voice_session_id, _inbound_track_id, _packet), do: :ok

  @doc false
  @spec sync(pid()) :: :ok
  def sync(forwarder), do: GenServer.call(forwarder, :sync)

  @impl true
  def init(opts) do
    voice_channel_id = Keyword.fetch!(opts, :voice_channel_id)
    room_server = room_server(voice_channel_id)

    SessionCoordinator.forwarder_started(voice_channel_id, self(), room_server)

    if is_pid(room_server) do
      send(room_server, {:forwarder_started, self()})
    end

    {:ok,
     %{
       voice_channel_id: voice_channel_id,
       room_server: room_server,
       sessions: %{},
       routes: %{},
       forwarded_packet_count: 0,
       dropped_packet_count: 0
     }}
  end

  @impl true
  def handle_call({:session_started, voice_session_id, session}, _from, state) do
    session_state =
      case Map.get(state.sessions, voice_session_id) do
        %{session: ^session} = current -> current
        _missing_or_replaced -> %{session: session, receive_codec: nil, source: nil}
      end

    state =
      state
      |> put_in([:sessions, voice_session_id], session_state)
      |> rebuild_routes()

    {:reply, :ok, state}
  end

  def handle_call({:session_removed, voice_session_id}, _from, state) do
    state =
      state
      |> update_in([:sessions], &Map.delete(&1, voice_session_id))
      |> rebuild_routes()

    {:reply, :ok, state}
  end

  def handle_call(:sync, _from, state), do: {:reply, :ok, state}

  @impl true
  def handle_cast({:receive_ready, voice_session_id, session, :opus}, state) do
    {:noreply,
     update_session(state, voice_session_id, session, fn session_state ->
       %{session_state | receive_codec: :opus}
     end)}
  end

  def handle_cast(
        {:send_ready, voice_session_id, session, inbound_track_id, :opus},
        state
      ) do
    {:noreply,
     update_session(state, voice_session_id, session, fn session_state ->
       %{session_state | source: %{track_id: inbound_track_id, codec: :opus}}
     end)}
  end

  def handle_cast({:source_ended, voice_session_id, session, inbound_track_id}, state) do
    case Map.get(state.sessions, voice_session_id) do
      %{session: ^session, source: %{track_id: ^inbound_track_id}} = session_state ->
        {:noreply,
         state
         |> put_in([:sessions, voice_session_id], %{session_state | source: nil})
         |> update_in([:routes], &Map.delete(&1, {voice_session_id, inbound_track_id}))}

      _missing_replaced_or_stale_source ->
        {:noreply, state}
    end
  end

  def handle_cast({:forward_rtp, voice_session_id, inbound_track_id, packet}, state) do
    source = {voice_session_id, inbound_track_id}

    case Map.get(state.routes, source) do
      %{
        destination_voice_session_id: destination_voice_session_id,
        audio_output_slot: audio_output_slot,
        session: session
      } ->
        case Map.get(state.sessions, destination_voice_session_id) do
          %{session: ^session} ->
            :ok =
              Session.deliver_rtp(
                session,
                destination_voice_session_id,
                audio_output_slot,
                packet
              )

            {:noreply, record_forward(state)}

          _stale_destination ->
            {:noreply, record_drop(state)}
        end

      nil ->
        {:noreply, record_drop(state)}
    end
  end

  defp update_session(state, voice_session_id, session, update) do
    case Map.get(state.sessions, voice_session_id) do
      %{session: ^session} = session_state ->
        state
        |> put_in([:sessions, voice_session_id], update.(session_state))
        |> rebuild_routes()

      _missing_or_replaced ->
        state
    end
  end

  defp rebuild_routes(%{sessions: sessions} = state) when map_size(sessions) == 2 do
    [{first_id, first}, {second_id, second}] = Map.to_list(sessions)

    routes =
      if fully_ready?(first) and fully_ready?(second) do
        %{}
        |> put_route(first_id, first, second_id, second)
        |> put_route(second_id, second, first_id, first)
      else
        %{}
      end

    %{state | routes: routes}
  end

  defp rebuild_routes(state), do: %{state | routes: %{}}

  defp fully_ready?(%{receive_codec: :opus, source: %{codec: :opus}}), do: true
  defp fully_ready?(_session), do: false

  defp put_route(
         routes,
         source_voice_session_id,
         %{source: %{track_id: track_id, codec: :opus}},
         destination_voice_session_id,
         %{receive_codec: :opus, session: destination_session}
       ) do
    Map.put(routes, {source_voice_session_id, track_id}, %{
      destination_voice_session_id: destination_voice_session_id,
      audio_output_slot: @first_audio_output_slot,
      session: destination_session
    })
  end

  defp record_forward(state) do
    state = Map.update!(state, :forwarded_packet_count, &(&1 + 1))
    Diagnostics.emit_route(:rtp_forwarded, route_counts(state))
    state
  end

  defp record_drop(state) do
    state = Map.update!(state, :dropped_packet_count, &(&1 + 1))
    Diagnostics.emit_route(:rtp_dropped, route_counts(state))
    state
  end

  defp route_counts(state) do
    Map.take(state, [:forwarded_packet_count, :dropped_packet_count])
  end

  defp room_server(voice_channel_id) do
    case Registry.lookup(RoomRegistry, {:room, voice_channel_id}) do
      [{pid, _value}] when is_pid(pid) -> pid
      _missing_or_stopped -> nil
    end
  end
end
