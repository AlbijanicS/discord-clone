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

      %{socket: socket, voice_channel: voice_channel}
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
  end
end
