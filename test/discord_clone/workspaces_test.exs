defmodule DiscordClone.WorkspacesTest do
  use DiscordClone.DataCase

  alias DiscordClone.Workspaces
  alias DiscordClone.Workspaces.{Channel, WorkspaceMembership}

  import DiscordClone.AccountsFixtures
  import DiscordClone.WorkspacesFixtures

  describe "create_workspace/2" do
    test "creates a workspace without a default channel and with owner membership" do
      scope = user_scope_fixture()

      assert {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "My Server"})

      assert workspace.name == "My Server"
      assert workspace.owner_id == scope.user.id
      assert workspace.invite_policy == "owner_only"
      assert is_nil(workspace.default_channel_id)
      refute Repo.get_by(Channel, workspace_id: workspace.id)

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

    test "ignores main channel input in the workspace creation workflow" do
      scope = user_scope_fixture()

      assert {:ok, workspace} =
               Workspaces.create_workspace(scope, %{
                 name: "Channels Later",
                 main_channel_name: "general"
               })

      assert is_nil(workspace.default_channel_id)
      refute Repo.get_by(Channel, workspace_id: workspace.id)
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

    test "rejects unauthenticated scopes" do
      assert Workspaces.create_workspace(nil, %{name: "Nope"}) == {:error, :unauthenticated}

      assert Workspaces.create_workspace(%DiscordClone.Accounts.Scope{}, %{name: "Nope"}) ==
               {:error, :unauthenticated}
    end
  end

  describe "workspace_fixture/1" do
    test "creates a workspace through the public context" do
      workspace = workspace_fixture(%{name: "Fixture Server"})

      assert workspace.name == "Fixture Server"
      assert is_nil(workspace.default_channel_id)
      assert Repo.get_by(WorkspaceMembership, workspace_id: workspace.id, role: "owner")
    end
  end
end
