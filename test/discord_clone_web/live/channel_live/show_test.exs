defmodule DiscordCloneWeb.ChannelLive.ShowTest do
  use DiscordCloneWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DiscordClone.Workspaces
  alias DiscordClone.Chat
  alias DiscordClone.Chat.Message
  alias DiscordClone.Workspaces.WorkspaceMembership
  alias DiscordClone.Repo

  describe "unauthorized channel access" do
    setup :register_and_log_in_user

    test "redirects a non-member to the workspace app with a flash", %{conn: conn} do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      assert {:error, {:redirect, %{to: "/workspaces", flash: flash}}} =
               live(
                 conn,
                 ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
               )

      assert flash["error"] =~ "Channel not found or you do not have access"
    end

    test "redirects when the workspace or channel is missing", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/workspaces", flash: flash}}} =
               live(conn, ~p"/workspaces/not-a-uuid/channels/also-missing")

      assert flash["error"] =~ "Channel not found or you do not have access"
    end
  end

  describe "channel render" do
    setup :register_and_log_in_user

    test "renders the channel surface with its existing messages", %{conn: conn, scope: scope} do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, first} =
        Chat.send_message(scope, workspace.default_channel_id, %{content: "first up"})

      {:ok, second} =
        Chat.send_message(scope, workspace.default_channel_id, %{content: "second up"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#channel-message-surface")
      assert has_element?(view, "#message-composer-form")
      assert has_element?(view, "#message-#{first.id}-content", "first up")
      assert has_element?(view, "#message-#{second.id}-content", "second up")
      refute has_element?(view, "#channel-empty-state")
    end
  end

  describe "sending messages" do
    setup :register_and_log_in_user

    test "posts a message from the composer and renders it in the stream", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#channel-empty-state")

      view
      |> form("#message-composer-form", message: %{content: "hello team"})
      |> render_submit()

      message = Repo.get_by!(Message, content: "hello team")

      assert has_element?(view, "#message-#{message.id}-content", "hello team")
      refute has_element?(view, "#channel-empty-state")
    end

    test "ignores a blank message submission", %{conn: conn, scope: scope} do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> form("#message-composer-form", message: %{content: "   "})
      |> render_submit()

      assert has_element?(view, "#channel-empty-state")
      assert Repo.aggregate(Message, :count) == 0
    end
  end

  describe "deleting messages" do
    setup :register_and_log_in_user

    test "replaces a deleted message with the deleted placeholder", %{conn: conn, scope: scope} do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, message} =
        Chat.send_message(scope, workspace.default_channel_id, %{content: "delete me"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#message-#{message.id}-content", "delete me")

      view
      |> element("#message-#{message.id}-delete")
      |> render_click()

      assert has_element?(view, "#message-#{message.id}-deleted-placeholder", "Message deleted")
      refute has_element?(view, "#message-#{message.id}-content")
    end
  end

  describe "toggling reactions" do
    setup :register_and_log_in_user

    test "adds and then removes a reaction on a message", %{conn: conn, scope: scope} do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, message} =
        Chat.send_message(scope, workspace.default_channel_id, %{content: "react to me"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      refute has_element?(view, "#message-#{message.id}-reaction-0")

      view
      |> element("#message-#{message.id}-reaction-option-0")
      |> render_click()

      assert has_element?(
               view,
               "#message-#{message.id}-reaction-0[data-current-user-reacted='true']"
             )

      view
      |> element("#message-#{message.id}-reaction-option-0")
      |> render_click()

      refute has_element?(view, "#message-#{message.id}-reaction-0")
    end
  end

  describe "message moderation menu visibility" do
    setup :register_and_log_in_user

    test "surfaces moderation controls to an owner over a member's message", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      member_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope, "member")

      {:ok, message} =
        Chat.send_message(member_scope, workspace.default_channel_id, %{content: "hi from member"})

      {:ok, view, _html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#message-#{message.id}-actions")
      assert has_element?(view, "#message-#{message.id}-delete")
      assert has_element?(view, "#message-#{message.id}-promote-to-admin")
      assert has_element?(view, "#message-#{message.id}-mute")
      assert has_element?(view, "#message-#{message.id}-kick")
      assert has_element?(view, "#message-#{message.id}-ban")
    end

    test "hides the moderation menu from a member over another member's message", %{
      conn: conn,
      scope: viewer_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      author_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, viewer_scope, "member")
      add_workspace_member!(workspace, author_scope, "member")

      {:ok, message} =
        Chat.send_message(author_scope, workspace.default_channel_id, %{content: "peer message"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#message-#{message.id}-content", "peer message")
      refute has_element?(view, "#message-#{message.id}-actions")
      refute has_element?(view, "#message-#{message.id}-mute")
    end

    test "surfaces moderation controls to an admin over a member's message", %{
      conn: conn,
      scope: admin_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      member_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, admin_scope, "admin")
      add_workspace_member!(workspace, member_scope, "member")

      {:ok, message} =
        Chat.send_message(member_scope, workspace.default_channel_id, %{content: "member ping"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#message-#{message.id}-actions")
      assert has_element?(view, "#message-#{message.id}-mute")
      assert has_element?(view, "#message-#{message.id}-kick")
    end

    test "hides moderation controls from an admin over an owner's message", %{
      conn: conn,
      scope: admin_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, admin_scope, "admin")

      {:ok, message} =
        Chat.send_message(owner_scope, workspace.default_channel_id, %{content: "owner note"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#message-#{message.id}-content", "owner note")
      refute has_element?(view, "#message-#{message.id}-actions")
    end
  end

  describe "forged member actions" do
    setup :register_and_log_in_user

    test "rejects a member-action event from a non-permitted actor", %{
      conn: conn,
      scope: viewer_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      target_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, viewer_scope, "member")
      add_workspace_member!(workspace, target_scope, "member")

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      html =
        render_hook(view, "member_action", %{
          "action" => "promote_to_admin",
          "user_id" => target_scope.user.id
        })

      # The LiveView event path handled and rejected the forged action itself:
      # it surfaces the error flash rather than silently applying the change.
      assert html =~ "Member action could not be completed."

      assert Repo.get_by(WorkspaceMembership,
               workspace_id: workspace.id,
               user_id: target_scope.user.id
             ).role == "member"
    end
  end

  defp add_workspace_member!(workspace, scope, role) do
    {:ok, membership} =
      %WorkspaceMembership{}
      |> WorkspaceMembership.changeset(%{
        workspace_id: workspace.id,
        user_id: scope.user.id,
        role: role
      })
      |> Repo.insert()

    :ok = Chat.initialize_workspace_reads_for_user(scope.user.id, workspace.id)

    membership
  end
end
