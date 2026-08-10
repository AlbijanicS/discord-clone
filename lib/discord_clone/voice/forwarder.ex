defmodule DiscordClone.Voice.Forwarder do
  @moduledoc false

  use GenServer

  alias DiscordClone.Voice.{Diagnostics, RoomRegistry, Session, SessionCoordinator}

  @audio_output_slots 0..3

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
       next_session_order: 0,
       slot_assignments: %{},
       routes: %{},
       forwarded_packet_count: 0,
       dropped_packet_count: 0
     }}
  end

  @impl true
  def handle_call({:session_started, voice_session_id, session}, _from, state) do
    {session_state, next_session_order} =
      case Map.get(state.sessions, voice_session_id) do
        %{session: ^session} = current ->
          {current, state.next_session_order}

        %{started_order: started_order} ->
          {%{
             session: session,
             receive_codec: nil,
             source: nil,
             started_order: started_order
           }, state.next_session_order}

        nil ->
          {%{
             session: session,
             receive_codec: nil,
             source: nil,
             started_order: state.next_session_order
           }, state.next_session_order + 1}
      end

    state =
      state
      |> put_in([:sessions, voice_session_id], session_state)
      |> Map.put(:next_session_order, next_session_order)
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
         |> rebuild_routes()}

      _missing_replaced_or_stale_source ->
        {:noreply, state}
    end
  end

  def handle_cast({:forward_rtp, voice_session_id, inbound_track_id, packet}, state) do
    source = {voice_session_id, inbound_track_id}

    case Map.get(state.routes, source) do
      routes when is_map(routes) and map_size(routes) > 0 ->
        {:noreply, Enum.reduce(routes, state, &deliver_route(&1, packet, &2))}

      _missing_routes ->
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

  defp rebuild_routes(state) do
    slot_assignments = rebuild_slot_assignments(state.sessions, state.slot_assignments)
    routes = build_routes(state.sessions, slot_assignments)
    %{state | routes: routes, slot_assignments: slot_assignments}
  end

  defp rebuild_slot_assignments(sessions, current_assignments) do
    sessions
    |> sessions_in_started_order()
    |> Enum.reduce(%{}, fn {destination_id, destination}, assignments ->
      if receive_ready?(destination) do
        source_ids =
          sessions
          |> sessions_in_started_order()
          |> Enum.filter(fn {source_id, source} ->
            source_id != destination_id and source_ready?(source)
          end)
          |> Enum.map(&elem(&1, 0))

        current_destination_assignments = Map.get(current_assignments, destination_id, %{})

        Map.put(
          assignments,
          destination_id,
          assign_destination_slots(current_destination_assignments, source_ids)
        )
      else
        assignments
      end
    end)
  end

  defp assign_destination_slots(current_assignments, source_ids) do
    source_id_set = MapSet.new(source_ids)

    preserved_assignments =
      Map.filter(current_assignments, fn {source_id, slot} ->
        MapSet.member?(source_id_set, source_id) and slot in @audio_output_slots
      end)

    free_slots = Enum.reject(@audio_output_slots, &(&1 in Map.values(preserved_assignments)))

    source_ids
    |> Enum.reject(&Map.has_key?(preserved_assignments, &1))
    |> Enum.zip(free_slots)
    |> Enum.reduce(preserved_assignments, fn {source_id, slot}, assignments ->
      Map.put(assignments, source_id, slot)
    end)
  end

  defp build_routes(sessions, slot_assignments) do
    Enum.reduce(slot_assignments, %{}, fn {destination_id, source_slots}, routes ->
      destination = Map.fetch!(sessions, destination_id)

      Enum.reduce(source_slots, routes, fn {source_id, audio_output_slot}, routes ->
        put_route(
          routes,
          source_id,
          Map.fetch!(sessions, source_id),
          destination_id,
          destination,
          audio_output_slot
        )
      end)
    end)
  end

  defp source_ready?(%{source: %{codec: :opus}}), do: true
  defp source_ready?(_session), do: false

  defp receive_ready?(%{receive_codec: :opus}), do: true
  defp receive_ready?(_session), do: false

  defp sessions_in_started_order(sessions) do
    Enum.sort_by(sessions, fn {_voice_session_id, session} -> session.started_order end)
  end

  defp put_route(
         routes,
         source_voice_session_id,
         %{source: %{track_id: track_id, codec: :opus}},
         destination_voice_session_id,
         %{receive_codec: :opus, session: destination_session},
         audio_output_slot
       ) do
    route = %{
      destination_voice_session_id: destination_voice_session_id,
      audio_output_slot: audio_output_slot,
      session: destination_session
    }

    Map.update(
      routes,
      {source_voice_session_id, track_id},
      %{destination_voice_session_id => route},
      &Map.put(&1, destination_voice_session_id, route)
    )
  end

  defp deliver_route(
         {_destination_id,
          %{
            destination_voice_session_id: destination_voice_session_id,
            audio_output_slot: audio_output_slot,
            session: session
          }},
         packet,
         state
       ) do
    case Map.get(state.sessions, destination_voice_session_id) do
      %{session: ^session} ->
        :ok =
          Session.deliver_rtp(
            session,
            destination_voice_session_id,
            audio_output_slot,
            packet
          )

        record_forward(state)

      _stale_destination ->
        record_drop(state)
    end
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
