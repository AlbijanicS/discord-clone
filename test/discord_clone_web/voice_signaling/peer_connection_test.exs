defmodule DiscordCloneWeb.VoiceSignaling.PeerConnectionTest do
  use ExUnit.Case, async: true

  alias DiscordCloneWeb.VoiceSignaling.PeerConnection
  alias DiscordCloneWeb.VoiceSignaling.RealMessage
  import DiscordCloneWeb.VoiceSignalingHelpers

  test "creates a serialized answer for a browser-shaped offer" do
    offer = browser_offer()

    assert {:ok, peer_connection} = PeerConnection.start()

    assert {:ok, answer, peer_connection} = PeerConnection.accept_offer(peer_connection, offer)
    assert %{"type" => "answer", "sdp" => sdp} = answer
    assert is_binary(sdp)
    assert byte_size(sdp) > 0

    assert :ok = PeerConnection.stop(peer_connection)
  end

  test "provisions an Opus echo sender and routes only its accepted inbound track" do
    peer_connection = start_supervised_peer_connection()

    assert {:ok, _answer, peer_connection} =
             PeerConnection.accept_offer(peer_connection, browser_offer())

    [transceiver] = ExWebRTC.PeerConnection.get_transceivers(peer_connection.peer_connection)
    assert transceiver.kind == :audio
    assert transceiver.direction == :sendrecv
    assert transceiver.sender.track.id == peer_connection.outbound_track_id
    assert Enum.any?(transceiver.codecs, &(&1.mime_type == "audio/opus"))

    inbound_track = transceiver.receiver.track

    assert {:accepted_inbound_track, peer_connection} =
             PeerConnection.route_media(peer_connection, {
               :ex_webrtc,
               peer_connection.peer_connection,
               {:track, inbound_track}
             })

    packet =
      ExRTP.Packet.new(<<1, 2, 3>>, payload_type: 111, sequence_number: 1, timestamp: 1, ssrc: 1)

    assert {:echoed_rtp, ^peer_connection} =
             PeerConnection.route_media(peer_connection, {
               :ex_webrtc,
               peer_connection.peer_connection,
               {:rtp, inbound_track.id, nil, packet}
             })

    assert {:dropped_rtp, ^peer_connection} =
             PeerConnection.route_media(peer_connection, {
               :ex_webrtc,
               peer_connection.peer_connection,
               {:rtp, inbound_track.id + 1, nil, packet}
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
    assert {:ok, peer_connection} = PeerConnection.start()
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
