defmodule DiscordClone.Voice.Forwarder do
  @moduledoc false

  use GenServer

  alias DiscordClone.Voice.{RoomRegistry, Session, SessionCoordinator}

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
    GenServer.cast(forwarder, {:session_started, voice_session_id, session})
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
  def handle_call(:sync, _from, state), do: {:reply, :ok, state}

  @impl true
  def handle_cast({:session_started, voice_session_id, session}, state) do
    session_state = %{session: session, receive_codec: nil, source: nil}

    {:noreply,
     state
     |> put_in([:sessions, voice_session_id], session_state)
     |> rebuild_routes()}
  end

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

  def handle_cast({:forward_rtp, voice_session_id, inbound_track_id, packet}, state) do
    source = {voice_session_id, inbound_track_id}

    case Map.get(state.routes, source) do
      %{destination_voice_session_id: destination_voice_session_id, session: session} ->
        case Map.get(state.sessions, destination_voice_session_id) do
          %{session: ^session} ->
            :ok = Session.deliver_rtp(session, destination_voice_session_id, packet)
            {:noreply, Map.update!(state, :forwarded_packet_count, &(&1 + 1))}

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
      %{}
      |> maybe_put_route(first_id, first, second_id, second)
      |> maybe_put_route(second_id, second, first_id, first)

    %{state | routes: routes}
  end

  defp rebuild_routes(state), do: %{state | routes: %{}}

  defp maybe_put_route(
         routes,
         source_voice_session_id,
         %{source: %{track_id: track_id, codec: :opus}},
         destination_voice_session_id,
         %{receive_codec: :opus, session: destination_session}
       ) do
    Map.put(routes, {source_voice_session_id, track_id}, %{
      destination_voice_session_id: destination_voice_session_id,
      session: destination_session
    })
  end

  defp maybe_put_route(routes, _source_id, _source, _destination_id, _destination), do: routes

  defp record_drop(state), do: Map.update!(state, :dropped_packet_count, &(&1 + 1))

  defp room_server(voice_channel_id) do
    case Registry.lookup(RoomRegistry, {:room, voice_channel_id}) do
      [{pid, _value}] when is_pid(pid) -> pid
      _missing_or_stopped -> nil
    end
  end
end
