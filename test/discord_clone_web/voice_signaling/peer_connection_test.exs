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
end
