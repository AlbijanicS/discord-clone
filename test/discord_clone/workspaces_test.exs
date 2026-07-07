defmodule DiscordClone.WorkspacesTest do
  use DiscordClone.DataCase

  alias DiscordClone.Chat.{
    ChannelRead,
    ChannelReadState,
    ChannelUnreadSpan,
    Message,
    WorkspaceServer
  }

  alias DiscordClone.Workspaces

  alias DiscordClone.Workspaces.{
    Channel,
    WorkspaceAuditEvent,
    WorkspaceInvite,
    WorkspaceMembership
  }

  import DiscordClone.AccountsFixtures
  import DiscordClone.WorkspacesFixtures

  describe "create_workspace/2" do
    test "creates a workspace with owner membership and a default general channel" do
      scope = user_scope_fixture()

      assert {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})

      assert workspace.name == "My Server"
      assert workspace.owner_id == scope.user.id
      assert workspace.invite_policy == "owner_only"

      assert %Channel{name: "general", id: default_channel_id} =
               Repo.get_by(Channel, workspace_id: workspace.id)

      assert workspace.default_channel_id == default_channel_id

      assert %WorkspaceMembership{role: "owner"} =
               Repo.get_by(WorkspaceMembership,
                 workspace_id: workspace.id,
                 user_id: scope.user.id
               )
    end

    test "initializes the owner read row for the default general channel" do
      scope = user_scope_fixture()

      assert {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})

      assert %ChannelRead{last_read_message_id: nil} =
               Repo.get_by(ChannelRead,
                 channel_id: workspace.default_channel_id,
                 user_id: scope.user.id
               )
    end

    test "initializes the owner read state for the default general channel" do
      scope = user_scope_fixture()

      assert {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})

      assert %ChannelReadState{
               unread_count: 0,
               first_unread_seq: nil,
               last_unread_seq: nil
             } =
               Repo.get_by(ChannelReadState,
                 channel_id: workspace.default_channel_id,
                 user_id: scope.user.id
               )
    end

    test "uses the authenticated user and owner-only invite policy" do
      scope = user_scope_fixture()
      other_user = user_fixture()

      assert {:ok, workspace} =
               Workspaces.create_workspace(scope, %{
                 "name" => "Spoof Proof",
                 "owner_id" => other_user.id,
                 "invite_policy" => "members_can_invite"
               })

      assert workspace.owner_id == scope.user.id
      assert workspace.invite_policy == "owner_only"
    end

    test "uses general as the default channel name instead of caller-provided channel input" do
      scope = user_scope_fixture()

      assert {:ok, workspace} =
               Workspaces.create_workspace(scope, %{
                 name: "Channels Later",
                 main_channel_name: "lobby"
               })

      assert %Channel{name: "general", id: default_channel_id} =
               Repo.get_by(Channel, workspace_id: workspace.id)

      assert workspace.default_channel_id == default_channel_id
    end

    test "allows duplicate workspace names" do
      first_scope = user_scope_fixture()
      second_scope = user_scope_fixture()

      assert {:ok, first_workspace} =
               Workspaces.create_workspace(first_scope, %{name: "Same Name"})

      assert {:ok, second_workspace} =
               Workspaces.create_workspace(second_scope, %{name: "Same Name"})

      assert first_workspace.name == second_workspace.name
      assert first_workspace.id != second_workspace.id
    end

    test "allows duplicate workspace names for the same user" do
      scope = user_scope_fixture()

      assert {:ok, first_workspace} =
               Workspaces.create_workspace(scope, %{name: "Same Name"})

      assert {:ok, second_workspace} =
               Workspaces.create_workspace(scope, %{name: "Same Name"})

      assert first_workspace.name == second_workspace.name
      assert first_workspace.owner_id == second_workspace.owner_id
      assert first_workspace.id != second_workspace.id
    end

    test "rejects unauthenticated scopes" do
      assert Workspaces.create_workspace(nil, %{name: "Nope"}) == {:error, :unauthenticated}

      assert Workspaces.create_workspace(%DiscordClone.Accounts.Scope{}, %{name: "Nope"}) ==
               {:error, :unauthenticated}
    end

    test "returns an invalid workspace changeset for invalid input" do
      scope = user_scope_fixture()

      assert {:error, :invalid_workspace, changeset} =
               Workspaces.create_workspace(scope, %{name: ""})

      assert errors_on(changeset).name == ["can't be blank"]
    end

    test "rejects invalid workspace attrs from authenticated scopes" do
      scope = user_scope_fixture()

      assert Workspaces.create_workspace(scope, "bad attrs") == {:error, :invalid_attrs}
    end
  end

  describe "workspace_fixture/1" do
    test "creates a workspace through the public context" do
      workspace = workspace_fixture(%{name: "Fixture Server"})

      assert workspace.name == "Fixture Server"
      assert workspace.default_channel_id
      assert Repo.get_by(WorkspaceMembership, workspace_id: workspace.id, role: "owner")
    end
  end

  describe "workspace membership roles" do
    test "accepts owner, admin, and member roles" do
      owner_scope = user_scope_fixture()
      admin_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Role Workspace"})

      assert add_workspace_member!(workspace, admin_scope, "admin").role == "admin"
      assert add_workspace_member!(workspace, member_scope, "member").role == "member"
      assert Repo.get_by!(WorkspaceMembership, workspace_id: workspace.id, role: "owner")
    end
  end

  describe "role capabilities" do
    test "exposes workspace, channel, and invite capabilities by workspace role" do
      owner_scope = user_scope_fixture()
      admin_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Role Workspace"})
      add_workspace_member!(workspace, admin_scope, "admin")
      add_workspace_member!(workspace, member_scope, "member")

      assert Workspaces.can_rename_workspace?(owner_scope, workspace)
      assert Workspaces.can_delete_workspace?(owner_scope, workspace)
      assert Workspaces.can_create_channel?(owner_scope, workspace)
      assert Workspaces.can_rename_channel?(owner_scope, workspace)
      assert Workspaces.can_delete_channel?(owner_scope, workspace)
      assert Workspaces.can_create_workspace_invite?(owner_scope, workspace)

      refute Workspaces.can_rename_workspace?(admin_scope, workspace)
      refute Workspaces.can_delete_workspace?(admin_scope, workspace)
      assert Workspaces.can_create_channel?(admin_scope, workspace)
      assert Workspaces.can_rename_channel?(admin_scope, workspace)
      refute Workspaces.can_delete_channel?(admin_scope, workspace)
      assert Workspaces.can_create_workspace_invite?(admin_scope, workspace)

      refute Workspaces.can_rename_workspace?(member_scope, workspace)
      refute Workspaces.can_delete_workspace?(member_scope, workspace)
      refute Workspaces.can_create_channel?(member_scope, workspace)
      refute Workspaces.can_rename_channel?(member_scope, workspace)
      refute Workspaces.can_delete_channel?(member_scope, workspace)
      refute Workspaces.can_create_workspace_invite?(member_scope, workspace)
    end

    test "derives member action availability by actor and target role" do
      owner_scope = user_scope_fixture()
      admin_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Role Workspace"})
      add_workspace_member!(workspace, admin_scope, "admin")
      add_workspace_member!(workspace, member_scope, "member")

      owner_membership =
        Repo.get_by!(WorkspaceMembership,
          workspace_id: workspace.id,
          user_id: owner_scope.user.id
        )

      admin_membership =
        Repo.get_by!(WorkspaceMembership,
          workspace_id: workspace.id,
          user_id: admin_scope.user.id
        )

      member_membership =
        Repo.get_by!(WorkspaceMembership,
          workspace_id: workspace.id,
          user_id: member_scope.user.id
        )

      assert Workspaces.available_member_actions(owner_scope, workspace, admin_membership) == [
               :demote_to_member,
               :mute,
               :timeout,
               :kick,
               :ban
             ]

      assert Workspaces.available_member_actions(owner_scope, workspace, member_membership) == [
               :promote_to_admin,
               :mute,
               :timeout,
               :kick,
               :ban
             ]

      assert Workspaces.available_member_actions(admin_scope, workspace, owner_membership) == []

      assert Workspaces.available_member_actions(admin_scope, workspace, admin_membership) == [
               :mute,
               :timeout
             ]

      assert Workspaces.available_member_actions(admin_scope, workspace, member_membership) == [
               :mute,
               :timeout,
               :kick,
               :ban
             ]

      assert Workspaces.available_member_actions(member_scope, workspace, owner_membership) == []
      assert Workspaces.available_member_actions(nil, workspace, member_membership) == []
    end
  end

  describe "change_member_role/4" do
    test "allows owners to promote members to admins" do
      owner_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Role Workspace"})
      add_workspace_member!(workspace, member_scope, "member")

      assert {:ok, membership} =
               Workspaces.change_member_role(
                 owner_scope,
                 workspace.id,
                 member_scope.user.id,
                 "admin"
               )

      assert membership.role == "admin"

      assert %WorkspaceMembership{role: "admin"} =
               Repo.get_by(WorkspaceMembership,
                 workspace_id: workspace.id,
                 user_id: member_scope.user.id
               )
    end

    test "allows owners to demote admins to members" do
      owner_scope = user_scope_fixture()
      admin_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Role Workspace"})
      add_workspace_member!(workspace, admin_scope, "admin")

      assert {:ok, membership} =
               Workspaces.change_member_role(
                 owner_scope,
                 workspace.id,
                 admin_scope.user.id,
                 "member"
               )

      assert membership.role == "member"

      assert %WorkspaceMembership{role: "member"} =
               Repo.get_by(WorkspaceMembership,
                 workspace_id: workspace.id,
                 user_id: admin_scope.user.id
               )
    end

    test "rejects admin and member role changes" do
      owner_scope = user_scope_fixture()
      admin_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      target_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Role Workspace"})
      add_workspace_member!(workspace, admin_scope, "admin")
      add_workspace_member!(workspace, member_scope, "member")
      add_workspace_member!(workspace, target_scope, "member")

      assert Workspaces.change_member_role(
               admin_scope,
               workspace.id,
               target_scope.user.id,
               "admin"
             ) ==
               {:error, :owner_required}

      assert Workspaces.change_member_role(
               member_scope,
               workspace.id,
               target_scope.user.id,
               "admin"
             ) ==
               {:error, :owner_required}

      assert Repo.get_by!(
               WorkspaceMembership,
               workspace_id: workspace.id,
               user_id: target_scope.user.id
             ).role == "member"
    end

    test "rejects owner role changes" do
      owner_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Role Workspace"})

      assert Workspaces.change_member_role(
               owner_scope,
               workspace.id,
               owner_scope.user.id,
               "member"
             ) ==
               {:error, :owner_role_locked}

      assert Repo.get_by!(
               WorkspaceMembership,
               workspace_id: workspace.id,
               user_id: owner_scope.user.id
             ).role == "owner"
    end

    test "rejects unsupported role transitions" do
      owner_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Role Workspace"})
      add_workspace_member!(workspace, member_scope, "member")

      assert Workspaces.change_member_role(
               owner_scope,
               workspace.id,
               member_scope.user.id,
               "owner"
             ) ==
               {:error, :unsupported_role_transition}

      assert Repo.get_by!(
               WorkspaceMembership,
               workspace_id: workspace.id,
               user_id: member_scope.user.id
             ).role == "member"
    end

    test "role changes append audit events visible newest first to owners" do
      owner_scope = user_scope_fixture()
      admin_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Role Workspace"})
      add_workspace_member!(workspace, admin_scope, "admin")
      add_workspace_member!(workspace, member_scope, "member")

      assert {:ok, _membership} =
               Workspaces.change_member_role(
                 owner_scope,
                 workspace.id,
                 member_scope.user.id,
                 "admin"
               )

      assert {:ok, _membership} =
               Workspaces.change_member_role(
                 owner_scope,
                 workspace.id,
                 admin_scope.user.id,
                 "member"
               )

      assert {:ok, [demotion, promotion]} =
               Workspaces.list_audit_events(owner_scope, workspace.id)

      assert %WorkspaceAuditEvent{} = promotion
      assert promotion.workspace_id == workspace.id
      assert promotion.actor_user_id == owner_scope.user.id
      assert promotion.target_user_id == member_scope.user.id
      assert promotion.event_type == "member_role_promoted"
      assert promotion.reason == nil
      assert promotion.metadata == %{"from_role" => "member", "to_role" => "admin"}

      assert demotion.target_user_id == admin_scope.user.id
      assert demotion.event_type == "member_role_demoted"
      assert demotion.metadata == %{"from_role" => "admin", "to_role" => "member"}
    end

    test "rejects audit event listing for admins and members" do
      owner_scope = user_scope_fixture()
      admin_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Role Workspace"})
      add_workspace_member!(workspace, admin_scope, "admin")
      add_workspace_member!(workspace, member_scope, "member")

      assert Workspaces.list_audit_events(admin_scope, workspace.id) == {:error, :owner_required}
      assert Workspaces.list_audit_events(member_scope, workspace.id) == {:error, :owner_required}
    end
  end

  describe "list_workspaces/1" do
    test "returns only workspaces where the user is a workspace member" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()

      assert {:ok, member_workspace} =
               Workspaces.create_workspace(scope, %{name: "Member Workspace"})

      assert {:ok, _other_workspace} =
               Workspaces.create_workspace(other_scope, %{name: "Other Workspace"})

      assert Workspaces.list_workspaces(scope) == {:ok, [member_workspace]}
    end

    test "orders workspaces by newest membership first" do
      scope = user_scope_fixture()

      assert {:ok, first_workspace} =
               Workspaces.create_workspace(scope, %{name: "First Workspace"})

      assert {:ok, second_workspace} =
               Workspaces.create_workspace(scope, %{name: "Second Workspace"})

      assert Workspaces.list_workspaces(scope) == {:ok, [second_workspace, first_workspace]}
    end

    test "requires an authenticated scope" do
      assert Workspaces.list_workspaces(nil) == {:error, :unauthenticated}

      assert Workspaces.list_workspaces(%DiscordClone.Accounts.Scope{}) ==
               {:error, :unauthenticated}
    end
  end

  describe "fetch_workspace/2" do
    test "returns a workspace where the user is a workspace member" do
      scope = user_scope_fixture()

      assert {:ok, workspace} =
               Workspaces.create_workspace(scope, %{name: "Member Workspace"})

      assert Workspaces.fetch_workspace(scope, workspace.id) == {:ok, workspace}
    end

    test "returns not found for a missing workspace" do
      scope = user_scope_fixture()

      assert Workspaces.fetch_workspace(scope, -1) == {:error, :not_found}
    end

    test "rejects logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()

      assert {:ok, workspace} =
               Workspaces.create_workspace(owner_scope, %{name: "Private Workspace"})

      assert Workspaces.fetch_workspace(non_member_scope, workspace.id) == {:error, :unauthorized}
    end

    test "requires an authenticated scope" do
      assert Workspaces.fetch_workspace(nil, 1) == {:error, :unauthenticated}

      assert Workspaces.fetch_workspace(%DiscordClone.Accounts.Scope{}, 1) ==
               {:error, :unauthenticated}
    end
  end

  describe "list_channels/2" do
    test "returns workspace channels oldest first for a workspace member" do
      scope = user_scope_fixture()

      assert {:ok, workspace} =
               Workspaces.create_workspace(scope, %{name: "Member Workspace"})

      assert {:ok, first_channel} =
               Workspaces.create_channel(scope, workspace.id, %{name: "first"})

      assert {:ok, second_channel} =
               Workspaces.create_channel(scope, workspace.id, %{name: "second"})

      default_channel = Repo.get!(Channel, workspace.default_channel_id)

      assert Workspaces.list_channels(scope, workspace.id) ==
               {:ok, [default_channel, first_channel, second_channel]}
    end

    test "returns not found for a missing workspace" do
      scope = user_scope_fixture()

      assert Workspaces.list_channels(scope, -1) == {:error, :not_found}
    end

    test "rejects logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()

      assert {:ok, workspace} =
               Workspaces.create_workspace(owner_scope, %{name: "Private Workspace"})

      assert Workspaces.list_channels(non_member_scope, workspace.id) == {:error, :unauthorized}
    end

    test "requires an authenticated scope" do
      assert Workspaces.list_channels(nil, 1) == {:error, :unauthenticated}

      assert Workspaces.list_channels(%DiscordClone.Accounts.Scope{}, 1) ==
               {:error, :unauthenticated}
    end
  end

  describe "list_members/2" do
    test "returns workspace members with user display data for a workspace member" do
      owner_scope = user_fixture(%{username: "owner_user"}) |> user_scope_fixture()
      member_scope = user_fixture(%{username: "member_user"}) |> user_scope_fixture()

      assert {:ok, workspace} =
               Workspaces.create_workspace(owner_scope, %{name: "Presence Workspace"})

      add_workspace_member!(workspace, member_scope)

      assert {:ok, members} = Workspaces.list_members(owner_scope, workspace.id)

      assert Enum.map(members, & &1.role) == ["owner", "member"]
      assert Enum.map(members, & &1.user.username) == ["owner_user", "member_user"]
      assert Enum.all?(members, &(&1.workspace_id == workspace.id))
    end

    test "requires an authenticated scope" do
      assert Workspaces.list_members(nil, 1) == {:error, :unauthenticated}

      assert Workspaces.list_members(%DiscordClone.Accounts.Scope{}, 1) ==
               {:error, :unauthenticated}
    end

    test "rejects logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()

      assert {:ok, workspace} =
               Workspaces.create_workspace(owner_scope, %{name: "Private Workspace"})

      assert Workspaces.list_members(non_member_scope, workspace.id) == {:error, :unauthorized}
    end

    test "returns not found for a missing workspace" do
      scope = user_scope_fixture()

      assert Workspaces.list_members(scope, -1) == {:error, :not_found}
    end

    test "allows non-owner workspace members to list members" do
      owner_scope = user_scope_fixture()
      member_scope = user_scope_fixture()

      assert {:ok, workspace} =
               Workspaces.create_workspace(owner_scope, %{name: "Member Visible Workspace"})

      add_workspace_member!(workspace, member_scope)

      assert {:ok, members} = Workspaces.list_members(member_scope, workspace.id)
      assert Enum.map(members, & &1.user_id) == [owner_scope.user.id, member_scope.user.id]
    end
  end

  describe "fetch_channel/3" do
    test "returns a channel in the selected workspace for a workspace member" do
      scope = user_scope_fixture()

      assert {:ok, workspace} =
               Workspaces.create_workspace(scope, %{name: "Member Workspace"})

      assert {:ok, channel} =
               Workspaces.create_channel(scope, workspace.id, %{name: "planning"})

      assert Workspaces.fetch_channel(scope, workspace.id, channel.id) == {:ok, channel}
    end

    test "returns not found when the channel is missing or belongs to another workspace" do
      scope = user_scope_fixture()

      assert {:ok, selected_workspace} =
               Workspaces.create_workspace(scope, %{name: "Selected Workspace"})

      assert {:ok, other_workspace} =
               Workspaces.create_workspace(scope, %{name: "Other Workspace"})

      assert {:ok, other_channel} =
               Workspaces.create_channel(scope, other_workspace.id, %{name: "planning"})

      assert Workspaces.fetch_channel(scope, selected_workspace.id, -1) == {:error, :not_found}

      assert Workspaces.fetch_channel(scope, selected_workspace.id, other_channel.id) ==
               {:error, :not_found}
    end

    test "rejects logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()

      assert {:ok, workspace} =
               Workspaces.create_workspace(owner_scope, %{name: "Private Workspace"})

      assert {:ok, channel} =
               Workspaces.create_channel(owner_scope, workspace.id, %{name: "planning"})

      assert Workspaces.fetch_channel(non_member_scope, workspace.id, channel.id) ==
               {:error, :unauthorized}
    end

    test "requires an authenticated scope" do
      assert Workspaces.fetch_channel(nil, 1, 1) == {:error, :unauthenticated}

      assert Workspaces.fetch_channel(%DiscordClone.Accounts.Scope{}, 1, 1) ==
               {:error, :unauthenticated}
    end
  end

  describe "resolve_landing_channel/2" do
    test "returns the workspace default channel for a workspace member" do
      scope = user_scope_fixture()

      assert {:ok, workspace} =
               Workspaces.create_workspace(scope, %{name: "Workspace"})

      default_channel = Repo.get!(Channel, workspace.default_channel_id)

      assert Workspaces.resolve_landing_channel(scope, workspace.id) == {:ok, default_channel}
    end

    test "returns an explicit error when the default channel is missing" do
      scope = user_scope_fixture()

      assert {:ok, workspace} =
               Workspaces.create_workspace(scope, %{name: "Workspace"})

      assert {:ok, _channel} =
               Workspaces.create_channel(scope, workspace.id, %{name: "oldest"})

      assert {:ok, _newest_channel} =
               Workspaces.create_channel(scope, workspace.id, %{name: "newest"})

      workspace
      |> Ecto.Changeset.change(default_channel_id: nil)
      |> Repo.update!()

      assert Workspaces.resolve_landing_channel(scope, workspace.id) ==
               {:error, :landing_channel_not_found}
    end

    test "returns an explicit error when no landing channel can be resolved" do
      scope = user_scope_fixture()

      assert {:ok, workspace} =
               Workspaces.create_workspace(scope, %{name: "Workspace"})

      Repo.delete_all(from channel in Channel, where: channel.workspace_id == ^workspace.id)

      assert Workspaces.resolve_landing_channel(scope, workspace.id) ==
               {:error, :landing_channel_not_found}
    end

    test "returns not found for a missing workspace" do
      scope = user_scope_fixture()

      assert Workspaces.resolve_landing_channel(scope, -1) == {:error, :not_found}
    end

    test "rejects logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()

      assert {:ok, workspace} =
               Workspaces.create_workspace(owner_scope, %{name: "Private Workspace"})

      assert Workspaces.resolve_landing_channel(non_member_scope, workspace.id) ==
               {:error, :unauthorized}
    end

    test "requires an authenticated scope" do
      assert Workspaces.resolve_landing_channel(nil, 1) == {:error, :unauthenticated}

      assert Workspaces.resolve_landing_channel(%DiscordClone.Accounts.Scope{}, 1) ==
               {:error, :unauthenticated}
    end
  end

  describe "create_channel/3" do
    test "allows the workspace owner to create a channel" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})

      assert {:ok, channel} =
               Workspaces.create_channel(scope, workspace.id, %{name: "General Chat"})

      assert channel.workspace_id == workspace.id
      assert channel.name == "general-chat"
    end

    test "allows admins but rejects members creating channels" do
      owner_scope = user_scope_fixture()
      admin_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "My Server"})
      add_workspace_member!(workspace, admin_scope, "admin")
      add_workspace_member!(workspace, member_scope, "member")

      assert {:ok, channel} =
               Workspaces.create_channel(admin_scope, workspace.id, %{name: "Admin Planning"})

      assert channel.name == "admin-planning"

      assert Workspaces.create_channel(member_scope, workspace.id, %{name: "Member Planning"}) ==
               {:error, :unauthorized}
    end

    test "initializes empty read rows for all current workspace members" do
      owner_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "My Server"})
      add_workspace_member!(workspace, member_scope)

      assert {:ok, channel} =
               Workspaces.create_channel(owner_scope, workspace.id, %{name: "planning"})

      assert %ChannelRead{last_read_message_id: nil} =
               Repo.get_by(ChannelRead,
                 channel_id: channel.id,
                 user_id: owner_scope.user.id
               )

      assert %ChannelRead{last_read_message_id: nil} =
               Repo.get_by(ChannelRead,
                 channel_id: channel.id,
                 user_id: member_scope.user.id
               )

      assert %ChannelReadState{unread_count: 0} =
               Repo.get_by(ChannelReadState,
                 channel_id: channel.id,
                 user_id: owner_scope.user.id
               )

      assert %ChannelReadState{unread_count: 0} =
               Repo.get_by(ChannelReadState,
                 channel_id: channel.id,
                 user_id: member_scope.user.id
               )
    end

    test "starts empty channels with no message sequence progress" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})

      assert Repo.get!(Channel, workspace.default_channel_id).last_message_seq == 0

      assert {:ok, channel} =
               Workspaces.create_channel(scope, workspace.id, %{name: "planning"})

      assert channel.last_message_seq == 0
      assert Repo.get!(Channel, channel.id).last_message_seq == 0
    end

    test "accepts string-keyed channel attributes" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})

      assert {:ok, channel} =
               Workspaces.create_channel(scope, workspace.id, %{"name" => "General Chat"})

      assert channel.name == "general-chat"
    end

    test "returns not found for a missing workspace" do
      scope = user_scope_fixture()

      assert Workspaces.create_channel(scope, -1, %{name: "general"}) == {:error, :not_found}
    end

    test "rejects logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Private Server"})

      assert Workspaces.create_channel(non_member_scope, workspace.id, %{name: "general"}) ==
               {:error, :unauthorized}
    end

    test "returns an invalid channel changeset for invalid input" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})

      assert {:error, :invalid_channel, changeset} =
               Workspaces.create_channel(scope, workspace.id, %{name: ""})

      assert errors_on(changeset).name == ["can't be blank"]
    end

    test "rejects unauthenticated scopes" do
      assert Workspaces.create_channel(nil, 1, %{name: "general"}) == {:error, :unauthenticated}

      assert Workspaces.create_channel(%DiscordClone.Accounts.Scope{}, 1, %{name: "general"}) ==
               {:error, :unauthenticated}
    end

    test "rejects invalid channel attrs from authenticated scopes" do
      scope = user_scope_fixture()

      assert Workspaces.create_channel(scope, 1, "bad attrs") == {:error, :invalid_attrs}
    end

    test "uses the explicit workspace identifier instead of spoofed attrs" do
      scope = user_scope_fixture()
      {:ok, selected_workspace} = Workspaces.create_workspace(scope, %{name: "Selected"})
      {:ok, spoofed_workspace} = Workspaces.create_workspace(scope, %{name: "Spoofed"})

      assert {:ok, channel} =
               Workspaces.create_channel(scope, selected_workspace.id, %{
                 name: "planning",
                 workspace_id: spoofed_workspace.id
               })

      assert channel.workspace_id == selected_workspace.id
    end

    test "rejects duplicate normalized names inside the same workspace" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})

      assert {:ok, _channel} =
               Workspaces.create_channel(scope, workspace.id, %{name: "Main Room"})

      assert {:error, :invalid_channel, changeset} =
               Workspaces.create_channel(scope, workspace.id, %{name: "main-room"})

      assert errors_on(changeset).name == ["has already been taken"]
    end

    test "allows duplicate normalized names in different workspaces" do
      scope = user_scope_fixture()
      {:ok, first_workspace} = Workspaces.create_workspace(scope, %{name: "First"})
      {:ok, second_workspace} = Workspaces.create_workspace(scope, %{name: "Second"})

      assert {:ok, first_channel} =
               Workspaces.create_channel(scope, first_workspace.id, %{name: "General Chat"})

      assert {:ok, second_channel} =
               Workspaces.create_channel(scope, second_workspace.id, %{name: "general-chat"})

      assert first_channel.name == second_channel.name
      assert first_channel.workspace_id != second_channel.workspace_id
    end

    test "does not update the workspace default channel after creating another channel" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})

      assert {:ok, _channel} = Workspaces.create_channel(scope, workspace.id, %{name: "planning"})

      assert Repo.reload!(workspace).default_channel_id == workspace.default_channel_id
    end
  end

  describe "change_channel/2" do
    test "returns a channel changeset for form usage" do
      changeset = Workspaces.change_channel(123, %{"name" => "Main Room", "workspace_id" => 456})

      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_field(changeset, :workspace_id) == 123
      assert Ecto.Changeset.get_change(changeset, :name) == "main-room"
    end
  end

  describe "create_workspace_invite/3" do
    test "allows the workspace owner to create a fresh 30-minute invite" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      before_create = DateTime.utc_now(:second)

      assert {:ok, invite} = Workspaces.create_workspace_invite(scope, workspace.id)

      assert %WorkspaceInvite{} = invite
      assert invite.workspace_id == workspace.id
      assert invite.created_by_user_id == scope.user.id
      assert invite.uses_count == 0
      assert invite.revoked_at == nil
      assert invite.max_uses == nil
      assert invite.code =~ ~r/^[A-Za-z0-9_-]{32}$/

      expires_at_lower_bound = DateTime.add(before_create, 30, :minute)
      expires_at_upper_bound = DateTime.add(DateTime.utc_now(:second), 30, :minute)

      assert DateTime.compare(invite.expires_at, expires_at_lower_bound) in [:eq, :gt]
      assert DateTime.compare(invite.expires_at, expires_at_upper_bound) in [:eq, :lt]
    end

    test "rejects non-owner members in owner-only workspaces" do
      owner_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)

      assert Workspaces.create_workspace_invite(member_scope, workspace.id) ==
               {:error, :invite_permission_required}

      assert Repo.aggregate(WorkspaceInvite, :count) == 0
    end

    test "allows admins but rejects members creating invites" do
      owner_scope = user_scope_fixture()
      admin_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, admin_scope, "admin")
      add_workspace_member!(workspace, member_scope, "member")

      assert {:ok, invite} = Workspaces.create_workspace_invite(admin_scope, workspace.id)

      assert invite.workspace_id == workspace.id
      assert invite.created_by_user_id == admin_scope.user.id

      assert Workspaces.create_workspace_invite(member_scope, workspace.id) ==
               {:error, :invite_permission_required}
    end

    test "ignores server-owned attributes while accepting controlled expiration and max uses" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, spoofed_workspace} = Workspaces.create_workspace(scope, %{name: "Spoofed"})
      expires_at = DateTime.add(DateTime.utc_now(:second), 2, :hour)

      assert {:ok, invite} =
               Workspaces.create_workspace_invite(scope, workspace.id, %{
                 "workspace_id" => spoofed_workspace.id,
                 "created_by_user_id" => other_scope.user.id,
                 "code" => "spoofed-code",
                 "expires_at" => expires_at,
                 "max_uses" => 5,
                 "uses_count" => 99,
                 "revoked_at" => DateTime.utc_now(:second)
               })

      assert invite.workspace_id == workspace.id
      assert invite.created_by_user_id == scope.user.id
      assert invite.code != "spoofed-code"
      assert invite.expires_at == expires_at
      assert invite.max_uses == 5
      assert invite.uses_count == 0
      assert invite.revoked_at == nil
    end
  end

  describe "change_workspace_invite/1" do
    test "returns an invite changeset for form usage with controlled fields only" do
      expires_at = DateTime.add(DateTime.utc_now(:second), 1, :hour)

      changeset =
        Workspaces.change_workspace_invite(%{
          "workspace_id" => 456,
          "code" => "spoofed-code",
          "expires_at" => expires_at,
          "max_uses" => 3
        })

      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_field(changeset, :workspace_id) == nil
      assert Ecto.Changeset.get_change(changeset, :code) == nil
      assert Ecto.Changeset.get_change(changeset, :expires_at) == expires_at
      assert Ecto.Changeset.get_change(changeset, :max_uses) == 3
    end
  end

  describe "preview_workspace_invite/2" do
    test "returns privacy-safe invite details without joining or incrementing usage" do
      owner_scope = user_scope_fixture()
      invited_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      {:ok, invite} = Workspaces.create_workspace_invite(owner_scope, workspace.id)

      assert {:ok, preview} = Workspaces.preview_workspace_invite(invited_scope, invite.code)

      assert preview.invite_code == invite.code
      assert preview.workspace_name == "Foundry"
      assert preview.inviter_username == owner_scope.user.username
      assert preview.accepting_username == invited_scope.user.username
      refute Map.has_key?(preview, :channels)
      refute Map.has_key?(preview, :members)
      refute Map.has_key?(preview, :owner_email)
      refute Map.has_key?(preview, :inviter_email)

      assert Repo.get!(WorkspaceInvite, invite.id).uses_count == 0

      refute Repo.get_by(WorkspaceMembership,
               workspace_id: workspace.id,
               user_id: invited_scope.user.id
             )
    end

    test "returns not found for a missing invite code" do
      scope = user_scope_fixture()

      assert Workspaces.preview_workspace_invite(scope, "missing-code") == {:error, :not_found}
    end

    test "returns revoked for a revoked invite" do
      owner_scope = user_scope_fixture()
      invited_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      {:ok, invite} = Workspaces.create_workspace_invite(owner_scope, workspace.id)

      invite
      |> Ecto.Changeset.change(revoked_at: DateTime.utc_now(:second))
      |> Repo.update!()

      assert Workspaces.preview_workspace_invite(invited_scope, invite.code) == {:error, :revoked}
    end

    test "returns expired for an expired invite" do
      owner_scope = user_scope_fixture()
      invited_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      {:ok, invite} =
        Workspaces.create_workspace_invite(owner_scope, workspace.id, %{
          expires_at: DateTime.add(DateTime.utc_now(:second), -1, :second)
        })

      assert Workspaces.preview_workspace_invite(invited_scope, invite.code) == {:error, :expired}
    end

    test "returns full for a fully-used invite" do
      owner_scope = user_scope_fixture()
      invited_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      {:ok, invite} =
        Workspaces.create_workspace_invite(owner_scope, workspace.id, %{max_uses: 1})

      invite
      |> Ecto.Changeset.change(uses_count: 1)
      |> Repo.update!()

      assert Workspaces.preview_workspace_invite(invited_scope, invite.code) == {:error, :full}
    end

    test "requires an authenticated scope" do
      assert Workspaces.preview_workspace_invite(nil, "missing-code") ==
               {:error, :unauthenticated}

      assert Workspaces.preview_workspace_invite(%DiscordClone.Accounts.Scope{}, "missing-code") ==
               {:error, :unauthenticated}
    end
  end

  describe "accept_workspace_invite/2" do
    test "creates a member membership, consumes one use, and returns the landing channel" do
      owner_scope = user_scope_fixture()
      invited_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      {:ok, invite} = Workspaces.create_workspace_invite(owner_scope, workspace.id)

      assert {:ok, landing} = Workspaces.accept_workspace_invite(invited_scope, invite.code)

      assert landing.workspace_id == workspace.id
      assert landing.channel_id == workspace.default_channel_id

      assert %WorkspaceMembership{role: "member"} =
               Repo.get_by(WorkspaceMembership,
                 workspace_id: workspace.id,
                 user_id: invited_scope.user.id
               )

      assert Repo.get!(WorkspaceInvite, invite.id).uses_count == 1
    end

    test "initializes read rows for new invite members" do
      owner_scope = user_scope_fixture()
      invited_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      {:ok, release_channel} =
        Workspaces.create_channel(owner_scope, workspace.id, %{name: "release"})

      {:ok, invite} = Workspaces.create_workspace_invite(owner_scope, workspace.id)

      release_message =
        insert_message!(
          release_channel.id,
          owner_scope.user.id,
          "Release notes",
          DateTime.add(DateTime.utc_now(:second), -60, :second)
        )

      assert {:ok, _landing} = Workspaces.accept_workspace_invite(invited_scope, invite.code)

      assert %ChannelRead{last_read_message_id: nil} =
               Repo.get_by(ChannelRead,
                 channel_id: workspace.default_channel_id,
                 user_id: invited_scope.user.id
               )

      assert %ChannelRead{last_read_message_id: last_read_message_id} =
               Repo.get_by(ChannelRead,
                 channel_id: release_channel.id,
                 user_id: invited_scope.user.id
               )

      assert last_read_message_id == release_message.id

      assert %ChannelReadState{
               unread_count: 0,
               first_unread_seq: nil,
               last_unread_seq: nil
             } =
               Repo.get_by(ChannelReadState,
                 channel_id: release_channel.id,
                 user_id: invited_scope.user.id
               )

      refute Repo.get_by(ChannelUnreadSpan,
               channel_id: release_channel.id,
               user_id: invited_scope.user.id
             )
    end

    test "existing workspace members enter the landing channel without duplicate membership or usage" do
      owner_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)
      {:ok, invite} = Workspaces.create_workspace_invite(owner_scope, workspace.id)

      assert {:ok, landing} = Workspaces.accept_workspace_invite(member_scope, invite.code)

      assert landing.workspace_id == workspace.id
      assert landing.channel_id == workspace.default_channel_id
      assert landing.already_member? == true

      assert Repo.aggregate(
               from(membership in WorkspaceMembership,
                 where:
                   membership.workspace_id == ^workspace.id and
                     membership.user_id == ^member_scope.user.id
               ),
               :count
             ) == 1

      assert Repo.get!(WorkspaceInvite, invite.id).uses_count == 0
    end

    test "existing workspace member invite acceptance leaves read rows unchanged" do
      owner_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      {:ok, release_channel} =
        Workspaces.create_channel(owner_scope, workspace.id, %{name: "release"})

      add_workspace_member!(workspace, member_scope)

      first_message =
        insert_message!(
          release_channel.id,
          owner_scope.user.id,
          "First",
          DateTime.add(DateTime.utc_now(:second), -60, :second)
        )

      _second_message =
        insert_message!(
          release_channel.id,
          owner_scope.user.id,
          "Second",
          DateTime.add(DateTime.utc_now(:second), -30, :second)
        )

      Repo.insert!(%ChannelRead{
        channel_id: release_channel.id,
        user_id: member_scope.user.id,
        last_read_message_id: first_message.id
      })

      Repo.insert!(
        ChannelReadState.changeset(%ChannelReadState{}, %{
          channel_id: release_channel.id,
          user_id: member_scope.user.id,
          unread_count: 1,
          first_unread_seq: 2,
          last_unread_seq: 2,
          last_viewed_anchor_seq: 1
        })
      )

      Repo.insert!(
        ChannelUnreadSpan.changeset(%ChannelUnreadSpan{}, %{
          channel_id: release_channel.id,
          user_id: member_scope.user.id,
          from_seq: 2,
          to_seq: 2
        })
      )

      {:ok, invite} = Workspaces.create_workspace_invite(owner_scope, workspace.id)

      assert {:ok, landing} = Workspaces.accept_workspace_invite(member_scope, invite.code)
      assert landing.already_member? == true

      assert %ChannelRead{last_read_message_id: last_read_message_id} =
               Repo.get_by(ChannelRead,
                 channel_id: release_channel.id,
                 user_id: member_scope.user.id
               )

      assert last_read_message_id == first_message.id

      assert %ChannelReadState{
               unread_count: 1,
               first_unread_seq: 2,
               last_unread_seq: 2,
               last_viewed_anchor_seq: 1
             } =
               Repo.get_by(ChannelReadState,
                 channel_id: release_channel.id,
                 user_id: member_scope.user.id
               )

      assert %ChannelUnreadSpan{from_seq: 2, to_seq: 2} =
               Repo.get_by(ChannelUnreadSpan,
                 channel_id: release_channel.id,
                 user_id: member_scope.user.id
               )
    end

    test "workspace owners accept their own invites as navigation-only" do
      owner_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      {:ok, invite} = Workspaces.create_workspace_invite(owner_scope, workspace.id)

      assert {:ok, landing} = Workspaces.accept_workspace_invite(owner_scope, invite.code)

      assert landing.workspace_id == workspace.id
      assert landing.channel_id == workspace.default_channel_id
      assert landing.already_member? == true

      assert Repo.aggregate(
               from(membership in WorkspaceMembership,
                 where:
                   membership.workspace_id == ^workspace.id and
                     membership.user_id == ^owner_scope.user.id
               ),
               :count
             ) == 1

      assert Repo.get!(WorkspaceInvite, invite.id).uses_count == 0
    end

    test "rejects revoked invites without creating membership or consuming usage" do
      owner_scope = user_scope_fixture()
      invited_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      {:ok, invite} = Workspaces.create_workspace_invite(owner_scope, workspace.id)

      invite
      |> Ecto.Changeset.change(revoked_at: DateTime.utc_now(:second))
      |> Repo.update!()

      assert Workspaces.accept_workspace_invite(invited_scope, invite.code) == {:error, :revoked}

      refute Repo.get_by(WorkspaceMembership,
               workspace_id: workspace.id,
               user_id: invited_scope.user.id
             )

      assert Repo.get!(WorkspaceInvite, invite.id).uses_count == 0
    end

    test "rejects expired invites without creating membership or consuming usage" do
      owner_scope = user_scope_fixture()
      invited_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      {:ok, invite} =
        Workspaces.create_workspace_invite(owner_scope, workspace.id, %{
          expires_at: DateTime.add(DateTime.utc_now(:second), -1, :second)
        })

      assert Workspaces.accept_workspace_invite(invited_scope, invite.code) == {:error, :expired}

      refute Repo.get_by(WorkspaceMembership,
               workspace_id: workspace.id,
               user_id: invited_scope.user.id
             )

      assert Repo.get!(WorkspaceInvite, invite.id).uses_count == 0
    end

    test "rejects fully-used invites without creating membership or consuming usage" do
      owner_scope = user_scope_fixture()
      invited_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      {:ok, invite} =
        Workspaces.create_workspace_invite(owner_scope, workspace.id, %{max_uses: 1})

      invite
      |> Ecto.Changeset.change(uses_count: 1)
      |> Repo.update!()

      assert Workspaces.accept_workspace_invite(invited_scope, invite.code) == {:error, :full}

      refute Repo.get_by(WorkspaceMembership,
               workspace_id: workspace.id,
               user_id: invited_scope.user.id
             )

      assert Repo.get!(WorkspaceInvite, invite.id).uses_count == 1
    end

    test "treats nil max uses as unlimited until expiration or revocation" do
      owner_scope = user_scope_fixture()
      invited_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      {:ok, invite} = Workspaces.create_workspace_invite(owner_scope, workspace.id)

      invite
      |> Ecto.Changeset.change(uses_count: 3)
      |> Repo.update!()

      assert {:ok, landing} = Workspaces.accept_workspace_invite(invited_scope, invite.code)

      assert landing.workspace_id == workspace.id
      assert landing.channel_id == workspace.default_channel_id

      assert %WorkspaceMembership{role: "member"} =
               Repo.get_by(WorkspaceMembership,
                 workspace_id: workspace.id,
                 user_id: invited_scope.user.id
               )

      assert Repo.get!(WorkspaceInvite, invite.id).uses_count == 4
    end

    test "returns not found for a missing invite without creating membership" do
      invited_scope = user_scope_fixture()

      assert Workspaces.accept_workspace_invite(invited_scope, "missing-code") ==
               {:error, :not_found}

      refute Repo.get_by(WorkspaceMembership, user_id: invited_scope.user.id)
    end
  end

  describe "rename_workspace/3" do
    test "allows the workspace owner to rename a workspace" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})

      assert {:ok, renamed_workspace} =
               Workspaces.rename_workspace(scope, workspace.id, %{name: "Design Guild"})

      assert renamed_workspace.id == workspace.id
      assert renamed_workspace.name == "Design Guild"
    end

    test "rejects admins and members renaming a workspace" do
      owner_scope = user_scope_fixture()
      admin_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "My Server"})
      add_workspace_member!(workspace, admin_scope, "admin")
      add_workspace_member!(workspace, member_scope, "member")

      assert Workspaces.rename_workspace(admin_scope, workspace.id, %{name: "Admin Name"}) ==
               {:error, :owner_required}

      assert Workspaces.rename_workspace(member_scope, workspace.id, %{name: "Member Name"}) ==
               {:error, :owner_required}

      assert Repo.reload!(workspace).name == "My Server"
    end

    test "returns an invalid workspace changeset for invalid input" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})

      assert {:error, :invalid_workspace, changeset} =
               Workspaces.rename_workspace(scope, workspace.id, %{name: ""})

      assert errors_on(changeset).name == ["can't be blank"]
    end

    test "rejects logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Private Server"})

      assert Workspaces.rename_workspace(non_member_scope, workspace.id, %{name: "New Name"}) ==
               {:error, :unauthorized}
    end

    test "distinguishes missing workspaces, unauthenticated scopes, and invalid attrs" do
      scope = user_scope_fixture()

      assert Workspaces.rename_workspace(scope, -1, %{name: "New Name"}) == {:error, :not_found}

      assert Workspaces.rename_workspace(nil, 1, %{name: "New Name"}) ==
               {:error, :unauthenticated}

      assert Workspaces.rename_workspace(%DiscordClone.Accounts.Scope{}, 1, %{name: "New Name"}) ==
               {:error, :unauthenticated}

      assert Workspaces.rename_workspace(scope, 1, "bad attrs") == {:error, :invalid_attrs}
    end
  end

  describe "rename_channel/4" do
    test "allows the workspace owner to rename a channel" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})
      {:ok, channel} = Workspaces.create_channel(scope, workspace.id, %{name: "planning"})

      assert {:ok, renamed_channel} =
               Workspaces.rename_channel(scope, workspace.id, channel.id, %{name: "Design Room"})

      assert renamed_channel.id == channel.id
      assert renamed_channel.workspace_id == workspace.id
      assert renamed_channel.name == "design-room"
    end

    test "allows admins but rejects members renaming channels" do
      owner_scope = user_scope_fixture()
      admin_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "My Server"})
      add_workspace_member!(workspace, admin_scope, "admin")
      add_workspace_member!(workspace, member_scope, "member")
      {:ok, channel} = Workspaces.create_channel(owner_scope, workspace.id, %{name: "planning"})

      assert {:ok, renamed_channel} =
               Workspaces.rename_channel(admin_scope, workspace.id, channel.id, %{
                 name: "Admin Planning"
               })

      assert renamed_channel.name == "admin-planning"

      assert Workspaces.rename_channel(member_scope, workspace.id, channel.id, %{
               name: "Member Planning"
             }) == {:error, :unauthorized}
    end

    test "allows renaming the landing channel without changing the landing channel id" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})
      landing_channel = Repo.get!(Channel, workspace.default_channel_id)

      assert {:ok, renamed_channel} =
               Workspaces.rename_channel(scope, workspace.id, landing_channel.id, %{
                 name: "Welcome Desk"
               })

      assert renamed_channel.id == workspace.default_channel_id
      assert renamed_channel.name == "welcome-desk"
      assert Repo.reload!(workspace).default_channel_id == landing_channel.id
    end

    test "returns not found when the workspace or channel is missing" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})

      assert Workspaces.rename_channel(scope, -1, workspace.default_channel_id, %{name: "new"}) ==
               {:error, :not_found}

      assert Workspaces.rename_channel(scope, workspace.id, -1, %{name: "new"}) ==
               {:error, :not_found}
    end

    test "returns not found when the channel belongs to another workspace" do
      scope = user_scope_fixture()
      {:ok, selected_workspace} = Workspaces.create_workspace(scope, %{name: "Selected"})
      {:ok, other_workspace} = Workspaces.create_workspace(scope, %{name: "Other"})
      other_channel = Repo.get!(Channel, other_workspace.default_channel_id)

      assert Workspaces.rename_channel(scope, selected_workspace.id, other_channel.id, %{
               name: "new"
             }) == {:error, :not_found}
    end

    test "rejects logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Private Server"})

      assert Workspaces.rename_channel(
               non_member_scope,
               workspace.id,
               workspace.default_channel_id,
               %{name: "new"}
             ) == {:error, :unauthorized}
    end

    test "requires an authenticated scope" do
      assert Workspaces.rename_channel(nil, 1, 1, %{name: "new"}) == {:error, :unauthenticated}

      assert Workspaces.rename_channel(%DiscordClone.Accounts.Scope{}, 1, 1, %{name: "new"}) ==
               {:error, :unauthenticated}
    end

    test "returns an invalid channel changeset for invalid input" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})

      assert {:error, :invalid_channel, changeset} =
               Workspaces.rename_channel(scope, workspace.id, workspace.default_channel_id, %{
                 name: ""
               })

      assert errors_on(changeset).name == ["can't be blank"]
    end

    test "rejects duplicate normalized names inside the same workspace" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})
      {:ok, channel} = Workspaces.create_channel(scope, workspace.id, %{name: "Planning"})

      assert {:error, :invalid_channel, changeset} =
               Workspaces.rename_channel(scope, workspace.id, channel.id, %{name: "general"})

      assert errors_on(changeset).name == ["has already been taken"]
    end
  end

  describe "delete_channel/3" do
    test "deletes a non-landing channel" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})
      {:ok, channel} = Workspaces.create_channel(scope, workspace.id, %{name: "planning"})

      assert {:ok, deleted_channel} = Workspaces.delete_channel(scope, workspace.id, channel.id)

      assert deleted_channel.id == channel.id
      refute Repo.get(Channel, channel.id)
    end

    test "rejects admins and members deleting channels" do
      owner_scope = user_scope_fixture()
      admin_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "My Server"})
      add_workspace_member!(workspace, admin_scope, "admin")
      add_workspace_member!(workspace, member_scope, "member")
      {:ok, channel} = Workspaces.create_channel(owner_scope, workspace.id, %{name: "planning"})

      assert Workspaces.delete_channel(admin_scope, workspace.id, channel.id) ==
               {:error, :owner_required}

      assert Workspaces.delete_channel(member_scope, workspace.id, channel.id) ==
               {:error, :owner_required}

      assert Repo.get(Channel, channel.id)
    end

    test "deletes messages for the deleted channel only" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})
      {:ok, channel} = Workspaces.create_channel(scope, workspace.id, %{name: "planning"})

      deleted_channel_message =
        insert_message!(
          channel.id,
          scope.user.id,
          "delete this history",
          ~U[2026-06-19 10:00:00Z]
        )

      kept_channel_message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "keep this history",
          ~U[2026-06-19 10:01:00Z]
        )

      assert {:ok, deleted_channel} = Workspaces.delete_channel(scope, workspace.id, channel.id)

      assert deleted_channel.id == channel.id
      refute Repo.get(Channel, channel.id)
      refute Repo.get(Message, deleted_channel_message.id)
      assert Repo.get(Message, kept_channel_message.id)
    end

    test "rejects deleting the landing channel" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})

      assert Workspaces.delete_channel(scope, workspace.id, workspace.default_channel_id) ==
               {:error, :landing_channel_required}

      assert Repo.get(Channel, workspace.default_channel_id)
    end

    test "returns not found when the workspace or channel is missing" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})

      assert Workspaces.delete_channel(scope, -1, workspace.default_channel_id) ==
               {:error, :not_found}

      assert Workspaces.delete_channel(scope, workspace.id, -1) == {:error, :not_found}
    end

    test "returns not found when the channel belongs to another workspace" do
      scope = user_scope_fixture()
      {:ok, selected_workspace} = Workspaces.create_workspace(scope, %{name: "Selected"})
      {:ok, other_workspace} = Workspaces.create_workspace(scope, %{name: "Other"})

      {:ok, other_channel} =
        Workspaces.create_channel(scope, other_workspace.id, %{name: "other"})

      assert Workspaces.delete_channel(scope, selected_workspace.id, other_channel.id) ==
               {:error, :not_found}
    end

    test "rejects logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Private Server"})
      {:ok, channel} = Workspaces.create_channel(owner_scope, workspace.id, %{name: "planning"})

      assert Workspaces.delete_channel(non_member_scope, workspace.id, channel.id) ==
               {:error, :unauthorized}

      assert Repo.get(Channel, channel.id)
    end

    test "requires an authenticated scope" do
      assert Workspaces.delete_channel(nil, 1, 1) == {:error, :unauthenticated}

      assert Workspaces.delete_channel(%DiscordClone.Accounts.Scope{}, 1, 1) ==
               {:error, :unauthenticated}
    end
  end

  describe "leave_workspace/2" do
    test "allows a non-owner workspace member to leave a workspace" do
      owner_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Team Space"})
      add_workspace_member!(workspace, member_scope)

      assert {:ok, %WorkspaceMembership{}} =
               Workspaces.leave_workspace(member_scope, workspace.id)

      refute Repo.get_by(WorkspaceMembership,
               workspace_id: workspace.id,
               user_id: member_scope.user.id
             )

      assert Workspaces.list_workspaces(member_scope) == {:ok, []}
    end

    test "deletes the leaving member read rows for channels in that workspace" do
      owner_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Team Space"})
      {:ok, channel} = Workspaces.create_channel(owner_scope, workspace.id, %{name: "planning"})
      {:ok, other_workspace} = Workspaces.create_workspace(member_scope, %{name: "Other Space"})
      add_workspace_member!(workspace, member_scope)

      Repo.insert!(%ChannelRead{
        channel_id: workspace.default_channel_id,
        user_id: member_scope.user.id,
        last_read_message_id: nil
      })

      Repo.insert!(%ChannelRead{
        channel_id: channel.id,
        user_id: member_scope.user.id,
        last_read_message_id: nil
      })

      Repo.insert!(
        ChannelReadState.changeset(%ChannelReadState{}, %{
          channel_id: workspace.default_channel_id,
          user_id: member_scope.user.id,
          unread_count: 1,
          first_unread_seq: 1,
          last_unread_seq: 1
        })
      )

      Repo.insert!(
        ChannelUnreadSpan.changeset(%ChannelUnreadSpan{}, %{
          channel_id: workspace.default_channel_id,
          user_id: member_scope.user.id,
          from_seq: 1,
          to_seq: 1
        })
      )

      Repo.insert!(
        ChannelReadState.changeset(%ChannelReadState{}, %{
          channel_id: channel.id,
          user_id: member_scope.user.id,
          unread_count: 1,
          first_unread_seq: 1,
          last_unread_seq: 1
        })
      )

      Repo.insert!(
        ChannelUnreadSpan.changeset(%ChannelUnreadSpan{}, %{
          channel_id: channel.id,
          user_id: member_scope.user.id,
          from_seq: 1,
          to_seq: 1
        })
      )

      Repo.insert!(
        ChannelUnreadSpan.changeset(%ChannelUnreadSpan{}, %{
          channel_id: other_workspace.default_channel_id,
          user_id: member_scope.user.id,
          from_seq: 1,
          to_seq: 1
        })
      )

      assert {:ok, %WorkspaceMembership{}} =
               Workspaces.leave_workspace(member_scope, workspace.id)

      refute Repo.get_by(ChannelRead,
               channel_id: workspace.default_channel_id,
               user_id: member_scope.user.id
             )

      refute Repo.get_by(ChannelRead,
               channel_id: channel.id,
               user_id: member_scope.user.id
             )

      refute Repo.get_by(ChannelReadState,
               channel_id: workspace.default_channel_id,
               user_id: member_scope.user.id
             )

      refute Repo.get_by(ChannelUnreadSpan,
               channel_id: workspace.default_channel_id,
               user_id: member_scope.user.id
             )

      refute Repo.get_by(ChannelReadState,
               channel_id: channel.id,
               user_id: member_scope.user.id
             )

      refute Repo.get_by(ChannelUnreadSpan,
               channel_id: channel.id,
               user_id: member_scope.user.id
             )

      assert Repo.get_by(ChannelRead,
               channel_id: channel.id,
               user_id: owner_scope.user.id
             )

      assert Repo.get_by(ChannelReadState,
               channel_id: other_workspace.default_channel_id,
               user_id: member_scope.user.id
             )

      assert Repo.get_by(ChannelUnreadSpan,
               channel_id: other_workspace.default_channel_id,
               user_id: member_scope.user.id
             )
    end

    test "requires owners to delete the workspace instead of leaving" do
      owner_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Team Space"})

      assert Workspaces.leave_workspace(owner_scope, workspace.id) == {:error, :owner_must_delete}

      assert Repo.get_by(WorkspaceMembership,
               workspace_id: workspace.id,
               user_id: owner_scope.user.id
             )
    end

    test "distinguishes missing workspaces, non-members, and unauthenticated scopes" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Team Space"})

      assert Workspaces.leave_workspace(owner_scope, -1) == {:error, :not_found}
      assert Workspaces.leave_workspace(non_member_scope, workspace.id) == {:error, :unauthorized}
      assert Workspaces.leave_workspace(nil, workspace.id) == {:error, :unauthenticated}

      assert Workspaces.leave_workspace(%DiscordClone.Accounts.Scope{}, workspace.id) ==
               {:error, :unauthenticated}
    end
  end

  describe "delete_workspace/2" do
    test "allows the owner to delete a workspace" do
      owner_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Team Space"})
      {:ok, channel} = Workspaces.create_channel(owner_scope, workspace.id, %{name: "planning"})

      assert {:ok, deleted_workspace} = Workspaces.delete_workspace(owner_scope, workspace.id)

      assert deleted_workspace.id == workspace.id
      refute Repo.get(DiscordClone.Workspaces.Workspace, workspace.id)
      refute Repo.get(Channel, channel.id)
      refute Repo.get_by(WorkspaceMembership, workspace_id: workspace.id)
      assert Workspaces.list_workspaces(owner_scope) == {:ok, []}
    end

    test "stops the workspace presence runtime for a deleted workspace" do
      owner_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Team Space"})

      assert :ok = DiscordClone.Chat.join_workspace_presence(owner_scope, workspace.id)
      presence_pid = WorkspaceServer.whereis(workspace.id)
      assert is_pid(presence_pid)

      ref = Process.monitor(presence_pid)

      assert {:ok, deleted_workspace} = Workspaces.delete_workspace(owner_scope, workspace.id)

      assert deleted_workspace.id == workspace.id
      assert_receive {:DOWN, ^ref, :process, ^presence_pid, :shutdown}
      assert WorkspaceServer.whereis(workspace.id) == nil
    end

    test "rejects non-owners, missing workspaces, and unauthenticated scopes" do
      owner_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Team Space"})
      add_workspace_member!(workspace, member_scope)

      assert Workspaces.delete_workspace(member_scope, workspace.id) == {:error, :owner_required}
      assert Workspaces.delete_workspace(owner_scope, -1) == {:error, :not_found}
      assert Workspaces.delete_workspace(nil, workspace.id) == {:error, :unauthenticated}

      assert Workspaces.delete_workspace(%DiscordClone.Accounts.Scope{}, workspace.id) ==
               {:error, :unauthenticated}

      assert Repo.get(DiscordClone.Workspaces.Workspace, workspace.id)
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

  defp insert_message!(channel_id, user_id, content, inserted_at) do
    {:ok, message} =
      Repo.transaction(fn ->
        channel =
          Repo.one!(
            from channel in Channel,
              where: channel.id == ^channel_id,
              lock: "FOR UPDATE"
          )

        seq = channel.last_message_seq + 1

        message =
          Repo.insert!(%Message{
            channel_id: channel_id,
            user_id: user_id,
            content: content,
            seq: seq,
            inserted_at: inserted_at,
            updated_at: inserted_at
          })

        channel
        |> Ecto.Changeset.change(last_message_seq: seq)
        |> Repo.update!()

        message
      end)

    message
  end
end
