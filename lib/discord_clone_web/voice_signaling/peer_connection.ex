defmodule DiscordCloneWeb.VoiceSignaling.PeerConnection do
  @moduledoc false

  alias DiscordCloneWeb.VoiceSignaling.Configuration
  alias ExWebRTC.{ICECandidate, MediaStreamTrack, PeerConnection, SessionDescription}

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

  @spec start() :: {:ok, t()} | {:error, :peer_connection_unavailable}
  def start do
    case PeerConnection.start_link(ice_servers: Configuration.ice_servers()) do
      {:ok, peer_connection} -> {:ok, %__MODULE__{peer_connection: peer_connection}}
      {:error, _reason} -> {:error, :peer_connection_unavailable}
    end
  end

  @spec accept_offer(t(), map()) :: {:ok, map(), t()} | {:error, :negotiation_failed}
  def accept_offer(%__MODULE__{} = state, description) do
    with :ok <-
           PeerConnection.set_remote_description(
             state.peer_connection,
             SessionDescription.from_json(description)
           ),
         {:ok, inbound_track_id} <- compatible_inbound_track_id(state.peer_connection),
         {:ok, sender} <-
           PeerConnection.add_track(state.peer_connection, MediaStreamTrack.new(:audio)),
         {:ok, answer} <- PeerConnection.create_answer(state.peer_connection),
         :ok <- PeerConnection.set_local_description(state.peer_connection, answer) do
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

  @spec add_ice_candidate(t(), map()) :: :ok | {:error, :candidate_rejected}
  def add_ice_candidate(%__MODULE__{remote_description?: true} = state, candidate) do
    case PeerConnection.add_ice_candidate(
           state.peer_connection,
           ICECandidate.from_json(candidate)
         ) do
      :ok -> :ok
      {:error, _reason} -> {:error, :candidate_rejected}
    end
  rescue
    _error -> {:error, :candidate_rejected}
  end

  def add_ice_candidate(%__MODULE__{}, _candidate), do: {:error, :candidate_rejected}

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

  defp compatible_inbound_track_id(peer_connection) do
    case Enum.filter(PeerConnection.get_transceivers(peer_connection), &compatible_audio?/1) do
      [transceiver] -> {:ok, transceiver.receiver.track.id}
      _other -> {:error, :incompatible_media}
    end
  end

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
