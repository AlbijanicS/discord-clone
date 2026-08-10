defmodule DiscordClone.Voice.PeerConnection do
  @moduledoc false

  alias ExWebRTC.{ICECandidate, MediaStreamTrack, PeerConnection, SessionDescription}
  alias ExWebRTC.SDPUtils

  @audio_output_slot_count 4
  @command_timeout_ms 5_000
  @startup_timeout_ms 5_000
  @ice_servers []
  @test_environment Code.ensure_loaded?(Mix) and Mix.env() == :test

  defstruct [
    :peer_connection,
    :expected_inbound_track_id,
    :audio_output_slot_track_ids,
    :test_candidate_observer,
    :test_rtp_observer,
    remote_description?: false
  ]

  @type t :: %__MODULE__{
          peer_connection: pid(),
          expected_inbound_track_id: integer() | nil,
          audio_output_slot_track_ids: %{optional(non_neg_integer()) => integer()} | nil,
          test_candidate_observer: pid() | nil,
          test_rtp_observer: pid() | nil,
          remote_description?: boolean()
        }

  @spec start(keyword()) :: {:ok, t()} | {:error, :peer_connection_unavailable}
  def start(options \\ []) do
    peer_connection_options =
      options
      |> Keyword.put_new(:ice_servers, @ice_servers)
      |> Keyword.put(:controlling_process, self())

    case PeerConnection.start_link(peer_connection_options) do
      {:ok, peer_connection} ->
        case await_ready(peer_connection, options) do
          :ok ->
            {:ok,
             %__MODULE__{
               peer_connection: peer_connection,
               audio_output_slot_track_ids: %{},
               test_candidate_observer: test_candidate_observer(options),
               test_rtp_observer: test_rtp_observer(options)
             }}

          {:error, _reason} ->
            stop(%__MODULE__{peer_connection: peer_connection})
            {:error, :peer_connection_unavailable}
        end

      {:error, _reason} ->
        {:error, :peer_connection_unavailable}
    end
  rescue
    _error -> {:error, :peer_connection_unavailable}
  catch
    :exit, _reason -> {:error, :peer_connection_unavailable}
  end

  defp await_ready(peer_connection, options) do
    await_test_readiness_gate(options)
    _ = GenServer.call(peer_connection, :get_transceivers, @startup_timeout_ms)
    :ok
  catch
    :exit, _reason -> {:error, :peer_connection_unavailable}
  end

  defp await_test_readiness_gate(options) do
    if @test_environment do
      case Keyword.get(options, :test_readiness_gate) do
        {observer, reference} when is_pid(observer) and is_reference(reference) ->
          send(observer, {:peer_connection_starting, reference, self()})

          receive do
            {:release_peer_connection_start, ^reference} -> :ok
          end

        _missing_gate ->
          :ok
      end
    else
      :ok
    end
  end

  @spec accept_offer(t(), map(), timeout()) ::
          {:ok, map(), t()}
          | {:error, :incompatible_audio_output_slots | :negotiation_failed}
  def accept_offer(%__MODULE__{} = state, description, timeout \\ @command_timeout_ms) do
    accept_offer_until(state, description, deadline(timeout))
  end

  @doc false
  @spec validate_audio_topology(map()) :: :ok | {:error, :incompatible_audio_output_slots}
  def validate_audio_topology(description) do
    case compatible_audio_topology(description) do
      {:ok, _topology} -> :ok
      {:error, _reason} -> {:error, :incompatible_audio_output_slots}
    end
  end

  @spec accept_offer_until(t(), map(), integer()) ::
          {:ok, map(), t()}
          | {:error, :incompatible_audio_output_slots | :negotiation_failed}
  def accept_offer_until(%__MODULE__{} = state, description, deadline) do
    with {:ok, audio_topology} <- compatible_audio_topology(description),
         :ok <-
           peer_call(
             state.peer_connection,
             {:set_remote_description, SessionDescription.from_json(description)},
             deadline
           ),
         {:ok, inbound_track_id, output_slot_track_ids} <-
           provision_audio_topology(state.peer_connection, audio_topology, deadline),
         {:ok, answer} <- peer_call(state.peer_connection, :create_answer, deadline),
         :ok <-
           peer_call(
             state.peer_connection,
             {:set_local_description, answer},
             deadline
           ) do
      {:ok, SessionDescription.to_json(answer),
       %{
         state
         | expected_inbound_track_id: inbound_track_id,
           audio_output_slot_track_ids: output_slot_track_ids,
           remote_description?: true
       }}
    else
      {:error, :incompatible_audio_output_slots} = error -> error
      {:error, _reason} -> {:error, :negotiation_failed}
    end
  rescue
    _error -> {:error, :negotiation_failed}
  end

  @spec add_ice_candidate(t(), map(), timeout()) :: :ok | {:error, :candidate_rejected}
  def add_ice_candidate(_state, _candidate, timeout \\ @command_timeout_ms)

  def add_ice_candidate(state, candidate, timeout),
    do: add_ice_candidate_until(state, candidate, deadline(timeout))

  @spec add_ice_candidate_until(t(), map(), integer()) ::
          :ok | {:error, :candidate_rejected}
  def add_ice_candidate_until(
        %__MODULE__{remote_description?: true} = state,
        candidate,
        deadline
      ) do
    case peer_call(
           state.peer_connection,
           {:add_ice_candidate, ICECandidate.from_json(candidate)},
           deadline
         ) do
      :ok ->
        notify_test_candidate_observer(state, candidate)
        :ok

      {:error, _reason} ->
        {:error, :candidate_rejected}
    end
  rescue
    _error -> {:error, :candidate_rejected}
  end

  def add_ice_candidate_until(%__MODULE__{}, _candidate, _deadline),
    do: {:error, :candidate_rejected}

  @spec route_media(t(), term()) ::
          {{:accepted_inbound_track, integer()}
           | {:accepted_inbound_rtp, integer(), ExRTP.Packet.t()}
           | {:accepted_inbound_track_muted, integer()}
           | {:accepted_inbound_track_ended, integer()}
           | :dropped_rtp
           | :dropped_media
           | :ignore, t()}
  def route_media(
        %__MODULE__{peer_connection: peer_connection} = state,
        {:ex_webrtc, peer_connection, message}
      ) do
    route_peer_media(state, message)
  end

  def route_media(%__MODULE__{} = state, _message), do: {:ignore, state}

  @spec send_rtp(t(), non_neg_integer(), ExRTP.Packet.t()) ::
          :ok | {:error, :outbound_track_unavailable}
  def send_rtp(
        %__MODULE__{
          peer_connection: peer_connection,
          audio_output_slot_track_ids: audio_output_slot_track_ids
        } = state,
        audio_output_slot,
        packet
      )
      when is_map(audio_output_slot_track_ids) and is_integer(audio_output_slot) do
    case Map.fetch(audio_output_slot_track_ids, audio_output_slot) do
      {:ok, outbound_track_id} ->
        notify_test_rtp_observer(state, outbound_track_id, packet)
        PeerConnection.send_rtp(peer_connection, outbound_track_id, packet)

      :error ->
        {:error, :outbound_track_unavailable}
    end
  end

  def send_rtp(%__MODULE__{}, _audio_output_slot, _packet),
    do: {:error, :outbound_track_unavailable}

  @spec signal(t(), term()) ::
          {:ice_candidate, map()}
          | {:connection_state_change, atom()}
          | :end_of_candidates
          | :ignore
  def signal(
        %__MODULE__{peer_connection: peer_connection},
        {:ex_webrtc, peer_connection, {:ice_candidate, candidate}}
      ) do
    {:ice_candidate, ICECandidate.to_json(candidate)}
  end

  def signal(
        %__MODULE__{peer_connection: peer_connection},
        {:ex_webrtc, peer_connection, {:connection_state_change, state}}
      )
      when state in [:new, :connecting, :connected, :disconnected, :failed, :closed] do
    {:connection_state_change, state}
  end

  def signal(
        %__MODULE__{peer_connection: peer_connection},
        {:ex_webrtc, peer_connection, {:ice_gathering_state_change, :complete}}
      ) do
    :end_of_candidates
  end

  def signal(%__MODULE__{}, _message), do: :ignore

  @spec stop(t()) :: :ok
  def stop(%__MODULE__{peer_connection: peer_connection}) do
    PeerConnection.stop(peer_connection)
  catch
    :exit, _reason -> :ok
  end

  defp compatible_audio_topology(%{"type" => "offer", "sdp" => raw_sdp})
       when is_binary(raw_sdp) do
    with {:ok, sdp} <- ExSDP.parse(raw_sdp) do
      compatible_audio_mlines = Enum.filter(sdp.media, &compatible_audio_mline?/1)

      source_mlines =
        Enum.filter(
          compatible_audio_mlines,
          &(SDPUtils.get_media_direction(&1) in [:sendonly, :sendrecv])
        )

      output_slot_mlines =
        Enum.filter(compatible_audio_mlines, &(SDPUtils.get_media_direction(&1) == :recvonly))

      case {source_mlines, output_slot_mlines} do
        {[source_mline], output_slot_mlines}
        when length(output_slot_mlines) == @audio_output_slot_count ->
          {:ok,
           %{
             source_mid: media_mid(source_mline),
             output_slot_mids: Enum.map(output_slot_mlines, &media_mid/1)
           }}

        {[_source_mline], _wrong_output_slot_count} ->
          {:error, :incompatible_audio_output_slots}

        _incompatible_source ->
          {:error, :incompatible_media}
      end
    end
  end

  defp compatible_audio_topology(_description), do: {:error, :incompatible_media}

  defp provision_audio_topology(peer_connection, audio_topology, deadline) do
    transceivers = peer_call(peer_connection, :get_transceivers, deadline)
    transceivers_by_mid = Map.new(transceivers, &{&1.mid, &1})

    with %{receiver: %{track: %{id: inbound_track_id}}} <-
           Map.get(transceivers_by_mid, audio_topology.source_mid),
         {:ok, output_slot_track_ids} <-
           provision_audio_output_slots(
             peer_connection,
             transceivers_by_mid,
             audio_topology.output_slot_mids,
             deadline
           ) do
      {:ok, inbound_track_id, output_slot_track_ids}
    else
      _missing_transceiver -> {:error, :incompatible_media}
    end
  end

  defp provision_audio_output_slots(
         peer_connection,
         transceivers_by_mid,
         output_slot_mids,
         deadline
       ) do
    output_slot_mids
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, %{}}, fn {mid, slot}, {:ok, track_ids} ->
      with %{id: transceiver_id, sender: %{id: sender_id}} <-
             Map.get(transceivers_by_mid, mid),
           :ok <-
             peer_call(
               peer_connection,
               {:set_transceiver_direction, transceiver_id, :sendonly},
               deadline
             ),
           track = MediaStreamTrack.new(:audio),
           :ok <-
             peer_call(
               peer_connection,
               {:replace_track, sender_id, track},
               deadline
             ) do
        {:cont, {:ok, Map.put(track_ids, slot, track.id)}}
      else
        _error -> {:halt, {:error, :audio_output_slot_unavailable}}
      end
    end)
  end

  defp media_mid(mline) do
    {:mid, mid} = ExSDP.get_attribute(mline, :mid)
    mid
  end

  defp compatible_audio_mline?(%{type: :audio, port: port} = mline) when port != 0 do
    mline
    |> SDPUtils.get_rtp_codec_parameters()
    |> Enum.any?(&opus?/1)
  end

  defp compatible_audio_mline?(_mline), do: false

  defp peer_call(peer_connection, request, :infinity),
    do: GenServer.call(peer_connection, request, :infinity)

  defp peer_call(peer_connection, request, deadline) do
    timeout = deadline - System.monotonic_time(:millisecond)

    if timeout <= 0 do
      exit({:timeout, {__MODULE__, :peer_call}})
    else
      GenServer.call(peer_connection, request, timeout)
    end
  end

  defp deadline(:infinity), do: :infinity
  defp deadline(timeout), do: System.monotonic_time(:millisecond) + timeout

  defp test_candidate_observer(options) do
    if @test_environment do
      Keyword.get(options, :test_candidate_observer)
    end
  end

  defp test_rtp_observer(options) do
    if @test_environment do
      Keyword.get(options, :test_rtp_observer)
    end
  end

  defp notify_test_candidate_observer(%{test_candidate_observer: observer}, candidate)
       when is_pid(observer) do
    send(observer, {:peer_connection_candidate_applied, candidate})
  end

  defp notify_test_candidate_observer(_state, _candidate), do: :ok

  defp opus?(%{mime_type: "audio/opus", clock_rate: 48_000, channels: channels})
       when channels in [1, 2],
       do: true

  defp opus?(_codec), do: false

  defp route_peer_media(
         %__MODULE__{expected_inbound_track_id: expected_track_id} = state,
         {:track, %{id: expected_track_id, kind: :audio}}
       )
       when not is_nil(expected_track_id) do
    {{:accepted_inbound_track, expected_track_id}, state}
  end

  defp route_peer_media(
         %__MODULE__{
           expected_inbound_track_id: expected_track_id
         } = state,
         {:rtp, expected_track_id, _rid, packet}
       )
       when not is_nil(expected_track_id) do
    {{:accepted_inbound_rtp, expected_track_id, packet}, state}
  end

  defp route_peer_media(state, {:rtp, _track_id, _rid, _packet}), do: {:dropped_rtp, state}

  defp route_peer_media(
         %__MODULE__{expected_inbound_track_id: expected_track_id} = state,
         {:track_muted, expected_track_id}
       )
       when not is_nil(expected_track_id) do
    {{:accepted_inbound_track_muted, expected_track_id}, state}
  end

  defp route_peer_media(
         %__MODULE__{expected_inbound_track_id: expected_track_id} = state,
         {:track_ended, expected_track_id}
       )
       when not is_nil(expected_track_id) do
    {{:accepted_inbound_track_ended, expected_track_id},
     %{state | expected_inbound_track_id: nil}}
  end

  defp route_peer_media(state, {:track, _track}), do: {:dropped_media, state}
  defp route_peer_media(state, {:track_muted, _track_id}), do: {:dropped_media, state}
  defp route_peer_media(state, {:track_ended, _track_id}), do: {:dropped_media, state}
  defp route_peer_media(state, {:data_channel, _channel}), do: {:dropped_media, state}

  defp route_peer_media(state, {:data_channel_state_change, _channel_ref, _state}),
    do: {:dropped_media, state}

  defp route_peer_media(state, {:data, _channel_ref, _data}), do: {:dropped_media, state}
  defp route_peer_media(state, {:rtcp, _packets}), do: {:dropped_media, state}
  defp route_peer_media(state, _message), do: {:ignore, state}

  defp notify_test_rtp_observer(
         %{test_rtp_observer: observer, peer_connection: peer_connection},
         track_id,
         packet
       )
       when is_pid(observer) do
    send(observer, {:peer_connection_rtp_sent, peer_connection, track_id, packet})
  end

  defp notify_test_rtp_observer(_state, _track_id, _packet), do: :ok
end
