defmodule DiscordClone.Voice.Session do
  @moduledoc false

  use GenServer, restart: :temporary

  alias DiscordClone.Voice.{Diagnostics, PeerConnection}

  @command_timeout_ms 5_000
  @test_environment Code.ensure_loaded?(Mix) and Mix.env() == :test
  @max_accepted_candidates 64
  @max_pending_candidates 16
  @max_pending_candidate_bytes @max_pending_candidates * 8 * 1024

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @spec accept_offer(pid(), binary(), map(), integer()) ::
          {:ok, map()} | {:error, atom()}
  def accept_offer(session, negotiation_id, description) do
    accept_offer(session, negotiation_id, description, command_deadline())
  end

  def accept_offer(session, negotiation_id, description, deadline) do
    GenServer.call(
      session,
      {:accept_offer, negotiation_id, description, deadline},
      remaining_timeout(deadline)
    )
  end

  @spec add_ice_candidate(pid(), binary(), map(), integer()) ::
          {:ok, map()} | {:error, atom()}
  def add_ice_candidate(session, negotiation_id, candidate) do
    add_ice_candidate(session, negotiation_id, candidate, command_deadline())
  end

  def add_ice_candidate(session, negotiation_id, candidate, deadline) do
    GenServer.call(
      session,
      {:add_ice_candidate, negotiation_id, candidate, deadline},
      remaining_timeout(deadline)
    )
  end

  @spec end_of_candidates(pid(), binary(), integer()) :: {:error, atom()}
  def end_of_candidates(session, negotiation_id) do
    end_of_candidates(session, negotiation_id, command_deadline())
  end

  def end_of_candidates(session, negotiation_id, deadline) do
    GenServer.call(
      session,
      {:end_of_candidates, negotiation_id, deadline},
      remaining_timeout(deadline)
    )
  end

  @spec deliver_rtp(pid(), Ecto.UUID.t(), ExRTP.Packet.t()) :: :ok
  def deliver_rtp(session, voice_session_id, packet) do
    GenServer.cast(session, {:deliver_rtp, voice_session_id, packet})
  end

  @spec crash(pid()) :: :ok
  def crash(session) do
    Process.exit(session, :kill)
    :ok
  end

  @impl true
  def init(opts) do
    signaling_channel = Keyword.fetch!(opts, :signaling_channel)

    peer_connection_opts =
      if @test_environment do
        Keyword.get(opts, :test_peer_connection_opts, [])
      else
        []
      end

    case PeerConnection.start(peer_connection_opts) do
      {:ok, peer_connection} ->
        {:ok,
         %{
           room_server: Keyword.fetch!(opts, :room_server),
           voice_session_id: Keyword.fetch!(opts, :voice_session_id),
           signaling_channel: signaling_channel,
           signaling_channel_monitor: Process.monitor(signaling_channel),
           peer_connection: peer_connection,
           negotiation_id: nil,
           pending_candidates: [],
           accepted_candidate_count: 0,
           media_counts: empty_media_counts()
         }}

      {:error, :peer_connection_unavailable} ->
        {:stop, :peer_connection_unavailable}
    end
  end

  @impl true
  def handle_call({:accept_offer, negotiation_id, description, deadline}, _from, state) do
    case state.negotiation_id do
      nil ->
        case PeerConnection.accept_offer_until(state.peer_connection, description, deadline) do
          {:ok, answer, peer_connection} ->
            {peer_connection, accepted_candidate_count} =
              apply_pending_candidates(
                peer_connection,
                state,
                negotiation_id,
                deadline
              )

            {:reply, {:ok, answer},
             %{
               state
               | peer_connection: peer_connection,
                 negotiation_id: negotiation_id,
                 pending_candidates: [],
                 accepted_candidate_count: accepted_candidate_count
             }}

          {:error, :negotiation_failed} ->
            {:stop, :normal, {:error, :negotiation_failed}, state}
        end

      _active_negotiation ->
        {:reply, {:error, :negotiation_already_active}, state}
    end
  end

  def handle_call({:add_ice_candidate, negotiation_id, candidate, deadline}, _from, state) do
    case state.negotiation_id do
      nil -> queue_candidate(state, negotiation_id, candidate)
      ^negotiation_id -> add_current_candidate(state, negotiation_id, candidate, deadline)
      _stale_negotiation -> {:reply, {:error, :invalid_negotiation}, state}
    end
  end

  def handle_call({:end_of_candidates, negotiation_id, _deadline}, _from, state) do
    if state.negotiation_id == negotiation_id do
      {:reply, {:error, :end_of_candidates_unsupported}, state}
    else
      {:reply, {:error, :invalid_negotiation}, state}
    end
  end

  @impl true
  def handle_cast(
        {:deliver_rtp, voice_session_id, packet},
        %{voice_session_id: voice_session_id} = state
      ) do
    case PeerConnection.send_rtp(state.peer_connection, packet) do
      :ok ->
        {:noreply,
         record_media(state, state.peer_connection, :rtp_routed, [:forwarded_packet_count])}

      {:error, :outbound_track_unavailable} ->
        {:noreply, record_dropped_rtp(state)}
    end
  end

  def handle_cast({:deliver_rtp, _stale_voice_session_id, _packet}, state) do
    {:noreply, record_dropped_rtp(state)}
  end

  @impl true
  def handle_info(
        {:DOWN, signaling_channel_monitor, :process, _signaling_channel, _reason},
        %{signaling_channel_monitor: signaling_channel_monitor} = state
      ) do
    GenServer.cast(state.room_server, {:signaling_channel_down, state.voice_session_id})
    {:stop, :normal, state}
  end

  def handle_info(
        {:ex_webrtc, peer_connection, _message} = message,
        %{peer_connection: %PeerConnection{peer_connection: peer_connection}} = state
      ) do
    case PeerConnection.route_media(state.peer_connection, message) do
      {:ignore, peer_connection} ->
        handle_peer_signal(peer_connection, message, state)

      {outcome, peer_connection} ->
        {:noreply, record_media_outcome(state, peer_connection, outcome)}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{peer_connection: peer_connection}) do
    PeerConnection.stop(peer_connection)
    :ok
  end

  defp handle_peer_signal(peer_connection, message, state) do
    state = %{state | peer_connection: peer_connection}

    case PeerConnection.signal(peer_connection, message) do
      {:ice_candidate, candidate} when is_binary(state.negotiation_id) ->
        send_event(state, {:ice_candidate, state.negotiation_id, candidate})
        {:noreply, state}

      :end_of_candidates when is_binary(state.negotiation_id) ->
        send_event(state, {:end_of_candidates, state.negotiation_id})
        {:noreply, state}

      {:connection_state_change, connection_state} ->
        Diagnostics.emit("connection_state", :accepted, connection_state: connection_state)

        if connection_state in [:failed, :closed] do
          send_event(state, {:connection_state_change, connection_state, state.negotiation_id})
          {:stop, :normal, state}
        else
          {:noreply, state}
        end

      _other ->
        {:noreply, state}
    end
  end

  defp queue_candidate(state, negotiation_id, candidate) do
    pending_candidates = state.pending_candidates

    if length(pending_candidates) < @max_pending_candidates and
         Enum.sum(Enum.map(pending_candidates, & &1.byte_count)) + candidate.byte_count <=
           @max_pending_candidate_bytes do
      {:reply, {:ok, %{negotiation_id: negotiation_id}},
       %{state | pending_candidates: [candidate | pending_candidates]}}
    else
      {:reply, {:error, :pending_candidate_limit_reached}, state}
    end
  end

  defp add_current_candidate(state, negotiation_id, candidate, deadline) do
    with :ok <- under_candidate_limit?(state),
         :ok <-
           PeerConnection.add_ice_candidate_until(
             state.peer_connection,
             candidate.candidate,
             deadline
           ) do
      {:reply, {:ok, %{negotiation_id: negotiation_id}},
       %{state | accepted_candidate_count: state.accepted_candidate_count + 1}}
    else
      {:error, error_code} -> {:reply, {:error, error_code}, state}
    end
  end

  defp apply_pending_candidates(peer_connection, state, negotiation_id, deadline) do
    state.pending_candidates
    |> Enum.filter(&(&1.negotiation_id == negotiation_id))
    |> Enum.reverse()
    |> Enum.reduce({peer_connection, 0}, fn candidate, {peer_connection, accepted_count} ->
      case PeerConnection.add_ice_candidate_until(peer_connection, candidate.candidate, deadline) do
        :ok -> {peer_connection, accepted_count + 1}
        {:error, _error_code} -> {peer_connection, accepted_count}
      end
    end)
  end

  defp under_candidate_limit?(%{accepted_candidate_count: count})
       when count < @max_accepted_candidates,
       do: :ok

  defp under_candidate_limit?(_state), do: {:error, :candidate_limit_reached}

  defp remaining_timeout(deadline) do
    max(deadline - System.monotonic_time(:millisecond), 1)
  end

  defp command_deadline do
    System.monotonic_time(:millisecond) + @command_timeout_ms
  end

  defp send_event(state, event) do
    send(state.signaling_channel, {:voice_session_event, state.voice_session_id, event})
  end

  defp record_media_outcome(state, peer_connection, {:accepted_inbound_track, _track_id}) do
    record_media(state, peer_connection, :inbound_track_admitted, [])
  end

  defp record_media_outcome(
         state,
         peer_connection,
         {:accepted_inbound_rtp, _track_id, _packet}
       ) do
    record_media(state, peer_connection, :rtp_received, [:inbound_packet_count])
  end

  defp record_media_outcome(state, peer_connection, :dropped_rtp) do
    record_media(state, peer_connection, :unexpected_media_dropped, [:dropped_packet_count])
  end

  defp record_media_outcome(state, peer_connection, :dropped_media) do
    record_media(state, peer_connection, :unexpected_media_dropped, [:dropped_media_count])
  end

  defp record_dropped_rtp(state) do
    record_media(state, state.peer_connection, :unexpected_media_dropped, [
      :dropped_packet_count
    ])
  end

  defp record_media(state, peer_connection, lifecycle, count_names) do
    media_counts =
      Enum.reduce(count_names, state.media_counts, &increment_media_count(&2, &1))

    Diagnostics.emit_media(lifecycle, media_counts)

    %{state | peer_connection: peer_connection, media_counts: media_counts}
  end

  defp increment_media_count(media_counts, count_name) do
    Map.update!(media_counts, count_name, &(&1 + 1))
  end

  defp empty_media_counts do
    %{
      inbound_packet_count: 0,
      forwarded_packet_count: 0,
      dropped_packet_count: 0,
      dropped_media_count: 0
    }
  end
end
