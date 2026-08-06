defmodule DiscordClone.Voice.PeerConnectionTest do
  use ExUnit.Case, async: true

  alias DiscordClone.Voice.PeerConnection
  alias DiscordCloneWeb.VoiceSignaling.RealMessage
  import DiscordCloneWeb.VoiceSignalingHelpers

  test "creates a serialized answer for a browser-shaped offer" do
    offer = browser_offer()
    peer_connection = start_supervised_peer_connection()

    assert {:ok, answer, _peer_connection} = PeerConnection.accept_offer(peer_connection, offer)
    assert %{"type" => "answer", "sdp" => sdp} = answer
    assert is_binary(sdp)
    assert byte_size(sdp) > 0
  end

  test "rejects startup failure without leaving a PeerConnection process behind" do
    running_before = MapSet.new(ExWebRTC.PeerConnection.get_all_running())

    assert {:error, :peer_connection_unavailable} =
             PeerConnection.start(audio_codecs: [:invalid])

    assert MapSet.new(ExWebRTC.PeerConnection.get_all_running()) == running_before
  end

  test "returns accepted source media without echoing and sends through its destination track" do
    peer_connection =
      start_supervised_peer_connection()
      |> Map.put(:test_rtp_observer, self())

    assert {:ok, _answer, peer_connection} =
             PeerConnection.accept_offer(peer_connection, browser_offer())

    [transceiver] = ExWebRTC.PeerConnection.get_transceivers(peer_connection.peer_connection)
    assert transceiver.kind == :audio
    assert transceiver.direction == :sendrecv
    assert transceiver.sender.track.id == peer_connection.outbound_track_id
    assert Enum.any?(transceiver.codecs, &(&1.mime_type == "audio/opus"))

    inbound_track = transceiver.receiver.track

    assert {{:accepted_inbound_track, inbound_track_id}, peer_connection} =
             PeerConnection.route_media(peer_connection, {
               :ex_webrtc,
               peer_connection.peer_connection,
               {:track, inbound_track}
             })

    assert inbound_track_id == inbound_track.id

    packet =
      ExRTP.Packet.new(<<1, 2, 3>>, payload_type: 111, sequence_number: 1, timestamp: 1, ssrc: 1)

    assert {{:accepted_inbound_rtp, ^inbound_track_id, ^packet}, ^peer_connection} =
             PeerConnection.route_media(peer_connection, {
               :ex_webrtc,
               peer_connection.peer_connection,
               {:rtp, inbound_track.id, nil, packet}
             })

    refute_receive {:peer_connection_rtp_sent, _, _, _}, 0

    assert :ok = PeerConnection.send_rtp(peer_connection, packet)

    peer_connection_pid = peer_connection.peer_connection
    outbound_track_id = peer_connection.outbound_track_id

    assert_receive {:peer_connection_rtp_sent, ^peer_connection_pid, ^outbound_track_id, ^packet}

    _ = :sys.get_state(peer_connection.peer_connection)

    assert %{packets_sent: 1, bytes_sent: bytes_sent} =
             peer_connection.peer_connection
             |> ExWebRTC.PeerConnection.get_stats()
             |> Map.values()
             |> Enum.find(fn stats ->
               stats.type == :outbound_rtp and
                 stats.track_identifier == peer_connection.outbound_track_id
             end)

    assert bytes_sent > byte_size(packet.payload)

    assert {:dropped_rtp, ^peer_connection} =
             PeerConnection.route_media(peer_connection, {
               :ex_webrtc,
               peer_connection.peer_connection,
               {:rtp, inbound_track.id + 1, nil, packet}
             })
  end

  test "drops unsupported media and ignores RTP from another PeerConnection" do
    peer_connection = start_supervised_peer_connection()

    packet =
      ExRTP.Packet.new(<<1, 2, 3>>, payload_type: 111, sequence_number: 1, timestamp: 1, ssrc: 1)

    for message <- [
          {:track, %ExWebRTC.MediaStreamTrack{id: 1, kind: :video}},
          {:track_muted, 1},
          {:track_ended, 1},
          {:data_channel, %{}},
          {:data_channel_state_change, make_ref(), :open},
          {:data, make_ref(), "unsupported"},
          {:rtcp, []}
        ] do
      assert {:dropped_media, ^peer_connection} =
               PeerConnection.route_media(peer_connection, {
                 :ex_webrtc,
                 peer_connection.peer_connection,
                 message
               })
    end

    assert {:dropped_rtp, ^peer_connection} =
             PeerConnection.route_media(peer_connection, {
               :ex_webrtc,
               peer_connection.peer_connection,
               {:rtp, 1, nil, packet}
             })

    assert {:ignore, ^peer_connection} =
             PeerConnection.route_media(peer_connection, {
               :ex_webrtc,
               self(),
               {:rtp, 1, nil, packet}
             })
  end

  test "rejects an offer without a compatible Opus audio source" do
    peer_connection = start_supervised_peer_connection()
    offer = browser_offer()

    incompatible_offer =
      Map.update!(offer, "sdp", &String.replace(&1, "opus/48000/2", "ISAC/16000"))

    assert {:error, :negotiation_failed} =
             PeerConnection.accept_offer(peer_connection, incompatible_offer)
  end

  test "serializes server ICE messages and stops its linked peer process" do
    peer_connection = start_supervised_peer_connection()
    monitor_ref = Process.monitor(peer_connection.peer_connection)

    candidate = %ExWebRTC.ICECandidate{
      candidate: "candidate:1 1 udp 1 127.0.0.1 9 typ host",
      sdp_mid: "0",
      sdp_m_line_index: 0
    }

    assert {:ice_candidate, %{"candidate" => "candidate:1 1 udp 1 127.0.0.1 9 typ host"}} =
             PeerConnection.signal(peer_connection, {
               :ex_webrtc,
               peer_connection.peer_connection,
               {:ice_candidate, candidate}
             })

    assert :ok = PeerConnection.stop(peer_connection)
    assert_receive {:DOWN, ^monitor_ref, :process, _, :normal}
  end

  test "accepts a browser-shaped ICE candidate without a username fragment" do
    payload = %{
      "signaling_session_id" => "current-session",
      "negotiation_id" => "current-negotiation",
      "candidate" => %{
        "candidate" => "candidate:1 1 udp 1 127.0.0.1 9 typ host",
        "sdpMid" => "0",
        "sdpMLineIndex" => 0
      }
    }

    assert {:ok, %{negotiation_id: "current-negotiation", candidate: candidate}} =
             RealMessage.ice_candidate(payload)

    assert candidate["usernameFragment"] == nil
  end

  test "ExWebRTC 0.17.0 marks remote ICE gathering complete with an empty candidate" do
    peer_connection = start_supervised_peer_connection()

    assert {:ok, _answer, peer_connection} =
             PeerConnection.accept_offer(peer_connection, browser_offer())

    peer_connection_pid = peer_connection.peer_connection

    assert_receive {
      :ex_webrtc,
      ^peer_connection_pid,
      {:ice_gathering_state_change, :complete}
    }

    end_of_candidates = %ExWebRTC.ICECandidate{
      candidate: "",
      sdp_mid: "0",
      sdp_m_line_index: 0
    }

    assert :ok =
             ExWebRTC.PeerConnection.add_ice_candidate(
               peer_connection.peer_connection,
               end_of_candidates
             )

    assert :ok = PeerConnection.stop(peer_connection)
  end

  test "serializes the server gathering-complete notification as an end marker" do
    peer_connection = start_supervised_peer_connection()

    assert :end_of_candidates =
             PeerConnection.signal(peer_connection, {
               :ex_webrtc,
               peer_connection.peer_connection,
               {:ice_gathering_state_change, :complete}
             })

    assert :ok = PeerConnection.stop(peer_connection)
  end

  defp start_supervised_peer_connection do
    peer_connection =
      start_supervised!(%{
        id: make_ref(),
        start:
          {ExWebRTC.PeerConnection, :start_link, [[ice_servers: [], controlling_process: self()]]}
      })

    %PeerConnection{peer_connection: peer_connection}
  end
end
