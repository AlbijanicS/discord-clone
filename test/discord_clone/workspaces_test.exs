defmodule DiscordClone.WorkspacesTest do
  use DiscordClone.DataCase

  alias DiscordClone.Workspaces
  alias DiscordClone.Workspaces.{Channel, WorkspaceMembership}

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

    test "returns a landing channel missing error if the default channel invariant is broken" do
      scope = user_scope_fixture()

      assert {:ok, workspace} =
               Workspaces.create_workspace(scope, %{name: "Workspace"})

      workspace
      |> Ecto.Changeset.change(default_channel_id: nil)
      |> Repo.update!()

      assert Workspaces.resolve_landing_channel(scope, workspace.id) ==
               {:error, :landing_channel_missing}
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
    test "allows an authenticated workspace member to create a channel" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})

      assert {:ok, channel} =
               Workspaces.create_channel(scope, workspace.id, %{name: "General Chat"})

      assert channel.workspace_id == workspace.id
      assert channel.name == "general-chat"
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
end
