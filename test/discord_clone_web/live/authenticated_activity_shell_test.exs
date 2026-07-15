defmodule DiscordCloneWeb.AuthenticatedActivityShellTest do
  use DiscordCloneWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DiscordCloneWeb.WorkspaceLiveTestHelpers, only: [add_workspace_member!: 2]

  alias DiscordClone.Chat
  alias DiscordClone.Workspaces

  describe "authenticated activity bell" do
    setup :register_and_log_in_user

    test "shows the scoped unread count with no selected workspace and in a channel", %{
      conn: recipient_conn,
      scope: recipient_scope
    } do
      author_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(author_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, recipient_scope)

      assert {:ok, _message} =
               Chat.send_message(author_scope, workspace.default_channel_id, %{
                 content: "please review @#{recipient_scope.user.username}"
               })

      {:ok, workspace_view, _html} = live(recipient_conn, ~p"/workspaces")

      assert has_element?(workspace_view, "#global-activity-bell[aria-label='1 unread activity']")
      assert has_element?(workspace_view, "#global-activity-unread-count", "1")
      refute has_element?(workspace_view, "#selected-workspace-name")

      {:ok, channel_view, _html} =
        live(
          recipient_conn,
          ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
        )

      assert has_element?(channel_view, "#global-activity-bell[aria-label='1 unread activity']")
      assert has_element?(channel_view, "#global-activity-unread-count", "1")
    end

    test "does not expose another user's unread count", %{conn: conn} do
      other_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      author_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(author_scope, %{name: "Private"})
      add_workspace_member!(workspace, other_scope)

      assert {:ok, _message} =
               Chat.send_message(author_scope, workspace.default_channel_id, %{
                 content: "hello @#{other_scope.user.username}"
               })

      {:ok, view, _html} = live(conn, ~p"/workspaces")

      assert has_element?(view, "#global-activity-bell[aria-label='0 unread activities']")
      assert has_element?(view, "#global-activity-unread-count", "0")
    end
  end
end
