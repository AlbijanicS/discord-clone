defmodule DiscordClone.Voice.PeerConnection do
  @moduledoc false

  alias ExWebRTC.{ICECandidate, MediaStreamTrack, PeerConnection, SessionDescription}

  @command_timeout_ms 5_000
  @startup_timeout_ms 5_000
  @ice_servers []
  @test_environment Code.ensure_loaded?(Mix) and Mix.env() == :test

  defstruct [
    :peer_connection,
    :expected_inbound_track_id,
    :outbound_track_id,
    remote_description?: false
  ]

  @type t :: %__MODULE__{
          peer_connection: pid(),
          expected_inbound_track_id: integer() | nil,
          outbound_track_id: integer() | nil,
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
            {:ok, %__MODULE__{peer_connection: peer_connection}}

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
          {:ok, map(), t()} | {:error, :negotiation_failed}
  def accept_offer(%__MODULE__{} = state, description, timeout \\ @command_timeout_ms) do
    accept_offer_until(state, description, deadline(timeout))
  end

  @spec accept_offer_until(t(), map(), integer()) ::
          {:ok, map(), t()} | {:error, :negotiation_failed}
  def accept_offer_until(%__MODULE__{} = state, description, deadline) do
    with :ok <-
           peer_call(
             state.peer_connection,
             {:set_remote_description, SessionDescription.from_json(description)},
             deadline
           ),
         {:ok, inbound_track_id} <- compatible_inbound_track_id(state.peer_connection, deadline),
         {:ok, sender} <-
           peer_call(
             state.peer_connection,
             {:add_track, MediaStreamTrack.new(:audio)},
             deadline
           ),
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
           outbound_track_id: sender.track.id,
           remote_description?: true
       }}
    else
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
      :ok -> :ok
      {:error, _reason} -> {:error, :candidate_rejected}
    end
  rescue
    _error -> {:error, :candidate_rejected}
  end

  def add_ice_candidate_until(%__MODULE__{}, _candidate, _deadline),
    do: {:error, :candidate_rejected}

  @spec route_media(t(), term()) ::
          {:accepted_inbound_track | :echoed_rtp | :dropped_rtp | :dropped_media | :ignore, t()}
  def route_media(
        %__MODULE__{peer_connection: peer_connection} = state,
        {:ex_webrtc, peer_connection, message}
      ) do
    route_peer_media(state, message)
  end

  def route_media(%__MODULE__{} = state, _message), do: {:ignore, state}

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

  defp compatible_inbound_track_id(peer_connection, deadline) do
    case Enum.filter(
           peer_call(peer_connection, :get_transceivers, deadline),
           &compatible_audio?/1
         ) do
      [transceiver] -> {:ok, transceiver.receiver.track.id}
      _other -> {:error, :incompatible_media}
    end
  end

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

  defp compatible_audio?(%{kind: :audio, direction: direction, codecs: codecs})
       when direction in [:recvonly, :sendrecv] do
    Enum.any?(codecs, &opus?/1)
  end

  defp compatible_audio?(_transceiver), do: false

  defp opus?(%{mime_type: "audio/opus", clock_rate: 48_000, channels: channels})
       when channels in [1, 2],
       do: true

  defp opus?(_codec), do: false

  defp route_peer_media(
         %__MODULE__{expected_inbound_track_id: expected_track_id} = state,
         {:track, %{id: expected_track_id, kind: :audio}}
       )
       when not is_nil(expected_track_id) do
    {:accepted_inbound_track, state}
  end

  defp route_peer_media(
         %__MODULE__{
           peer_connection: peer_connection,
           expected_inbound_track_id: expected_track_id,
           outbound_track_id: outbound_track_id
         } = state,
         {:rtp, expected_track_id, _rid, packet}
       )
       when not is_nil(expected_track_id) and not is_nil(outbound_track_id) do
    :ok = PeerConnection.send_rtp(peer_connection, outbound_track_id, packet)
    {:echoed_rtp, state}
  end

  defp route_peer_media(state, {:rtp, _track_id, _rid, _packet}), do: {:dropped_rtp, state}

  defp route_peer_media(state, {:track, _track}), do: {:dropped_media, state}
  defp route_peer_media(state, {:track_muted, _track_id}), do: {:dropped_media, state}
  defp route_peer_media(state, {:track_ended, _track_id}), do: {:dropped_media, state}
  defp route_peer_media(state, {:data_channel, _channel}), do: {:dropped_media, state}

  defp route_peer_media(state, {:data_channel_state_change, _channel_ref, _state}),
    do: {:dropped_media, state}

  defp route_peer_media(state, {:data, _channel_ref, _data}), do: {:dropped_media, state}
  defp route_peer_media(state, {:rtcp, _packets}), do: {:dropped_media, state}
  defp route_peer_media(state, _message), do: {:ignore, state}
end
