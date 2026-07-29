defmodule DiscordCloneWeb.VoiceChannelTest do
  use DiscordClone.DataCase, async: false

  import DiscordClone.AccountsFixtures
  import Phoenix.ChannelTest

  alias DiscordClone.Accounts
  alias DiscordClone.Workspaces
  alias DiscordCloneWeb.{VoiceChannel, VoiceSocket}

  @endpoint DiscordCloneWeb.Endpoint

  describe "socket authentication" do
    test "derives the scope from the signed session rather than browser identity params" do
      user = user_fixture()
      other_user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert {:ok, socket} =
               connect(VoiceSocket, %{"user_id" => other_user.id},
                 connect_info: %{session: %{"user_token" => token}}
               )

      assert socket.assigns.current_scope.user.id == user.id
    end

    test "rejects missing, invalid, expired, and revoked sessions" do
      user = user_fixture()
      expired_token = Accounts.generate_user_session_token(user)
      revoked_token = Accounts.generate_user_session_token(user)
      offset_user_token(expired_token, -61, :day)
      Accounts.delete_user_session_token(revoked_token)

      for session <- [
            nil,
            %{"user_token" => "invalid"},
            %{"user_token" => expired_token},
            %{"user_token" => revoked_token}
          ] do
        assert :error = connect(VoiceSocket, %{}, connect_info: %{session: session})
      end
    end
  end

  describe "Voice Channel topic admission" do
    setup do
      owner = user_fixture()
      scope = DiscordClone.Accounts.Scope.for_user(owner)
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Voice admission"})

      {:ok, voice_channel} =
        Workspaces.create_voice_channel(scope, workspace.id, %{name: "lobby"})

      token = Accounts.generate_user_session_token(owner)

      {:ok, socket} =
        connect(VoiceSocket, %{}, connect_info: %{session: %{"user_token" => token}})

      %{socket: socket, token: token, voice_channel: voice_channel}
    end

    test "admits an authorized member with a fresh opaque signaling session ID", %{
      socket: socket,
      voice_channel: voice_channel
    } do
      topic = "voice:#{voice_channel.id}"

      assert {:ok, %{signaling_session_id: first_id}, first_socket} =
               subscribe_and_join(socket, VoiceChannel, topic)

      assert is_binary(first_id)
      assert first_id =~ ~r/^[A-Za-z0-9_-]+$/
      assert byte_size(first_id) >= 32

      assert {:ok, %{signaling_session_id: second_id}, _second_socket} =
               subscribe_and_join(socket, VoiceChannel, topic)

      refute first_id == second_id

      Process.unlink(first_socket.channel_pid)
      assert_reply leave(first_socket), :ok
    end

    test "denies malformed, missing, and inaccessible topics with the same safe error", %{
      socket: socket
    } do
      inaccessible_user = user_fixture()
      inaccessible_scope = DiscordClone.Accounts.Scope.for_user(inaccessible_user)

      {:ok, other_workspace} =
        Workspaces.create_workspace(inaccessible_scope, %{name: "Private voice"})

      {:ok, inaccessible_voice_channel} =
        Workspaces.create_voice_channel(inaccessible_scope, other_workspace.id, %{name: "private"})

      for topic <- [
            "voice:not-a-uuid",
            "voice:00000000-0000-0000-0000-000000000000",
            "voice:#{inaccessible_voice_channel.id}"
          ] do
        assert {:error, %{reason: "not_found"}} = subscribe_and_join(socket, VoiceChannel, topic)
      end
    end

    test "unexpected topic close ends its Channel-bound signaling session", %{
      socket: socket,
      token: token,
      voice_channel: voice_channel
    } do
      topic = "voice:#{voice_channel.id}"

      assert {:ok, %{signaling_session_id: first_id}, first_socket} =
               subscribe_and_join(socket, VoiceChannel, topic)

      Process.unlink(first_socket.channel_pid)
      monitor_ref = Process.monitor(first_socket.channel_pid)
      :ok = close(first_socket)
      assert_receive {:DOWN, ^monitor_ref, :process, _, _}

      assert {:ok, reconnected_socket} =
               connect(VoiceSocket, %{}, connect_info: %{session: %{"user_token" => token}})

      assert {:ok, %{signaling_session_id: second_id}, _second_socket} =
               subscribe_and_join(reconnected_socket, VoiceChannel, topic)

      refute first_id == second_id
    end
  end

  describe "fake offer signaling" do
    setup do
      owner = user_fixture()
      scope = DiscordClone.Accounts.Scope.for_user(owner)
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Fake offer signaling"})

      {:ok, voice_channel} =
        Workspaces.create_voice_channel(scope, workspace.id, %{name: "lobby"})

      {:ok, other_voice_channel} =
        Workspaces.create_voice_channel(scope, workspace.id, %{name: "breakout"})

      token = Accounts.generate_user_session_token(owner)

      {:ok, socket} =
        connect(VoiceSocket, %{}, connect_info: %{session: %{"user_token" => token}})

      {:ok, %{signaling_session_id: signaling_session_id}, channel_socket} =
        subscribe_and_join(socket, VoiceChannel, "voice:#{voice_channel.id}")

      %{
        channel_socket: channel_socket,
        other_voice_channel: other_voice_channel,
        signaling_session_id: signaling_session_id
      }
    end

    test "returns a correlated fake answer for a valid fake offer", %{
      channel_socket: channel_socket,
      signaling_session_id: signaling_session_id
    } do
      offer = %{
        "signaling_session_id" => signaling_session_id,
        "label" => "fake-offer",
        "sequence" => 7
      }

      ref = push(channel_socket, "offer", offer)

      assert_reply ref, :ok, %{
        signaling_session_id: ^signaling_session_id,
        label: "fake-answer",
        sequence: 7
      }
    end

    test "returns field-level errors for malformed fake offer fields", %{
      channel_socket: channel_socket,
      signaling_session_id: signaling_session_id
    } do
      assert_reply push(channel_socket, "offer", %{"signaling_session_id" => signaling_session_id}),
                   :error,
                   %{errors: %{"label" => "is required"}}

      assert_reply(
        push(channel_socket, "offer", %{
          "signaling_session_id" => signaling_session_id,
          "label" => String.duplicate("a", 257),
          "sequence" => 1
        }),
        :error,
        %{errors: %{"label" => "must be at most 256 characters"}}
      )

      assert_reply(
        push(channel_socket, "offer", %{
          "signaling_session_id" => signaling_session_id,
          "label" => 1,
          "sequence" => 1
        }),
        :error,
        %{errors: %{"label" => "must be a string"}}
      )

      assert_reply(
        push(channel_socket, "offer", %{
          "signaling_session_id" => signaling_session_id,
          "label" => "fake-offer",
          "sequence" => "one"
        }),
        :error,
        %{errors: %{"sequence" => "must be a non-negative integer"}}
      )

      assert_reply(
        push(channel_socket, "offer", %{
          "signaling_session_id" => signaling_session_id,
          "label" => "fake-offer",
          "sequence" => 1,
          "unexpected" => "field"
        }),
        :error,
        %{errors: %{"payload" => "contains unsupported fields"}}
      )

      assert_reply(
        push(channel_socket, "offer", %{
          "signaling_session_id" => signaling_session_id,
          "label" => String.duplicate("a", 4_096),
          "sequence" => 1
        }),
        :error,
        %{errors: %{"payload" => "must be at most 4096 bytes"}}
      )
    end

    test "rejects missing, mismatched, stale, and cross-topic signaling session IDs safely", %{
      channel_socket: channel_socket,
      other_voice_channel: other_voice_channel,
      signaling_session_id: first_id
    } do
      offer = %{"label" => "fake-offer", "sequence" => 1}

      for signaling_session_id <- [nil, "mismatched-signaling-session"] do
        assert_reply(
          push(
            channel_socket,
            "offer",
            Map.put(offer, "signaling_session_id", signaling_session_id)
          ),
          :error,
          %{reason: "invalid_request"}
        )
      end

      assert {:ok, %{signaling_session_id: other_id}, other_channel_socket} =
               subscribe_and_join(
                 channel_socket,
                 VoiceChannel,
                 "voice:#{other_voice_channel.id}"
               )

      refute first_id == other_id

      assert_reply(
        push(other_channel_socket, "offer", Map.put(offer, "signaling_session_id", first_id)),
        :error,
        %{reason: "invalid_request"}
      )

      Process.unlink(channel_socket.channel_pid)
      assert_reply leave(channel_socket), :ok

      assert {:ok, %{signaling_session_id: rejoined_id}, rejoined_channel_socket} =
               subscribe_and_join(channel_socket, VoiceChannel, channel_socket.topic)

      refute first_id == rejoined_id

      assert_reply(
        push(rejoined_channel_socket, "offer", Map.put(offer, "signaling_session_id", first_id)),
        :error,
        %{reason: "invalid_request"}
      )
    end

    test "does not push offer or answer traffic to another topic subscriber", %{
      channel_socket: channel_socket,
      signaling_session_id: signaling_session_id
    } do
      assert {:ok, _reply, _other_channel_socket} =
               subscribe_and_join(channel_socket, VoiceChannel, channel_socket.topic)

      assert_reply(
        push(channel_socket, "offer", %{
          "signaling_session_id" => signaling_session_id,
          "label" => "fake-offer",
          "sequence" => 1
        }),
        :ok
      )

      refute_push "offer", _payload
      refute_push "answer", _payload
      refute_push "error", _payload
    end
  end

  describe "fake ICE and heartbeat signaling" do
    setup do
      owner = user_fixture()
      scope = DiscordClone.Accounts.Scope.for_user(owner)
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Fake ICE signaling"})

      {:ok, voice_channel} =
        Workspaces.create_voice_channel(scope, workspace.id, %{name: "lobby"})

      {:ok, other_voice_channel} =
        Workspaces.create_voice_channel(scope, workspace.id, %{name: "breakout"})

      token = Accounts.generate_user_session_token(owner)

      {:ok, socket} =
        connect(VoiceSocket, %{}, connect_info: %{session: %{"user_token" => token}})

      {:ok, %{signaling_session_id: signaling_session_id}, channel_socket} =
        subscribe_and_join(socket, VoiceChannel, "voice:#{voice_channel.id}")

      %{
        channel_socket: channel_socket,
        other_voice_channel: other_voice_channel,
        signaling_session_id: signaling_session_id,
        token: token
      }
    end

    test "acknowledges fake client ICE and pushes one fake server ICE only to its caller", %{
      channel_socket: channel_socket,
      signaling_session_id: signaling_session_id
    } do
      assert {:ok, _reply, _other_channel_socket} =
               subscribe_and_join(channel_socket, VoiceChannel, channel_socket.topic)

      ref =
        push(channel_socket, "ice_candidate", %{
          "signaling_session_id" => signaling_session_id,
          "label" => "fake-client-ice",
          "sequence" => 3
        })

      assert_reply ref, :ok, %{
        signaling_session_id: ^signaling_session_id,
        label: "fake-client-ice-ack",
        sequence: 3
      }

      assert_push "ice_candidate", %{
        signaling_session_id: ^signaling_session_id,
        label: "fake-server-ice",
        sequence: 3
      }

      refute_push "ice_candidate", _payload
      refute_push "error", _payload
    end

    test "returns field-level errors for malformed fake ICE and heartbeat fields", %{
      channel_socket: channel_socket,
      signaling_session_id: signaling_session_id
    } do
      for event <- ["ice_candidate", "heartbeat"] do
        assert_reply push(channel_socket, event, %{"signaling_session_id" => signaling_session_id}),
                     :error,
                     %{errors: %{"label" => "is required"}}

        assert_reply(
          push(channel_socket, event, %{
            "signaling_session_id" => signaling_session_id,
            "label" => String.duplicate("a", 257),
            "sequence" => 1
          }),
          :error,
          %{errors: %{"label" => "must be at most 256 characters"}}
        )

        assert_reply(
          push(channel_socket, event, %{
            "signaling_session_id" => signaling_session_id,
            "label" => 1,
            "sequence" => 1
          }),
          :error,
          %{errors: %{"label" => "must be a string"}}
        )

        assert_reply(
          push(channel_socket, event, %{
            "signaling_session_id" => signaling_session_id,
            "label" => "fake-value",
            "sequence" => "one"
          }),
          :error,
          %{errors: %{"sequence" => "must be a non-negative integer"}}
        )

        assert_reply(
          push(channel_socket, event, %{
            "signaling_session_id" => signaling_session_id,
            "label" => "fake-value",
            "sequence" => 1,
            "unexpected" => "field"
          }),
          :error,
          %{errors: %{"payload" => "contains unsupported fields"}}
        )

        assert_reply(
          push(channel_socket, event, %{
            "signaling_session_id" => signaling_session_id,
            "label" => String.duplicate("a", 4_096),
            "sequence" => 1
          }),
          :error,
          %{errors: %{"payload" => "must be at most 4096 bytes"}}
        )
      end
    end

    test "rejects missing, mismatched, stale, and cross-topic IDs safely for fake ICE and heartbeat",
         %{
           channel_socket: channel_socket,
           other_voice_channel: other_voice_channel,
           signaling_session_id: first_id
         } do
      payload = %{"label" => "fake-value", "sequence" => 1}

      for event <- ["ice_candidate", "heartbeat"],
          signaling_session_id <- [nil, "mismatched-id"] do
        assert_reply(
          push(
            channel_socket,
            event,
            Map.put(payload, "signaling_session_id", signaling_session_id)
          ),
          :error,
          %{reason: "invalid_request"}
        )
      end

      assert {:ok, %{signaling_session_id: other_id}, other_channel_socket} =
               subscribe_and_join(channel_socket, VoiceChannel, "voice:#{other_voice_channel.id}")

      refute first_id == other_id

      for event <- ["ice_candidate", "heartbeat"] do
        assert_reply(
          push(other_channel_socket, event, Map.put(payload, "signaling_session_id", first_id)),
          :error,
          %{reason: "invalid_request"}
        )
      end

      Process.flag(:trap_exit, true)
      assert_reply leave(channel_socket), :ok
      assert_receive {:EXIT, _, {:shutdown, :left}}

      assert {:ok, %{signaling_session_id: rejoined_id}, rejoined_channel_socket} =
               subscribe_and_join(channel_socket, VoiceChannel, channel_socket.topic)

      refute first_id == rejoined_id

      for event <- ["ice_candidate", "heartbeat"] do
        assert_reply(
          push(
            rejoined_channel_socket,
            event,
            Map.put(payload, "signaling_session_id", first_id)
          ),
          :error,
          %{reason: "invalid_request"}
        )
      end
    end

    test "acknowledges a heartbeat without pushing a server event", %{
      channel_socket: channel_socket,
      signaling_session_id: signaling_session_id
    } do
      ref =
        push(channel_socket, "heartbeat", %{
          "signaling_session_id" => signaling_session_id,
          "label" => "fake-heartbeat",
          "sequence" => 4
        })

      assert_reply ref, :ok, %{
        signaling_session_id: ^signaling_session_id,
        label: "fake-heartbeat-ack",
        sequence: 4
      }

      refute_push "heartbeat", _payload
      refute_push "ice_candidate", _payload
    end

    test "rejects the prior ID for fake ICE and heartbeat after an unexpected topic close", %{
      channel_socket: channel_socket,
      signaling_session_id: first_id,
      token: token
    } do
      Process.flag(:trap_exit, true)
      :ok = close(channel_socket)
      assert_receive {:EXIT, _, {:shutdown, :closed}}

      assert {:ok, reconnected_socket} =
               connect(VoiceSocket, %{}, connect_info: %{session: %{"user_token" => token}})

      assert {:ok, %{signaling_session_id: second_id}, rejoined_channel_socket} =
               subscribe_and_join(reconnected_socket, VoiceChannel, channel_socket.topic)

      refute first_id == second_id

      for event <- ["ice_candidate", "heartbeat"] do
        assert_reply(
          push(rejoined_channel_socket, event, %{
            "signaling_session_id" => first_id,
            "label" => "fake-value",
            "sequence" => 1
          }),
          :error,
          %{reason: "invalid_request"}
        )
      end
    end
  end
end
