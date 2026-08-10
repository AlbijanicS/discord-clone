defmodule DiscordClone.VoiceTest do
  use DiscordClone.DataCase, async: false

  import DiscordClone.AccountsFixtures
  import DiscordCloneWeb.VoiceSignalingHelpers

  alias DiscordClone.Accounts.Scope
  alias DiscordClone.Voice
  alias DiscordClone.Voice.{Forwarder, RoomServer, SessionSupervisor}

  setup do
    on_exit(fn ->
      DiscordClone.Voice.running_room_servers()
      |> Enum.each(fn {voice_channel_id, _room_server} ->
        :ok = Voice.end_channel_sessions(voice_channel_id)
        :ok = Voice.expire_idle_room(voice_channel_id)
      end)
    end)

    :ok
  end

  describe "room runtime lifecycle" do
    test "starts a room for a durable Voice Channel ID without exposing its process" do
      voice_channel_id = Ecto.UUID.generate()

      assert :ok = Voice.ensure_room(voice_channel_id)
      assert Voice.room_running?(voice_channel_id)
    end

    test "reuses one running room when the same Voice Channel is requested concurrently" do
      voice_channel_id = Ecto.UUID.generate()

      results =
        1..8
        |> Task.async_stream(fn _ -> Voice.ensure_room(voice_channel_id) end,
          max_concurrency: 8,
          timeout: :infinity
        )
        |> Enum.to_list()

      assert Enum.all?(results, &(&1 == {:ok, :ok}))
      assert Voice.room_running?(voice_channel_id)
    end

    test "retires an empty room after its idle grace" do
      voice_channel_id = Ecto.UUID.generate()

      assert :ok = Voice.ensure_room(voice_channel_id)
      room_server = room_server(voice_channel_id)
      ref = Process.monitor(room_server)

      assert :ok = Voice.mark_room_empty(voice_channel_id, idle_timeout: 0)
      assert_receive {:DOWN, ^ref, :process, ^room_server, :normal}
      refute Voice.room_running?(voice_channel_id)
    end

    test "new room use cancels a pending idle shutdown" do
      voice_channel_id = Ecto.UUID.generate()

      assert :ok = Voice.ensure_room(voice_channel_id)
      room_server = room_server(voice_channel_id)
      ref = Process.monitor(room_server)

      assert :ok = Voice.mark_room_empty(voice_channel_id, idle_timeout: 25)
      assert :ok = Voice.mark_room_in_use(voice_channel_id)
      _ = :sys.get_state(room_server)

      refute_receive {:DOWN, ^ref, :process, ^room_server, _reason}, 50
      assert Voice.room_running?(voice_channel_id)

      assert :ok = Voice.mark_room_empty(voice_channel_id, idle_timeout: 0)
      assert_receive {:DOWN, ^ref, :process, ^room_server, :normal}
    end

    test "malformed IDs do not start rooms" do
      assert Voice.ensure_room("not-a-uuid") == {:error, :not_found}
      refute Voice.room_running?("not-a-uuid")
      assert Voice.mark_room_in_use("not-a-uuid") == {:error, :not_found}
      assert Voice.mark_room_empty("not-a-uuid") == {:error, :not_found}
    end

    test "retries safely after a room process dies during lookup" do
      voice_channel_id = Ecto.UUID.generate()

      assert :ok = Voice.ensure_room(voice_channel_id)
      room_server = room_server(voice_channel_id)
      ref = Process.monitor(room_server)
      Process.exit(room_server, :kill)

      assert_receive {:DOWN, ^ref, :process, ^room_server, :killed}
      assert :ok = Voice.ensure_room(voice_channel_id)
      assert Voice.room_running?(voice_channel_id)
    end

    test "a RoomServer failure clears its room and preserves an unrelated room" do
      affected_voice_channel_id = Ecto.UUID.generate()
      unaffected_voice_channel_id = Ecto.UUID.generate()
      affected_user_ids = Enum.map(1..2, fn _ -> Ecto.UUID.generate() end)

      for {user_id, number} <- Enum.with_index(affected_user_ids, 1) do
        assert {:ok, %{occupancy: ^number}} =
                 Voice.join(
                   affected_voice_channel_id,
                   user_id,
                   "affected-connection-#{number}",
                   self()
                 )
      end

      assert {:ok, %{occupancy: 1}} =
               Voice.join(
                 unaffected_voice_channel_id,
                 Ecto.UUID.generate(),
                 "unaffected-connection-1",
                 self()
               )

      room_server = room_server(affected_voice_channel_id)
      room_ref = Process.monitor(room_server)
      Process.exit(room_server, :kill)

      assert_receive {:DOWN, ^room_ref, :process, ^room_server, :killed}

      for {user_id, number} <- Enum.with_index(affected_user_ids, 1) do
        assert {:ok, %{occupancy: ^number}} =
                 Voice.join(
                   affected_voice_channel_id,
                   user_id,
                   "rejoin-after-room-failure-#{number}",
                   self()
                 )
      end

      assert {:ok, %{occupancy: 1, capacity: 5}} =
               Voice.room_occupancy(unaffected_voice_channel_id)
    end

    test "a Forwarder failure clears its room and preserves an unrelated room" do
      affected_voice_channel_id = Ecto.UUID.generate()
      unaffected_voice_channel_id = Ecto.UUID.generate()
      affected_user_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: old_voice_session_id, occupancy: 1}} =
               Voice.join(
                 affected_voice_channel_id,
                 affected_user_id,
                 "affected-connection-1",
                 self()
               )

      assert {:ok, %{occupancy: 1}} =
               Voice.join(
                 unaffected_voice_channel_id,
                 Ecto.UUID.generate(),
                 "unaffected-connection-1",
                 self()
               )

      affected_room_server = room_server(affected_voice_channel_id)
      unaffected_room_server = room_server(unaffected_voice_channel_id)
      affected_room_monitor = Process.monitor(affected_room_server)
      unaffected_room_monitor = Process.monitor(unaffected_room_server)

      assert :ok = Voice.crash_forwarder(affected_voice_channel_id)

      assert_receive {:DOWN, ^affected_room_monitor, :process, ^affected_room_server, _reason}

      refute_receive {:DOWN, ^unaffected_room_monitor, :process, ^unaffected_room_server,
                      _reason},
                     0

      assert {:ok, %{voice_session_id: new_voice_session_id, occupancy: 1}} =
               Voice.join(
                 affected_voice_channel_id,
                 affected_user_id,
                 "rejoin-after-forwarder-failure",
                 self()
               )

      refute new_voice_session_id == old_voice_session_id
      assert :ok = Voice.leave(affected_voice_channel_id, old_voice_session_id)

      assert {:ok, %{occupancy: 1, capacity: 5}} =
               Voice.room_occupancy(affected_voice_channel_id)

      assert {:ok, %{occupancy: 1, capacity: 5}} =
               Voice.room_occupancy(unaffected_voice_channel_id)
    end

    test "late cleanup for a failed room cannot clear a rejoined Voice Session" do
      voice_channel_id = Ecto.UUID.generate()
      replacement_voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: old_voice_session_id}} =
               Voice.join(voice_channel_id, user_id, "same-signaling-session", self())

      room_server = room_server(voice_channel_id)
      room_ref = Process.monitor(room_server)
      Process.exit(room_server, :kill)

      assert_receive {:DOWN, ^room_ref, :process, ^room_server, :killed}

      assert {:ok, %{voice_session_id: new_voice_session_id, occupancy: 1}} =
               Voice.join(voice_channel_id, user_id, "same-signaling-session", self())

      refute new_voice_session_id == old_voice_session_id
      assert :ok = Voice.leave(voice_channel_id, old_voice_session_id)

      assert {:ok, _join_result} =
               Voice.join(replacement_voice_channel_id, user_id, "replacement-session", self())

      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(voice_channel_id)

      assert {:ok, %{occupancy: 1, capacity: 5}} =
               Voice.room_occupancy(replacement_voice_channel_id)
    end

    test "SessionCoordinator restart retires old rooms before accepting fresh joins" do
      voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: old_voice_session_id}} =
               Voice.join(voice_channel_id, user_id, "before-coordinator-restart", self())

      room_server = room_server(voice_channel_id)
      room_ref = Process.monitor(room_server)
      session_coordinator = Process.whereis(DiscordClone.Voice.SessionCoordinator)
      coordinator_ref = Process.monitor(session_coordinator)

      assert :ok = Voice.crash_session_coordinator()
      assert_receive {:DOWN, ^coordinator_ref, :process, ^session_coordinator, :killed}
      assert_receive {:DOWN, ^room_ref, :process, ^room_server, _reason}
      assert :ok = Voice.await_session_coordinator_recovery()
      refute Voice.room_running?(voice_channel_id)

      assert {:ok, %{voice_session_id: new_voice_session_id, occupancy: 1}} =
               Voice.join(voice_channel_id, user_id, "after-coordinator-restart", self())

      refute new_voice_session_id == old_voice_session_id
    end
  end

  describe "room-local Voice Sessions" do
    test "routes accepted RTP only to the other ready Session's real outbound track" do
      voice_channel_id = Ecto.UUID.generate()
      room_supervisor = start_signaling_channel(:routing_room_supervisor)

      room_server =
        start_supervised!(
          {RoomServer,
           voice_channel_id: voice_channel_id,
           room_supervisor: room_supervisor,
           test_peer_connection_opts: [test_rtp_observer: self()]}
        )

      _session_supervisor =
        start_supervised!({SessionSupervisor, voice_channel_id: voice_channel_id})

      _forwarder = start_supervised!({Forwarder, voice_channel_id: voice_channel_id})

      first_user_id = Ecto.UUID.generate()
      second_user_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: first_voice_session_id}} =
               RoomServer.join(room_server, first_user_id, "connection-1", self())

      assert {:ok, %{voice_session_id: second_voice_session_id}} =
               RoomServer.join(room_server, second_user_id, "connection-2", self())

      assert {:ok, _answer} =
               RoomServer.accept_offer(
                 room_server,
                 first_user_id,
                 first_voice_session_id,
                 "negotiation-1",
                 browser_offer(),
                 command_deadline()
               )

      first_peer_connection = negotiated_server_peer_connection([])

      assert {:ok, _answer} =
               RoomServer.accept_offer(
                 room_server,
                 second_user_id,
                 second_voice_session_id,
                 "negotiation-2",
                 browser_offer(),
                 command_deadline()
               )

      second_peer_connection = negotiated_server_peer_connection([first_peer_connection])

      first_transceiver = inbound_audio_transceiver(first_peer_connection)
      second_transceiver = inbound_audio_transceiver(second_peer_connection)
      first_output_transceiver = first_audio_output_transceiver(first_peer_connection)
      second_output_transceiver = first_audio_output_transceiver(second_peer_connection)

      assert :ok =
               RoomServer.dispatch_test_ex_webrtc(
                 room_server,
                 first_voice_session_id,
                 {:ex_webrtc, first_peer_connection, {:track, first_transceiver.receiver.track}}
               )

      assert :ok =
               RoomServer.dispatch_test_ex_webrtc(
                 room_server,
                 second_voice_session_id,
                 {:ex_webrtc, second_peer_connection, {:track, second_transceiver.receiver.track}}
               )

      assert :ok = RoomServer.sync_test_media(room_server)

      first_packet =
        ExRTP.Packet.new(<<1>>, payload_type: 111, sequence_number: 1, timestamp: 1, ssrc: 1)

      second_packet =
        ExRTP.Packet.new(<<2>>, payload_type: 111, sequence_number: 2, timestamp: 2, ssrc: 2)

      assert :ok =
               RoomServer.dispatch_test_ex_webrtc(
                 room_server,
                 first_voice_session_id,
                 {:ex_webrtc, first_peer_connection,
                  {:rtp, first_transceiver.receiver.track.id, nil, first_packet}}
               )

      assert_receive {:peer_connection_rtp_sent, ^second_peer_connection,
                      second_outbound_track_id, ^first_packet}

      assert second_outbound_track_id == second_output_transceiver.sender.track.id
      refute_receive {:peer_connection_rtp_sent, ^first_peer_connection, _, ^first_packet}, 0

      assert :ok =
               RoomServer.dispatch_test_ex_webrtc(
                 room_server,
                 second_voice_session_id,
                 {:ex_webrtc, second_peer_connection,
                  {:rtp, second_transceiver.receiver.track.id, nil, second_packet}}
               )

      assert_receive {:peer_connection_rtp_sent, ^first_peer_connection, first_outbound_track_id,
                      ^second_packet}

      assert first_outbound_track_id == first_output_transceiver.sender.track.id
      refute_receive {:peer_connection_rtp_sent, ^second_peer_connection, _, ^second_packet}, 0

      assert :ok =
               RoomServer.dispatch_test_ex_webrtc(
                 room_server,
                 first_voice_session_id,
                 {:ex_webrtc, first_peer_connection, {:connection_state_change, :disconnected}}
               )

      assert :ok = RoomServer.sync_test_media(room_server)

      disconnected_source_packet =
        ExRTP.Packet.new(<<3>>, payload_type: 111, sequence_number: 3, timestamp: 3, ssrc: 3)

      assert :ok =
               RoomServer.dispatch_test_ex_webrtc(
                 room_server,
                 first_voice_session_id,
                 {:ex_webrtc, first_peer_connection,
                  {:rtp, first_transceiver.receiver.track.id, nil, disconnected_source_packet}}
               )

      assert_receive {:peer_connection_rtp_sent, ^second_peer_connection, _,
                      ^disconnected_source_packet}

      assert :ok =
               RoomServer.dispatch_test_ex_webrtc(
                 room_server,
                 first_voice_session_id,
                 {:ex_webrtc, first_peer_connection,
                  {:track_muted, first_transceiver.receiver.track.id}}
               )

      muted_source_packet =
        ExRTP.Packet.new(<<4>>, payload_type: 111, sequence_number: 4, timestamp: 4, ssrc: 4)

      assert :ok =
               RoomServer.dispatch_test_ex_webrtc(
                 room_server,
                 first_voice_session_id,
                 {:ex_webrtc, first_peer_connection,
                  {:rtp, first_transceiver.receiver.track.id, nil, muted_source_packet}}
               )

      assert_receive {:peer_connection_rtp_sent, ^second_peer_connection, _, ^muted_source_packet}

      assert :ok =
               RoomServer.dispatch_test_ex_webrtc(
                 room_server,
                 first_voice_session_id,
                 {:ex_webrtc, first_peer_connection,
                  {:track_ended, first_transceiver.receiver.track.id}}
               )

      assert :ok = RoomServer.sync_test_media(room_server)

      ended_source_packet =
        ExRTP.Packet.new(<<5>>, payload_type: 111, sequence_number: 5, timestamp: 5, ssrc: 5)

      assert :ok =
               RoomServer.dispatch_test_ex_webrtc(
                 room_server,
                 first_voice_session_id,
                 {:ex_webrtc, first_peer_connection,
                  {:rtp, first_transceiver.receiver.track.id, nil, ended_source_packet}}
               )

      assert :ok = RoomServer.sync_test_media(room_server)
      refute_receive {:peer_connection_rtp_sent, _, _, ^ended_source_packet}, 0
    end

    test "routes both directions when the second Session completes its offer first" do
      voice_channel_id = Ecto.UUID.generate()
      room_supervisor = start_signaling_channel(:reverse_offer_routing_room_supervisor)

      room_server =
        start_supervised!(
          {RoomServer,
           voice_channel_id: voice_channel_id,
           room_supervisor: room_supervisor,
           test_peer_connection_opts: [test_rtp_observer: self()]}
        )

      _session_supervisor =
        start_supervised!({SessionSupervisor, voice_channel_id: voice_channel_id})

      _forwarder = start_supervised!({Forwarder, voice_channel_id: voice_channel_id})
      first_user_id = Ecto.UUID.generate()
      second_user_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: first_voice_session_id}} =
               RoomServer.join(room_server, first_user_id, "reverse-connection-1", self())

      assert {:ok, %{voice_session_id: second_voice_session_id}} =
               RoomServer.join(room_server, second_user_id, "reverse-connection-2", self())

      assert {:ok, _answer} =
               RoomServer.accept_offer(
                 room_server,
                 second_user_id,
                 second_voice_session_id,
                 "reverse-negotiation-2",
                 browser_offer(),
                 command_deadline()
               )

      second_peer_connection = negotiated_server_peer_connection([])

      assert {:ok, _answer} =
               RoomServer.accept_offer(
                 room_server,
                 first_user_id,
                 first_voice_session_id,
                 "reverse-negotiation-1",
                 browser_offer(),
                 command_deadline()
               )

      first_peer_connection = negotiated_server_peer_connection([second_peer_connection])
      first_transceiver = inbound_audio_transceiver(first_peer_connection)
      second_transceiver = inbound_audio_transceiver(second_peer_connection)

      for {voice_session_id, peer_connection, track} <- [
            {second_voice_session_id, second_peer_connection, second_transceiver.receiver.track},
            {first_voice_session_id, first_peer_connection, first_transceiver.receiver.track}
          ] do
        assert :ok =
                 RoomServer.dispatch_test_ex_webrtc(
                   room_server,
                   voice_session_id,
                   {:ex_webrtc, peer_connection, {:track, track}}
                 )
      end

      assert :ok = RoomServer.sync_test_media(room_server)

      first_packet =
        ExRTP.Packet.new(<<10>>, payload_type: 111, sequence_number: 10, timestamp: 10, ssrc: 10)

      second_packet =
        ExRTP.Packet.new(<<11>>, payload_type: 111, sequence_number: 11, timestamp: 11, ssrc: 11)

      assert :ok =
               RoomServer.dispatch_test_ex_webrtc(
                 room_server,
                 first_voice_session_id,
                 {:ex_webrtc, first_peer_connection,
                  {:rtp, first_transceiver.receiver.track.id, nil, first_packet}}
               )

      assert_receive {:peer_connection_rtp_sent, ^second_peer_connection, _, ^first_packet}
      refute_receive {:peer_connection_rtp_sent, ^first_peer_connection, _, ^first_packet}, 0

      assert :ok =
               RoomServer.dispatch_test_ex_webrtc(
                 room_server,
                 second_voice_session_id,
                 {:ex_webrtc, second_peer_connection,
                  {:rtp, second_transceiver.receiver.track.id, nil, second_packet}}
               )

      assert_receive {:peer_connection_rtp_sent, ^first_peer_connection, _, ^second_packet}
      refute_receive {:peer_connection_rtp_sent, ^second_peer_connection, _, ^second_packet}, 0
    end

    test "routes the real three-Session matrix across different negotiation and source orders" do
      voice_channel_id = Ecto.UUID.generate()
      room_supervisor = start_signaling_channel(:three_session_routing_room_supervisor)

      room_server =
        start_supervised!(
          {RoomServer,
           voice_channel_id: voice_channel_id,
           room_supervisor: room_supervisor,
           test_peer_connection_opts: [test_rtp_observer: self()]}
        )

      _session_supervisor =
        start_supervised!({SessionSupervisor, voice_channel_id: voice_channel_id})

      _forwarder = start_supervised!({Forwarder, voice_channel_id: voice_channel_id})

      sessions =
        Enum.map(1..3, fn number ->
          user_id = Ecto.UUID.generate()

          assert {:ok, %{voice_session_id: voice_session_id}} =
                   RoomServer.join(
                     room_server,
                     user_id,
                     "three-session-connection-#{number}",
                     self()
                   )

          %{number: number, user_id: user_id, voice_session_id: voice_session_id}
        end)

      {sessions_by_id, _peer_connections} =
        sessions
        |> Enum.reverse()
        |> Enum.reduce({%{}, []}, fn session, {sessions_by_id, peer_connections} ->
          assert {:ok, _answer} =
                   RoomServer.accept_offer(
                     room_server,
                     session.user_id,
                     session.voice_session_id,
                     "three-session-negotiation-#{session.number}",
                     browser_offer(),
                     command_deadline()
                   )

          peer_connection = negotiated_server_peer_connection(peer_connections)

          session =
            Map.put(session, :peer_connection, peer_connection)
            |> Map.put(:inbound_track, inbound_audio_transceiver(peer_connection).receiver.track)

          {Map.put(sessions_by_id, session.voice_session_id, session),
           [
             peer_connection | peer_connections
           ]}
        end)

      sessions_by_id
      |> Map.values()
      |> Enum.sort_by(& &1.number)
      |> Enum.each(fn session ->
        assert :ok =
                 RoomServer.dispatch_test_ex_webrtc(
                   room_server,
                   session.voice_session_id,
                   {:ex_webrtc, session.peer_connection, {:track, session.inbound_track}}
                 )
      end)

      assert :ok = RoomServer.sync_test_media(room_server)

      destination_ids_by_peer =
        Map.new(sessions_by_id, fn {voice_session_id, session} ->
          {session.peer_connection, voice_session_id}
        end)

      deliveries =
        sessions_by_id
        |> Map.values()
        |> Enum.sort_by(& &1.number, :desc)
        |> Enum.flat_map(fn session ->
          packet =
            ExRTP.Packet.new(<<session.number>>,
              payload_type: 111,
              sequence_number: session.number,
              timestamp: session.number,
              ssrc: session.number
            )

          assert :ok =
                   RoomServer.dispatch_test_ex_webrtc(
                     room_server,
                     session.voice_session_id,
                     {:ex_webrtc, session.peer_connection,
                      {:rtp, session.inbound_track.id, nil, packet}}
                   )

          Enum.map(1..2, fn _ ->
            assert_receive {:peer_connection_rtp_sent, destination_peer_connection,
                            output_track_id, ^packet}

            {session.voice_session_id,
             Map.fetch!(destination_ids_by_peer, destination_peer_connection), output_track_id}
          end)
        end)

      assert Enum.all?(deliveries, fn {source_id, destination_id, output_track_id} ->
               source_id != destination_id and
                 output_track_id in audio_output_track_ids(
                   Map.fetch!(sessions_by_id, destination_id).peer_connection
                 )
             end)

      for destination_id <- Map.keys(sessions_by_id) do
        destination_track_ids =
          for {_source_id, ^destination_id, output_track_id} <- deliveries,
              do: output_track_id

        assert destination_track_ids |> Enum.uniq() |> length() == 2
      end
    end

    test "canonical removal withdraws exact routes and protects a healthy replacement pair" do
      voice_channel_id = Ecto.UUID.generate()
      room_supervisor = start_signaling_channel(:cleanup_routing_room_supervisor)

      room_server =
        start_supervised!(
          {RoomServer,
           voice_channel_id: voice_channel_id,
           room_supervisor: room_supervisor,
           test_peer_connection_opts: [test_rtp_observer: self()]}
        )

      _session_supervisor =
        start_supervised!({SessionSupervisor, voice_channel_id: voice_channel_id})

      forwarder = start_supervised!({Forwarder, voice_channel_id: voice_channel_id})
      departing_user_id = Ecto.UUID.generate()
      healthy_user_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: departing_voice_session_id}} =
               RoomServer.join(room_server, departing_user_id, "departing-connection", self())

      assert {:ok, %{voice_session_id: healthy_voice_session_id}} =
               RoomServer.join(room_server, healthy_user_id, "healthy-connection", self())

      assert {:ok, _answer} =
               RoomServer.accept_offer(
                 room_server,
                 departing_user_id,
                 departing_voice_session_id,
                 "departing-negotiation",
                 browser_offer(),
                 command_deadline()
               )

      departing_peer_connection = negotiated_server_peer_connection([])

      assert {:ok, _answer} =
               RoomServer.accept_offer(
                 room_server,
                 healthy_user_id,
                 healthy_voice_session_id,
                 "healthy-negotiation",
                 browser_offer(),
                 command_deadline()
               )

      healthy_peer_connection = negotiated_server_peer_connection([departing_peer_connection])

      departing_transceiver = inbound_audio_transceiver(departing_peer_connection)
      healthy_transceiver = inbound_audio_transceiver(healthy_peer_connection)

      for {voice_session_id, peer_connection, track} <- [
            {departing_voice_session_id, departing_peer_connection,
             departing_transceiver.receiver.track},
            {healthy_voice_session_id, healthy_peer_connection,
             healthy_transceiver.receiver.track}
          ] do
        assert :ok =
                 RoomServer.dispatch_test_ex_webrtc(
                   room_server,
                   voice_session_id,
                   {:ex_webrtc, peer_connection, {:track, track}}
                 )
      end

      assert :ok = RoomServer.sync_test_media(room_server)
      departing_monitor = Process.monitor(departing_peer_connection)
      healthy_monitor = Process.monitor(healthy_peer_connection)

      assert :ok = RoomServer.leave(room_server, departing_voice_session_id)
      assert_receive {:DOWN, ^departing_monitor, :process, ^departing_peer_connection, _reason}
      refute_receive {:DOWN, ^healthy_monitor, :process, ^healthy_peer_connection, _reason}, 0

      removed_destination_packet =
        ExRTP.Packet.new(<<6>>, payload_type: 111, sequence_number: 6, timestamp: 6, ssrc: 6)

      assert :ok =
               Forwarder.forward_rtp(
                 forwarder,
                 healthy_voice_session_id,
                 healthy_transceiver.receiver.track.id,
                 removed_destination_packet
               )

      assert :ok = Forwarder.sync(forwarder)
      refute_receive {:peer_connection_rtp_sent, _, _, ^removed_destination_packet}, 0

      assert {:ok, %{voice_session_id: replacement_voice_session_id}} =
               RoomServer.join(room_server, departing_user_id, "replacement-connection", self())

      refute replacement_voice_session_id == departing_voice_session_id

      assert {:ok, _answer} =
               RoomServer.accept_offer(
                 room_server,
                 departing_user_id,
                 replacement_voice_session_id,
                 "replacement-negotiation",
                 browser_offer(),
                 command_deadline()
               )

      replacement_peer_connection =
        negotiated_server_peer_connection([healthy_peer_connection])

      replacement_transceiver = inbound_audio_transceiver(replacement_peer_connection)

      assert :ok =
               RoomServer.dispatch_test_ex_webrtc(
                 room_server,
                 replacement_voice_session_id,
                 {:ex_webrtc, replacement_peer_connection,
                  {:track, replacement_transceiver.receiver.track}}
               )

      assert :ok = RoomServer.sync_test_media(room_server)

      late_old_source_packet =
        ExRTP.Packet.new(<<7>>, payload_type: 111, sequence_number: 7, timestamp: 7, ssrc: 7)

      assert :ok =
               Forwarder.forward_rtp(
                 forwarder,
                 departing_voice_session_id,
                 departing_transceiver.receiver.track.id,
                 late_old_source_packet
               )

      assert :ok = Forwarder.sync(forwarder)
      refute_receive {:peer_connection_rtp_sent, _, _, ^late_old_source_packet}, 0

      restored_route_packet =
        ExRTP.Packet.new(<<8>>, payload_type: 111, sequence_number: 8, timestamp: 8, ssrc: 8)

      assert :ok =
               Forwarder.forward_rtp(
                 forwarder,
                 healthy_voice_session_id,
                 healthy_transceiver.receiver.track.id,
                 restored_route_packet
               )

      assert_receive {:peer_connection_rtp_sent, ^replacement_peer_connection, _,
                      ^restored_route_packet}

      replacement_monitor = Process.monitor(replacement_peer_connection)
      assert :ok = RoomServer.crash_session(room_server, replacement_voice_session_id)

      assert_receive {:DOWN, ^replacement_monitor, :process, ^replacement_peer_connection,
                      _reason}

      refute_receive {:DOWN, ^healthy_monitor, :process, ^healthy_peer_connection, _reason}, 0

      post_crash_packet =
        ExRTP.Packet.new(<<9>>, payload_type: 111, sequence_number: 9, timestamp: 9, ssrc: 9)

      assert :ok =
               Forwarder.forward_rtp(
                 forwarder,
                 healthy_voice_session_id,
                 healthy_transceiver.receiver.track.id,
                 post_crash_packet
               )

      assert :ok = Forwarder.sync(forwarder)
      refute_receive {:peer_connection_rtp_sent, _, _, ^post_crash_packet}, 0
    end

    test "does not commit membership when Session PeerConnection startup fails" do
      voice_channel_id = Ecto.UUID.generate()
      room_supervisor = start_signaling_channel(:failed_room_supervisor)

      room_server =
        start_supervised!(
          {RoomServer,
           voice_channel_id: voice_channel_id,
           room_supervisor: room_supervisor,
           test_peer_connection_opts: [audio_codecs: [:invalid]]}
        )

      _session_supervisor =
        start_supervised!({SessionSupervisor, voice_channel_id: voice_channel_id})

      _forwarder = start_supervised!({Forwarder, voice_channel_id: voice_channel_id})

      running_before = MapSet.new(ExWebRTC.PeerConnection.get_all_running())

      assert {:error, :unavailable} =
               RoomServer.join(room_server, Ecto.UUID.generate(), "connection-1", self())

      assert {:ok, %{occupancy: 0, capacity: 5}} = RoomServer.occupancy(room_server)
      assert MapSet.new(ExWebRTC.PeerConnection.get_all_running()) == running_before
    end

    test "does not commit membership until the Session-owned PeerConnection is ready" do
      voice_channel_id = Ecto.UUID.generate()
      room_supervisor = start_signaling_channel(:readiness_room_supervisor)
      readiness_reference = make_ref()

      room_server =
        start_supervised!(
          {RoomServer,
           voice_channel_id: voice_channel_id,
           room_supervisor: room_supervisor,
           test_admission_observer: self(),
           test_peer_connection_opts: [
             test_readiness_gate: {self(), readiness_reference}
           ]}
        )

      _session_supervisor =
        start_supervised!({SessionSupervisor, voice_channel_id: voice_channel_id})

      _forwarder = start_supervised!({Forwarder, voice_channel_id: voice_channel_id})

      test_pid = self()

      _join_task =
        start_supervised!(
          {Task,
           fn ->
             result =
               RoomServer.join(room_server, Ecto.UUID.generate(), "connection-1", test_pid)

             send(test_pid, {:voice_session_join_result, result})
           end}
        )

      assert_receive {:peer_connection_starting, ^readiness_reference, session_pid}
      refute_receive {:voice_session_membership_committed, _voice_session_id}, 0

      send(session_pid, {:release_peer_connection_start, readiness_reference})

      assert_receive {:voice_session_join_result, {:ok, %{voice_session_id: voice_session_id}}},
                     1_000

      assert_receive {:voice_session_membership_committed, ^voice_session_id}, 1_000
      assert {:ok, %{occupancy: 1, capacity: 5}} = RoomServer.occupancy(room_server)

      assert [peer_connection] = ExWebRTC.PeerConnection.get_all_running()
      peer_connection_monitor = Process.monitor(peer_connection)
      assert :ok = RoomServer.leave(room_server, voice_session_id)
      assert_receive {:DOWN, ^peer_connection_monitor, :process, ^peer_connection, _reason}
    end

    test "applies buffered client ICE to the PeerConnection in arrival order" do
      voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()
      room_supervisor = start_signaling_channel(:candidate_order_room_supervisor)

      room_server =
        start_supervised!(
          {RoomServer,
           voice_channel_id: voice_channel_id,
           room_supervisor: room_supervisor,
           test_peer_connection_opts: [test_candidate_observer: self()]}
        )

      _session_supervisor =
        start_supervised!({SessionSupervisor, voice_channel_id: voice_channel_id})

      _forwarder = start_supervised!({Forwarder, voice_channel_id: voice_channel_id})

      assert {:ok, %{voice_session_id: voice_session_id}} =
               RoomServer.join(room_server, user_id, "connection-1", self())

      negotiation_id = "current-negotiation"
      first_candidate = runtime_candidate(1)
      stale_negotiation_id = "stale-negotiation"
      stale_candidate = %{runtime_candidate(99) | negotiation_id: stale_negotiation_id}
      second_candidate = runtime_candidate(2)

      assert {:ok, %{negotiation_id: ^stale_negotiation_id}} =
               RoomServer.add_ice_candidate(
                 room_server,
                 user_id,
                 voice_session_id,
                 stale_negotiation_id,
                 stale_candidate,
                 command_deadline()
               )

      assert {:ok, %{negotiation_id: ^negotiation_id}} =
               RoomServer.add_ice_candidate(
                 room_server,
                 user_id,
                 voice_session_id,
                 negotiation_id,
                 first_candidate,
                 command_deadline()
               )

      assert {:ok, %{negotiation_id: ^negotiation_id}} =
               RoomServer.add_ice_candidate(
                 room_server,
                 user_id,
                 voice_session_id,
                 negotiation_id,
                 second_candidate,
                 command_deadline()
               )

      assert {:ok, %{"type" => "answer"}} =
               RoomServer.accept_offer(
                 room_server,
                 user_id,
                 voice_session_id,
                 negotiation_id,
                 browser_offer(),
                 command_deadline()
               )

      first_candidate_value = first_candidate.candidate
      stale_candidate_value = stale_candidate.candidate
      second_candidate_value = second_candidate.candidate

      assert_receive {:peer_connection_candidate_applied, ^first_candidate_value}
      assert_receive {:peer_connection_candidate_applied, ^second_candidate_value}
      refute_receive {:peer_connection_candidate_applied, ^stale_candidate_value}, 0
    end

    test "admits a Voice Session only after its Session-owned PeerConnection is ready" do
      voice_channel_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: voice_session_id, occupancy: 1}} =
               Voice.join(voice_channel_id, Ecto.UUID.generate(), "connection-1", self())

      assert [peer_connection] = ExWebRTC.PeerConnection.get_all_running()
      assert ExWebRTC.PeerConnection.get_transceivers(peer_connection) == []
      peer_connection_monitor = Process.monitor(peer_connection)

      assert :ok = Voice.leave(voice_channel_id, voice_session_id)
      assert_receive {:DOWN, ^peer_connection_monitor, :process, ^peer_connection, _reason}

      assert :ok = Voice.leave(voice_channel_id, voice_session_id)
      refute_receive {:DOWN, ^peer_connection_monitor, :process, ^peer_connection, _reason}, 0
      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(voice_channel_id)
    end

    test "a crashed Voice Session takes its linked PeerConnection down" do
      voice_channel_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: voice_session_id}} =
               Voice.join(voice_channel_id, Ecto.UUID.generate(), "connection-1", self())

      assert [peer_connection] = ExWebRTC.PeerConnection.get_all_running()
      peer_connection_monitor = Process.monitor(peer_connection)

      assert :ok = Voice.crash_session(voice_channel_id, voice_session_id)
      assert_receive {:DOWN, ^peer_connection_monitor, :process, ^peer_connection, _reason}
    end

    test "an active room shutdown stops every Session-owned PeerConnection" do
      voice_channel_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: _voice_session_id}} =
               Voice.join(voice_channel_id, Ecto.UUID.generate(), "connection-1", self())

      room_server = room_server(voice_channel_id)
      assert [peer_connection] = ExWebRTC.PeerConnection.get_all_running()
      peer_connection_monitor = Process.monitor(peer_connection)

      assert :ok = RoomServer.shutdown(room_server)
      assert_receive {:DOWN, ^peer_connection_monitor, :process, ^peer_connection, _reason}
      assert :ok = Voice.await_empty_room(voice_channel_id)
    end

    test "a crashed PeerConnection removes its Voice Session without affecting another room" do
      affected_voice_channel_id = Ecto.UUID.generate()
      healthy_voice_channel_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: _affected_voice_session_id}} =
               Voice.join(
                 affected_voice_channel_id,
                 Ecto.UUID.generate(),
                 "affected-connection",
                 self()
               )

      [affected_peer_connection] = ExWebRTC.PeerConnection.get_all_running()

      assert {:ok, %{voice_session_id: _healthy_voice_session_id}} =
               Voice.join(
                 healthy_voice_channel_id,
                 Ecto.UUID.generate(),
                 "healthy-connection",
                 self()
               )

      [healthy_peer_connection] =
        ExWebRTC.PeerConnection.get_all_running() -- [affected_peer_connection]

      affected_peer_monitor = Process.monitor(affected_peer_connection)
      healthy_peer_monitor = Process.monitor(healthy_peer_connection)
      Process.exit(affected_peer_connection, :kill)

      assert_receive {:DOWN, ^affected_peer_monitor, :process, ^affected_peer_connection, :killed}
      assert :ok = Voice.await_empty_room(affected_voice_channel_id)

      assert {:ok, %{occupancy: 0, capacity: 5}} =
               Voice.room_occupancy(affected_voice_channel_id)

      assert {:ok, %{occupancy: 1, capacity: 5}} =
               Voice.room_occupancy(healthy_voice_channel_id)

      refute_receive {:DOWN, ^healthy_peer_monitor, :process, ^healthy_peer_connection, _reason},
                     0
    end

    test "a terminal peer state removes only its Session from a shared room" do
      voice_channel_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: failed_voice_session_id}} =
               Voice.join(voice_channel_id, Ecto.UUID.generate(), "failed-connection", self())

      [failed_peer_connection] = ExWebRTC.PeerConnection.get_all_running()

      assert {:ok, %{voice_session_id: healthy_voice_session_id}} =
               Voice.join(voice_channel_id, Ecto.UUID.generate(), "healthy-connection", self())

      [healthy_peer_connection] =
        ExWebRTC.PeerConnection.get_all_running() -- [failed_peer_connection]

      %{memberships: memberships} = :sys.get_state(room_server(voice_channel_id))
      failed_session = memberships[failed_voice_session_id].session_pid
      failed_session_monitor = Process.monitor(failed_session)
      failed_monitor = Process.monitor(failed_peer_connection)
      healthy_monitor = Process.monitor(healthy_peer_connection)

      assert :ok =
               Voice.dispatch_test_ex_webrtc(
                 voice_channel_id,
                 failed_voice_session_id,
                 {:ex_webrtc, failed_peer_connection, {:connection_state_change, :failed}}
               )

      assert_receive {:voice_session_event, ^failed_voice_session_id,
                      {:connection_state_change, :failed, nil}}

      assert_receive {:DOWN, ^failed_monitor, :process, ^failed_peer_connection, _reason}
      assert_receive {:DOWN, ^failed_session_monitor, :process, ^failed_session, :normal}
      refute_receive {:DOWN, ^healthy_monitor, :process, ^healthy_peer_connection, _reason}, 0
      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(voice_channel_id)

      assert :ok = Voice.leave(voice_channel_id, healthy_voice_session_id)
      assert_receive {:DOWN, ^healthy_monitor, :process, ^healthy_peer_connection, _reason}
    end

    test "an expired runtime command retires the Voice Session and its PeerConnection" do
      voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: voice_session_id}} =
               Voice.join(voice_channel_id, user_id, "connection-1", self())

      room_server = room_server(voice_channel_id)
      assert [peer_connection] = ExWebRTC.PeerConnection.get_all_running()
      peer_connection_monitor = Process.monitor(peer_connection)

      assert {:error, :invalid_session} =
               RoomServer.accept_offer(
                 room_server,
                 Ecto.UUID.generate(),
                 voice_session_id,
                 "other-user-negotiation",
                 %{},
                 System.monotonic_time(:millisecond) + 5_000
               )

      assert {:ok, %{occupancy: 1, capacity: 5}} = RoomServer.occupancy(room_server)
      expired_deadline = System.monotonic_time(:millisecond) - 1

      assert {:error, :unavailable} =
               RoomServer.accept_offer(
                 room_server,
                 user_id,
                 voice_session_id,
                 "expired-negotiation",
                 %{},
                 expired_deadline
               )

      assert_receive {:DOWN, ^peer_connection_monitor, :process, ^peer_connection, _reason}
      assert {:ok, %{occupancy: 0, capacity: 5}} = RoomServer.occupancy(room_server)
    end

    test "joins a Voice Session with a fresh opaque ID" do
      voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, join_result} =
               Voice.join(voice_channel_id, user_id, "signaling-connection-1", self())

      assert %{voice_session_id: voice_session_id, occupancy: 1, capacity: 5} = join_result
      assert {:ok, ^voice_session_id} = Ecto.UUID.cast(voice_session_id)
      refute voice_session_id in [voice_channel_id, user_id, "signaling-connection-1"]
      refute inspect(join_result) =~ "#PID"
    end

    test "reuses the existing Voice Session for the same signaling connection" do
      voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, first} = Voice.join(voice_channel_id, user_id, "connection-1", self())
      assert {:ok, repeated} = Voice.join(voice_channel_id, user_id, "connection-1", self())

      assert repeated == first
      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(voice_channel_id)
    end

    test "atomically caps a room at five concurrent Voice Sessions" do
      voice_channel_id = Ecto.UUID.generate()

      signaling_channels = Enum.map(1..6, &start_signaling_channel/1)

      results =
        1..6
        |> Task.async_stream(
          fn number ->
            Voice.join(
              voice_channel_id,
              Ecto.UUID.generate(),
              "connection-#{number}",
              Enum.at(signaling_channels, number - 1)
            )
          end,
          max_concurrency: 6,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, result} -> result end)

      {admitted, rejected} =
        Enum.split_with(results, &match?({:ok, %{capacity: 5}}, &1))

      assert length(admitted) == 5

      assert [{:error, %{reason: :room_full, occupancy: 5, capacity: 5} = room_full}] =
               rejected

      assert Map.keys(room_full) |> Enum.sort() == [:capacity, :occupancy, :reason]
      assert {:ok, %{occupancy: 5, capacity: 5}} = Voice.room_occupancy(voice_channel_id)
    end

    test "leave is idempotent and the final leave begins empty-room cleanup" do
      voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: voice_session_id}} =
               Voice.join(voice_channel_id, user_id, "connection-1", self())

      assert :ok = Voice.leave(voice_channel_id, voice_session_id)
      assert :ok = Voice.leave(voice_channel_id, voice_session_id)
      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(voice_channel_id)

      assert :ok = Voice.expire_idle_room(voice_channel_id)
      refute Voice.room_running?(voice_channel_id)
    end

    test "a crashed temporary Session removes only its own membership" do
      voice_channel_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: crashed_session_id}} =
               Voice.join(voice_channel_id, Ecto.UUID.generate(), "connection-1", self())

      assert {:ok, %{voice_session_id: healthy_session_id}} =
               Voice.join(voice_channel_id, Ecto.UUID.generate(), "connection-2", self())

      assert :ok = Voice.crash_session(voice_channel_id, crashed_session_id)

      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(voice_channel_id)

      assert {:ok, %{voice_session_id: replacement_session_id}} =
               Voice.join(voice_channel_id, Ecto.UUID.generate(), "connection-1", self())

      refute replacement_session_id == crashed_session_id

      assert :ok = Voice.leave(voice_channel_id, replacement_session_id)
      assert :ok = Voice.leave(voice_channel_id, healthy_session_id)
      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(voice_channel_id)
    end

    test "a signaling channel death removes only its Voice Session" do
      voice_channel_id = Ecto.UUID.generate()

      signaling_channel = start_signaling_channel(:connection_death)
      healthy_signaling_channel = start_signaling_channel(:healthy_connection)

      assert {:ok, %{voice_session_id: _departing_voice_session_id}} =
               Voice.join(
                 voice_channel_id,
                 Ecto.UUID.generate(),
                 "connection-1",
                 signaling_channel
               )

      [departing_peer_connection] = ExWebRTC.PeerConnection.get_all_running()

      assert {:ok, %{voice_session_id: healthy_voice_session_id}} =
               Voice.join(
                 voice_channel_id,
                 Ecto.UUID.generate(),
                 "connection-2",
                 healthy_signaling_channel
               )

      [healthy_peer_connection] =
        ExWebRTC.PeerConnection.get_all_running() -- [departing_peer_connection]

      departing_monitor = Process.monitor(departing_peer_connection)
      healthy_monitor = Process.monitor(healthy_peer_connection)
      Process.exit(signaling_channel, :shutdown)

      assert_receive {:DOWN, ^departing_monitor, :process, ^departing_peer_connection, _reason}
      refute_receive {:DOWN, ^healthy_monitor, :process, ^healthy_peer_connection, _reason}, 0
      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(voice_channel_id)

      assert :ok = Voice.leave(voice_channel_id, healthy_voice_session_id)
      assert_receive {:DOWN, ^healthy_monitor, :process, ^healthy_peer_connection, _reason}
    end
  end

  describe "Voice Session offer negotiation" do
    test "leave rejects late offer, ICE, and media work for the retired Voice Session" do
      user = user_fixture()
      current_scope = Scope.for_user(user)
      voice_channel_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: retired_voice_session_id}} =
               Voice.join(voice_channel_id, user.id, "retired-connection", self())

      [retired_peer_connection] = ExWebRTC.PeerConnection.get_all_running()
      retired_monitor = Process.monitor(retired_peer_connection)

      assert :ok = Voice.leave(voice_channel_id, retired_voice_session_id)
      assert_receive {:DOWN, ^retired_monitor, :process, ^retired_peer_connection, _reason}

      assert {:error, :invalid_session} =
               Voice.accept_offer(
                 current_scope,
                 voice_channel_id,
                 retired_voice_session_id,
                 "late-negotiation",
                 browser_offer()
               )

      assert {:error, :invalid_session} =
               Voice.add_ice_candidate(
                 current_scope,
                 voice_channel_id,
                 retired_voice_session_id,
                 "late-negotiation",
                 runtime_candidate(1)
               )

      assert {:error, :not_found} =
               Voice.dispatch_test_ex_webrtc(
                 voice_channel_id,
                 retired_voice_session_id,
                 {:ex_webrtc, retired_peer_connection, {:connection_state_change, :connected}}
               )

      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(voice_channel_id)
    end

    test "routes an offer through the public Voice boundary to its admitted Voice Session" do
      user = user_fixture()
      current_scope = Scope.for_user(user)
      voice_channel_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: voice_session_id}} =
               Voice.join(voice_channel_id, user.id, "connection-1", self())

      negotiation_id = "first-negotiation"

      assert {:ok, %{"type" => "answer", "sdp" => answer_sdp}} =
               Voice.accept_offer(
                 current_scope,
                 voice_channel_id,
                 voice_session_id,
                 negotiation_id,
                 browser_offer()
               )

      assert is_binary(answer_sdp)
      assert byte_size(answer_sdp) > 0

      assert {:error, :negotiation_already_active} =
               Voice.accept_offer(
                 current_scope,
                 voice_channel_id,
                 voice_session_id,
                 "duplicate-negotiation",
                 browser_offer()
               )
    end

    test "rejects another User, Voice Channel, or stale Voice Session without mutation" do
      user = user_fixture()
      other_user = user_fixture()
      current_scope = Scope.for_user(user)
      other_scope = Scope.for_user(other_user)
      voice_channel_id = Ecto.UUID.generate()
      other_voice_channel_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: voice_session_id}} =
               Voice.join(voice_channel_id, user.id, "connection-1", self())

      assert {:ok, %{voice_session_id: _other_voice_session_id}} =
               Voice.join(other_voice_channel_id, other_user.id, "connection-2", self())

      offer = browser_offer()

      assert {:error, :invalid_session} =
               Voice.accept_offer(
                 other_scope,
                 voice_channel_id,
                 voice_session_id,
                 "other-user",
                 offer
               )

      assert {:error, :invalid_session} =
               Voice.accept_offer(
                 current_scope,
                 other_voice_channel_id,
                 voice_session_id,
                 "other-channel",
                 offer
               )

      assert {:error, :invalid_session} =
               Voice.accept_offer(
                 current_scope,
                 voice_channel_id,
                 Ecto.UUID.generate(),
                 "stale-session",
                 offer
               )

      assert {:ok, %{"type" => "answer"}} =
               Voice.accept_offer(
                 current_scope,
                 voice_channel_id,
                 voice_session_id,
                 "current-session",
                 offer
               )
    end

    test "routes early and current client ICE through the owning Voice Session" do
      user = user_fixture()
      current_scope = Scope.for_user(user)
      voice_channel_id = Ecto.UUID.generate()
      negotiation_id = "current-negotiation"

      assert {:ok, %{voice_session_id: voice_session_id}} =
               Voice.join(voice_channel_id, user.id, "connection-1", self())

      assert {:ok, %{negotiation_id: ^negotiation_id}} =
               Voice.add_ice_candidate(
                 current_scope,
                 voice_channel_id,
                 voice_session_id,
                 negotiation_id,
                 runtime_candidate(1)
               )

      assert {:ok, %{"type" => "answer"}} =
               Voice.accept_offer(
                 current_scope,
                 voice_channel_id,
                 voice_session_id,
                 negotiation_id,
                 browser_offer()
               )

      assert {:ok, %{negotiation_id: ^negotiation_id}} =
               Voice.add_ice_candidate(
                 current_scope,
                 voice_channel_id,
                 voice_session_id,
                 negotiation_id,
                 runtime_candidate(3)
               )
    end

    test "rejects client ICE for a stale runtime Negotiation" do
      user = user_fixture()
      current_scope = Scope.for_user(user)
      voice_channel_id = Ecto.UUID.generate()
      negotiation_id = "current-negotiation"

      assert {:ok, %{voice_session_id: voice_session_id}} =
               Voice.join(voice_channel_id, user.id, "connection-1", self())

      assert {:ok, %{"type" => "answer"}} =
               Voice.accept_offer(
                 current_scope,
                 voice_channel_id,
                 voice_session_id,
                 negotiation_id,
                 browser_offer()
               )

      assert {:error, :invalid_negotiation} =
               Voice.add_ice_candidate(
                 current_scope,
                 voice_channel_id,
                 voice_session_id,
                 "stale-negotiation",
                 runtime_candidate(2)
               )
    end

    test "retains the unsupported browser end-marker runtime contract" do
      user = user_fixture()
      current_scope = Scope.for_user(user)
      voice_channel_id = Ecto.UUID.generate()
      negotiation_id = "current-negotiation"

      assert {:ok, %{voice_session_id: voice_session_id}} =
               Voice.join(voice_channel_id, user.id, "connection-1", self())

      assert {:ok, %{"type" => "answer"}} =
               Voice.accept_offer(
                 current_scope,
                 voice_channel_id,
                 voice_session_id,
                 negotiation_id,
                 browser_offer()
               )

      assert {:error, :end_of_candidates_unsupported} =
               Voice.end_of_candidates(
                 current_scope,
                 voice_channel_id,
                 voice_session_id,
                 negotiation_id
               )
    end

    test "rejects ICE commands for mismatched runtime membership" do
      user = user_fixture()
      other_user = user_fixture()
      current_scope = Scope.for_user(user)
      other_scope = Scope.for_user(other_user)
      voice_channel_id = Ecto.UUID.generate()
      other_voice_channel_id = Ecto.UUID.generate()
      negotiation_id = "current-negotiation"

      assert {:ok, %{voice_session_id: voice_session_id}} =
               Voice.join(voice_channel_id, user.id, "connection-1", self())

      assert {:ok, %{voice_session_id: _other_voice_session_id}} =
               Voice.join(
                 other_voice_channel_id,
                 other_user.id,
                 "connection-2",
                 self()
               )

      candidate = runtime_candidate(1)

      assert {:error, :invalid_session} =
               Voice.add_ice_candidate(
                 other_scope,
                 voice_channel_id,
                 voice_session_id,
                 negotiation_id,
                 candidate
               )

      assert {:error, :invalid_session} =
               Voice.add_ice_candidate(
                 current_scope,
                 other_voice_channel_id,
                 voice_session_id,
                 negotiation_id,
                 candidate
               )

      assert {:error, :invalid_session} =
               Voice.add_ice_candidate(
                 current_scope,
                 voice_channel_id,
                 Ecto.UUID.generate(),
                 negotiation_id,
                 candidate
               )

      assert {:error, :invalid_session} =
               Voice.end_of_candidates(
                 current_scope,
                 other_voice_channel_id,
                 voice_session_id,
                 negotiation_id
               )
    end
  end

  describe "cross-room Voice Sessions" do
    test "serializes concurrent join requests for one User into one active Voice Session" do
      user_id = Ecto.UUID.generate()
      voice_channel_ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]
      signaling_channels = Enum.map(1..8, &start_signaling_channel/1)

      results =
        0..7
        |> Task.async_stream(
          fn number ->
            Voice.join(
              Enum.at(voice_channel_ids, rem(number, 2)),
              user_id,
              "connection-#{number}",
              Enum.at(signaling_channels, number)
            )
          end,
          max_concurrency: 8,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.all?(results, &match?({:ok, %{voice_session_id: _}}, &1))

      total_occupancy =
        Enum.reduce(voice_channel_ids, 0, fn voice_channel_id, total ->
          case Voice.room_occupancy(voice_channel_id) do
            {:ok, %{occupancy: occupancy}} -> total + occupancy
            {:error, :not_found} -> total
          end
        end)

      assert total_occupancy == 1
    end

    test "moves a User to an available Voice Channel and retires the old Voice Session" do
      first_voice_channel_id = Ecto.UUID.generate()
      second_voice_channel_id = Ecto.UUID.generate()
      third_voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: first_voice_session_id}} =
               Voice.join(first_voice_channel_id, user_id, "connection-1", self())

      assert {:ok, %{voice_session_id: second_voice_session_id}} =
               Voice.join(second_voice_channel_id, user_id, "connection-2", self())

      refute second_voice_session_id == first_voice_session_id
      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(first_voice_channel_id)
      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(second_voice_channel_id)
      assert :ok = Voice.leave(first_voice_channel_id, first_voice_session_id)

      assert {:ok, %{voice_session_id: third_voice_session_id}} =
               Voice.join(third_voice_channel_id, user_id, "connection-3", self())

      refute third_voice_session_id == second_voice_session_id
      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(second_voice_channel_id)
      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(third_voice_channel_id)
    end

    test "clears an explicitly left Voice Session from global coordination" do
      first_voice_channel_id = Ecto.UUID.generate()
      second_voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: voice_session_id}} =
               Voice.join(first_voice_channel_id, user_id, "connection-1", self())

      assert :ok = Voice.leave(first_voice_channel_id, voice_session_id)

      assert {:ok, _join_result} =
               Voice.join(second_voice_channel_id, user_id, "connection-2", self())

      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(first_voice_channel_id)
      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(second_voice_channel_id)
    end

    test "ignores a leave with the wrong Voice Channel ID" do
      first_voice_channel_id = Ecto.UUID.generate()
      wrong_voice_channel_id = Ecto.UUID.generate()
      second_voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: voice_session_id}} =
               Voice.join(first_voice_channel_id, user_id, "connection-1", self())

      assert :ok = Voice.leave(wrong_voice_channel_id, voice_session_id)

      assert {:ok, _join_result} =
               Voice.join(second_voice_channel_id, user_id, "connection-2", self())

      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(first_voice_channel_id)
      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(second_voice_channel_id)
    end

    test "preserves the current Voice Session when a move target is full" do
      first_voice_channel_id = Ecto.UUID.generate()
      full_voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: current_voice_session_id}} =
               Voice.join(first_voice_channel_id, user_id, "connection-1", self())

      full_signaling_channels = Enum.map(1..5, &start_signaling_channel/1)

      for number <- 1..5 do
        assert {:ok, _join_result} =
                 Voice.join(
                   full_voice_channel_id,
                   Ecto.UUID.generate(),
                   "full-connection-#{number}",
                   Enum.at(full_signaling_channels, number - 1)
                 )
      end

      assert {:error, %{reason: :room_full, occupancy: 5, capacity: 5}} =
               Voice.join(full_voice_channel_id, user_id, "connection-2", self())

      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(first_voice_channel_id)
      assert {:ok, %{occupancy: 5, capacity: 5}} = Voice.room_occupancy(full_voice_channel_id)
      assert :ok = Voice.leave(first_voice_channel_id, current_voice_session_id)
    end

    test "clears a failed Voice Session from global coordination before a replacement join" do
      first_voice_channel_id = Ecto.UUID.generate()
      second_voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, %{voice_session_id: crashed_voice_session_id}} =
               Voice.join(first_voice_channel_id, user_id, "connection-1", self())

      assert :ok = Voice.crash_session(first_voice_channel_id, crashed_voice_session_id)

      assert {:ok, %{voice_session_id: replacement_voice_session_id}} =
               Voice.join(second_voice_channel_id, user_id, "connection-2", self())

      refute replacement_voice_session_id == crashed_voice_session_id
      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(first_voice_channel_id)
      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(second_voice_channel_id)
    end
  end

  describe "durable Voice lifecycle notifications" do
    test "ends only the matching user's Voice Session in a Voice Channel" do
      voice_channel_id = Ecto.UUID.generate()
      target_user_id = Ecto.UUID.generate()
      retained_user_id = Ecto.UUID.generate()

      assert {:ok, _target_join} =
               Voice.join(voice_channel_id, target_user_id, "target-connection", self())

      assert {:ok, _retained_join} =
               Voice.join(voice_channel_id, retained_user_id, "retained-connection", self())

      assert :ok = Voice.end_user_session(voice_channel_id, target_user_id)
      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(voice_channel_id)

      assert :ok = Voice.end_user_session(voice_channel_id, target_user_id)
      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(voice_channel_id)
    end

    test "does not let a late notification for an old room end a moved Voice Session" do
      old_voice_channel_id = Ecto.UUID.generate()
      current_voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert {:ok, _old_join} =
               Voice.join(old_voice_channel_id, user_id, "old-connection", self())

      assert {:ok, _current_join} =
               Voice.join(current_voice_channel_id, user_id, "current-connection", self())

      assert :ok = Voice.end_user_session(old_voice_channel_id, user_id)

      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(old_voice_channel_id)
      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(current_voice_channel_id)
    end

    test "ends every Voice Session in one channel and retires only that empty room" do
      ended_voice_channel_id = Ecto.UUID.generate()
      unrelated_voice_channel_id = Ecto.UUID.generate()

      for number <- 1..2 do
        assert {:ok, %{occupancy: ^number}} =
                 Voice.join(
                   ended_voice_channel_id,
                   Ecto.UUID.generate(),
                   "ended-connection-#{number}",
                   self()
                 )
      end

      assert {:ok, %{occupancy: 1}} =
               Voice.join(
                 unrelated_voice_channel_id,
                 Ecto.UUID.generate(),
                 "unrelated-connection",
                 self()
               )

      assert :ok = Voice.end_channel_sessions(ended_voice_channel_id)
      assert :ok = Voice.await_empty_room(ended_voice_channel_id)

      assert {:ok, %{occupancy: 0, capacity: 5}} =
               Voice.room_occupancy(ended_voice_channel_id)

      assert {:ok, %{occupancy: 1, capacity: 5}} =
               Voice.room_occupancy(unrelated_voice_channel_id)

      assert :ok = Voice.expire_idle_room(ended_voice_channel_id)
      refute Voice.room_running?(ended_voice_channel_id)
    end

    test "treats missing and malformed durable cleanup notifications safely" do
      voice_channel_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      assert :ok = Voice.end_user_session(voice_channel_id, user_id)
      assert :ok = Voice.end_channel_sessions(voice_channel_id)
      assert Voice.end_user_session("not-a-uuid", user_id) == {:error, :not_found}
      assert Voice.end_channel_sessions("not-a-uuid") == {:error, :not_found}
    end
  end

  defp room_server(voice_channel_id) do
    {:via, Registry, {DiscordClone.Voice.RoomRegistry, {:room, voice_channel_id}}}
    |> GenServer.whereis()
  end

  defp runtime_candidate(number, options \\ []) do
    address = Keyword.get(options, :address, "127.0.0.1")
    priority = Keyword.get(options, :priority, 1)
    port = Keyword.get(options, :port, 10_000 + number)

    candidate = %{
      "candidate" => "candidate:#{number} 1 udp #{priority} #{address} #{port} typ host",
      "sdpMid" => "0",
      "sdpMLineIndex" => 0,
      "usernameFragment" => nil
    }

    %{
      negotiation_id: "current-negotiation",
      candidate: candidate,
      byte_count: byte_size(Jason.encode!(candidate))
    }
  end

  defp command_deadline, do: System.monotonic_time(:millisecond) + 5_000

  defp negotiated_server_peer_connection(excluded) do
    ExWebRTC.PeerConnection.get_all_running()
    |> Enum.reject(&(&1 in excluded))
    |> Enum.find(fn peer_connection ->
      peer_connection
      |> ExWebRTC.PeerConnection.get_transceivers()
      |> Enum.count(&(&1.current_direction == :sendonly))
      |> Kernel.==(4)
    end)
  end

  defp inbound_audio_transceiver(peer_connection) do
    peer_connection
    |> ExWebRTC.PeerConnection.get_transceivers()
    |> Enum.find(&(&1.current_direction == :recvonly))
  end

  defp first_audio_output_transceiver(peer_connection) do
    peer_connection
    |> ExWebRTC.PeerConnection.get_transceivers()
    |> Enum.find(&(&1.current_direction == :sendonly))
  end

  defp audio_output_track_ids(peer_connection) do
    peer_connection
    |> ExWebRTC.PeerConnection.get_transceivers()
    |> Enum.filter(&(&1.current_direction == :sendonly))
    |> Enum.map(& &1.sender.track.id)
  end

  defp start_signaling_channel(id) do
    start_supervised!(%{
      id: {:voice_signaling_channel, id},
      start:
        {Task, :start_link,
         [
           fn ->
             receive do
               :stop -> :ok
             end
           end
         ]}
    })
  end
end
