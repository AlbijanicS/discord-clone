defmodule DiscordClone.Voice.SessionTest do
  use ExUnit.Case, async: false

  import DiscordCloneWeb.VoiceSignalingHelpers

  alias DiscordClone.Voice.Session

  test "a destination Session validates its identity and outbound readiness before sending RTP" do
    voice_session_id = Ecto.UUID.generate()
    session = start_session(voice_session_id)

    packet =
      ExRTP.Packet.new(<<1, 2, 3>>, payload_type: 111, sequence_number: 1, timestamp: 1, ssrc: 1)

    assert :ok = Session.deliver_rtp(session, voice_session_id, 0, packet)
    _ = :sys.get_state(session)
    refute_receive {:peer_connection_rtp_sent, _, _, _}, 0

    assert {:ok, _answer} = Session.accept_offer(session, "negotiation-1", browser_offer())

    assert :ok = Session.deliver_rtp(session, Ecto.UUID.generate(), 0, packet)
    _ = :sys.get_state(session)
    refute_receive {:peer_connection_rtp_sent, _, _, _}, 0

    assert :ok = Session.deliver_rtp(session, voice_session_id, 4, packet)
    _ = :sys.get_state(session)
    refute_receive {:peer_connection_rtp_sent, _, _, _}, 0

    assert :ok = Session.deliver_rtp(session, voice_session_id, 2, packet)

    assert_receive {:peer_connection_rtp_sent, peer_connection, outbound_track_id, ^packet}
    assert is_pid(peer_connection)

    expected_track_id =
      peer_connection
      |> ExWebRTC.PeerConnection.get_transceivers()
      |> Enum.filter(&(&1.current_direction == :sendonly))
      |> Enum.at(2)
      |> then(& &1.sender.track.id)

    assert outbound_track_id == expected_track_id
  end

  test "accepted inbound RTP from a lone Session is not echoed" do
    voice_session_id = Ecto.UUID.generate()
    session = start_session(voice_session_id)

    assert {:ok, _answer} = Session.accept_offer(session, "negotiation-1", browser_offer())

    [peer_connection] =
      Enum.filter(ExWebRTC.PeerConnection.get_all_running(), fn peer_connection ->
        peer_connection
        |> ExWebRTC.PeerConnection.get_transceivers()
        |> Enum.count(&(&1.current_direction == :sendonly))
        |> Kernel.==(4)
      end)

    transceiver =
      peer_connection
      |> ExWebRTC.PeerConnection.get_transceivers()
      |> Enum.find(&(&1.current_direction == :recvonly))

    inbound_track = transceiver.receiver.track

    send(session, {:ex_webrtc, peer_connection, {:track, inbound_track}})

    packet =
      ExRTP.Packet.new(<<4, 5, 6>>, payload_type: 111, sequence_number: 2, timestamp: 2, ssrc: 2)

    send(session, {:ex_webrtc, peer_connection, {:rtp, inbound_track.id, nil, packet}})
    _ = :sys.get_state(session)

    refute_receive {:peer_connection_rtp_sent, _, _, _}, 0
  end

  test "stops when the first offer does not arrive before negotiation starts" do
    session = start_session(Ecto.UUID.generate(), negotiation_timeout_ms: 10)
    ref = Process.monitor(session)

    assert_receive {:DOWN, ^ref, :process, ^session, :normal}
  end

  defp start_session(voice_session_id, opts \\ []) do
    session_opts =
      [
        room_server: self(),
        voice_session_id: voice_session_id,
        signaling_channel: self(),
        test_peer_connection_opts: [test_rtp_observer: self()]
      ] ++ opts

    start_supervised!({Session, session_opts})
  end
end
