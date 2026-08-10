defmodule DiscordCloneWeb.VoiceChannelTest do
  use DiscordClone.DataCase, async: false

  import DiscordClone.AccountsFixtures
  import Phoenix.ChannelTest

  alias DiscordClone.Accounts
  alias DiscordClone.Voice
  alias DiscordClone.Workspaces
  alias DiscordClone.Workspaces.VoiceChannel, as: VoiceChannelSchema
  alias DiscordClone.Workspaces.WorkspaceMembership
  alias DiscordCloneWeb.{VoiceChannel, VoiceSocket}
  import DiscordCloneWeb.VoiceSignalingHelpers

  @endpoint DiscordCloneWeb.Endpoint

  describe "authenticated Voice Channel negotiation" do
    setup do
      user = user_fixture()
      voice_channel = create_voice_channel!(user, "Voice negotiation")

      token = Accounts.generate_user_session_token(user)

      {:ok, socket} =
        connect(VoiceSocket, %{}, connect_info: %{session: %{"user_token" => token}})

      {:ok, join_payload, channel_socket} =
        subscribe_and_join(
          socket,
          VoiceChannel,
          "voice:#{voice_channel.id}",
          admission_params()
        )

      %{
        channel_socket: channel_socket,
        join_payload: join_payload,
        signaling_session_id: join_payload.signaling_session_id,
        voice_channel_id: voice_channel.id
      }
    end

    test "returns opaque signaling and Voice Session IDs", context do
      %{join_payload: join_payload, signaling_session_id: signaling_session_id} = context

      assert %{
               signaling_session_id: ^signaling_session_id,
               voice_session_id: voice_session_id,
               occupancy: 1,
               capacity: 5
             } = join_payload

      assert {:ok, ^voice_session_id} = Ecto.UUID.cast(voice_session_id)
      refute voice_session_id == signaling_session_id

      assert Map.keys(join_payload) |> Enum.sort() == [
               :capacity,
               :occupancy,
               :signaling_session_id,
               :voice_session_id
             ]
    end

    test "returns a correlated real answer and sends server ICE only to its connection",
         context do
      %{channel_socket: channel_socket, signaling_session_id: signaling_session_id} = context

      negotiation_id = "first-negotiation"

      offer_ref = push(channel_socket, "offer", offer(signaling_session_id, negotiation_id))

      assert_reply offer_ref, :ok, reply

      assert %{
               signaling_session_id: ^signaling_session_id,
               negotiation_id: ^negotiation_id,
               description: %{"type" => "answer", "sdp" => answer_sdp}
             } = reply

      assert Map.keys(reply) |> Enum.sort() == [
               :description,
               :negotiation_id,
               :signaling_session_id
             ]

      assert is_binary(answer_sdp)
      assert byte_size(answer_sdp) > 0

      assert_push "ice_candidate", %{
        signaling_session_id: ^signaling_session_id,
        negotiation_id: ^negotiation_id,
        candidate: %{"candidate" => candidate}
      }

      assert is_binary(candidate)

      assert_push "ice_candidate", %{
        signaling_session_id: ^signaling_session_id,
        negotiation_id: ^negotiation_id,
        end_of_candidates: true
      }

      refute_push "ice_candidate", _payload
    end

    test "rejects mismatched, duplicate, malformed, and oversized offers safely", context do
      %{channel_socket: channel_socket, signaling_session_id: signaling_session_id} = context
      valid_offer = offer(signaling_session_id, "first-negotiation")

      assert_reply push(
                     channel_socket,
                     "offer",
                     put_in(valid_offer["signaling_session_id"], "wrong")
                   ),
                   :error,
                   %{reason: "invalid_request"}

      assert_reply push(channel_socket, "offer", %{"signaling_session_id" => signaling_session_id}),
                   :error,
                   %{reason: "invalid_negotiation"}

      oversized_offer = %{
        "signaling_session_id" => signaling_session_id,
        "negotiation_id" => "oversized",
        "description" => %{"type" => "offer", "sdp" => String.duplicate("x", 64 * 1024 + 1)}
      }

      assert_reply push(channel_socket, "offer", oversized_offer), :error, %{
        reason: "description_too_large"
      }

      assert_reply push(channel_socket, "offer", valid_offer), :ok

      assert_reply push(
                     channel_socket,
                     "offer",
                     put_in(valid_offer["negotiation_id"], "another")
                   ),
                   :error,
                   %{reason: "negotiation_already_active"}
    end

    test "closes an incompatible media offer without exposing its description", context do
      %{channel_socket: channel_socket, signaling_session_id: signaling_session_id} = context

      incompatible_offer =
        offer(signaling_session_id, "first-negotiation")
        |> update_in(["description", "sdp"], &String.replace(&1, "opus/48000/2", "ISAC/16000"))

      Process.unlink(channel_socket.channel_pid)
      monitor_ref = Process.monitor(channel_socket.channel_pid)

      assert_reply push(channel_socket, "offer", incompatible_offer), :error, %{
        reason: "negotiation_failed"
      }

      assert_receive {:DOWN, ^monitor_ref, :process, _, :normal}
    end

    test "reports a retryable four-slot compatibility failure and removes the attempted Session",
         context do
      %{
        channel_socket: channel_socket,
        signaling_session_id: signaling_session_id,
        voice_channel_id: voice_channel_id
      } = context

      incomplete_offer = %{
        "signaling_session_id" => signaling_session_id,
        "negotiation_id" => "first-negotiation",
        "description" => browser_offer(3)
      }

      Process.unlink(channel_socket.channel_pid)
      monitor_ref = Process.monitor(channel_socket.channel_pid)

      assert_reply push(channel_socket, "offer", incomplete_offer), :error, %{
        reason: "incompatible_audio_output_slots"
      }

      assert_receive {:DOWN, ^monitor_ref, :process, _, :normal}
      assert :ok = Voice.await_empty_room(voice_channel_id)
      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(voice_channel_id)
    end

    test "rejects client ICE from a stale Signaling Session", context do
      %{channel_socket: channel_socket, signaling_session_id: signaling_session_id} = context
      negotiation_id = "first-negotiation"
      assert_reply push(channel_socket, "offer", offer(signaling_session_id, negotiation_id)), :ok

      assert_reply(
        push(channel_socket, "ice_candidate", %{
          "signaling_session_id" => "stale-signaling-session",
          "negotiation_id" => negotiation_id,
          "candidate" => candidate()
        }),
        :error,
        %{reason: "invalid_request"}
      )
    end

    test "rejects malformed client ICE at the Channel boundary", context do
      %{channel_socket: channel_socket, signaling_session_id: signaling_session_id} = context
      negotiation_id = "first-negotiation"

      assert_reply(
        push(channel_socket, "ice_candidate", %{
          "signaling_session_id" => signaling_session_id,
          "negotiation_id" => negotiation_id,
          "candidate" => Map.delete(candidate(), "sdpMid")
        }),
        :error,
        %{reason: "invalid_candidate"}
      )
    end

    test "rejects client ICE from a stale Negotiation", context do
      %{channel_socket: channel_socket, signaling_session_id: signaling_session_id} = context
      negotiation_id = "first-negotiation"
      assert_reply push(channel_socket, "offer", offer(signaling_session_id, negotiation_id)), :ok

      assert_reply(
        push(channel_socket, "ice_candidate", %{
          "signaling_session_id" => signaling_session_id,
          "negotiation_id" => "stale-negotiation",
          "candidate" => candidate()
        }),
        :error,
        %{reason: "invalid_negotiation"}
      )
    end

    test "rejects oversized client ICE at the Channel boundary", context do
      %{channel_socket: channel_socket, signaling_session_id: signaling_session_id} = context
      negotiation_id = "first-negotiation"

      assert_reply(
        push(channel_socket, "ice_candidate", %{
          "signaling_session_id" => signaling_session_id,
          "negotiation_id" => negotiation_id,
          "candidate" => Map.put(candidate(), "candidate", String.duplicate("x", 8 * 1024 + 1))
        }),
        :error,
        %{reason: "candidate_too_large"}
      )
    end

    test "buffers a bounded early ICE candidate until its offer is accepted", context do
      %{channel_socket: channel_socket, signaling_session_id: signaling_session_id} = context
      negotiation_id = "first-negotiation"

      assert_reply(
        push(channel_socket, "ice_candidate", %{
          "signaling_session_id" => signaling_session_id,
          "negotiation_id" => negotiation_id,
          "candidate" => candidate()
        }),
        :ok,
        %{negotiation_id: ^negotiation_id}
      )

      assert_reply push(channel_socket, "offer", offer(signaling_session_id, negotiation_id)), :ok
    end

    test "rejects a seventeenth early ICE candidate before the offer", context do
      %{channel_socket: channel_socket, signaling_session_id: signaling_session_id} = context
      negotiation_id = "first-negotiation"

      for number <- 1..16 do
        assert_reply(
          push(channel_socket, "ice_candidate", %{
            "signaling_session_id" => signaling_session_id,
            "negotiation_id" => negotiation_id,
            "candidate" =>
              Map.put(
                candidate(),
                "candidate",
                "candidate:#{number} 1 udp 1 127.0.0.1 9 typ host"
              )
          }),
          :ok,
          %{negotiation_id: ^negotiation_id}
        )
      end

      assert_reply(
        push(channel_socket, "ice_candidate", %{
          "signaling_session_id" => signaling_session_id,
          "negotiation_id" => negotiation_id,
          "candidate" => candidate()
        }),
        :error,
        %{reason: "pending_candidate_limit_reached"}
      )
    end

    test "bounds early ICE by total decoded candidate bytes before the count limit", context do
      %{channel_socket: channel_socket, signaling_session_id: signaling_session_id} = context
      negotiation_id = "first-negotiation"

      # Edge validation sees 8,177 bytes. Runtime normalization adds usernameFragment,
      # making each queued candidate 8,201 bytes and the sixteenth exceed 16 * 8 KiB.
      near_limit_candidate =
        candidate()
        |> Map.put("candidate", String.duplicate("x", 8_130))

      for _number <- 1..15 do
        assert_reply(
          push(channel_socket, "ice_candidate", %{
            "signaling_session_id" => signaling_session_id,
            "negotiation_id" => negotiation_id,
            "candidate" => near_limit_candidate
          }),
          :ok,
          %{negotiation_id: ^negotiation_id}
        )
      end

      assert_reply(
        push(channel_socket, "ice_candidate", %{
          "signaling_session_id" => signaling_session_id,
          "negotiation_id" => negotiation_id,
          "candidate" => near_limit_candidate
        }),
        :error,
        %{reason: "pending_candidate_limit_reached"}
      )
    end

    test "rejects the sixty-fifth accepted ICE candidate", context do
      %{channel_socket: channel_socket, signaling_session_id: signaling_session_id} = context
      negotiation_id = "first-negotiation"
      assert_reply push(channel_socket, "offer", offer(signaling_session_id, negotiation_id)), :ok

      for number <- 1..64 do
        assert_reply(
          push(channel_socket, "ice_candidate", %{
            "signaling_session_id" => signaling_session_id,
            "negotiation_id" => negotiation_id,
            "candidate" =>
              Map.put(
                candidate(),
                "candidate",
                "candidate:#{number} 1 udp 1 127.0.0.1 9 typ host"
              )
          }),
          :ok,
          %{negotiation_id: ^negotiation_id}
        )
      end

      assert_reply(
        push(channel_socket, "ice_candidate", %{
          "signaling_session_id" => signaling_session_id,
          "negotiation_id" => negotiation_id,
          "candidate" => candidate()
        }),
        :error,
        %{reason: "candidate_limit_reached"}
      )
    end

    test "keeps server ICE events isolated between two joined connections",
         context do
      %{
        channel_socket: first_channel_socket,
        signaling_session_id: first_signaling_session_id,
        join_payload: %{voice_session_id: first_voice_session_id},
        voice_channel_id: voice_channel_id
      } = context

      [first_peer_connection] = ExWebRTC.PeerConnection.get_all_running()

      second_user = user_fixture()
      add_workspace_member!(voice_channel_id, second_user)
      {:ok, second_socket} = connect_voice_socket(second_user)

      assert {:ok,
              %{
                signaling_session_id: second_signaling_session_id,
                voice_session_id: second_voice_session_id
              }, second_channel_socket} =
               subscribe_and_join(
                 second_socket,
                 VoiceChannel,
                 first_channel_socket.topic,
                 admission_params()
               )

      refute first_signaling_session_id == second_signaling_session_id

      [second_peer_connection] =
        ExWebRTC.PeerConnection.get_all_running() -- [first_peer_connection]

      negotiation_id = "shared-negotiation"

      assert_reply push(
                     first_channel_socket,
                     "offer",
                     offer(first_signaling_session_id, negotiation_id)
                   ),
                   :ok

      assert_push "ice_candidate", %{signaling_session_id: ^first_signaling_session_id}

      assert_push "ice_candidate", %{
        signaling_session_id: ^first_signaling_session_id,
        end_of_candidates: true
      }

      assert_reply push(
                     second_channel_socket,
                     "offer",
                     offer(second_signaling_session_id, negotiation_id)
                   ),
                   :ok

      assert_push "ice_candidate", %{signaling_session_id: ^second_signaling_session_id}

      assert_push "ice_candidate", %{
        signaling_session_id: ^second_signaling_session_id,
        end_of_candidates: true
      }

      refute_push "ice_candidate", _payload

      first_candidate_value = "candidate:101 1 udp 1 127.0.0.1 10001 typ host"

      assert :ok =
               Voice.dispatch_test_ex_webrtc(
                 voice_channel_id,
                 first_voice_session_id,
                 {:ex_webrtc, first_peer_connection,
                  {:ice_candidate, server_candidate(first_candidate_value)}}
               )

      assert_push "ice_candidate", %{
        signaling_session_id: ^first_signaling_session_id,
        negotiation_id: ^negotiation_id,
        candidate: %{"candidate" => ^first_candidate_value}
      }

      refute_push "ice_candidate", %{
        signaling_session_id: ^second_signaling_session_id,
        candidate: %{"candidate" => ^first_candidate_value}
      }

      second_candidate_value = "candidate:202 1 udp 1 127.0.0.1 10002 typ host"

      assert :ok =
               Voice.dispatch_test_ex_webrtc(
                 voice_channel_id,
                 second_voice_session_id,
                 {:ex_webrtc, second_peer_connection,
                  {:ice_candidate, server_candidate(second_candidate_value)}}
               )

      assert_push "ice_candidate", %{
        signaling_session_id: ^second_signaling_session_id,
        negotiation_id: ^negotiation_id,
        candidate: %{"candidate" => ^second_candidate_value}
      }

      refute_push "ice_candidate", %{
        signaling_session_id: ^first_signaling_session_id,
        candidate: %{"candidate" => ^second_candidate_value}
      }

      assert :ok =
               Voice.dispatch_test_ex_webrtc(
                 voice_channel_id,
                 first_voice_session_id,
                 {:ex_webrtc, first_peer_connection, {:ice_gathering_state_change, :complete}}
               )

      assert_push "ice_candidate", %{
        signaling_session_id: ^first_signaling_session_id,
        negotiation_id: ^negotiation_id,
        end_of_candidates: true
      }

      refute_push "ice_candidate", %{
        signaling_session_id: ^second_signaling_session_id,
        end_of_candidates: true
      }

      assert :ok =
               Voice.dispatch_test_ex_webrtc(
                 voice_channel_id,
                 second_voice_session_id,
                 {:ex_webrtc, second_peer_connection, {:ice_gathering_state_change, :complete}}
               )

      assert_push "ice_candidate", %{
        signaling_session_id: ^second_signaling_session_id,
        negotiation_id: ^negotiation_id,
        end_of_candidates: true
      }

      refute_push "ice_candidate", %{
        signaling_session_id: ^first_signaling_session_id,
        end_of_candidates: true
      }
    end

    test "ignores stale Voice Session and Negotiation events before serializing server ICE",
         context do
      %{
        channel_socket: channel_socket,
        signaling_session_id: signaling_session_id,
        join_payload: %{voice_session_id: voice_session_id}
      } = context

      negotiation_id = "current-negotiation"
      assert_reply push(channel_socket, "offer", offer(signaling_session_id, negotiation_id)), :ok
      assert_push "ice_candidate", %{signaling_session_id: ^signaling_session_id}

      assert_push "ice_candidate", %{
        signaling_session_id: ^signaling_session_id,
        end_of_candidates: true
      }

      stale_session_candidate = %{"candidate" => "stale-session-candidate"}
      stale_negotiation_candidate = %{"candidate" => "stale-negotiation-candidate"}

      send(
        channel_socket.channel_pid,
        {:voice_session_event, Ecto.UUID.generate(),
         {:ice_candidate, negotiation_id, stale_session_candidate}}
      )

      send(
        channel_socket.channel_pid,
        {:voice_session_event, voice_session_id,
         {:ice_candidate, "stale-negotiation", stale_negotiation_candidate}}
      )

      send(
        channel_socket.channel_pid,
        {:voice_session_event, voice_session_id, {:end_of_candidates, "stale-negotiation"}}
      )

      _ = :sys.get_state(channel_socket.channel_pid)

      refute_push "ice_candidate", %{candidate: ^stale_session_candidate}
      refute_push "ice_candidate", %{candidate: ^stale_negotiation_candidate}
      refute_push "ice_candidate", %{negotiation_id: "stale-negotiation"}

      current_candidate = %{"candidate" => "current-candidate"}

      send(
        channel_socket.channel_pid,
        {:voice_session_event, voice_session_id,
         {:ice_candidate, negotiation_id, current_candidate}}
      )

      assert_push "ice_candidate", %{
        signaling_session_id: ^signaling_session_id,
        negotiation_id: ^negotiation_id,
        candidate: ^current_candidate
      }
    end

    test "stops the Session-owned peer connection when the topic leaves", context do
      %{channel_socket: channel_socket} = context
      running_before_leave = ExWebRTC.PeerConnection.get_all_running()

      assert Enum.any?(running_before_leave)
      [peer_connection] = running_before_leave
      peer_connection_ref = Process.monitor(peer_connection)

      Process.unlink(channel_socket.channel_pid)
      monitor_ref = Process.monitor(channel_socket.channel_pid)
      assert_reply leave(channel_socket), :ok
      assert_receive {:DOWN, ^monitor_ref, :process, _, _reason}
      assert_receive {:DOWN, ^peer_connection_ref, :process, ^peer_connection, _reason}

      refute Enum.any?(ExWebRTC.PeerConnection.get_all_running())
      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(context.voice_channel_id)
    end

    test "keeps disconnected peers available but releases terminal server peers", context do
      %{channel_socket: channel_socket, join_payload: %{voice_session_id: voice_session_id}} =
        context

      [peer_connection] = ExWebRTC.PeerConnection.get_all_running()

      assert :ok =
               Voice.dispatch_test_ex_webrtc(
                 context.voice_channel_id,
                 voice_session_id,
                 {:ex_webrtc, peer_connection, {:connection_state_change, :disconnected}}
               )

      _ = :sys.get_state(channel_socket.channel_pid)

      Process.unlink(channel_socket.channel_pid)
      monitor_ref = Process.monitor(channel_socket.channel_pid)

      assert :ok =
               Voice.dispatch_test_ex_webrtc(
                 context.voice_channel_id,
                 voice_session_id,
                 {:ex_webrtc, peer_connection, {:connection_state_change, :failed}}
               )

      assert_receive {:DOWN, ^monitor_ref, :process, _, :normal}
      refute Enum.any?(ExWebRTC.PeerConnection.get_all_running())
      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(context.voice_channel_id)
    end

    test "closes the owning Channel for a closed server peer", context do
      %{channel_socket: channel_socket, join_payload: %{voice_session_id: voice_session_id}} =
        context

      [peer_connection] = ExWebRTC.PeerConnection.get_all_running()
      peer_connection_monitor = Process.monitor(peer_connection)

      Process.unlink(channel_socket.channel_pid)
      channel_monitor = Process.monitor(channel_socket.channel_pid)

      assert :ok =
               Voice.dispatch_test_ex_webrtc(
                 context.voice_channel_id,
                 voice_session_id,
                 {:ex_webrtc, peer_connection, {:connection_state_change, :closed}}
               )

      assert_receive {:DOWN, ^channel_monitor, :process, _, :normal}
      assert_receive {:DOWN, ^peer_connection_monitor, :process, ^peer_connection, _reason}
      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(context.voice_channel_id)
    end

    test "emits metadata-only diagnostics for real descriptions", context do
      %{channel_socket: channel_socket, signaling_session_id: signaling_session_id} = context
      handler_id = "voice-signaling-#{System.unique_integer([:positive])}"
      test_pid = self()

      :ok =
        :telemetry.attach(
          handler_id,
          [:discord_clone, :voice_signaling, :operation],
          fn _, _, metadata, _ ->
            send(test_pid, {:voice_diagnostic, metadata})
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert_reply push(
                     channel_socket,
                     "offer",
                     offer(signaling_session_id, "first-negotiation")
                   ),
                   :ok

      assert_receive {:voice_diagnostic, %{operation: "offer"} = metadata}

      assert metadata.outcome == :accepted
      assert is_integer(metadata.decoded_request_byte_count)

      assert Map.keys(metadata) |> Enum.sort() == [
               :decoded_request_byte_count,
               :operation,
               :outcome
             ]

      for forbidden <- [
            :sdp,
            :ice_username_fragment,
            :raw_rtp,
            :packet,
            :pid,
            :user_id,
            :voice_channel_id,
            :voice_session_id,
            :signaling_session_id,
            :negotiation_id,
            :description,
            :candidate,
            :ice_servers,
            :ice_credentials,
            :params,
            :socket,
            :user,
            :voice_channel
          ] do
        refute Map.has_key?(metadata, forbidden)
      end

      refute Enum.any?(Map.values(metadata), &is_pid/1)
    end

    test "counts accepted and dropped media without self-echo or identifying metadata", context do
      %{
        channel_socket: channel_socket,
        signaling_session_id: signaling_session_id,
        join_payload: %{voice_session_id: voice_session_id}
      } = context

      handler_id = "voice-media-#{System.unique_integer([:positive])}"
      test_pid = self()

      assert_reply push(
                     channel_socket,
                     "offer",
                     offer(signaling_session_id, "first-negotiation")
                   ),
                   :ok

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

      :ok =
        :telemetry.attach(
          handler_id,
          [:discord_clone, :voice_signaling, :operation],
          fn _, _, metadata, _ -> send(test_pid, {:voice_media_diagnostic, metadata}) end,
          nil
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert :ok =
               Voice.dispatch_test_ex_webrtc(
                 context.voice_channel_id,
                 voice_session_id,
                 {:ex_webrtc, peer_connection, {:track, inbound_track}}
               )

      assert_receive {:voice_media_diagnostic,
                      %{media_lifecycle: :inbound_track_admitted} = admitted_metadata}

      assert_media_diagnostic_metadata(admitted_metadata)
      assert admitted_metadata.inbound_packet_count == 0
      assert admitted_metadata.forwarded_packet_count == 0
      assert admitted_metadata.dropped_packet_count == 0
      assert admitted_metadata.dropped_media_count == 0

      packet =
        ExRTP.Packet.new(<<>>, payload_type: 111, sequence_number: 1, timestamp: 1, ssrc: 1)

      assert :ok =
               Voice.dispatch_test_ex_webrtc(
                 context.voice_channel_id,
                 voice_session_id,
                 {:ex_webrtc, peer_connection, {:rtp, inbound_track.id, nil, packet}}
               )

      assert_receive {:voice_media_diagnostic,
                      %{media_lifecycle: :rtp_received} = received_metadata}

      assert_media_diagnostic_metadata(received_metadata)
      assert received_metadata.inbound_packet_count == 1
      assert received_metadata.forwarded_packet_count == 0
      assert received_metadata.dropped_packet_count == 0
      assert received_metadata.dropped_media_count == 0

      assert_receive {:voice_media_diagnostic, %{media_lifecycle: :rtp_dropped} = route_metadata}
      assert_route_diagnostic_metadata(route_metadata)
      assert route_metadata.forwarded_packet_count == 0
      assert route_metadata.dropped_packet_count == 1

      for {message, lifecycle} <- [
            {{:track_muted, inbound_track.id}, :inbound_track_muted},
            {{:track_ended, inbound_track.id}, :inbound_track_ended}
          ] do
        assert :ok =
                 Voice.dispatch_test_ex_webrtc(
                   context.voice_channel_id,
                   voice_session_id,
                   {:ex_webrtc, peer_connection, message}
                 )

        assert_receive {:voice_media_diagnostic, %{media_lifecycle: ^lifecycle} = track_metadata}
        assert_media_diagnostic_metadata(track_metadata)
      end

      unsupported_media = [
        {:track, %ExWebRTC.MediaStreamTrack{id: inbound_track.id + 1, kind: :video}},
        {:data_channel, %{}},
        {:data_channel_state_change, make_ref(), :open},
        {:data, make_ref(), "unsupported"},
        {:rtcp, []}
      ]

      for message <- unsupported_media do
        assert :ok =
                 Voice.dispatch_test_ex_webrtc(
                   context.voice_channel_id,
                   voice_session_id,
                   {:ex_webrtc, peer_connection, message}
                 )

        assert_receive {:voice_media_diagnostic,
                        %{media_lifecycle: :unexpected_media_dropped} = dropped_metadata}

        assert_media_diagnostic_metadata(dropped_metadata)
      end

      assert :ok =
               Voice.dispatch_test_ex_webrtc(
                 context.voice_channel_id,
                 voice_session_id,
                 {:ex_webrtc, self(), {:rtp, inbound_track.id, nil, packet}}
               )

      assert :ok =
               Voice.dispatch_test_ex_webrtc(
                 context.voice_channel_id,
                 voice_session_id,
                 {:ex_webrtc, peer_connection, {:rtp, inbound_track.id + 2, nil, packet}}
               )

      assert_receive {:voice_media_diagnostic,
                      %{media_lifecycle: :unexpected_media_dropped} = final_metadata}

      assert_media_diagnostic_metadata(final_metadata)
      assert final_metadata.inbound_packet_count == 1
      assert final_metadata.forwarded_packet_count == 0
      assert final_metadata.dropped_packet_count == 1
      assert final_metadata.dropped_media_count == length(unsupported_media)
    end
  end

  describe "authenticated Voice joins" do
    test "rejects missing or incompatible admission offers before starting runtime state" do
      owner = user_fixture()
      voice_channel = create_voice_channel!(owner)
      {:ok, socket} = connect_voice_socket(owner)

      assert {:error, %{reason: "incompatible_audio_output_slots"}} =
               subscribe_and_join(socket, VoiceChannel, "voice:#{voice_channel.id}")

      assert {:error, %{reason: "incompatible_audio_output_slots"}} =
               subscribe_and_join(
                 socket,
                 VoiceChannel,
                 "voice:#{voice_channel.id}",
                 %{"description" => browser_offer(3)}
               )

      refute Voice.room_running?(voice_channel.id)
    end

    test "denies unauthorized, missing, and malformed Voice Channels without runtime state" do
      owner = user_fixture()
      unauthorized_user = user_fixture()
      voice_channel = create_voice_channel!(owner)

      {:ok, unauthorized_socket} = connect_voice_socket(unauthorized_user)
      missing_voice_channel_id = Ecto.UUID.generate()

      assert {:error, %{reason: "not_found"}} =
               subscribe_and_join(unauthorized_socket, VoiceChannel, "voice:#{voice_channel.id}")

      assert {:error, %{reason: "not_found"}} =
               subscribe_and_join(
                 unauthorized_socket,
                 VoiceChannel,
                 "voice:#{missing_voice_channel_id}"
               )

      assert {:error, %{reason: "not_found"}} =
               subscribe_and_join(unauthorized_socket, VoiceChannel, "voice:not-a-uuid")

      refute Voice.room_running?(voice_channel.id)
      refute Voice.room_running?(missing_voice_channel_id)
      refute Voice.room_running?("not-a-uuid")
    end

    test "normalizes a full-room join and releases the unused PeerConnection" do
      owner = user_fixture()
      voice_channel = create_voice_channel!(owner)

      voice_session_ids =
        for number <- 1..5 do
          assert {:ok, %{voice_session_id: voice_session_id, occupancy: ^number, capacity: 5}} =
                   Voice.join(
                     voice_channel.id,
                     Ecto.UUID.generate(),
                     "filler-#{number}",
                     self()
                   )

          voice_session_id
        end

      on_exit(fn ->
        Enum.each(voice_session_ids, &Voice.leave(voice_channel.id, &1))
        Voice.expire_idle_room(voice_channel.id)
      end)

      running_before_join = ExWebRTC.PeerConnection.get_all_running()
      {:ok, socket} = connect_voice_socket(owner)

      assert {:error, %{reason: "room_full", occupancy: 5, capacity: 5}} =
               subscribe_and_join(
                 socket,
                 VoiceChannel,
                 "voice:#{voice_channel.id}",
                 admission_params()
               )

      assert ExWebRTC.PeerConnection.get_all_running() == running_before_join
      assert {:ok, %{occupancy: 5, capacity: 5}} = Voice.room_occupancy(voice_channel.id)
    end

    test "an older Channel termination cannot remove a newer Voice Session" do
      user = user_fixture()
      voice_channel = create_voice_channel!(user)
      {:ok, socket} = connect_voice_socket(user)

      assert {:ok, %{voice_session_id: first_voice_session_id}, first_channel_socket} =
               subscribe_and_join(
                 socket,
                 VoiceChannel,
                 "voice:#{voice_channel.id}",
                 admission_params()
               )

      assert {:ok, %{voice_session_id: second_voice_session_id}, second_channel_socket} =
               subscribe_and_join(
                 first_channel_socket,
                 VoiceChannel,
                 first_channel_socket.topic,
                 admission_params()
               )

      refute first_voice_session_id == second_voice_session_id
      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(voice_channel.id)

      Process.unlink(first_channel_socket.channel_pid)
      monitor_ref = Process.monitor(first_channel_socket.channel_pid)
      Process.exit(first_channel_socket.channel_pid, :shutdown)
      assert_receive {:DOWN, ^monitor_ref, :process, _, _reason}

      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(voice_channel.id)

      Process.unlink(second_channel_socket.channel_pid)
      second_monitor_ref = Process.monitor(second_channel_socket.channel_pid)
      Process.exit(second_channel_socket.channel_pid, :shutdown)
      assert_receive {:DOWN, ^second_monitor_ref, :process, _, _reason}
      assert :ok = Voice.await_empty_room(voice_channel.id)
      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(voice_channel.id)
    end
  end

  describe "socket joins" do
    test "derives scope from the signed session and denies invalid sessions" do
      user = user_fixture()
      other_user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert {:ok, socket} =
               connect(VoiceSocket, %{"user_id" => other_user.id},
                 connect_info: %{session: %{"user_token" => token}}
               )

      assert socket.assigns.current_scope.user.id == user.id
      assert :error = connect(VoiceSocket, %{}, connect_info: %{session: nil})
    end
  end

  defp offer(signaling_session_id, negotiation_id) do
    %{
      "signaling_session_id" => signaling_session_id,
      "negotiation_id" => negotiation_id,
      "description" => browser_offer()
    }
  end

  defp admission_params do
    %{"description" => browser_offer()}
  end

  defp assert_media_diagnostic_metadata(metadata) do
    assert Map.keys(metadata) |> Enum.sort() == [
             :dropped_media_count,
             :dropped_packet_count,
             :forwarded_packet_count,
             :inbound_packet_count,
             :media_lifecycle
           ]
  end

  defp assert_route_diagnostic_metadata(metadata) do
    assert Map.keys(metadata) |> Enum.sort() == [
             :dropped_packet_count,
             :forwarded_packet_count,
             :media_lifecycle
           ]
  end

  defp candidate do
    %{
      "candidate" => "candidate:1 1 udp 1 127.0.0.1 9 typ host",
      "sdpMid" => "0",
      "sdpMLineIndex" => 0
    }
  end

  defp server_candidate(candidate_value) do
    %ExWebRTC.ICECandidate{
      candidate: candidate_value,
      sdp_mid: "0",
      sdp_m_line_index: 0
    }
  end

  defp create_voice_channel!(user, workspace_name \\ "Voice join") do
    scope = DiscordClone.Accounts.Scope.for_user(user)
    {:ok, workspace} = Workspaces.create_workspace(scope, %{name: workspace_name})
    {:ok, voice_channel} = Workspaces.create_voice_channel(scope, workspace.id, %{name: "lobby"})
    voice_channel
  end

  defp connect_voice_socket(user) do
    token = Accounts.generate_user_session_token(user)
    connect(VoiceSocket, %{}, connect_info: %{session: %{"user_token" => token}})
  end

  defp add_workspace_member!(voice_channel_id, user) do
    voice_channel = Repo.get!(VoiceChannelSchema, voice_channel_id)

    %WorkspaceMembership{}
    |> WorkspaceMembership.changeset(%{
      workspace_id: voice_channel.workspace_id,
      user_id: user.id,
      role: "member"
    })
    |> Repo.insert!()
  end
end
