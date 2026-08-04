defmodule DiscordClone.WorkspacesVoiceLifecycleTest do
  use DiscordClone.DataCase, async: false

  alias DiscordClone.Voice
  alias DiscordClone.Workspaces
  alias DiscordClone.Workspaces.{VoiceChannel, WorkspaceMembership}

  import DiscordClone.AccountsFixtures

  describe "durable access revocation" do
    test "kicking a connected member ends only that member's Voice Session" do
      owner_scope = user_scope_fixture()
      kicked_scope = user_scope_fixture()
      retained_scope = user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Voice Access"})
      add_workspace_member!(workspace, kicked_scope)
      add_workspace_member!(workspace, retained_scope)

      {:ok, voice_channel} =
        Workspaces.create_voice_channel(owner_scope, workspace.id, %{name: "lobby"})

      on_exit(fn -> cleanup_room(voice_channel.id) end)

      assert {:ok, %{occupancy: 1}} =
               Voice.join(voice_channel.id, kicked_scope.user.id, "kicked-connection", self())

      assert {:ok, %{occupancy: 2}} =
               Voice.join(voice_channel.id, retained_scope.user.id, "retained-connection", self())

      assert {:ok, _membership} =
               Workspaces.kick_member(owner_scope, workspace.id, kicked_scope.user.id, %{
                 "reason" => "Access removed"
               })

      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(voice_channel.id)

      assert {:ok, %{occupancy: 2, capacity: 5}} =
               Voice.join(voice_channel.id, kicked_scope.user.id, "reconnected", self())
    end

    test "banning a connected member ends only that member's Voice Session" do
      owner_scope = user_scope_fixture()
      banned_scope = user_scope_fixture()
      retained_scope = user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Voice Ban"})
      add_workspace_member!(workspace, banned_scope)
      add_workspace_member!(workspace, retained_scope)

      {:ok, voice_channel} =
        Workspaces.create_voice_channel(owner_scope, workspace.id, %{name: "lobby"})

      on_exit(fn -> cleanup_room(voice_channel.id) end)

      assert {:ok, %{occupancy: 1}} =
               Voice.join(voice_channel.id, banned_scope.user.id, "banned-connection", self())

      assert {:ok, %{occupancy: 2}} =
               Voice.join(voice_channel.id, retained_scope.user.id, "retained-connection", self())

      assert {:ok, _ban} =
               Workspaces.ban_member(owner_scope, workspace.id, banned_scope.user.id, %{
                 "reason" => "Access removed"
               })

      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(voice_channel.id)

      assert {:ok, %{occupancy: 2, capacity: 5}} =
               Voice.join(voice_channel.id, banned_scope.user.id, "reconnected", self())
    end

    test "a member leaving a workspace ends that member's Voice Session" do
      owner_scope = user_scope_fixture()
      leaving_scope = user_scope_fixture()
      retained_scope = user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Voice Leave"})
      add_workspace_member!(workspace, leaving_scope)
      add_workspace_member!(workspace, retained_scope)

      {:ok, voice_channel} =
        Workspaces.create_voice_channel(owner_scope, workspace.id, %{name: "lobby"})

      on_exit(fn -> cleanup_room(voice_channel.id) end)

      assert {:ok, %{occupancy: 1}} =
               Voice.join(voice_channel.id, leaving_scope.user.id, "leaving-connection", self())

      assert {:ok, %{occupancy: 2}} =
               Voice.join(voice_channel.id, retained_scope.user.id, "retained-connection", self())

      assert {:ok, _membership} = Workspaces.leave_workspace(leaving_scope, workspace.id)

      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(voice_channel.id)

      assert {:ok, %{occupancy: 2, capacity: 5}} =
               Voice.join(voice_channel.id, leaving_scope.user.id, "reconnected", self())
    end

    test "failed kick and ban validation preserve a connected member's Voice Session" do
      owner_scope = user_scope_fixture()
      member_scope = user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Voice Validation"})
      add_workspace_member!(workspace, member_scope)

      {:ok, voice_channel} =
        Workspaces.create_voice_channel(owner_scope, workspace.id, %{name: "lobby"})

      on_exit(fn -> cleanup_room(voice_channel.id) end)

      assert {:ok, %{occupancy: 1}} =
               Voice.join(voice_channel.id, member_scope.user.id, "member-connection", self())

      assert {:error, :reason_required} =
               Workspaces.kick_member(owner_scope, workspace.id, member_scope.user.id, %{})

      assert {:error, :reason_required} =
               Workspaces.ban_member(owner_scope, workspace.id, member_scope.user.id, %{})

      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(voice_channel.id)
    end
  end

  describe "durable Voice Channel deletion" do
    test "ends every session in the deleted channel and preserves an unrelated room" do
      owner_scope = user_scope_fixture()
      first_user_scope = user_scope_fixture()
      second_user_scope = user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Voice Deletion"})

      {:ok, ended_voice_channel} =
        Workspaces.create_voice_channel(owner_scope, workspace.id, %{name: "ended"})

      {:ok, unrelated_voice_channel} =
        Workspaces.create_voice_channel(owner_scope, workspace.id, %{name: "unrelated"})

      on_exit(fn ->
        cleanup_room(ended_voice_channel.id)
        cleanup_room(unrelated_voice_channel.id)
      end)

      assert {:ok, %{occupancy: 1}} =
               Voice.join(
                 ended_voice_channel.id,
                 first_user_scope.user.id,
                 "ended-connection-1",
                 self()
               )

      assert {:ok, %{occupancy: 2}} =
               Voice.join(
                 ended_voice_channel.id,
                 second_user_scope.user.id,
                 "ended-connection-2",
                 self()
               )

      assert {:ok, %{occupancy: 1}} =
               Voice.join(
                 unrelated_voice_channel.id,
                 owner_scope.user.id,
                 "unrelated-connection",
                 self()
               )

      assert {:ok, deleted_voice_channel} =
               Workspaces.delete_voice_channel(owner_scope, workspace.id, ended_voice_channel.id)

      assert deleted_voice_channel.id == ended_voice_channel.id
      refute Repo.get(VoiceChannel, ended_voice_channel.id)
      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(ended_voice_channel.id)

      assert {:ok, %{occupancy: 1, capacity: 5}} =
               Voice.room_occupancy(unrelated_voice_channel.id)

      assert Voice.room_running?(ended_voice_channel.id)

      assert :ok = Voice.expire_idle_room(ended_voice_channel.id)
      refute Voice.room_running?(ended_voice_channel.id)
    end

    test "deleting a workspace ends sessions in Voice Channels removed by cascade" do
      owner_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Voice Cascade"})

      {:ok, voice_channel} =
        Workspaces.create_voice_channel(owner_scope, workspace.id, %{name: "cascade"})

      on_exit(fn -> cleanup_room(voice_channel.id) end)

      assert {:ok, %{occupancy: 1}} =
               Voice.join(voice_channel.id, owner_scope.user.id, "cascade-connection", self())

      assert {:ok, deleted_workspace} = Workspaces.delete_workspace(owner_scope, workspace.id)

      assert deleted_workspace.id == workspace.id
      refute Repo.get(VoiceChannel, voice_channel.id)
      assert {:ok, %{occupancy: 0, capacity: 5}} = Voice.room_occupancy(voice_channel.id)

      assert :ok = Voice.expire_idle_room(voice_channel.id)
      refute Voice.room_running?(voice_channel.id)
    end

    test "unauthorized Voice Channel deletion preserves its active sessions" do
      owner_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Voice Delete Auth"})
      add_workspace_member!(workspace, member_scope)

      {:ok, voice_channel} =
        Workspaces.create_voice_channel(owner_scope, workspace.id, %{name: "lobby"})

      on_exit(fn -> cleanup_room(voice_channel.id) end)

      assert {:ok, %{occupancy: 1}} =
               Voice.join(voice_channel.id, member_scope.user.id, "member-connection", self())

      assert {:error, :unauthorized} =
               Workspaces.delete_voice_channel(member_scope, workspace.id, voice_channel.id)

      assert {:ok, %{occupancy: 1, capacity: 5}} = Voice.room_occupancy(voice_channel.id)
    end
  end

  defp add_workspace_member!(workspace, scope, role \\ "member") do
    %WorkspaceMembership{}
    |> WorkspaceMembership.changeset(%{
      workspace_id: workspace.id,
      user_id: scope.user.id,
      role: role
    })
    |> Repo.insert!()
  end

  defp cleanup_room(voice_channel_id) do
    _ = Voice.end_channel_sessions(voice_channel_id)
    _ = Voice.expire_idle_room(voice_channel_id)
  end
end
