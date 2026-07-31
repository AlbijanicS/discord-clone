defmodule DiscordCloneWeb.VoiceChannelTest do
  use DiscordClone.DataCase, async: false

  import DiscordClone.AccountsFixtures
  import Phoenix.ChannelTest

  alias DiscordClone.Accounts
  alias DiscordClone.Workspaces
  alias DiscordCloneWeb.{VoiceChannel, VoiceSocket}
  import DiscordCloneWeb.VoiceSignalingHelpers

  @endpoint DiscordCloneWeb.Endpoint

  describe "authenticated Voice Channel negotiation" do
    setup do
      user = user_fixture()
      scope = DiscordClone.Accounts.Scope.for_user(user)
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Voice negotiation"})

      {:ok, voice_channel} =
        Workspaces.create_voice_channel(scope, workspace.id, %{name: "lobby"})

      token = Accounts.generate_user_session_token(user)

      {:ok, socket} =
        connect(VoiceSocket, %{}, connect_info: %{session: %{"user_token" => token}})

      {:ok, %{signaling_session_id: signaling_session_id}, channel_socket} =
        subscribe_and_join(socket, VoiceChannel, "voice:#{voice_channel.id}")

      %{channel_socket: channel_socket, signaling_session_id: signaling_session_id}
    end

    test "returns a correlated real answer and sends server ICE only to its connection",
         context do
      %{channel_socket: channel_socket, signaling_session_id: signaling_session_id} = context

      assert {:ok, _reply, _other_channel_socket} =
               subscribe_and_join(channel_socket, VoiceChannel, channel_socket.topic)

      negotiation_id = "first-negotiation"

      assert_reply push(channel_socket, "offer", offer(signaling_session_id, negotiation_id)),
                   :ok,
                   %{
                     signaling_session_id: ^signaling_session_id,
                     negotiation_id: ^negotiation_id,
                     description: %{"type" => "answer", "sdp" => answer_sdp}
                   }

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

    test "requires the current negotiation for safely bounded client ICE", context do
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

    test "keeps signaling session IDs and server ICE isolated between admitted connections",
         context do
      %{channel_socket: first_channel, signaling_session_id: first_id} = context

      assert {:ok, %{signaling_session_id: second_id}, second_channel} =
               subscribe_and_join(first_channel, VoiceChannel, first_channel.topic)

      refute first_id == second_id

      assert_reply push(second_channel, "offer", offer(first_id, "cross-connection")), :error, %{
        reason: "invalid_request"
      }

      assert_reply push(first_channel, "offer", offer(first_id, "first-negotiation")), :ok

      assert_push "ice_candidate", %{signaling_session_id: ^first_id}
      assert_push "ice_candidate", %{signaling_session_id: ^first_id, end_of_candidates: true}
      refute_push "ice_candidate", _payload
    end

    test "stops the Channel-owned peer connection when the topic leaves", context do
      %{channel_socket: channel_socket} = context
      running_before_leave = ExWebRTC.PeerConnection.get_all_running()

      assert Enum.any?(running_before_leave)

      Process.unlink(channel_socket.channel_pid)
      monitor_ref = Process.monitor(channel_socket.channel_pid)
      assert_reply leave(channel_socket), :ok
      assert_receive {:DOWN, ^monitor_ref, :process, _, _reason}

      refute Enum.any?(ExWebRTC.PeerConnection.get_all_running())
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

      for forbidden <- [
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
    end

    test "counts admitted, echoed, and dropped media without identifying metadata", context do
      %{channel_socket: channel_socket, signaling_session_id: signaling_session_id} = context
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
          |> Enum.any?(& &1.sender.track)
        end)

      [transceiver] = ExWebRTC.PeerConnection.get_transceivers(peer_connection)
      inbound_track = transceiver.receiver.track

      :ok =
        :telemetry.attach(
          handler_id,
          [:discord_clone, :voice_signaling, :operation],
          fn _, _, metadata, _ -> send(test_pid, {:voice_media_diagnostic, metadata}) end,
          nil
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      send(channel_socket.channel_pid, {:ex_webrtc, peer_connection, {:track, inbound_track}})

      assert_receive {:voice_media_diagnostic,
                      %{media_lifecycle: :inbound_track_admitted} = admitted_metadata}

      assert admitted_metadata.inbound_packet_count == 0
      assert admitted_metadata.echoed_packet_count == 0
      assert admitted_metadata.dropped_packet_count == 0
      assert admitted_metadata.dropped_media_count == 0

      packet =
        ExRTP.Packet.new(<<>>, payload_type: 111, sequence_number: 1, timestamp: 1, ssrc: 1)

      send(
        channel_socket.channel_pid,
        {:ex_webrtc, peer_connection, {:rtp, inbound_track.id, nil, packet}}
      )

      assert_receive {:voice_media_diagnostic,
                      %{
                        media_lifecycle: :rtp_routed,
                        inbound_packet_count: 1,
                        echoed_packet_count: 1,
                        dropped_packet_count: 0,
                        dropped_media_count: 0
                      }}

      send(
        channel_socket.channel_pid,
        {:ex_webrtc, peer_connection,
         {:track, %ExWebRTC.MediaStreamTrack{id: inbound_track.id + 1, kind: :video}}}
      )

      send(channel_socket.channel_pid, {:ex_webrtc, peer_connection, {:data_channel, %{}}})

      send(
        channel_socket.channel_pid,
        {:ex_webrtc, peer_connection, {:rtp, inbound_track.id + 2, nil, packet}}
      )

      assert_receive {:voice_media_diagnostic,
                      %{media_lifecycle: :unexpected_media_dropped, dropped_media_count: 1}}

      assert_receive {:voice_media_diagnostic,
                      %{media_lifecycle: :unexpected_media_dropped, dropped_media_count: 2}}

      assert_receive {:voice_media_diagnostic,
                      %{
                        media_lifecycle: :unexpected_media_dropped,
                        inbound_packet_count: 1,
                        echoed_packet_count: 1,
                        dropped_packet_count: 1,
                        dropped_media_count: 2
                      }}
    end
  end

  describe "socket admission" do
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

  defp candidate do
    %{
      "candidate" => "candidate:1 1 udp 1 127.0.0.1 9 typ host",
      "sdpMid" => "0",
      "sdpMLineIndex" => 0
    }
  end
end
