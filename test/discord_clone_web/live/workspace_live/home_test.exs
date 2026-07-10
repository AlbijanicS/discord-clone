defmodule DiscordCloneWeb.WorkspaceLive.HomeTest do
  use DiscordCloneWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias DiscordClone.Workspaces
  alias DiscordClone.Chat
  alias DiscordClone.Chat.{ChannelReadState, Message}
  alias DiscordClone.Chat.Runtime
  alias DiscordCloneWeb.WorkspaceLive.Shell
  alias DiscordClone.Workspaces.{Channel, WorkspaceInvite, WorkspaceMembership}
  alias DiscordClone.Repo

  describe "/workspaces authentication" do
    test "requires an authenticated user", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/workspaces")
    end
  end

  describe "/workspaces shell" do
    setup :register_and_log_in_user

    test "shows the app shell and open workspace form when the user has no workspaces", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/workspaces")

      assert has_element?(view, "#workspace-app-shell")
      assert has_element?(view, "#workspace-sidebar")
      assert has_element?(view, "#channel-sidebar")
      assert has_element?(view, "#workspace-main")
      assert has_element?(view, "#workspace-create-form")
      assert has_element?(view, "#workspace-empty-state")
    end

    test "shows existing workspaces as first-letter rail items with compact create action", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} = live(conn, ~p"/workspaces")

      assert has_element?(
               view,
               "#workspaces [aria-label='Open #{workspace.name}'][title='#{workspace.name}']",
               "F"
             )

      assert has_element?(view, "#workspace-create-toggle[title='Create workspace']")
      refute has_element?(view, "#workspace-create-form")
      refute has_element?(view, "#workspace-sidebar", "Workspaces")
    end

    test "opens the workspace form from the compact create action", %{
      conn: conn,
      scope: scope
    } do
      {:ok, _workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, view, _html} = live(conn, ~p"/workspaces")

      view
      |> element("#workspace-create-toggle")
      |> render_click()

      assert has_element?(view, "#workspace-create-form")
    end

    test "cancels workspace creation without navigating", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, view, _html} = live(conn, ~p"/workspaces")

      view
      |> element("#workspace-create-toggle")
      |> render_click()

      assert has_element?(view, "#workspace-create-form")

      view
      |> element("#workspace-create-cancel")
      |> render_click()

      refute has_element?(view, "#workspace-create-form")
      assert has_element?(view, "#workspace-create-toggle")
      assert has_element?(view, "#workspaces [aria-label='Open #{workspace.name}']")
    end

    test "keeps the workspace form open with field errors for invalid input", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/workspaces")

      view
      |> form("#workspace-create-form", workspace: %{name: ""})
      |> render_submit()

      assert has_element?(view, "#workspace-create-form")
      assert has_element?(view, "#workspace_name.input-error")
      assert has_element?(view, "#workspace-create-form", "can't be blank")
    end

    test "creates a workspace and navigates into workspace entry", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/workspaces")

      {:error, {:live_redirect, %{to: path}}} =
        view
        |> form("#workspace-create-form", workspace: %{name: "Launch Room"})
        |> render_submit()

      assert path =~ ~r|^/workspaces/[0-9a-f-]{36}$|
    end
  end

  describe "/workspaces/:workspace_id entry" do
    setup :register_and_log_in_user

    test "navigates to the resolved landing channel", %{conn: conn, scope: scope} do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/workspaces/#{workspace.id}")

      assert path == ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
    end

    test "redirects when no landing channel exists", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      Repo.delete_all(Channel)

      assert {:error, {:redirect, %{to: "/workspaces", flash: flash}}} =
               live(conn, ~p"/workspaces/#{workspace.id}")

      assert flash["error"] =~ "Workspace not found or you do not have access"
    end

    test "redirects missing or unauthorized workspace entry to the workspace app", %{
      conn: conn
    } do
      assert {:error, {:redirect, %{to: "/workspaces", flash: flash}}} =
               live(conn, ~p"/workspaces/not-a-uuid")

      assert flash["error"] =~ "Workspace not found"
    end
  end

  describe "/workspaces/:workspace_id/channels/:channel_id show" do
    setup :register_and_log_in_user

    test "renders a refreshable channel URL with selected shell state", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, channel} = Workspaces.create_channel(scope, workspace.id, %{name: "Planning"})

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/channels/#{channel.id}")

      assert has_element?(view, "#workspace-app-shell")
      assert has_element?(view, "#workspace-#{workspace.id}[aria-current='page']")
      assert has_element?(view, "#channel-#{channel.id}[aria-current='page']")
      assert has_element?(view, "#channel-#{channel.id}-actions")
      assert has_element?(view, "#channel-create-toggle")
      assert has_element?(view, "#channel-message-surface")
      assert has_element?(view, "#channel-messages[phx-hook='ChannelMessages']")
      assert has_element?(view, "#channel-empty-state")
      assert has_element?(view, "#message-composer-form")
      assert has_element?(view, "#message_content")
      refute has_element?(view, "#message-composer-placeholder")
    end

    test "renders an unread badge for a sibling channel when entering a channel", %{
      conn: conn,
      scope: member_scope
    } do
      {_owner_scope, workspace, sibling_channel} =
        workspace_with_sibling_unread!(member_scope)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(
               view,
               "#channel-#{sibling_channel.id}-unread-badge[aria-label='1 unread message in ops']",
               "1"
             )
    end

    test "syncs sidebar read state across same-user channel sessions", %{
      conn: conn,
      scope: member_scope
    } do
      {_owner_scope, workspace, sibling_channel} =
        workspace_with_sibling_unread!(member_scope)

      path = ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
      other_conn = build_conn() |> log_in_user(member_scope.user)

      {:ok, reading_view, _html} = live(conn, path)
      {:ok, synced_view, _html} = live(other_conn, path)

      assert has_element?(reading_view, "#channel-#{sibling_channel.id}-unread-badge", "1")
      assert has_element?(synced_view, "#channel-#{sibling_channel.id}-unread-badge", "1")

      reading_view
      |> element("#channel-#{sibling_channel.id}-actions")
      |> render_click()

      reading_view
      |> element("#channel-#{sibling_channel.id}-mark-read")
      |> render_click()

      refute has_element?(reading_view, "#channel-#{sibling_channel.id}-unread-badge")
      refute has_element?(synced_view, "#channel-#{sibling_channel.id}-unread-badge")
    end

    test "keeps private read-state events isolated between different users", %{
      conn: unread_conn,
      scope: unread_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      other_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      other_conn = build_conn() |> log_in_user(other_scope.user)

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      {:ok, sibling_channel} =
        Workspaces.create_channel(owner_scope, workspace.id, %{name: "ops"})

      add_workspace_member!(workspace, unread_scope)
      add_workspace_member!(workspace, other_scope)
      :ok = Chat.initialize_workspace_reads_for_user(unread_scope.user.id, workspace.id)
      :ok = Chat.initialize_workspace_reads_for_user(other_scope.user.id, workspace.id)

      {:ok, _message} =
        Chat.send_message(owner_scope, sibling_channel.id, %{content: "ops update"})

      path = ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
      {:ok, unread_view, _html} = live(unread_conn, path)
      {:ok, other_view, _html} = live(other_conn, path)

      assert has_element?(unread_view, "#channel-#{sibling_channel.id}-unread-badge", "1")
      assert has_element?(other_view, "#channel-#{sibling_channel.id}-unread-badge", "1")

      other_view
      |> element("#channel-#{sibling_channel.id}-actions")
      |> render_click()

      other_view
      |> element("#channel-#{sibling_channel.id}-mark-read")
      |> render_click()

      assert has_element?(unread_view, "#channel-#{sibling_channel.id}-unread-badge", "1")
      refute has_element?(other_view, "#channel-#{sibling_channel.id}-unread-badge")
    end

    test "clears selected-channel unread UI across same-user channel sessions", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      add_workspace_member!(workspace, member_scope)
      :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)

      for index <- 1..80 do
        insert_message!(
          workspace.default_channel_id,
          owner_scope.user.id,
          "general update #{index}",
          DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
        )
      end

      assert {:ok, _read_state} =
               Chat.add_channel_unread_range(member_scope, workspace.default_channel_id, 10, 12)

      path = ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
      other_conn = build_conn() |> log_in_user(member_scope.user)

      {:ok, reading_view, _html} = live(conn, path)
      {:ok, synced_view, _html} = live(other_conn, path)

      assert has_element?(reading_view, "#channel-unread-divider[data-unread-divider-seq='10']")
      assert has_element?(synced_view, "#channel-unread-divider[data-unread-divider-seq='10']")

      reading_view
      |> element("#channel-#{workspace.default_channel_id}-actions")
      |> render_click()

      reading_view
      |> element("#channel-#{workspace.default_channel_id}-mark-read")
      |> render_click()

      refute has_element?(reading_view, "#selected-channel-unread-actions")
      refute has_element?(reading_view, "#channel-unread-divider")
      refute has_element?(synced_view, "#selected-channel-unread-actions")
      refute has_element?(synced_view, "#channel-unread-divider")
    end

    test "recalculates selected-channel unread UI across same-user channel sessions", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      add_workspace_member!(workspace, member_scope)
      :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)

      for index <- 1..80 do
        insert_message!(
          workspace.default_channel_id,
          owner_scope.user.id,
          "general update #{index}",
          DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
        )
      end

      assert {:ok, _read_state} =
               Chat.add_channel_unread_range(member_scope, workspace.default_channel_id, 10, 12)

      path = ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
      other_conn = build_conn() |> log_in_user(member_scope.user)

      {:ok, reading_view, _html} = live(conn, path)
      {:ok, synced_view, _html} = live(other_conn, path)

      assert has_element?(reading_view, "#channel-unread-divider[data-unread-divider-seq='10']")
      assert has_element?(synced_view, "#channel-unread-divider[data-unread-divider-seq='10']")

      render_hook(reading_view, "visible_read_observed", %{
        "ranges" => [%{"from_seq" => 10, "to_seq" => 10}]
      })

      assert has_element?(reading_view, "#channel-unread-divider[data-unread-divider-seq='10']")
      assert has_element?(synced_view, "#channel-unread-divider[data-unread-divider-seq='11']")
    end

    test "starts disconnected channel render with no unread badges", %{
      conn: conn,
      scope: member_scope
    } do
      {_owner_scope, workspace, sibling_channel} =
        workspace_with_sibling_unread!(member_scope)

      html =
        conn
        |> get(~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")
        |> html_response(200)

      assert html
             |> LazyHTML.from_fragment()
             |> then(& &1["#channel-#{sibling_channel.id}-unread-badge"])
             |> LazyHTML.attribute("id") == []
    end

    test "opens an unread channel near its unread messages without marking it read", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      {:ok, sibling_channel} =
        Workspaces.create_channel(owner_scope, workspace.id, %{name: "ops"})

      add_workspace_member!(workspace, member_scope)
      :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)

      messages =
        for index <- 1..60 do
          insert_message!(
            sibling_channel.id,
            owner_scope.user.id,
            "ops update #{index}",
            DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
          )
        end

      unread_message = Enum.at(messages, 9)
      latest_message = List.last(messages)

      assert {:ok, _read_state} =
               Chat.add_channel_unread_range(member_scope, sibling_channel.id, 10, 12)

      default_channel_path =
        ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"

      sibling_channel_path = ~p"/workspaces/#{workspace.id}/channels/#{sibling_channel.id}"

      {:ok, view, _html} = live(conn, default_channel_path)

      assert has_element?(view, "#channel-#{sibling_channel.id}-unread-badge", "3")

      {:ok, opened_view, _html} =
        view
        |> element("#channel-#{sibling_channel.id} a")
        |> render_click()
        |> follow_redirect(conn, sibling_channel_path)

      assert has_element?(opened_view, "#channel-#{sibling_channel.id}[aria-current='page']")
      assert has_element?(opened_view, "#message-#{unread_message.id}-content", "ops update 10")

      assert has_element?(
               opened_view,
               "#channel-unread-divider[data-unread-divider-seq='10']"
             )

      assert has_element?(
               opened_view,
               "#channel-unread-divider-marker[data-message-id='#{unread_message.id}']"
             )

      refute has_element?(opened_view, "#message-#{latest_message.id}-content", "ops update 60")
      refute has_element?(opened_view, "#channel-#{sibling_channel.id}-unread-badge")

      assert Chat.list_unread_counts(member_scope, workspace.id) ==
               {:ok, %{sibling_channel.id => 3}}
    end

    test "jumps to oldest unread from the selected channel without marking it read", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)
      :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)

      messages =
        for index <- 1..80 do
          insert_message!(
            workspace.default_channel_id,
            owner_scope.user.id,
            "general update #{index}",
            DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
          )
        end

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      latest_message = List.last(messages)
      oldest_unread_message = Enum.at(messages, 9)

      assert has_element?(view, "#message-#{latest_message.id}-content", "general update 80")
      refute has_element?(view, "#message-#{oldest_unread_message.id}-content")

      assert {:ok, _read_state} =
               Chat.add_channel_unread_range(member_scope, workspace.default_channel_id, 10, 12)

      send(
        view.pid,
        {:workspace_message_created,
         %{workspace_id: workspace.id, channel_id: workspace.default_channel_id}}
      )

      assert has_element?(view, "#selected-channel-unread-actions")
      refute has_element?(view, "#channel-unread-divider")
      assert has_element?(view, "#jump-to-oldest-unread", "Jump to oldest unread")
      assert has_element?(view, "#mark-channel-read", "Mark as read")
      refute has_element?(view, "#selected-channel-unread-count")
      refute has_element?(view, "#jump-to-next-unread")
      refute render(view) =~ "Jump to next unread"

      view
      |> element("#jump-to-oldest-unread")
      |> render_click()

      assert has_element?(
               view,
               "#message-#{oldest_unread_message.id}-content",
               "general update 10"
             )

      refute has_element?(view, "#message-#{latest_message.id}-content")
      assert has_element?(view, "#channel-unread-divider[data-unread-divider-seq='10']")
      refute has_element?(view, "#selected-channel-unread-actions")

      assert Chat.list_unread_counts(member_scope, workspace.id) ==
               {:ok, %{workspace.default_channel_id => 3}}
    end

    test "marks the selected channel read without changing the message window", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)
      :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)

      for index <- 1..80 do
        insert_message!(
          workspace.default_channel_id,
          owner_scope.user.id,
          "general update #{index}",
          DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
        )
      end

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert {:ok, _read_state} =
               Chat.add_channel_unread_range(member_scope, workspace.default_channel_id, 10, 12)

      send(
        view.pid,
        {:workspace_message_created,
         %{workspace_id: workspace.id, channel_id: workspace.default_channel_id}}
      )

      assert has_element?(view, "#selected-channel-unread-actions")
      refute has_element?(view, "#channel-unread-divider")
      message_ids_before = rendered_message_ids(view)

      view
      |> element("#mark-channel-read")
      |> render_click()

      refute has_element?(view, "#selected-channel-unread-actions")
      assert rendered_message_ids(view) == message_ids_before
      assert Chat.list_unread_counts(member_scope, workspace.id) == {:ok, %{}}
    end

    test "marks rendered visible message ranges read from the channel hook", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)
      :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)

      messages =
        for index <- 1..80 do
          insert_message!(
            workspace.default_channel_id,
            owner_scope.user.id,
            "general update #{index}",
            DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
          )
        end

      first_read_message = Enum.at(messages, 9)
      last_read_message = Enum.at(messages, 11)

      assert {:ok, _read_state} =
               Chat.add_channel_unread_range(member_scope, workspace.default_channel_id, 10, 12)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#channel-unread-divider[data-unread-divider-seq='10']")
      refute has_element?(view, "#selected-channel-unread-actions")
      assert has_element?(view, "#message-#{first_read_message.id}[data-message-seq='10']")
      assert has_element?(view, "#message-#{last_read_message.id}[data-message-seq='12']")

      render_hook(view, "visible_read_observed", %{
        "ranges" => [%{"from_seq" => "10", "to_seq" => "12"}]
      })

      refute has_element?(view, "#selected-channel-unread-actions")
      refute has_element?(view, "#channel-unread-divider")
      assert Chat.list_unread_counts(member_scope, workspace.id) == {:ok, %{}}
    end

    test "keeps the unread divider stable after a visible-read event", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)
      :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)

      messages =
        for index <- 1..80 do
          insert_message!(
            workspace.default_channel_id,
            owner_scope.user.id,
            "general update #{index}",
            DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
          )
        end

      original_divider_message = Enum.at(messages, 9)
      next_unread_message = Enum.at(messages, 10)

      assert {:ok, _read_state} =
               Chat.add_channel_unread_range(member_scope, workspace.default_channel_id, 10, 12)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#channel-unread-divider[data-unread-divider-seq='10']")

      assert has_element?(
               view,
               "#channel-unread-divider-marker[data-message-id='#{original_divider_message.id}']"
             )

      render_hook(view, "visible_read_observed", %{
        "ranges" => [%{"from_seq" => "10", "to_seq" => "10"}]
      })

      assert has_element?(view, "#channel-unread-divider[data-unread-divider-seq='10']")

      assert has_element?(
               view,
               "#channel-unread-divider-marker[data-message-id='#{original_divider_message.id}']"
             )

      refute has_element?(
               view,
               "#channel-unread-divider-marker[data-message-id='#{next_unread_message.id}']"
             )

      assert Chat.list_unread_counts(member_scope, workspace.id) ==
               {:ok, %{workspace.default_channel_id => 2}}
    end

    test "ignores invalid and non-rendered visible-read ranges from the channel hook", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)
      :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)

      messages =
        for index <- 1..80 do
          insert_message!(
            workspace.default_channel_id,
            owner_scope.user.id,
            "general update #{index}",
            DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
          )
        end

      non_rendered_message = Enum.at(messages, 69)

      assert {:ok, _read_state} =
               Chat.add_channel_unread_range(member_scope, workspace.default_channel_id, 10, 12)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#channel-unread-divider[data-unread-divider-seq='10']")
      refute has_element?(view, "#selected-channel-unread-actions")
      refute has_element?(view, "#message-#{non_rendered_message.id}[data-message-seq='70']")

      for ranges <- [
            [%{"from_seq" => "11", "to_seq" => "11"}, %{"from_seq" => "10", "to_seq" => "10"}],
            [%{"from_seq" => "70", "to_seq" => "70"}],
            [%{"from_seq" => "12", "to_seq" => "10"}],
            [%{"from_seq" => "1", "to_seq" => "51"}],
            [%{"from_seq" => "not-a-sequence", "to_seq" => "12"}]
          ] do
        render_hook(view, "visible_read_observed", %{"ranges" => ranges})

        assert Chat.list_unread_counts(member_scope, workspace.id) ==
                 {:ok, %{workspace.default_channel_id => 3}}
      end

      assert has_element?(view, "#channel-unread-divider[data-unread-divider-seq='10']")
      refute has_element?(view, "#selected-channel-unread-actions")
    end

    test "persists a rendered scroll anchor from the channel hook", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      messages =
        for index <- 1..80 do
          insert_message!(
            workspace.default_channel_id,
            scope.user.id,
            "anchorable update #{index}",
            DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
          )
        end

      anchored_message = Enum.at(messages, 39)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#message-#{anchored_message.id}[data-message-seq='40']")

      render_hook(view, "scroll_anchor_observed", %{"seq" => "40"})

      assert %ChannelReadState{last_viewed_anchor_seq: 40} =
               Repo.get_by(ChannelReadState,
                 channel_id: workspace.default_channel_id,
                 user_id: scope.user.id
               )
    end

    test "ignores invalid scroll anchors and preserves unread state", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)
      :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)

      messages =
        for index <- 1..80 do
          insert_message!(
            workspace.default_channel_id,
            owner_scope.user.id,
            "anchor guard update #{index}",
            DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
          )
        end

      non_rendered_message = Enum.at(messages, 19)
      rendered_message = Enum.at(messages, 39)

      assert {:ok, _read_state} =
               Chat.add_channel_unread_range(member_scope, workspace.default_channel_id, 40, 42)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#channel-unread-divider[data-unread-divider-seq='40']")
      refute has_element?(view, "#selected-channel-unread-actions")
      refute has_element?(view, "#message-#{non_rendered_message.id}[data-message-seq='20']")
      assert has_element?(view, "#message-#{rendered_message.id}[data-message-seq='40']")

      for payload <- [
            %{"seq" => "20"},
            %{"seq" => "81"},
            %{"seq" => "not-a-sequence"},
            %{}
          ] do
        render_hook(view, "scroll_anchor_observed", payload)

        assert %ChannelReadState{last_viewed_anchor_seq: nil} =
                 Repo.get_by(ChannelReadState,
                   channel_id: workspace.default_channel_id,
                   user_id: member_scope.user.id
                 )

        assert Chat.list_unread_counts(member_scope, workspace.id) ==
                 {:ok, %{workspace.default_channel_id => 3}}
      end

      render_hook(view, "scroll_anchor_observed", %{"seq" => "40"})

      assert %ChannelReadState{
               last_viewed_anchor_seq: 40,
               unread_count: 3,
               first_unread_seq: 40,
               last_unread_seq: 42
             } =
               Repo.get_by(ChannelReadState,
                 channel_id: workspace.default_channel_id,
                 user_id: member_scope.user.id
               )

      assert has_element?(view, "#channel-unread-divider[data-unread-divider-seq='40']")
      refute has_element?(view, "#selected-channel-unread-actions")

      assert Chat.list_unread_counts(member_scope, workspace.id) ==
               {:ok, %{workspace.default_channel_id => 3}}
    end

    test "skips to latest by clearing unread and replacing the message window", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)
      :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)

      messages =
        for index <- 1..80 do
          insert_message!(
            workspace.default_channel_id,
            owner_scope.user.id,
            "general update #{index}",
            DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
          )
        end

      oldest_unread_message = Enum.at(messages, 9)
      latest_message = List.last(messages)

      assert {:ok, _read_state} =
               Chat.add_channel_unread_range(member_scope, workspace.default_channel_id, 10, 12)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#channel-unread-divider[data-unread-divider-seq='10']")
      refute has_element?(view, "#selected-channel-unread-actions")

      assert has_element?(
               view,
               "#skip-to-latest[aria-label='Skip to latest and mark unread messages read']"
             )

      assert has_element?(
               view,
               "#message-#{oldest_unread_message.id}-content",
               "general update 10"
             )

      refute has_element?(view, "#message-#{latest_message.id}-content")

      view
      |> element("#skip-to-latest")
      |> render_click()

      refute has_element?(view, "#selected-channel-unread-actions")
      refute has_element?(view, "#message-#{oldest_unread_message.id}-content")
      assert has_element?(view, "#message-#{latest_message.id}-content", "general update 80")
      assert Chat.list_unread_counts(member_scope, workspace.id) == {:ok, %{}}

      assert %ChannelReadState{last_viewed_anchor_seq: 80} =
               Repo.get_by(ChannelReadState,
                 channel_id: workspace.default_channel_id,
                 user_id: member_scope.user.id
               )
    end

    test "reopens a read channel around its last viewed anchor", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id

      messages =
        for index <- 1..120 do
          insert_message!(
            channel_id,
            scope.user.id,
            "anchored update #{index}",
            DateTime.add(~U[2026-06-19 11:00:00Z], index, :second)
          )
        end

      anchored_message = Enum.at(messages, 19)
      latest_message = List.last(messages)

      Repo.get_by!(ChannelReadState, channel_id: channel_id, user_id: scope.user.id)
      |> ChannelReadState.changeset(%{last_viewed_anchor_seq: 20})
      |> Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/channels/#{channel_id}")

      assert has_element?(view, "#message-#{anchored_message.id}-content", "anchored update 20")
      refute has_element?(view, "#message-#{latest_message.id}-content", "anchored update 120")
      assert Chat.list_unread_counts(scope, workspace.id) == {:ok, %{}}
    end

    test "keeps selected-channel live messages out of an older landing window", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id

      add_workspace_member!(workspace, member_scope)
      :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)

      messages =
        for index <- 1..120 do
          insert_message!(
            channel_id,
            owner_scope.user.id,
            "older-window update #{index}",
            DateTime.add(~U[2026-06-19 12:00:00Z], index, :second)
          )
        end

      anchored_message = Enum.at(messages, 19)

      Repo.get_by!(ChannelReadState, channel_id: channel_id, user_id: member_scope.user.id)
      |> ChannelReadState.changeset(%{last_viewed_anchor_seq: 20})
      |> Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/channels/#{channel_id}")

      assert has_element?(
               view,
               "#message-#{anchored_message.id}-content",
               "older-window update 20"
             )

      assert {:ok, live_message} =
               Chat.send_message(owner_scope, channel_id, %{"content" => "new distant latest"})

      _ = :sys.get_state(view.pid)

      refute has_element?(view, "#message-#{live_message.id}-content", "new distant latest")

      refute_push_event(view, "scroll_channel_messages_to_bottom", %{
        container_id: _container_id
      })

      assert Chat.list_unread_counts(member_scope, workspace.id) == {:ok, %{channel_id => 1}}
    end

    test "refreshes a sibling channel unread badge from a live workspace message event", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      {:ok, sibling_channel} =
        Workspaces.create_channel(owner_scope, workspace.id, %{name: "ops"})

      add_workspace_member!(workspace, member_scope)
      :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      refute has_element?(view, "#channel-#{sibling_channel.id}-unread-badge")

      assert {:ok, message} =
               Chat.send_message(owner_scope, sibling_channel.id, %{
                 "content" => "ops live update"
               })

      _ = :sys.get_state(view.pid)

      assert has_element?(
               view,
               "#channel-#{sibling_channel.id}-unread-badge[aria-label='1 unread message in ops']",
               "1"
             )

      refute has_element?(view, "#message-#{message.id}")
    end

    test "renders exact larger unread counts and hides quiet channel badges", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      {:ok, busy_channel} = Workspaces.create_channel(owner_scope, workspace.id, %{name: "ops"})

      {:ok, quiet_channel} =
        Workspaces.create_channel(owner_scope, workspace.id, %{name: "quiet"})

      add_workspace_member!(workspace, member_scope)
      :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)

      now = DateTime.utc_now(:second)

      for index <- 1..123 do
        insert_message!(
          busy_channel.id,
          owner_scope.user.id,
          "ops update #{index}",
          DateTime.add(now, index, :second)
        )
      end

      assert {:ok, _read_state} =
               Chat.add_channel_unread_range(member_scope, busy_channel.id, 1, 123)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(
               view,
               "#channel-#{busy_channel.id}-unread-badge[aria-label='123 unread messages in ops']",
               "123"
             )

      refute has_element?(view, "#channel-#{quiet_channel.id}-unread-badge")
      refute has_element?(view, "#channel-#{workspace.default_channel_id}-unread-badge")
    end

    test "scopes unread badges to the current user", %{
      conn: unread_conn,
      scope: unread_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      read_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      read_conn = build_conn() |> log_in_user(read_scope.user)

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      {:ok, sibling_channel} =
        Workspaces.create_channel(owner_scope, workspace.id, %{name: "ops"})

      add_workspace_member!(workspace, unread_scope)
      add_workspace_member!(workspace, read_scope)
      :ok = Chat.initialize_workspace_reads_for_user(unread_scope.user.id, workspace.id)
      :ok = Chat.initialize_workspace_reads_for_user(read_scope.user.id, workspace.id)

      {:ok, _message} =
        Chat.send_message(owner_scope, sibling_channel.id, %{"content" => "ops update"})

      assert :ok = Chat.mark_channel_read(read_scope, sibling_channel.id)

      {:ok, unread_view, _html} =
        live(
          unread_conn,
          ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
        )

      {:ok, read_view, _html} =
        live(read_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(
               unread_view,
               "#channel-#{sibling_channel.id}-unread-badge[aria-label='1 unread message in ops']",
               "1"
             )

      refute has_element?(read_view, "#channel-#{sibling_channel.id}-unread-badge")
    end

    test "suppresses the selected channel badge when the shell receives a transient count", %{
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, sibling_channel} = Workspaces.create_channel(scope, workspace.id, %{name: "ops"})
      selected_channel = Repo.get!(Channel, workspace.default_channel_id)

      html =
        render_component(&Shell.app/1,
          workspace_stream: [{"workspace-#{workspace.id}", workspace}],
          channel_stream: [
            {"channel-#{selected_channel.id}", selected_channel},
            {"channel-#{sibling_channel.id}", sibling_channel}
          ],
          selected_workspace: workspace,
          selected_channel: selected_channel,
          current_scope: scope,
          main_state: :empty_channel,
          channel_unread_counts: %{selected_channel.id => 7, sibling_channel.id => 2}
        )

      document = LazyHTML.from_fragment(html)

      assert document
             |> then(& &1["#channel-#{sibling_channel.id}-unread-badge"])
             |> LazyHTML.attribute("id") == ["channel-#{sibling_channel.id}-unread-badge"]

      assert document
             |> then(& &1["#channel-#{selected_channel.id}-unread-badge"])
             |> LazyHTML.attribute("id") == []
    end

    test "starts a channel runtime after connected channel entry", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert Runtime.channel_pid(workspace.default_channel_id) == nil

      {:ok, _view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert is_pid(Runtime.channel_pid(workspace.default_channel_id))
    end

    test "does not start a channel runtime during disconnected static render", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      conn = get(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert html_response(conn, 200)
      assert Runtime.channel_pid(workspace.default_channel_id) == nil
    end

    test "renders durable workspace members in the channel shell", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope =
        %{username: "foundry_owner"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#workspace-members-sidebar[aria-label='Workspace members']")
      assert has_element?(view, "#workspace-members-sidebar", "Members")

      assert has_element?(
               view,
               "#workspace-member-#{owner_scope.user.id}[data-presence-state='offline']",
               "foundry_owner"
             )

      assert has_element?(
               view,
               "#workspace-member-#{member_scope.user.id}",
               member_scope.user.username
             )

      assert has_element?(
               view,
               "#workspace-member-#{owner_scope.user.id} [data-member-status='offline']",
               "Offline"
             )

      assert has_element?(view, "#channel-message-surface")
      assert has_element?(view, "#message-composer-form")
    end

    test "groups online members by role and offline members together", %{
      conn: conn,
      scope: owner_scope
    } do
      admin_scope =
        %{username: "sidebar_admin"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      member_scope =
        %{username: "sidebar_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      offline_scope =
        %{username: "sidebar_offline"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, admin_scope, "admin")
      add_workspace_member!(workspace, member_scope, "member")
      add_workspace_member!(workspace, offline_scope, "member")

      admin_live_view_pid = start_live_view_process()
      member_live_view_pid = start_live_view_process()
      assert :ok = Chat.join_workspace_presence(admin_scope, workspace.id, admin_live_view_pid)
      assert :ok = Chat.join_workspace_presence(member_scope, workspace.id, member_live_view_pid)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#workspace-members-online-owner-section", "Owner")
      assert has_element?(view, "#workspace-members-online-admin-section", "Admins")
      assert has_element?(view, "#workspace-members-online-member-section", "Members")
      assert has_element?(view, "#workspace-members-offline-section", "Offline")

      assert has_element?(
               view,
               "#workspace-members-online-owner-section + #workspace-member-#{owner_scope.user.id}[data-presence-state='online']",
               owner_scope.user.username
             )

      assert has_element?(
               view,
               "#workspace-members-online-admin-section ~ #workspace-member-#{admin_scope.user.id}[data-presence-state='online']",
               "sidebar_admin"
             )

      assert has_element?(
               view,
               "#workspace-members-online-member-section ~ #workspace-member-#{member_scope.user.id}[data-presence-state='online']",
               "sidebar_member"
             )

      assert has_element?(
               view,
               "#workspace-members-offline-section ~ #workspace-member-#{offline_scope.user.id}[data-presence-state='offline']",
               "sidebar_offline"
             )
    end

    test "shows member row actions to owners and hides them from regular members", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      member_scope =
        %{username: "sidebar_action_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope, "member")

      {:ok, owner_view, _html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(owner_view, "#workspace-member-#{member_scope.user.id}-actions")

      assert has_element?(
               owner_view,
               "#workspace-member-#{member_scope.user.id}-promote-to-admin"
             )

      assert has_element?(owner_view, "#workspace-member-#{member_scope.user.id}-mute")

      assert has_element?(
               owner_view,
               "#workspace-member-#{member_scope.user.id}-timeout-5-minutes"
             )

      assert has_element?(owner_view, "#workspace-member-#{member_scope.user.id}-kick")
      assert has_element?(owner_view, "#workspace-member-#{member_scope.user.id}-ban")

      refute has_element?(owner_view, "#workspace-member-#{owner_scope.user.id}-actions")

      member_conn = build_conn() |> log_in_user(member_scope.user)

      {:ok, member_view, _html} =
        live(
          member_conn,
          ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
        )

      assert has_element?(member_view, "#workspace-member-#{owner_scope.user.id}")
      refute has_element?(member_view, "#workspace-member-#{owner_scope.user.id}-actions")
      refute has_element?(member_view, "#workspace-member-#{member_scope.user.id}-actions")
    end

    test "limits admin member row actions by target role", %{conn: conn, scope: admin_scope} do
      owner_scope =
        %{username: "sidebar_action_owner"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      peer_admin_scope =
        %{username: "sidebar_action_admin"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      member_scope =
        %{username: "sidebar_action_target"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, admin_scope, "admin")
      add_workspace_member!(workspace, peer_admin_scope, "admin")
      add_workspace_member!(workspace, member_scope, "member")

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      refute has_element?(view, "#workspace-member-#{owner_scope.user.id}-actions")
      refute has_element?(view, "#workspace-member-#{admin_scope.user.id}-actions")

      assert has_element?(view, "#workspace-member-#{peer_admin_scope.user.id}-actions")
      assert has_element?(view, "#workspace-member-#{peer_admin_scope.user.id}-mute")
      assert has_element?(view, "#workspace-member-#{peer_admin_scope.user.id}-timeout-5-minutes")
      refute has_element?(view, "#workspace-member-#{peer_admin_scope.user.id}-kick")
      refute has_element?(view, "#workspace-member-#{peer_admin_scope.user.id}-ban")
      refute has_element?(view, "#workspace-member-#{peer_admin_scope.user.id}-demote-to-member")

      assert has_element?(view, "#workspace-member-#{member_scope.user.id}-actions")
      assert has_element?(view, "#workspace-member-#{member_scope.user.id}-mute")
      assert has_element?(view, "#workspace-member-#{member_scope.user.id}-timeout-5-minutes")
      assert has_element?(view, "#workspace-member-#{member_scope.user.id}-kick")
      assert has_element?(view, "#workspace-member-#{member_scope.user.id}-ban")
      refute has_element?(view, "#workspace-member-#{member_scope.user.id}-promote-to-admin")
    end

    test "shows active mute controls to staff and disables only the muted user's composer", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      muted_scope =
        %{username: "muted_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      observer_scope =
        %{username: "observer_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, muted_scope, "member")
      add_workspace_member!(workspace, observer_scope, "member")

      assert {:ok, _moderation} =
               Workspaces.mute_member(owner_scope, workspace.id, muted_scope.user.id, %{
                 "reason" => "Cooling down"
               })

      {:ok, owner_view, _html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(owner_view, "#workspace-member-#{muted_scope.user.id}-unmute")
      refute has_element?(owner_view, "#workspace-member-#{muted_scope.user.id}-mute")

      muted_conn = build_conn() |> log_in_user(muted_scope.user)

      {:ok, muted_view, _html} =
        live(
          muted_conn,
          ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
        )

      assert has_element?(muted_view, "#message_content[disabled]")
      assert has_element?(muted_view, "#message-composer-muted-feedback", "muted")

      observer_conn = build_conn() |> log_in_user(observer_scope.user)

      {:ok, observer_view, _html} =
        live(
          observer_conn,
          ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
        )

      assert has_element?(observer_view, "#workspace-member-#{muted_scope.user.id}")
      refute has_element?(observer_view, "#workspace-member-#{muted_scope.user.id}-unmute")
      refute has_element?(observer_view, "#message-composer-muted-feedback")
    end

    test "refreshes connected channel surfaces after mute and unmute actions", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      target_scope =
        %{username: "live_muted_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope, "member")

      {:ok, owner_view, _html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      target_conn = build_conn() |> log_in_user(target_scope.user)

      {:ok, target_view, _html} =
        live(
          target_conn,
          ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
        )

      refute has_element?(target_view, "#message-composer-muted-feedback")

      owner_view
      |> element("#workspace-member-#{target_scope.user.id}-mute")
      |> render_click()

      render(target_view)
      assert has_element?(target_view, "#message-composer-muted-feedback")
      assert has_element?(owner_view, "#workspace-member-#{target_scope.user.id}-unmute")

      owner_view
      |> element("#workspace-member-#{target_scope.user.id}-unmute")
      |> render_click()

      render(target_view)
      refute has_element?(target_view, "#message-composer-muted-feedback")
      assert has_element?(owner_view, "#workspace-member-#{target_scope.user.id}-mute")
    end

    test "promotes a member to admin from the member menu and refreshes the controls", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      target_scope =
        %{username: "promotable_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope, "member")

      {:ok, owner_view, _html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      owner_view
      |> element("#workspace-member-#{target_scope.user.id}-promote-to-admin")
      |> render_click()

      assert Repo.get_by(WorkspaceMembership,
               workspace_id: workspace.id,
               user_id: target_scope.user.id
             ).role == "admin"

      assert has_element?(
               owner_view,
               "#workspace-member-#{target_scope.user.id}-demote-to-member"
             )

      refute has_element?(
               owner_view,
               "#workspace-member-#{target_scope.user.id}-promote-to-admin"
             )
    end

    test "moves an online promoted member into the admins section from a broadcast", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      target_scope =
        %{username: "broadcast_promotable"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope, "member")

      target_live_view_pid = start_live_view_process()
      assert :ok = Chat.join_workspace_presence(target_scope, workspace.id, target_live_view_pid)

      {:ok, owner_view, _html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(
               owner_view,
               "#workspace-members-online-member-section ~ #workspace-member-#{target_scope.user.id}[data-presence-state='online']",
               "broadcast_promotable"
             )

      assert {:ok, _membership} =
               Workspaces.change_member_role(
                 owner_scope,
                 workspace.id,
                 target_scope.user.id,
                 "admin"
               )

      render(owner_view)

      assert has_element?(
               owner_view,
               "#workspace-members-online-admin-section ~ #workspace-member-#{target_scope.user.id}[data-presence-state='online']",
               "broadcast_promotable"
             )
    end

    test "demotes an admin to member from the member menu and refreshes the controls", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      target_scope =
        %{username: "demotable_admin"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope, "admin")

      {:ok, owner_view, _html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      owner_view
      |> element("#workspace-member-#{target_scope.user.id}-demote-to-member")
      |> render_click()

      assert Repo.get_by(WorkspaceMembership,
               workspace_id: workspace.id,
               user_id: target_scope.user.id
             ).role == "member"

      assert has_element?(
               owner_view,
               "#workspace-member-#{target_scope.user.id}-promote-to-admin"
             )

      refute has_element?(
               owner_view,
               "#workspace-member-#{target_scope.user.id}-demote-to-member"
             )
    end

    test "shows timeout preset controls and disables the timed-out user's composer", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      target_scope =
        %{username: "timed_out_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope, "member")

      {:ok, owner_view, _html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(
               owner_view,
               "#workspace-member-#{target_scope.user.id}-timeout-5-minutes"
             )

      owner_view
      |> element("#workspace-member-#{target_scope.user.id}-timeout-5-minutes")
      |> render_click()

      assert has_element?(owner_view, "#workspace-member-#{target_scope.user.id}-remove-timeout")

      target_conn = build_conn() |> log_in_user(target_scope.user)

      {:ok, target_view, _html} =
        live(
          target_conn,
          ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
        )

      assert has_element?(target_view, "#message_content[disabled]")
      assert has_element?(target_view, "#message-composer-muted-feedback", "timed out")
    end

    test "kicks a member with a reason, removes them live, and redirects the kicked user", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      target_scope =
        %{username: "kick_target_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope, "member")

      {:ok, owner_view, _html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      target_conn = build_conn() |> log_in_user(target_scope.user)

      {:ok, target_view, _html} =
        live(
          target_conn,
          ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
        )

      assert has_element?(owner_view, "#workspace-member-#{target_scope.user.id}-kick")

      owner_view
      |> form("#workspace-member-#{target_scope.user.id}-kick-form", %{reason: "Repeated spam"})
      |> render_submit()

      assert_redirect(target_view, ~p"/workspaces")

      refute has_element?(owner_view, "#workspace-member-#{target_scope.user.id}")

      refute Repo.get_by(WorkspaceMembership,
               workspace_id: workspace.id,
               user_id: target_scope.user.id
             )

      assert {:ok, events} = Workspaces.list_audit_events(owner_scope, workspace.id)

      assert Enum.any?(
               events,
               &(&1.event_type == "member_kicked" and &1.reason == "Repeated spam")
             )
    end

    test "rejects a kick submitted without a reason", %{conn: owner_conn, scope: owner_scope} do
      target_scope =
        %{username: "kick_reason_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope, "member")

      {:ok, owner_view, _html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      html =
        owner_view
        |> form("#workspace-member-#{target_scope.user.id}-kick-form", %{reason: "   "})
        |> render_submit()

      assert html =~ "reason is required"
      assert has_element?(owner_view, "#workspace-member-#{target_scope.user.id}")

      assert Repo.get_by(WorkspaceMembership,
               workspace_id: workspace.id,
               user_id: target_scope.user.id
             )
    end

    test "bans a member with a reason, removes them live, and redirects the banned user", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      target_scope =
        %{username: "ban_target_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope, "member")

      {:ok, owner_view, _html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      target_conn = build_conn() |> log_in_user(target_scope.user)

      {:ok, target_view, _html} =
        live(
          target_conn,
          ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
        )

      assert has_element?(owner_view, "#workspace-member-#{target_scope.user.id}-ban")

      owner_view
      |> form("#workspace-member-#{target_scope.user.id}-ban-form", %{reason: "Persistent abuse"})
      |> render_submit()

      assert_redirect(target_view, ~p"/workspaces")

      refute has_element?(owner_view, "#workspace-member-#{target_scope.user.id}")

      refute Repo.get_by(WorkspaceMembership,
               workspace_id: workspace.id,
               user_id: target_scope.user.id
             )

      assert Workspaces.workspace_banned?(workspace.id, target_scope.user.id)

      assert {:ok, events} = Workspaces.list_audit_events(owner_scope, workspace.id)

      assert Enum.any?(
               events,
               &(&1.event_type == "member_banned" and &1.reason == "Persistent abuse")
             )
    end

    test "rejects a ban submitted without a reason", %{conn: owner_conn, scope: owner_scope} do
      target_scope =
        %{username: "ban_reason_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope, "member")

      {:ok, owner_view, _html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      html =
        owner_view
        |> form("#workspace-member-#{target_scope.user.id}-ban-form", %{reason: "   "})
        |> render_submit()

      assert html =~ "reason is required"
      assert has_element?(owner_view, "#workspace-member-#{target_scope.user.id}")

      assert Repo.get_by(WorkspaceMembership,
               workspace_id: workspace.id,
               user_id: target_scope.user.id
             )

      refute Workspaces.workspace_banned?(workspace.id, target_scope.user.id)
    end

    test "bans a member with a cleanup window and refreshes affected messages live", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      target_scope =
        %{username: "ban_cleanup_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope, "member")

      {:ok, message} =
        Chat.send_message(target_scope, workspace.default_channel_id, %{
          "content" => "cleanup me"
        })

      {:ok, owner_view, html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert html =~ "cleanup me"

      assert has_element?(
               owner_view,
               "#workspace-member-#{target_scope.user.id}-ban-form input[name='cleanup_window'][value='all']"
             )

      owner_view
      |> form("#workspace-member-#{target_scope.user.id}-ban-form", %{
        reason: "Persistent abuse",
        cleanup_window: "all"
      })
      |> render_submit()

      assert Repo.get(Message, message.id).deleted_at

      updated_html = render(owner_view)
      assert updated_html =~ "Message deleted"
      refute updated_html =~ "cleanup me"

      assert {:ok, events} = Workspaces.list_audit_events(owner_scope, workspace.id)
      ban_event = Enum.find(events, &(&1.event_type == "member_banned"))
      assert ban_event.metadata["cleanup_window"] == "all"
      assert ban_event.metadata["cleanup_message_count"] == 1
    end

    test "hides the all-messages cleanup option from admins in the ban form", %{
      conn: admin_conn,
      scope: admin_scope
    } do
      owner_scope =
        %{username: "ban_cleanup_owner"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      member_scope =
        %{username: "ban_cleanup_target"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, admin_scope, "admin")
      add_workspace_member!(workspace, member_scope, "member")

      {:ok, admin_view, _html} =
        live(admin_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(
               admin_view,
               "#workspace-member-#{member_scope.user.id}-ban-form input[name='cleanup_window'][value='24_hours']"
             )

      refute has_element?(
               admin_view,
               "#workspace-member-#{member_scope.user.id}-ban-form input[name='cleanup_window'][value='all']"
             )
    end

    test "renders durable members offline after workspace presence runtime loss", %{
      conn: conn,
      scope: member_scope
    } do
      other_scope =
        %{username: "runtime_loss_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(member_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, other_scope)

      other_live_view_pid = start_live_view_process()
      assert :ok = Chat.join_workspace_presence(other_scope, workspace.id, other_live_view_pid)
      workspace_pid = Runtime.workspace_presence_pid(workspace.id)
      assert is_pid(workspace_pid)

      ref = Process.monitor(workspace_pid)
      Process.exit(workspace_pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^workspace_pid, :killed}
      _ = :sys.get_state(DiscordClone.Chat.WorkspaceSupervisor)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#workspace-members-sidebar[aria-label='Workspace members']")

      assert has_element?(
               view,
               "#workspace-member-#{other_scope.user.id}[data-presence-state='offline']",
               "runtime_loss_member"
             )

      assert has_element?(
               view,
               "#workspace-member-#{other_scope.user.id} [data-member-status='offline']",
               "Offline"
             )
    end

    test "marks the current member online after entering a channel surface", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope =
        %{username: "presence_owner"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(
               view,
               "#workspace-member-#{member_scope.user.id}[data-presence-state='online']",
               member_scope.user.username
             )

      assert has_element?(
               view,
               "#workspace-member-#{member_scope.user.id} [data-member-status='online']",
               "Online"
             )

      assert has_element?(
               view,
               "#workspace-member-#{owner_scope.user.id}[data-presence-state='offline']",
               "presence_owner"
             )
    end

    test "marks another member online when they enter the same workspace without refresh", %{
      conn: conn,
      scope: receiver_scope
    } do
      sender_scope =
        %{username: "live_presence_sender"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(receiver_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, sender_scope)
      channel_path = ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
      sender_conn = build_conn() |> log_in_user(sender_scope.user)

      {:ok, receiver_view, _html} = live(conn, channel_path)

      assert has_element?(
               receiver_view,
               "#workspace-member-#{sender_scope.user.id}[data-presence-state='offline']",
               "live_presence_sender"
             )

      {:ok, _sender_view, _html} = live(sender_conn, channel_path)

      assert has_element?(
               receiver_view,
               "#workspace-member-#{sender_scope.user.id}[data-presence-state='online']",
               "live_presence_sender"
             )

      assert has_element?(
               receiver_view,
               "#workspace-member-#{sender_scope.user.id} [data-member-status='online']",
               "Online"
             )
    end

    test "marks another member offline when their last channel surface closes without refresh", %{
      conn: conn,
      scope: receiver_scope
    } do
      sender_scope =
        %{username: "live_presence_leaver"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(receiver_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, sender_scope)
      channel_path = ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
      sender_conn = build_conn() |> log_in_user(sender_scope.user)

      {:ok, receiver_view, _html} = live(conn, channel_path)
      :ok = Chat.subscribe_to_workspace_presence(receiver_scope, workspace.id)
      {:ok, sender_view, _html} = live(sender_conn, channel_path)

      assert_receive {:workspace_user_joined,
                      %{workspace_id: workspace_id, user_id: sender_user_id}}

      assert workspace_id == workspace.id
      assert sender_user_id == sender_scope.user.id

      assert has_element?(
               receiver_view,
               "#workspace-member-#{sender_scope.user.id}[data-presence-state='online']",
               "live_presence_leaver"
             )

      workspace_server = Runtime.workspace_presence_pid(workspace.id)
      _ = :sys.get_state(workspace_server)

      ref = Process.monitor(sender_view.pid)
      Process.flag(:trap_exit, true)
      Process.exit(sender_view.pid, :shutdown)
      assert_receive {:DOWN, ^ref, :process, _pid, :shutdown}
      _ = :sys.get_state(workspace_server)

      assert_receive {:workspace_user_left,
                      %{workspace_id: ^workspace_id, user_id: ^sender_user_id}}

      assert has_element?(
               receiver_view,
               "#workspace-member-#{sender_scope.user.id}[data-presence-state='offline']",
               "live_presence_leaver"
             )

      assert has_element?(
               receiver_view,
               "#workspace-member-#{sender_scope.user.id} [data-member-status='offline']",
               "Offline"
             )
    end

    test "keeps another member online until their final connected surface closes", %{
      conn: conn,
      scope: receiver_scope
    } do
      sender_scope =
        %{username: "multi_surface_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(receiver_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, sender_scope)
      channel_path = ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
      first_sender_conn = build_conn() |> log_in_user(sender_scope.user)
      second_sender_conn = build_conn() |> log_in_user(sender_scope.user)

      {:ok, receiver_view, _html} = live(conn, channel_path)
      :ok = Chat.subscribe_to_workspace_presence(receiver_scope, workspace.id)
      {:ok, first_sender_view, _html} = live(first_sender_conn, channel_path)

      assert_receive {:workspace_user_joined,
                      %{workspace_id: workspace_id, user_id: sender_user_id}}

      assert workspace_id == workspace.id
      assert sender_user_id == sender_scope.user.id

      {:ok, second_sender_view, _html} = live(second_sender_conn, channel_path)

      assert has_element?(
               receiver_view,
               "#workspace-member-#{sender_scope.user.id}[data-presence-state='online']",
               "multi_surface_member"
             )

      assert workspace_member_row_ids(receiver_view, sender_scope.user.id) == [
               "workspace-member-#{sender_scope.user.id}"
             ]

      workspace_server = Runtime.workspace_presence_pid(workspace.id)
      _ = :sys.get_state(workspace_server)

      Process.flag(:trap_exit, true)
      first_ref = Process.monitor(first_sender_view.pid)
      Process.exit(first_sender_view.pid, :shutdown)
      assert_receive {:DOWN, ^first_ref, :process, _pid, :shutdown}
      _ = :sys.get_state(workspace_server)

      assert has_element?(
               receiver_view,
               "#workspace-member-#{sender_scope.user.id}[data-presence-state='online']",
               "multi_surface_member"
             )

      assert workspace_member_row_ids(receiver_view, sender_scope.user.id) == [
               "workspace-member-#{sender_scope.user.id}"
             ]

      second_ref = Process.monitor(second_sender_view.pid)
      Process.exit(second_sender_view.pid, :shutdown)
      assert_receive {:DOWN, ^second_ref, :process, _pid, :shutdown}
      _ = :sys.get_state(workspace_server)

      assert_receive {:workspace_user_left,
                      %{workspace_id: ^workspace_id, user_id: ^sender_user_id}}

      assert has_element?(
               receiver_view,
               "#workspace-member-#{sender_scope.user.id}[data-presence-state='offline']",
               "multi_surface_member"
             )

      assert has_element?(
               receiver_view,
               "#workspace-member-#{sender_scope.user.id} [data-member-status='offline']",
               "Offline"
             )
    end

    test "keeps another member online while they switch channels in the same workspace", %{
      conn: conn,
      scope: receiver_scope
    } do
      sender_scope =
        %{username: "channel_switch_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(receiver_scope, %{name: "Foundry"})

      {:ok, other_channel} =
        Workspaces.create_channel(receiver_scope, workspace.id, %{name: "Ops"})

      add_workspace_member!(workspace, sender_scope)

      first_channel_path =
        ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"

      other_channel_path = ~p"/workspaces/#{workspace.id}/channels/#{other_channel.id}"
      sender_conn = build_conn() |> log_in_user(sender_scope.user)

      {:ok, receiver_view, _html} = live(conn, first_channel_path)
      :ok = Chat.subscribe_to_workspace_presence(receiver_scope, workspace.id)
      {:ok, sender_view, _html} = live(sender_conn, first_channel_path)

      assert_receive {:workspace_user_joined, %{workspace_id: workspace_id, user_id: user_id}}

      assert workspace_id == workspace.id
      assert user_id == sender_scope.user.id

      assert has_element?(
               receiver_view,
               "#workspace-member-#{sender_scope.user.id}[data-presence-state='online']",
               "channel_switch_member"
             )

      workspace_id = workspace.id
      sender_user_id = sender_scope.user.id

      {:ok, _sender_view, _html} =
        sender_view
        |> element("#channel-#{other_channel.id} a")
        |> render_click()
        |> follow_redirect(sender_conn, other_channel_path)

      workspace_server = Runtime.workspace_presence_pid(workspace.id)
      _ = :sys.get_state(workspace_server)

      refute_receive {:workspace_user_left,
                      %{workspace_id: ^workspace_id, user_id: ^sender_user_id}},
                     50

      assert has_element?(
               receiver_view,
               "#workspace-member-#{sender_scope.user.id}[data-presence-state='online']",
               "channel_switch_member"
             )
    end

    test "keeps member rows stable when duplicate presence events arrive", %{
      conn: conn,
      scope: receiver_scope
    } do
      other_scope =
        %{username: "stable_presence_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(receiver_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, other_scope)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      joined_event =
        {:workspace_user_joined, %{workspace_id: workspace.id, user_id: other_scope.user.id}}

      send(view.pid, joined_event)
      send(view.pid, joined_event)

      assert has_element?(
               view,
               "#workspace-member-#{other_scope.user.id}[data-presence-state='online']",
               "stable_presence_member"
             )

      assert workspace_member_row_ids(view, other_scope.user.id) == [
               "workspace-member-#{other_scope.user.id}"
             ]

      left_event =
        {:workspace_user_left, %{workspace_id: workspace.id, user_id: other_scope.user.id}}

      send(view.pid, left_event)
      send(view.pid, left_event)

      assert has_element?(
               view,
               "#workspace-member-#{other_scope.user.id}[data-presence-state='offline']",
               "stable_presence_member"
             )

      assert workspace_member_row_ids(view, other_scope.user.id) == [
               "workspace-member-#{other_scope.user.id}"
             ]
    end

    test "renders persisted channel messages with author and timestamp", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "Hello <strong>there</strong>",
          ~U[2026-06-19 10:30:00Z]
        )

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#message-#{message.id}")
      assert has_element?(view, "#message-#{message.id}-author", scope.user.username)

      assert has_element?(
               view,
               "#message-#{message.id} time[datetime='2026-06-19T10:30:00.000000Z']"
             )

      assert has_element?(view, "#message-#{message.id}-content", message.content)
    end

    test "renders supported emoji shortcodes in persisted channel messages", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "Ship it :thumbsup:",
          ~U[2026-06-19 10:30:00Z]
        )

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert Repo.get!(Message, message.id).content == "Ship it :thumbsup:"
      assert has_element?(view, "#message-#{message.id}-content", "Ship it 👍")
    end

    test "leaves unknown emoji shortcodes unchanged in channel messages", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "Launch :rocketship:",
          ~U[2026-06-19 10:30:00Z]
        )

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#message-#{message.id}-content", "Launch :rocketship:")
    end

    test "renders reaction pills under persisted channel messages", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "tiny celebration",
          ~U[2026-06-19 10:30:00Z]
        )

      assert {:ok, _reaction} = Chat.toggle_reaction(scope, message.id, "👍")

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#message-#{message.id}-reactions")

      assert has_element?(
               view,
               "#message-#{message.id}-reaction-0[aria-label='👍 reaction, 1 reaction, you reacted']",
               "👍 1"
             )
    end

    test "keeps reaction summaries visible after page refresh", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      channel_path = ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"

      message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "refresh proof",
          ~U[2026-06-19 10:30:00Z]
        )

      assert {:ok, _reaction} = Chat.toggle_reaction(scope, message.id, "👍")

      {:ok, first_view, _html} = live(conn, channel_path)

      assert has_element?(
               first_view,
               "#message-#{message.id}-reaction-0[aria-label='👍 reaction, 1 reaction, you reacted']",
               "👍 1"
             )

      {:ok, refreshed_view, _html} = live(conn, channel_path)

      assert has_element?(
               refreshed_view,
               "#message-#{message.id}-reaction-0[aria-label='👍 reaction, 1 reaction, you reacted']",
               "👍 1"
             )
    end

    test "does not render empty reaction chrome for messages without reactions", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "plain update",
          ~U[2026-06-19 10:30:00Z]
        )

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#message-#{message.id}-content", "plain update")
      refute has_element?(view, "#message-#{message.id}-reactions")
      refute has_element?(view, "#message-#{message.id}-reaction-0")
    end

    test "renders another member's reaction without the current user state", %{
      conn: conn,
      scope: scope
    } do
      other_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      add_workspace_member!(workspace, other_scope)

      message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "someone noticed",
          ~U[2026-06-19 10:30:00Z]
        )

      assert {:ok, _reaction} = Chat.toggle_reaction(other_scope, message.id, "❤️")

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(
               view,
               "#message-#{message.id}-reaction-0[data-current-user-reacted='false'][aria-label='❤️ reaction, 1 reaction, you have not reacted']",
               "❤️ 1"
             )
    end

    test "renders reaction pills under compact grouped message rows", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      first_message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "first thought",
          ~U[2026-06-19 10:30:00Z]
        )

      second_message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "follow-up thought",
          ~U[2026-06-19 10:31:00Z]
        )

      assert {:ok, _reaction} = Chat.toggle_reaction(scope, second_message.id, "👀")

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#message-#{first_message.id}[data-message-row='full']")
      assert has_element?(view, "#message-#{second_message.id}[data-message-row='compact']")

      assert has_element?(
               view,
               "#message-#{first_message.id}[data-message-id='#{first_message.id}'][data-message-seq='#{first_message.seq}'][data-visible-read-observe='true']"
             )

      assert has_element?(
               view,
               "#message-#{second_message.id}-body #message-#{second_message.id}-reaction-0[data-current-user-reacted='true']",
               "👀 1"
             )
    end

    test "toggles a reaction from the fixed message palette", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "please react",
          ~U[2026-06-19 10:30:00Z]
        )

      message_id = message.id

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(
               view,
               "#message-#{message_id}-reaction-option-0[aria-label='React with 👍 to message']",
               "👍"
             )

      assert has_element?(
               view,
               "#message-#{message_id}-reaction-option-1[aria-label='React with ❤️ to message']",
               "❤️"
             )

      assert has_element?(
               view,
               "#message-#{message_id}-reaction-option-2[aria-label='React with 😂 to message']",
               "😂"
             )

      assert has_element?(
               view,
               "#message-#{message_id}-reaction-option-3[aria-label='React with 🎉 to message']",
               "🎉"
             )

      assert has_element?(
               view,
               "#message-#{message_id}-reaction-option-4[aria-label='React with 👀 to message']",
               "👀"
             )

      refute has_element?(
               view,
               "#message-#{message_id}-reaction-palette[class*='group-focus-within']"
             )

      view
      |> element("#message-#{message_id}-reaction-option-0")
      |> render_click()

      assert has_element?(
               view,
               "#message-#{message_id}-reaction-0[data-current-user-reacted='true'][aria-label='👍 reaction, 1 reaction, you reacted']",
               "👍 1"
             )

      assert {:ok, %{^message_id => [%{emoji: "👍", count: 1, reacted?: true}]}} =
               Chat.list_reaction_summaries(scope, [message_id])

      view
      |> element("#message-#{message_id}-reaction-option-0")
      |> render_click()

      refute has_element?(view, "#message-#{message_id}-reactions")
      refute has_element?(view, "#message-#{message_id}-reaction-0")

      assert {:ok, %{}} = Chat.list_reaction_summaries(scope, [message_id])
    end

    test "refreshes another connected viewer after a reaction changes", %{
      conn: viewer_conn,
      scope: viewer_scope
    } do
      sender_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(sender_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, viewer_scope)

      message =
        insert_message!(
          workspace.default_channel_id,
          sender_scope.user.id,
          "please react live",
          ~U[2026-06-19 10:30:00Z]
        )

      channel_path = ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
      sender_conn = build_conn() |> log_in_user(sender_scope.user)

      {:ok, viewer_view, _html} = live(viewer_conn, channel_path)
      {:ok, sender_view, _html} = live(sender_conn, channel_path)

      refute has_element?(viewer_view, "#message-#{message.id}-reactions")

      sender_view
      |> element("#message-#{message.id}-reaction-option-0")
      |> render_click()

      _ = :sys.get_state(viewer_view.pid)

      assert has_element?(
               viewer_view,
               "#message-#{message.id}-reaction-0[data-current-user-reacted='false'][aria-label='👍 reaction, 1 reaction, you have not reacted']",
               "👍 1"
             )

      assert has_element?(viewer_view, "#message-#{message.id}[data-message-row='full']")
      assert has_element?(viewer_view, "#message-#{message.id}-content", "please react live")
    end

    test "refreshes connected viewers with a deleted message placeholder and clears reactions", %{
      conn: viewer_conn,
      scope: viewer_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, viewer_scope)

      message =
        insert_message!(
          workspace.default_channel_id,
          viewer_scope.user.id,
          "remove this live",
          ~U[2026-06-19 10:30:00Z]
        )

      assert {:ok, _reaction} = Chat.toggle_reaction(owner_scope, message.id, "👍")

      channel_path = ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
      {:ok, viewer_view, _html} = live(viewer_conn, channel_path)

      assert has_element?(viewer_view, "#message-#{message.id}-content", "remove this live")
      assert has_element?(viewer_view, "#message-#{message.id}-reaction-0", "👍 1")

      assert {:ok, _deleted_message} = Chat.delete_message(owner_scope, message.id)
      _ = :sys.get_state(viewer_view.pid)

      assert has_element?(
               viewer_view,
               "#message-#{message.id}-deleted-placeholder",
               "Message deleted"
             )

      refute has_element?(viewer_view, "#message-#{message.id}-content", "remove this live")
      refute has_element?(viewer_view, "#message-#{message.id}-reaction-0")
      refute has_element?(viewer_view, "#message-#{message.id}-reaction-option-0")
    end

    test "keeps the full message experience working together", %{
      conn: viewer_conn,
      scope: viewer_scope
    } do
      sender_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(sender_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, viewer_scope)
      channel_id = workspace.default_channel_id

      first_message =
        insert_message!(
          channel_id,
          sender_scope.user.id,
          "Ship it :thumbsup:",
          ~U[2026-06-19 10:30:00Z]
        )

      second_message =
        insert_message!(
          channel_id,
          sender_scope.user.id,
          "Launch :rocketship:",
          ~U[2026-06-19 10:31:00Z]
        )

      channel_path = ~p"/workspaces/#{workspace.id}/channels/#{channel_id}"
      sender_conn = build_conn() |> log_in_user(sender_scope.user)

      {:ok, viewer_view, _html} = live(viewer_conn, channel_path)
      {:ok, sender_view, _html} = live(sender_conn, channel_path)

      assert has_element?(viewer_view, "#channel-message-surface")
      assert has_element?(viewer_view, "#channel-messages[phx-hook='ChannelMessages']")
      assert has_element?(viewer_view, "#message-composer-form")
      assert has_element?(viewer_view, "#message-composer-shell")
      refute has_element?(viewer_view, "#message-composer-submit")
      assert has_element?(viewer_view, "#message-#{first_message.id}[data-message-row='full']")
      assert has_element?(viewer_view, "#message-#{first_message.id}-avatar")
      assert has_element?(viewer_view, "#message-#{first_message.id}-header")
      assert has_element?(viewer_view, "#message-#{first_message.id}-content", "Ship it 👍")

      assert has_element?(
               viewer_view,
               "#message-#{second_message.id}[data-message-row='compact']"
             )

      assert has_element?(viewer_view, "#message-#{second_message.id}-spacer[aria-hidden='true']")

      assert has_element?(
               viewer_view,
               "#message-#{second_message.id}-content",
               "Launch :rocketship:"
             )

      refute has_element?(viewer_view, "#message-#{second_message.id}-avatar")
      refute has_element?(viewer_view, "#message-#{second_message.id}-reactions")

      assert has_element?(
               sender_view,
               "#message-#{second_message.id}-reaction-option-0[aria-label='React with 👍 to message']",
               "👍"
             )

      sender_view
      |> element("#message-#{second_message.id}-reaction-option-0")
      |> render_click()

      _ = :sys.get_state(viewer_view.pid)

      assert has_element?(
               viewer_view,
               "#message-#{second_message.id}-reaction-0[data-current-user-reacted='false'][aria-label='👍 reaction, 1 reaction, you have not reacted']",
               "👍 1"
             )

      viewer_view
      |> element("#message-#{second_message.id}-reaction-option-0")
      |> render_click()

      assert has_element?(
               viewer_view,
               "#message-#{second_message.id}-reaction-0[data-current-user-reacted='true'][aria-label='👍 reaction, 2 reactions, you reacted']",
               "👍 2"
             )

      viewer_view
      |> element("#message-#{second_message.id}-reaction-option-0")
      |> render_click()

      assert has_element?(
               viewer_view,
               "#message-#{second_message.id}-reaction-0[data-current-user-reacted='false'][aria-label='👍 reaction, 1 reaction, you have not reacted']",
               "👍 1"
             )

      {:ok, refreshed_view, _html} = live(viewer_conn, channel_path)

      assert has_element?(
               refreshed_view,
               "#message-#{second_message.id}-reaction-0[data-current-user-reacted='false'][aria-label='👍 reaction, 1 reaction, you have not reacted']",
               "👍 1"
             )
    end

    test "rejects invalid reaction payloads sent to the palette event", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "tamper-resistant",
          ~U[2026-06-19 10:30:00Z]
        )

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      render_click(view, "toggle_reaction", %{
        "message-id" => "not-a-uuid",
        "emoji" => "👍❤️"
      })

      assert {:ok, %{}} = Chat.list_reaction_summaries(scope, [message.id])
    end

    test "renders persisted channel messages in a stable anchored row layout", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      content = "first line\n#{String.duplicate("unbroken", 24)} 😀😀😀"

      message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          content,
          ~U[2026-06-19 10:30:00Z]
        )

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#message-#{message.id}[data-message-row='full']")

      assert has_element?(
               view,
               "#message-#{message.id}-avatar",
               scope.user.username |> String.first() |> String.upcase()
             )

      assert has_element?(view, "#message-#{message.id}-body")
      assert has_element?(view, "#message-#{message.id}-header")
      assert has_element?(view, "#message-#{message.id}-author", scope.user.username)

      assert has_element?(
               view,
               "#message-#{message.id}-timestamp[datetime='2026-06-19T10:30:00.000000Z']"
             )

      content_text =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> then(& &1["#message-#{message.id}-content"])
        |> LazyHTML.text()
        |> String.trim()

      assert content_text == content
    end

    test "groups consecutive same-author messages within five minutes", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      first_message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "first thought",
          ~U[2026-06-19 10:30:00Z]
        )

      second_message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "follow-up thought",
          ~U[2026-06-19 10:33:00Z]
        )

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#message-#{first_message.id}[data-message-row='full']")
      assert has_element?(view, "#message-#{first_message.id}-avatar")
      assert has_element?(view, "#message-#{first_message.id}-header")

      assert has_element?(view, "#message-#{second_message.id}[data-message-row='compact']")
      assert has_element?(view, "#message-#{second_message.id}-spacer[aria-hidden='true']")
      assert has_element?(view, "#message-#{second_message.id}-body")
      assert has_element?(view, "#message-#{second_message.id}-content", "follow-up thought")
      refute has_element?(view, "#message-#{second_message.id}-avatar")
      refute has_element?(view, "#message-#{second_message.id}-header")
    end

    test "keeps polished row and composer surfaces on stable selectors", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      first_message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "anchored thought",
          ~U[2026-06-19 10:30:00Z]
        )

      second_message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "connected follow-up",
          ~U[2026-06-19 10:31:00Z]
        )

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(
               view,
               "#message-#{first_message.id}[data-message-row='full'][data-hover-surface='message-row']"
             )

      assert has_element?(
               view,
               "#message-#{second_message.id}[data-message-row='compact'][data-hover-surface='message-row']"
             )

      assert has_element?(view, "#message-composer-panel #message-composer-form")
      assert has_element?(view, "#message-composer-shell #message_content")
      refute has_element?(view, "#message-composer-submit")
    end

    test "starts a full message row when the speaker changes", %{
      conn: conn,
      scope: first_scope
    } do
      second_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(first_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, second_scope)

      first_message =
        insert_message!(
          workspace.default_channel_id,
          first_scope.user.id,
          "first speaker",
          ~U[2026-06-19 10:30:00Z]
        )

      second_message =
        insert_message!(
          workspace.default_channel_id,
          second_scope.user.id,
          "second speaker",
          ~U[2026-06-19 10:31:00Z]
        )

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#message-#{first_message.id}[data-message-row='full']")
      assert has_element?(view, "#message-#{second_message.id}[data-message-row='full']")
      assert has_element?(view, "#message-#{second_message.id}-avatar")
      assert has_element?(view, "#message-#{second_message.id}-header")

      assert has_element?(
               view,
               "#message-#{second_message.id}-author",
               second_scope.user.username
             )
    end

    test "starts a full message row when the same speaker is outside the grouping window", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      first_message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "morning note",
          ~U[2026-06-19 10:30:00Z]
        )

      second_message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "later note",
          ~U[2026-06-19 10:36:00Z]
        )

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#message-#{first_message.id}[data-message-row='full']")
      assert has_element?(view, "#message-#{second_message.id}[data-message-row='full']")
      assert has_element?(view, "#message-#{second_message.id}-avatar")
      assert has_element?(view, "#message-#{second_message.id}-header")

      assert has_element?(
               view,
               "#message-#{second_message.id}-timestamp[datetime='2026-06-19T10:36:00.000000Z']"
             )
    end

    test "renders persisted messages after channel runtime loss", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id

      first_message =
        insert_message!(
          channel_id,
          scope.user.id,
          "before runtime loss",
          ~U[2026-06-19 10:30:00Z]
        )

      assert {:ok, first_pid} = Chat.ensure_channel_runtime(scope, channel_id)
      ref = Process.monitor(first_pid)
      Process.exit(first_pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^first_pid, :killed}
      _ = :sys.get_state(DiscordClone.Chat.ChannelSupervisor)

      second_message =
        insert_message!(
          channel_id,
          scope.user.id,
          "after runtime loss",
          ~U[2026-06-19 10:31:00Z]
        )

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/channels/#{channel_id}")

      assert has_element?(view, "#message-#{first_message.id}-content", "before runtime loss")
      assert has_element?(view, "#message-#{second_message.id}-content", "after runtime loss")

      replacement_pid = Runtime.channel_pid(channel_id)
      assert is_pid(replacement_pid)
      assert replacement_pid != first_pid
    end

    test "renders persisted reaction summaries after channel runtime loss", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id

      message =
        insert_message!(
          channel_id,
          scope.user.id,
          "reaction before runtime loss",
          ~U[2026-06-19 10:30:00Z]
        )

      assert {:ok, _reaction} = Chat.toggle_reaction(scope, message.id, "👍")

      assert {:ok, first_pid} = Chat.ensure_channel_runtime(scope, channel_id)
      ref = Process.monitor(first_pid)
      Process.exit(first_pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^first_pid, :killed}
      _ = :sys.get_state(DiscordClone.Chat.ChannelSupervisor)

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/channels/#{channel_id}")

      assert has_element?(
               view,
               "#message-#{message.id}-reaction-0[aria-label='👍 reaction, 1 reaction, you reacted']",
               "👍 1"
             )

      replacement_pid = Runtime.channel_pid(channel_id)
      assert is_pid(replacement_pid)
      assert replacement_pid != first_pid
    end

    test "sends a message into the current channel stream and clears the composer", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> form("#message-composer-form",
        message: %{
          content: "  hello from liveview  "
        }
      )
      |> render_submit()

      message = Repo.one!(Message)

      assert message.content == "hello from liveview"
      assert message.channel_id == workspace.default_channel_id
      assert message.user_id == scope.user.id
      assert has_element?(view, "#message-#{message.id}")
      assert has_element?(view, "#message-#{message.id}[data-message-row='full']")
      assert has_element?(view, "#message-#{message.id}-author", scope.user.username)
      assert has_element?(view, "#message-#{message.id}-content", "hello from liveview")
      refute has_element?(view, "#message_content[value='  hello from liveview  ']")

      assert_push_event(view, "clear_message_composer", %{input_id: "message_content"})

      assert_push_event(view, "scroll_channel_messages_to_bottom", %{
        container_id: "channel-messages"
      })

      _ = :sys.get_state(view.pid)

      assert has_element?(view, "#message-#{message.id}[data-message-row='full']")
      assert has_element?(view, "#message-#{message.id}-author", scope.user.username)
    end

    test "ignores blank message submits without showing composer errors", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> form("#message-composer-form", message: %{content: "   "})
      |> render_submit()

      assert Repo.aggregate(Message, :count) == 0
      assert has_element?(view, "#message-composer-form")
      refute has_element?(view, "#message_content.input-error")
      refute has_element?(view, "#message-composer-form", "can't be blank")
      refute_push_event(view, "clear_message_composer", %{input_id: _input_id})
      refute_push_event(view, "scroll_channel_messages_to_bottom", %{container_id: _container_id})
    end

    test "groups a sent live message with the current newest same-author message", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      existing_message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "already thinking",
          DateTime.add(DateTime.utc_now(:second), -60, :second)
        )

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> form("#message-composer-form", message: %{content: "same thread"})
      |> render_submit()

      sent_message =
        Message
        |> order_by([message], desc: message.seq)
        |> limit(1)
        |> Repo.one!()

      assert has_element?(view, "#message-#{existing_message.id}[data-message-row='full']")
      assert has_element?(view, "#message-#{sent_message.id}[data-message-row='compact']")
      assert has_element?(view, "#message-#{sent_message.id}-spacer[aria-hidden='true']")
      refute has_element?(view, "#message-#{sent_message.id}-header")
    end

    test "renders the sender's saved message exactly once", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> form("#message-composer-form", message: %{content: "one local copy"})
      |> render_submit()

      message = Repo.one!(Message)

      message_ids =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> then(& &1["#channel-messages > article"])
        |> LazyHTML.attribute("id")

      assert message_ids == ["message-#{message.id}"]
      assert has_element?(view, "#message-#{message.id}-content", "one local copy")
    end

    test "keeps invalid message content visible with field errors", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      content = String.duplicate("a", 4_001)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> form("#message-composer-form", message: %{content: content})
      |> render_submit()

      assert Repo.aggregate(Message, :count) == 0
      assert has_element?(view, "#message-composer-form")
      assert has_element?(view, "#message_content.input-error[value='#{content}']")

      assert has_element?(
               view,
               "#message-composer-form",
               "should be at most 4000 character(s)"
             )

      refute_push_event(view, "clear_message_composer", %{input_id: _input_id})
    end

    test "shows a sent message after reopening the channel page", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> form("#message-composer-form", message: %{content: "reload proof"})
      |> render_submit()

      message = Repo.one!(Message)

      {:ok, reloaded_view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(reloaded_view, "#message-#{message.id}")
      assert has_element?(reloaded_view, "#message-#{message.id}-content", "reload proof")
    end

    test "delivers sent messages live to another member in the same channel", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)
      channel_path = ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"

      existing_message =
        insert_message!(
          workspace.default_channel_id,
          member_scope.user.id,
          "already here",
          ~U[2026-06-19 10:00:00Z]
        )

      sender_conn = build_conn() |> log_in_user(owner_scope.user)

      {:ok, receiver_view, _html} = live(conn, channel_path)
      {:ok, sender_view, _html} = live(sender_conn, channel_path)

      sender_view
      |> form("#message-composer-form", message: %{content: "live hello"})
      |> render_submit()

      message =
        Message
        |> order_by([message], desc: message.seq)
        |> limit(1)
        |> Repo.one!()

      assert has_element?(receiver_view, "#message-#{message.id}")
      assert has_element?(receiver_view, "#message-#{message.id}[data-message-row='full']")

      assert has_element?(
               receiver_view,
               "#message-#{message.id}-author",
               owner_scope.user.username
             )

      assert has_element?(receiver_view, "#message-#{message.id}-content", "live hello")

      assert_push_event(receiver_view, "scroll_channel_messages_to_bottom", %{
        container_id: "channel-messages"
      })

      message_ids =
        receiver_view
        |> render()
        |> LazyHTML.from_fragment()
        |> then(& &1["#channel-messages > article"])
        |> LazyHTML.attribute("id")

      assert List.last(message_ids) == "message-#{message.id}"
      assert "message-#{existing_message.id}" in message_ids
    end

    test "keeps selected-channel live messages unread without duplicating timeline entries", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)
      :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)

      channel_path = ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
      sender_conn = build_conn() |> log_in_user(owner_scope.user)

      {:ok, receiver_view, _html} = live(conn, channel_path)
      {:ok, sender_view, _html} = live(sender_conn, channel_path)

      sender_view
      |> form("#message-composer-form", message: %{content: "read while open"})
      |> render_submit()

      message =
        Message
        |> order_by([message], desc: message.seq)
        |> limit(1)
        |> Repo.one!()

      _ = :sys.get_state(receiver_view.pid)

      assert has_element?(receiver_view, "#message-#{message.id}-content", "read while open")
      refute has_element?(receiver_view, "#channel-#{workspace.default_channel_id}-unread-badge")

      assert Chat.list_unread_counts(member_scope, workspace.id) ==
               {:ok, %{workspace.default_channel_id => 1}}

      message_ids =
        receiver_view
        |> render()
        |> LazyHTML.from_fragment()
        |> then(& &1["#channel-messages > article"])
        |> LazyHTML.attribute("id")

      assert Enum.count(message_ids, &(&1 == "message-#{message.id}")) == 1
    end

    test "does not deliver live messages across channels in the same workspace", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      {:ok, other_channel} = Workspaces.create_channel(owner_scope, workspace.id, %{name: "ops"})
      add_workspace_member!(workspace, member_scope)

      selected_channel_path =
        ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"

      other_channel_path = ~p"/workspaces/#{workspace.id}/channels/#{other_channel.id}"
      sender_conn = build_conn() |> log_in_user(owner_scope.user)

      {:ok, selected_channel_view, _html} = live(conn, selected_channel_path)
      {:ok, other_channel_view, _html} = live(conn, other_channel_path)
      {:ok, sender_view, _html} = live(sender_conn, selected_channel_path)

      sender_view
      |> form("#message-composer-form", message: %{content: "only planning"})
      |> render_submit()

      message =
        Message
        |> order_by([message], desc: message.seq)
        |> limit(1)
        |> Repo.one!()

      assert has_element?(
               selected_channel_view,
               "#message-#{message.id}-content",
               "only planning"
             )

      refute has_element?(other_channel_view, "#message-#{message.id}")

      other_channel_message_ids =
        other_channel_view
        |> render()
        |> LazyHTML.from_fragment()
        |> then(& &1["#channel-messages > article"])
        |> LazyHTML.attribute("id")

      refute "message-#{message.id}" in other_channel_message_ids
    end

    test "recovers live-delivered messages from Postgres after receiver refresh", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)
      channel_path = ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
      sender_conn = build_conn() |> log_in_user(owner_scope.user)

      {:ok, receiver_view, _html} = live(conn, channel_path)
      {:ok, sender_view, _html} = live(sender_conn, channel_path)

      sender_view
      |> form("#message-composer-form", message: %{content: "refresh after live"})
      |> render_submit()

      message =
        Message
        |> order_by([message], desc: message.seq)
        |> limit(1)
        |> Repo.one!()

      assert has_element?(receiver_view, "#message-#{message.id}-content", "refresh after live")

      {:ok, refreshed_receiver_view, _html} = live(conn, channel_path)

      assert has_element?(
               refreshed_receiver_view,
               "#message-#{message.id}-content",
               "refresh after live"
             )
    end

    test "keeps receiver composer state when a live message arrives", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)
      channel_path = ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
      sender_conn = build_conn() |> log_in_user(owner_scope.user)
      too_long_content = String.duplicate("draft", 801)

      {:ok, receiver_view, _html} = live(conn, channel_path)
      {:ok, sender_view, _html} = live(sender_conn, channel_path)

      receiver_view
      |> form("#message-composer-form", message: %{content: too_long_content})
      |> render_submit()

      assert has_element?(
               receiver_view,
               "#message_content.input-error[value='#{too_long_content}']"
             )

      sender_view
      |> form("#message-composer-form", message: %{content: "while you type"})
      |> render_submit()

      message =
        Message
        |> order_by([message], desc: message.seq)
        |> limit(1)
        |> Repo.one!()

      assert has_element?(receiver_view, "#message-#{message.id}-content", "while you type")

      assert has_element?(
               receiver_view,
               "#message_content.input-error[value='#{too_long_content}']"
             )
    end

    test "shows another member typing in the same channel and hides self typing", %{
      conn: conn,
      scope: receiver_scope
    } do
      sender_scope =
        %{username: "typing_sender"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(receiver_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, sender_scope)
      channel_path = ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
      sender_conn = build_conn() |> log_in_user(sender_scope.user)

      {:ok, receiver_view, _html} = live(conn, channel_path)
      {:ok, sender_view, _html} = live(sender_conn, channel_path)

      sender_view
      |> form("#message-composer-form", message: %{content: "typing now"})
      |> render_change()

      assert has_element?(
               receiver_view,
               "#channel-typing-indicator [data-typing-user-id='#{sender_scope.user.id}']",
               "typing_sender"
             )

      sender_view
      |> form("#message-composer-form", message: %{content: "still typing"})
      |> render_change()

      refute has_element?(
               sender_view,
               "#channel-typing-indicator [data-typing-user-id='#{sender_scope.user.id}']"
             )

      sender_view
      |> form("#message-composer-form", message: %{content: ""})
      |> render_change()

      refute has_element?(
               receiver_view,
               "#channel-typing-indicator [data-typing-user-id='#{sender_scope.user.id}']"
             )

      sender_view
      |> form("#message-composer-form", message: %{content: "typing before submit"})
      |> render_change()

      assert has_element?(
               receiver_view,
               "#channel-typing-indicator [data-typing-user-id='#{sender_scope.user.id}']",
               "typing_sender"
             )

      sender_view
      |> form("#message-composer-form", message: %{content: "sent after typing"})
      |> render_submit()

      refute has_element?(
               receiver_view,
               "#channel-typing-indicator [data-typing-user-id='#{sender_scope.user.id}']"
             )
    end

    test "does not show typing indicators across channels in the same workspace", %{
      conn: conn,
      scope: receiver_scope
    } do
      sender_scope =
        %{username: "typing_sender"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(receiver_scope, %{name: "Foundry"})

      {:ok, other_channel} =
        Workspaces.create_channel(receiver_scope, workspace.id, %{name: "ops"})

      add_workspace_member!(workspace, sender_scope)

      default_channel_path =
        ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"

      other_channel_path = ~p"/workspaces/#{workspace.id}/channels/#{other_channel.id}"
      sender_conn = build_conn() |> log_in_user(sender_scope.user)

      {:ok, receiver_view, _html} = live(conn, default_channel_path)
      {:ok, other_channel_view, _html} = live(conn, other_channel_path)
      {:ok, sender_view, _html} = live(sender_conn, default_channel_path)

      sender_view
      |> form("#message-composer-form", message: %{content: "typing in general"})
      |> render_change()

      assert has_element?(
               receiver_view,
               "#channel-typing-indicator [data-typing-user-id='#{sender_scope.user.id}']",
               "typing_sender"
             )

      refute has_element?(
               other_channel_view,
               "#channel-typing-indicator [data-typing-user-id='#{sender_scope.user.id}']"
             )
    end

    test "removes another member typing indicator after runtime expiry", %{
      conn: conn,
      scope: receiver_scope
    } do
      sender_scope =
        %{username: "typing_sender"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(receiver_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, sender_scope)
      channel_id = workspace.default_channel_id
      channel_path = ~p"/workspaces/#{workspace.id}/channels/#{channel_id}"
      sender_conn = build_conn() |> log_in_user(sender_scope.user)
      sender_id = sender_scope.user.id

      assert :ok = Chat.subscribe_to_channel_typing(receiver_scope, channel_id)

      {:ok, receiver_view, _html} = live(conn, channel_path)
      {:ok, sender_view, _html} = live(sender_conn, channel_path)

      sender_view
      |> form("#message-composer-form", message: %{content: "typing now"})
      |> render_change()

      assert has_element?(
               receiver_view,
               "#channel-typing-indicator [data-typing-user-id='#{sender_id}']",
               "typing_sender"
             )

      assert pid = Runtime.channel_pid(channel_id)
      assert %{typing_users: %{^sender_id => deadline}} = :sys.get_state(pid)

      send(pid, {:typing_expired, sender_id, deadline})

      assert_receive {:typing_stopped, %{channel_id: ^channel_id, user_id: ^sender_id}}

      refute has_element?(
               receiver_view,
               "#channel-typing-indicator [data-typing-user-id='#{sender_id}']"
             )
    end

    test "clears stale typing indicators after channel runtime loss", %{
      conn: conn,
      scope: receiver_scope
    } do
      sender_scope =
        %{username: "typing_sender"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(receiver_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, sender_scope)
      channel_id = workspace.default_channel_id
      channel_path = ~p"/workspaces/#{workspace.id}/channels/#{channel_id}"
      sender_conn = build_conn() |> log_in_user(sender_scope.user)
      sender_id = sender_scope.user.id

      {:ok, receiver_view, _html} = live(conn, channel_path)
      {:ok, sender_view, _html} = live(sender_conn, channel_path)

      sender_view
      |> form("#message-composer-form", message: %{content: "typing before crash"})
      |> render_change()

      assert has_element?(
               receiver_view,
               "#channel-typing-indicator [data-typing-user-id='#{sender_id}']",
               "typing_sender"
             )

      runtime_pid = Runtime.channel_pid(channel_id)
      ref = Process.monitor(runtime_pid)
      Process.exit(runtime_pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^runtime_pid, :killed}

      refute has_element?(
               receiver_view,
               "#channel-typing-indicator [data-typing-user-id='#{sender_id}']"
             )

      sender_view
      |> form("#message-composer-form", message: %{content: "typing after restart"})
      |> render_change()

      assert has_element?(
               receiver_view,
               "#channel-typing-indicator [data-typing-user-id='#{sender_id}']",
               "typing_sender"
             )

      restarted_runtime_pid = Runtime.channel_pid(channel_id)
      restarted_ref = Process.monitor(restarted_runtime_pid)
      Process.exit(restarted_runtime_pid, :kill)
      assert_receive {:DOWN, ^restarted_ref, :process, ^restarted_runtime_pid, :killed}

      refute has_element?(
               receiver_view,
               "#channel-typing-indicator [data-typing-user-id='#{sender_id}']"
             )
    end

    test "renders scroll-edge history controls without the old manual load button", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      for index <- 1..51 do
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "message #{index}",
          DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
        )
      end

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#channel-messages[phx-hook='ChannelMessages']")
      assert has_element?(view, "#older-messages-loading")
      assert has_element?(view, "#newer-messages-loading")
      refute has_element?(view, "#load-older-messages")
    end

    test "renders scroll-edge history controls for empty and short channels", %{
      conn: conn,
      scope: scope
    } do
      {:ok, empty_workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, empty_view, _html} =
        live(
          conn,
          ~p"/workspaces/#{empty_workspace.id}/channels/#{empty_workspace.default_channel_id}"
        )

      refute has_element?(empty_view, "#load-older-messages")
      assert has_element?(empty_view, "#older-messages-loading")
      assert has_element?(empty_view, "#newer-messages-loading")

      {:ok, short_workspace} = Workspaces.create_workspace(scope, %{name: "Workshop"})

      for index <- 1..3 do
        insert_message!(
          short_workspace.default_channel_id,
          scope.user.id,
          "short #{index}",
          DateTime.add(~U[2026-06-19 11:00:00Z], index, :second)
        )
      end

      {:ok, short_view, _html} =
        live(
          conn,
          ~p"/workspaces/#{short_workspace.id}/channels/#{short_workspace.default_channel_id}"
        )

      refute has_element?(short_view, "#load-older-messages")
      assert has_element?(short_view, "#older-messages-loading")
      assert has_element?(short_view, "#newer-messages-loading")
    end

    test "top-edge loading prepends older messages without duplicating the cursor", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      messages =
        for index <- 1..55 do
          insert_message!(
            workspace.default_channel_id,
            scope.user.id,
            "message #{index}",
            DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
          )
        end

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      recent_cursor = Enum.at(messages, 5)

      assert has_element?(view, "#message-#{recent_cursor.id}")
      assert has_element?(view, "#message-#{recent_cursor.id}[data-message-row='full']")
      refute has_element?(view, "#message-#{hd(messages).id}")

      render_hook(view, "load_older_messages", %{
        "anchor_offset_top" => 112.5,
        "anchor_row_id" => "message-#{recent_cursor.id}",
        "container_id" => "channel-messages",
        "scroll_height" => 1_600,
        "scroll_top" => 320
      })

      message_ids =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> then(& &1["#channel-messages > article"])
        |> LazyHTML.attribute("id")

      assert Enum.take(message_ids, 6) ==
               messages
               |> Enum.take(6)
               |> Enum.map(&"message-#{&1.id}")

      assert has_element?(view, "#message-#{hd(messages).id}")
      assert has_element?(view, "#message-#{recent_cursor.id}")
      assert has_element?(view, "#message-#{recent_cursor.id}[data-message-row='compact']")
      refute has_element?(view, "#load-older-messages")

      recent_cursor_row_id = "message-#{recent_cursor.id}"

      assert_push_event(view, "preserve_channel_messages_scroll", %{
        anchor_offset_top: 112.5,
        anchor_row_id: ^recent_cursor_row_id,
        container_id: "channel-messages",
        previous_scroll_height: 1600,
        previous_scroll_top: 320
      })

      refute_push_event(view, "scroll_channel_messages_to_bottom", %{
        container_id: _container_id
      })
    end

    test "top-edge loading accepts fractional browser scroll offsets", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      messages =
        for index <- 1..55 do
          insert_message!(
            workspace.default_channel_id,
            scope.user.id,
            "fractional message #{index}",
            DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
          )
        end

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      refute has_element?(view, "#message-#{hd(messages).id}")

      render_hook(view, "load_older_messages", %{
        "container_id" => "channel-messages",
        "scroll_height" => 5_425,
        "scroll_top" => 64.5
      })

      assert has_element?(view, "#message-#{hd(messages).id}")

      assert_push_event(view, "preserve_channel_messages_scroll", %{
        container_id: "channel-messages",
        previous_scroll_height: 5425,
        previous_scroll_top: 64.5
      })
    end

    test "top-edge loading trims newer rendered messages when the window exceeds the cap", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      messages =
        for index <- 1..350 do
          insert_message!(
            workspace.default_channel_id,
            scope.user.id,
            "bounded message #{index}",
            DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
          )
        end

      Repo.get_by!(ChannelReadState,
        channel_id: workspace.default_channel_id,
        user_id: scope.user.id
      )
      |> ChannelReadState.changeset(%{last_viewed_anchor_seq: 275})
      |> Repo.update!()

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#message-#{Enum.at(messages, 259).id}-content")
      assert has_element?(view, "#message-#{Enum.at(messages, 309).id}-content")
      refute has_element?(view, "#message-#{Enum.at(messages, 209).id}-content")

      for page <- 1..5 do
        render_hook(view, "load_older_messages", %{
          "container_id" => "channel-messages",
          "scroll_height" => 1_600 + page,
          "scroll_top" => 320
        })
      end

      message_ids = rendered_message_ids(view)

      assert length(message_ids) == 300
      assert List.first(message_ids) == "message-#{Enum.at(messages, 9).id}"
      assert List.last(message_ids) == "message-#{Enum.at(messages, 308).id}"
      assert has_element?(view, "#message-#{Enum.at(messages, 9).id}-content")
      refute has_element?(view, "#message-#{Enum.at(messages, 309).id}-content")

      trimmed_message = Enum.at(messages, 309)
      trimmed_message_id = trimmed_message.id
      trimmed_row_id = "message-#{trimmed_message.id}"

      assert_push_event(view, "remove_channel_message_rows", %{
        container_id: "channel-messages",
        message_ids: [^trimmed_message_id],
        row_ids: [^trimmed_row_id]
      })

      {:ok, _reaction} = Chat.toggle_reaction(scope, trimmed_message.id, "👍")

      refute has_element?(view, "#message-#{trimmed_message.id}-content")

      assert_push_event(view, "preserve_channel_messages_scroll", %{
        container_id: "channel-messages",
        previous_scroll_height: 1601,
        previous_scroll_top: 320
      })
    end

    test "top-edge loading prunes reaction summaries for trimmed messages", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      messages =
        for index <- 1..350 do
          insert_message!(
            workspace.default_channel_id,
            scope.user.id,
            "reaction bounded message #{index}",
            DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
          )
        end

      Repo.get_by!(ChannelReadState,
        channel_id: workspace.default_channel_id,
        user_id: scope.user.id
      )
      |> ChannelReadState.changeset(%{last_viewed_anchor_seq: 275})
      |> Repo.update!()

      trimmed_message = Enum.at(messages, 309)
      assert {:ok, _reaction} = Chat.toggle_reaction(scope, trimmed_message.id, "👍")

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#message-#{trimmed_message.id}-reaction-0", "👍 1")

      for page <- 1..5 do
        render_hook(view, "load_older_messages", %{
          "container_id" => "channel-messages",
          "scroll_height" => 1_600 + page,
          "scroll_top" => 320
        })
      end

      refute has_element?(view, "#message-#{trimmed_message.id}")
      assert {:ok, _deleted_reaction} = Chat.toggle_reaction(scope, trimmed_message.id, "👍")

      refute has_element?(view, "#message-#{trimmed_message.id}")
      refute has_element?(view, "#message-#{trimmed_message.id}-reaction-0")
    end

    test "bottom-edge loading continues from the visible boundary after newer rows were trimmed",
         %{
           conn: conn,
           scope: scope
         } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      messages =
        for index <- 1..350 do
          insert_message!(
            workspace.default_channel_id,
            scope.user.id,
            "continued message #{index}",
            DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
          )
        end

      Repo.get_by!(ChannelReadState,
        channel_id: workspace.default_channel_id,
        user_id: scope.user.id
      )
      |> ChannelReadState.changeset(%{last_viewed_anchor_seq: 275})
      |> Repo.update!()

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      for page <- 1..5 do
        render_hook(view, "load_older_messages", %{
          "container_id" => "channel-messages",
          "scroll_height" => 1_600 + page,
          "scroll_top" => 320
        })
      end

      assert List.last(rendered_message_ids(view)) == "message-#{Enum.at(messages, 308).id}"
      refute has_element?(view, "#message-#{Enum.at(messages, 349).id}-content")

      render_hook(view, "load_newer_messages", %{"container_id" => "channel-messages"})

      message_ids = rendered_message_ids(view)

      assert length(message_ids) == 300
      assert List.first(message_ids) == "message-#{Enum.at(messages, 50).id}"
      assert List.last(message_ids) == "message-#{Enum.at(messages, 349).id}"
      assert has_element?(view, "#message-#{Enum.at(messages, 349).id}-content")
      refute has_element?(view, "#message-#{Enum.at(messages, 9).id}-content")
    end

    test "bottom-edge loading appends newer messages in sequence order", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      messages =
        for index <- 1..120 do
          insert_message!(
            workspace.default_channel_id,
            scope.user.id,
            "paged message #{index}",
            DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
          )
        end

      Repo.get_by!(ChannelReadState,
        channel_id: workspace.default_channel_id,
        user_id: scope.user.id
      )
      |> ChannelReadState.changeset(%{last_viewed_anchor_seq: 20})
      |> Repo.update!()

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(
               view,
               "#message-#{Enum.at(messages, 19).id}-content",
               "paged message 20"
             )

      refute has_element?(view, "#message-#{List.last(messages).id}-content", "paged message 120")

      render_hook(view, "load_newer_messages", %{"container_id" => "channel-messages"})

      message_ids = rendered_message_ids(view)

      assert Enum.slice(message_ids, 0, 5) ==
               messages
               |> Enum.slice(4, 5)
               |> Enum.map(&"message-#{&1.id}")

      assert Enum.slice(message_ids, -5, 5) ==
               messages
               |> Enum.slice(100, 5)
               |> Enum.map(&"message-#{&1.id}")

      assert has_element?(
               view,
               "#message-#{Enum.at(messages, 104).id}-content",
               "paged message 105"
             )

      refute has_element?(view, "#message-#{List.last(messages).id}-content", "paged message 120")
    end

    test "bottom-edge loading accepts fractional browser scroll offsets", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      messages =
        for index <- 1..120 do
          insert_message!(
            workspace.default_channel_id,
            scope.user.id,
            "fractional newer message #{index}",
            DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
          )
        end

      Repo.get_by!(ChannelReadState,
        channel_id: workspace.default_channel_id,
        user_id: scope.user.id
      )
      |> ChannelReadState.changeset(%{last_viewed_anchor_seq: 20})
      |> Repo.update!()

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      refute has_element?(view, "#message-#{List.last(messages).id}-content")

      render_hook(view, "load_newer_messages", %{
        "anchor_offset_top" => 96.25,
        "anchor_row_id" => "message-#{Enum.at(messages, 19).id}",
        "container_id" => "channel-messages",
        "scroll_top" => 64.5
      })

      assert has_element?(view, "#message-#{Enum.at(messages, 104).id}-content")

      anchor_row_id = "message-#{Enum.at(messages, 19).id}"

      assert_push_event(view, "restore_channel_messages_scroll", %{
        anchor_offset_top: 96.25,
        anchor_row_id: ^anchor_row_id,
        container_id: "channel-messages",
        previous_scroll_top: 64.5
      })
    end

    test "bottom-edge loading trims older rendered messages when the window exceeds the cap", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      messages =
        for index <- 1..350 do
          insert_message!(
            workspace.default_channel_id,
            scope.user.id,
            "forward bounded message #{index}",
            DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
          )
        end

      Repo.get_by!(ChannelReadState,
        channel_id: workspace.default_channel_id,
        user_id: scope.user.id
      )
      |> ChannelReadState.changeset(%{last_viewed_anchor_seq: 40})
      |> Repo.update!()

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#message-#{Enum.at(messages, 24).id}-content")
      assert has_element?(view, "#message-#{Enum.at(messages, 74).id}-content")
      refute has_element?(view, "#message-#{Enum.at(messages, 324).id}-content")

      for _page <- 1..5 do
        render_hook(view, "load_newer_messages", %{"container_id" => "channel-messages"})
      end

      message_ids = rendered_message_ids(view)

      assert length(message_ids) == 300
      assert List.first(message_ids) == "message-#{Enum.at(messages, 25).id}"
      assert List.last(message_ids) == "message-#{Enum.at(messages, 324).id}"
      refute has_element?(view, "#message-#{Enum.at(messages, 24).id}-content")
      assert has_element?(view, "#message-#{Enum.at(messages, 324).id}-content")
    end

    test "shows and opens the workspace create action from a selected channel", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, channel} = Workspaces.create_channel(scope, workspace.id, %{name: "Planning"})

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/channels/#{channel.id}")

      assert has_element?(view, "#workspace-create-toggle[title='Create workspace']")
      refute has_element?(view, "#workspace-create-form")

      view
      |> element("#workspace-create-toggle")
      |> render_click()

      assert has_element?(view, "#workspace-create-form")
    end

    test "cancels workspace creation from a selected channel", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, channel} = Workspaces.create_channel(scope, workspace.id, %{name: "Planning"})

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/channels/#{channel.id}")

      view
      |> element("#workspace-create-toggle")
      |> render_click()

      view
      |> element("#workspace-create-cancel")
      |> render_click()

      refute has_element?(view, "#workspace-create-form")
      assert has_element?(view, "#channel-message-surface")
      assert has_element?(view, "#workspace-#{workspace.id}[aria-current='page']")
    end

    test "marks workspace and channel targets for context menu hooks", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(
               view,
               "#workspace-#{workspace.id}[phx-hook='ContextMenu'][data-context-menu-type='workspace'][data-context-menu-id='#{workspace.id}']"
             )

      assert has_element?(
               view,
               "#channel-#{workspace.default_channel_id}[phx-hook='ContextMenu'][data-context-menu-type='channel'][data-context-menu-id='#{workspace.default_channel_id}']"
             )
    end

    test "redirects missing or unauthorized channel URLs to the workspace app", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert {:error, {:redirect, %{to: "/workspaces", flash: flash}}} =
               live(conn, ~p"/workspaces/#{workspace.id}/channels/not-a-uuid")

      assert flash["error"] =~ "Channel not found"
    end

    test "redirects non-member channel URLs to the workspace app with generic access flash", %{
      conn: conn
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Private Foundry"})
      {:ok, channel} = Workspaces.create_channel(owner_scope, workspace.id, %{name: "planning"})

      assert {:error, {:redirect, %{to: "/workspaces", flash: flash}}} =
               live(conn, ~p"/workspaces/#{workspace.id}/channels/#{channel.id}")

      assert flash["error"] =~ "Channel not found or you do not have access"
    end

    test "creates a channel from the shell and navigates to it", %{conn: conn, scope: scope} do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> element("#channel-create-toggle")
      |> render_click()

      {:error, {:live_redirect, %{to: path}}} =
        view
        |> form("#channel-create-form", channel: %{name: "Planning"})
        |> render_submit()

      assert %{path: expected_path} = URI.parse(path)
      assert expected_path =~ ~r|^/workspaces/#{workspace.id}/channels/[0-9a-f-]{36}$|

      refute expected_path ==
               ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
    end

    test "opens the channel action menu with rename", %{conn: conn, scope: scope} do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> element("#channel-#{workspace.default_channel_id}-actions")
      |> render_click()

      assert has_element?(view, "#channel-#{workspace.default_channel_id}-menu")
      assert has_element?(view, "#channel-#{workspace.default_channel_id}-rename")
    end

    test "refreshes unread badges when opening a channel action menu", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      {:ok, sibling_channel} =
        Workspaces.create_channel(owner_scope, workspace.id, %{name: "ops"})

      add_workspace_member!(workspace, member_scope)
      :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      refute has_element?(view, "#channel-#{sibling_channel.id}-unread-badge")

      inserted_at = DateTime.add(DateTime.utc_now(:second), 5, :second)

      message =
        insert_message!(sibling_channel.id, owner_scope.user.id, "ops update", inserted_at)

      assert {:ok, _read_state} =
               Chat.add_channel_unread_range(
                 member_scope,
                 sibling_channel.id,
                 message.seq,
                 message.seq
               )

      view
      |> element("#channel-#{sibling_channel.id}-actions")
      |> render_click()

      assert has_element?(
               view,
               "#channel-#{sibling_channel.id}-unread-badge[aria-label='1 unread message in ops']",
               "1"
             )
    end

    test "shows mark as read in an unread channel action menu", %{
      conn: conn,
      scope: member_scope
    } do
      {_owner_scope, workspace, sibling_channel} =
        workspace_with_sibling_unread!(member_scope)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> element("#channel-#{sibling_channel.id}-actions")
      |> render_click()

      assert has_element?(view, "#channel-#{sibling_channel.id}-mark-read", "Mark as read")
    end

    test "hides mark as read in a quiet channel action menu", %{conn: conn, scope: scope} do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, quiet_channel} = Workspaces.create_channel(scope, workspace.id, %{name: "quiet"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> element("#channel-#{quiet_channel.id}-actions")
      |> render_click()

      refute has_element?(view, "#channel-#{quiet_channel.id}-mark-read")
    end

    test "marks a non-selected sidebar channel read without navigating", %{
      conn: conn,
      scope: member_scope
    } do
      {_owner_scope, workspace, sibling_channel} =
        workspace_with_sibling_unread!(member_scope)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#channel-#{workspace.default_channel_id}[aria-current='page']")
      assert has_element?(view, "#channel-#{sibling_channel.id}-unread-badge", "1")

      view
      |> element("#channel-#{sibling_channel.id}-actions")
      |> render_click()

      view
      |> element("#channel-#{sibling_channel.id}-mark-read")
      |> render_click()

      assert has_element?(view, "#channel-#{workspace.default_channel_id}[aria-current='page']")
      refute has_element?(view, "#channel-#{sibling_channel.id}-unread-badge")
      assert Chat.list_unread_counts(member_scope, workspace.id) == {:ok, %{}}
    end

    test "marks the selected sidebar channel read without changing the message window", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)
      :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)

      for index <- 1..80 do
        insert_message!(
          workspace.default_channel_id,
          owner_scope.user.id,
          "general update #{index}",
          DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
        )
      end

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert {:ok, _read_state} =
               Chat.add_channel_unread_range(member_scope, workspace.default_channel_id, 10, 12)

      send(
        view.pid,
        {:workspace_message_created,
         %{workspace_id: workspace.id, channel_id: workspace.default_channel_id}}
      )

      assert has_element?(view, "#selected-channel-unread-actions")
      refute has_element?(view, "#channel-#{workspace.default_channel_id}-unread-badge")
      message_ids_before = rendered_message_ids(view)

      view
      |> element("#channel-#{workspace.default_channel_id}-actions")
      |> render_click()

      assert has_element?(
               view,
               "#channel-#{workspace.default_channel_id}-mark-read",
               "Mark as read"
             )

      view
      |> element("#channel-#{workspace.default_channel_id}-mark-read")
      |> render_click()

      refute has_element?(view, "#selected-channel-unread-actions")
      refute has_element?(view, "#channel-unread-divider")
      assert rendered_message_ids(view) == message_ids_before
      assert Chat.list_unread_counts(member_scope, workspace.id) == {:ok, %{}}
    end

    test "opens the channel action menu from a context menu event", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      render_hook(view, "open_context_menu", %{
        "type" => "channel",
        "id" => workspace.default_channel_id,
        "x" => 320,
        "y" => 180
      })

      assert has_element?(
               view,
               "#channel-#{workspace.default_channel_id}-menu[style='left: 320px; top: 180px;']"
             )

      assert has_element?(view, "#channel-#{workspace.default_channel_id}-rename")
    end

    test "refreshes unread badges when opening a channel context menu", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      {:ok, sibling_channel} =
        Workspaces.create_channel(owner_scope, workspace.id, %{name: "ops"})

      add_workspace_member!(workspace, member_scope)
      :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      refute has_element?(view, "#channel-#{sibling_channel.id}-unread-badge")

      inserted_at = DateTime.add(DateTime.utc_now(:second), 5, :second)

      message =
        insert_message!(sibling_channel.id, owner_scope.user.id, "ops update", inserted_at)

      assert {:ok, _read_state} =
               Chat.add_channel_unread_range(
                 member_scope,
                 sibling_channel.id,
                 message.seq,
                 message.seq
               )

      render_hook(view, "open_context_menu", %{
        "type" => "channel",
        "id" => sibling_channel.id,
        "x" => 320,
        "y" => 180
      })

      assert has_element?(
               view,
               "#channel-#{sibling_channel.id}-unread-badge[aria-label='1 unread message in ops']",
               "1"
             )
    end

    test "opens the workspace action menu with rename", %{conn: conn, scope: scope} do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> element("#workspace-#{workspace.id}-actions")
      |> render_click()

      assert has_element?(view, "#workspace-#{workspace.id}-menu")
      assert has_element?(view, "#workspace-#{workspace.id}-rename")
    end

    test "opens the workspace action menu from a context menu event", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      render_hook(view, "open_context_menu", %{
        "type" => "workspace",
        "id" => workspace.id,
        "x" => 96,
        "y" => 144
      })

      assert has_element?(
               view,
               "#workspace-#{workspace.id}-menu[style='left: 96px; top: 144px;']"
             )

      assert has_element?(view, "#workspace-#{workspace.id}-rename")
      assert has_element?(view, "#workspace-#{workspace.id}-delete")
    end

    test "closes an open context menu", %{conn: conn, scope: scope} do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      render_hook(view, "open_context_menu", %{
        "type" => "channel",
        "id" => workspace.default_channel_id,
        "x" => 320,
        "y" => 180
      })

      assert has_element?(view, "#channel-#{workspace.default_channel_id}-menu")

      render_hook(view, "close_context_menu")

      refute has_element?(view, "#channel-#{workspace.default_channel_id}-menu")
    end

    test "wires context menus for click-away and Escape closing", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      render_hook(view, "open_context_menu", %{
        "type" => "workspace",
        "id" => workspace.id,
        "x" => 96,
        "y" => 144
      })

      assert has_element?(
               view,
               "#workspace-#{workspace.id}-menu[phx-click-away='close_context_menu'][phx-window-keydown='close_context_menu'][phx-key='escape']"
             )

      render_hook(view, "open_context_menu", %{
        "type" => "channel",
        "id" => workspace.default_channel_id,
        "x" => 320,
        "y" => 180
      })

      assert has_element?(
               view,
               "#channel-#{workspace.default_channel_id}-menu[phx-click-away='close_context_menu'][phx-window-keydown='close_context_menu'][phx-key='escape']"
             )
    end

    test "shows delete workspace for owner action menus", %{conn: conn, scope: scope} do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> element("#workspace-#{workspace.id}-actions")
      |> render_click()

      assert has_element?(
               view,
               "#workspace-#{workspace.id}-delete[phx-confirm='Delete this workspace? The workspace and all contained channels/messages will be removed.']",
               "Delete workspace"
             )

      refute has_element?(view, "#workspace-#{workspace.id}-leave")
    end

    test "shows leave workspace for non-owner member action menus", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> element("#workspace-#{workspace.id}-actions")
      |> render_click()

      assert has_element?(
               view,
               "#workspace-#{workspace.id}-leave[phx-confirm='Leave this workspace? You will lose access and need a new invite to return.']",
               "Leave workspace"
             )

      refute has_element?(view, "#workspace-#{workspace.id}-delete")
    end

    test "owner deletes the selected workspace and returns to workspace app", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> element("#workspace-#{workspace.id}-actions")
      |> render_click()

      assert {:error, {:live_redirect, %{to: path}}} =
               view
               |> element("#workspace-#{workspace.id}-delete")
               |> render_click()

      assert path == ~p"/workspaces"
      assert Workspaces.fetch_workspace(scope, workspace.id) == {:error, :not_found}
    end

    test "non-owner leaves the selected workspace and returns to workspace app", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> element("#workspace-#{workspace.id}-actions")
      |> render_click()

      assert {:error, {:live_redirect, %{to: path}}} =
               view
               |> element("#workspace-#{workspace.id}-leave")
               |> render_click()

      assert path == ~p"/workspaces"
      assert Workspaces.fetch_workspace(member_scope, workspace.id) == {:error, :unauthorized}
    end

    test "opens a workspace rename form from the action menu", %{conn: conn, scope: scope} do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> element("#workspace-#{workspace.id}-actions")
      |> render_click()

      view
      |> element("#workspace-#{workspace.id}-rename")
      |> render_click()

      assert has_element?(view, "#workspace-#{workspace.id}-rename-form")
    end

    test "renames the selected workspace and keeps the channel URL", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      path = ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
      {:ok, view, _html} = live(conn, path)

      view
      |> element("#workspace-#{workspace.id}-actions")
      |> render_click()

      view
      |> element("#workspace-#{workspace.id}-rename")
      |> render_click()

      view
      |> form("#workspace-#{workspace.id}-rename-form", workspace: %{name: "Design Guild"})
      |> render_submit()

      assert has_element?(view, "#workspace-#{workspace.id}[title='Design Guild']", "D")
      assert has_element?(view, "#selected-workspace-name", "Design Guild")
      assert has_element?(view, "#channel-message-surface")
      refute has_element?(view, "#workspace-#{workspace.id}-rename-form")
      assert {:ok, renamed_workspace} = Workspaces.fetch_workspace(scope, workspace.id)
      assert renamed_workspace.name == "Design Guild"
    end

    test "keeps the workspace rename form open with field errors for invalid input", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> element("#workspace-#{workspace.id}-actions")
      |> render_click()

      view
      |> element("#workspace-#{workspace.id}-rename")
      |> render_click()

      view
      |> form("#workspace-#{workspace.id}-rename-form", workspace: %{name: ""})
      |> render_submit()

      assert has_element?(view, "#workspace-#{workspace.id}-rename-form")
      assert has_element?(view, "#workspace_name.input-error")
      assert has_element?(view, "#workspace-#{workspace.id}-rename-form", "can't be blank")
    end

    test "shows delete only for non-landing channel action menus", %{conn: conn, scope: scope} do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, channel} = Workspaces.create_channel(scope, workspace.id, %{name: "Planning"})

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/channels/#{channel.id}")

      view
      |> element("#channel-#{workspace.default_channel_id}-actions")
      |> render_click()

      refute has_element?(view, "#channel-#{workspace.default_channel_id}-delete")

      view
      |> element("#channel-#{channel.id}-actions")
      |> render_click()

      assert has_element?(
               view,
               "#channel-#{channel.id}-delete[phx-confirm='Delete this channel? The channel and future messages in it will be removed.']"
             )
    end

    test "opens a channel rename form from the action menu", %{conn: conn, scope: scope} do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> element("#channel-#{workspace.default_channel_id}-actions")
      |> render_click()

      view
      |> element("#channel-#{workspace.default_channel_id}-rename")
      |> render_click()

      assert has_element?(view, "#channel-#{workspace.default_channel_id}-rename-form")
    end

    test "refreshes unread badges while a different channel is being renamed", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      {:ok, unread_channel} = Workspaces.create_channel(owner_scope, workspace.id, %{name: "ops"})

      {:ok, renamed_channel} =
        Workspaces.create_channel(owner_scope, workspace.id, %{name: "planning"})

      add_workspace_member!(workspace, member_scope, "admin")
      :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> element("#channel-#{renamed_channel.id}-actions")
      |> render_click()

      refute has_element?(view, "#channel-#{unread_channel.id}-unread-badge")

      inserted_at = DateTime.add(DateTime.utc_now(:second), 5, :second)
      message = insert_message!(unread_channel.id, owner_scope.user.id, "ops update", inserted_at)

      assert {:ok, _read_state} =
               Chat.add_channel_unread_range(
                 member_scope,
                 unread_channel.id,
                 message.seq,
                 message.seq
               )

      view
      |> element("#channel-#{renamed_channel.id}-rename")
      |> render_click()

      assert has_element?(view, "#channel-#{renamed_channel.id}-rename-form")

      assert has_element?(
               view,
               "#channel-#{unread_channel.id}-unread-badge[aria-label='1 unread message in ops']",
               "1"
             )
    end

    test "renames the selected channel and keeps the channel URL", %{conn: conn, scope: scope} do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      path = ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
      {:ok, view, _html} = live(conn, path)

      view
      |> element("#channel-#{workspace.default_channel_id}-actions")
      |> render_click()

      view
      |> element("#channel-#{workspace.default_channel_id}-rename")
      |> render_click()

      view
      |> form("#channel-#{workspace.default_channel_id}-rename-form",
        channel: %{name: "Welcome Desk"}
      )
      |> render_submit()

      assert has_element?(view, "#channel-#{workspace.default_channel_id}", "# welcome-desk")
      assert has_element?(view, "#selected-channel-title", "# welcome-desk")
      assert has_element?(view, "#channel-message-surface")
      refute has_element?(view, "#channel-#{workspace.default_channel_id}-rename-form")
      assert Repo.get!(Channel, workspace.default_channel_id).name == "welcome-desk"
    end

    test "deletes another channel and keeps the current channel open", %{conn: conn, scope: scope} do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, channel} = Workspaces.create_channel(scope, workspace.id, %{name: "Planning"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> element("#channel-#{channel.id}-actions")
      |> render_click()

      view
      |> element("#channel-#{channel.id}-delete")
      |> render_click()

      refute has_element?(view, "#channel-#{channel.id}")
      refute Repo.get(Channel, channel.id)
      assert has_element?(view, "#channel-#{workspace.default_channel_id}[aria-current='page']")
    end

    test "refreshes unread badges after deleting another channel", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      {:ok, unread_channel} = Workspaces.create_channel(owner_scope, workspace.id, %{name: "ops"})

      {:ok, deleted_channel} =
        Workspaces.create_channel(owner_scope, workspace.id, %{name: "planning"})

      add_workspace_member!(workspace, member_scope, "owner")
      :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> element("#channel-#{deleted_channel.id}-actions")
      |> render_click()

      refute has_element?(view, "#channel-#{unread_channel.id}-unread-badge")

      inserted_at = DateTime.add(DateTime.utc_now(:second), 5, :second)
      message = insert_message!(unread_channel.id, owner_scope.user.id, "ops update", inserted_at)

      assert {:ok, _read_state} =
               Chat.add_channel_unread_range(
                 member_scope,
                 unread_channel.id,
                 message.seq,
                 message.seq
               )

      view
      |> element("#channel-#{deleted_channel.id}-delete")
      |> render_click()

      refute has_element?(view, "#channel-#{deleted_channel.id}")

      assert has_element?(
               view,
               "#channel-#{unread_channel.id}-unread-badge[aria-label='1 unread message in ops']",
               "1"
             )
    end

    test "deletes the current channel and navigates to workspace entry", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, channel} = Workspaces.create_channel(scope, workspace.id, %{name: "Planning"})

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/channels/#{channel.id}")

      view
      |> element("#channel-#{channel.id}-actions")
      |> render_click()

      assert {:error, {:live_redirect, %{to: path}}} =
               view
               |> element("#channel-#{channel.id}-delete")
               |> render_click()

      assert path == ~p"/workspaces/#{workspace.id}"
      refute Repo.get(Channel, channel.id)
    end

    test "live-updates the channel sidebar when another session creates a channel", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert {:ok, channel} = Workspaces.create_channel(scope, workspace.id, %{name: "Ops Room"})

      render(view)

      assert has_element?(view, "#channel-#{channel.id}", "# ops-room")
    end

    test "adds a newly-joined member to the sidebar when they accept an invite", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, invite} = Workspaces.create_workspace_invite(scope, workspace.id)

      joiner_scope =
        DiscordClone.AccountsFixtures.user_fixture(%{username: "channel_view_joiner"})
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      refute has_element?(view, "#workspace-member-#{joiner_scope.user.id}")

      assert {:ok, _result} = Workspaces.accept_workspace_invite(joiner_scope, invite.code)

      render(view)

      assert has_element?(
               view,
               "#workspace-member-#{joiner_scope.user.id}",
               "channel_view_joiner"
             )
    end

    test "keeps the rename form open with field errors for invalid input", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> element("#channel-#{workspace.default_channel_id}-actions")
      |> render_click()

      view
      |> element("#channel-#{workspace.default_channel_id}-rename")
      |> render_click()

      view
      |> form("#channel-#{workspace.default_channel_id}-rename-form", channel: %{name: ""})
      |> render_submit()

      assert has_element?(view, "#channel-#{workspace.default_channel_id}-rename-form")
      assert has_element?(view, "#channel_name.input-error")

      assert has_element?(
               view,
               "#channel-#{workspace.default_channel_id}-rename-form",
               "can't be blank"
             )
    end

    test "keeps the channel form open with field errors for invalid input", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> element("#channel-create-toggle")
      |> render_click()

      view
      |> form("#channel-create-form", channel: %{name: ""})
      |> render_submit()

      assert has_element?(view, "#channel-create-form")
      assert has_element?(view, "#channel_name.input-error")
      assert has_element?(view, "#channel-create-form", "can't be blank")
    end

    test "cancels channel creation without navigating", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> element("#channel-create-toggle")
      |> render_click()

      assert has_element?(view, "#channel-create-form")

      view
      |> element("#channel-create-cancel")
      |> render_click()

      refute has_element?(view, "#channel-create-form")
      assert has_element?(view, "#channel-create-toggle")
      assert has_element?(view, "#channel-#{workspace.default_channel_id}[aria-current='page']")
    end
  end

  describe "channel message moderation context menus" do
    setup :register_and_log_in_user

    test "authors can delete their own message from its context menu", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, message} =
        Chat.send_message(scope, workspace.default_channel_id, %{"content" => "delete me please"})

      {:ok, view, html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert html =~ "delete me please"
      assert has_element?(view, "#message-#{message.id}-actions")
      assert has_element?(view, "#message-#{message.id}-delete")

      view
      |> element("#message-#{message.id}-delete")
      |> render_click()

      assert Repo.get(Message, message.id).deleted_at

      updated_html = render(view)
      assert updated_html =~ "Message deleted"
      refute updated_html =~ "delete me please"
    end

    test "moderators can delete another member's message from its context menu", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      member_scope =
        %{username: "message_delete_target"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope, "member")

      {:ok, message} =
        Chat.send_message(member_scope, workspace.default_channel_id, %{
          "content" => "moderate me"
        })

      {:ok, owner_view, html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert html =~ "moderate me"
      assert has_element?(owner_view, "#message-#{message.id}-delete")

      owner_view
      |> element("#message-#{message.id}-delete")
      |> render_click()

      assert Repo.get(Message, message.id).deleted_at

      updated_html = render(owner_view)
      assert updated_html =~ "Message deleted"
      refute updated_html =~ "moderate me"

      assert {:ok, events} = Workspaces.list_audit_events(owner_scope, workspace.id)
      assert Enum.any?(events, &(&1.event_type == "moderator_message_deleted"))
    end

    test "regular members cannot delete another member's message", %{
      conn: viewer_conn,
      scope: viewer_scope
    } do
      author_scope =
        %{username: "message_delete_author"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(author_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, viewer_scope, "member")

      {:ok, message} =
        Chat.send_message(author_scope, workspace.default_channel_id, %{"content" => "hands off"})

      {:ok, viewer_view, html} =
        live(
          viewer_conn,
          ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
        )

      assert html =~ "hands off"
      refute has_element?(viewer_view, "#message-#{message.id}-delete")
      refute has_element?(viewer_view, "#message-#{message.id}-mute")
      assert has_element?(viewer_view, "#message-#{message.id}-reaction-palette")
    end

    test "message menus expose author moderation actions per owner authorization", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      admin_scope =
        %{username: "msg_mod_admin"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      member_scope =
        %{username: "msg_mod_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, admin_scope, "admin")
      add_workspace_member!(workspace, member_scope, "member")

      channel_id = workspace.default_channel_id
      {:ok, owner_msg} = Chat.send_message(owner_scope, channel_id, %{"content" => "owner post"})
      {:ok, admin_msg} = Chat.send_message(admin_scope, channel_id, %{"content" => "admin post"})

      {:ok, member_msg} =
        Chat.send_message(member_scope, channel_id, %{"content" => "member post"})

      {:ok, owner_view, _html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{channel_id}")

      assert has_element?(owner_view, "#message-#{member_msg.id}-mute")
      assert has_element?(owner_view, "#message-#{member_msg.id}-timeout-5-minutes")
      assert has_element?(owner_view, "#message-#{member_msg.id}-kick")
      assert has_element?(owner_view, "#message-#{member_msg.id}-ban")
      assert has_element?(owner_view, "#message-#{member_msg.id}-promote-to-admin")

      assert has_element?(owner_view, "#message-#{admin_msg.id}-demote-to-member")
      assert has_element?(owner_view, "#message-#{admin_msg.id}-mute")
      assert has_element?(owner_view, "#message-#{admin_msg.id}-ban")

      refute has_element?(owner_view, "#message-#{owner_msg.id}-mute")
      assert has_element?(owner_view, "#message-#{owner_msg.id}-delete")
    end

    test "message menus hide actions blocked by admin/admin and owner immunity", %{
      conn: admin_conn,
      scope: admin_scope
    } do
      owner_scope =
        %{username: "msg_mod_owner"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      peer_admin_scope =
        %{username: "msg_mod_peer_admin"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      member_scope =
        %{username: "msg_mod_target"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, admin_scope, "admin")
      add_workspace_member!(workspace, peer_admin_scope, "admin")
      add_workspace_member!(workspace, member_scope, "member")

      channel_id = workspace.default_channel_id
      {:ok, self_msg} = Chat.send_message(admin_scope, channel_id, %{"content" => "self post"})
      {:ok, owner_msg} = Chat.send_message(owner_scope, channel_id, %{"content" => "owner post"})

      {:ok, peer_msg} =
        Chat.send_message(peer_admin_scope, channel_id, %{"content" => "peer admin post"})

      {:ok, member_msg} =
        Chat.send_message(member_scope, channel_id, %{"content" => "member post"})

      {:ok, admin_view, _html} =
        live(admin_conn, ~p"/workspaces/#{workspace.id}/channels/#{channel_id}")

      assert has_element?(admin_view, "#message-#{self_msg.id}-delete")
      refute has_element?(admin_view, "#message-#{self_msg.id}-mute")
      refute has_element?(admin_view, "#message-#{self_msg.id}-timeout-5-minutes")

      assert has_element?(admin_view, "#message-#{peer_msg.id}-mute")
      assert has_element?(admin_view, "#message-#{peer_msg.id}-timeout-5-minutes")
      refute has_element?(admin_view, "#message-#{peer_msg.id}-kick")
      refute has_element?(admin_view, "#message-#{peer_msg.id}-ban")

      refute has_element?(admin_view, "#message-#{owner_msg.id}-delete")
      refute has_element?(admin_view, "#message-#{owner_msg.id}-mute")
      assert has_element?(admin_view, "#message-#{owner_msg.id}-reaction-palette")

      assert has_element?(admin_view, "#message-#{member_msg.id}-kick")
      assert has_element?(admin_view, "#message-#{member_msg.id}-ban")
    end

    test "mute applies immediately from a message context menu", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      target_scope =
        %{username: "msg_mute_target"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope, "member")

      {:ok, message} =
        Chat.send_message(target_scope, workspace.default_channel_id, %{"content" => "noisy"})

      {:ok, owner_view, _html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(owner_view, "#message-#{message.id}-mute")

      owner_view
      |> element("#message-#{message.id}-mute")
      |> render_click()

      assert has_element?(owner_view, "#message-#{message.id}-unmute")
      refute has_element?(owner_view, "#message-#{message.id}-mute")

      assert {:ok, %{muted?: true}} =
               Workspaces.member_moderation_state(owner_scope, workspace.id, target_scope.user.id)
    end

    test "mute from a message context menu refreshes every rendered author row", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      target_scope =
        %{username: "msg_multi_row_mute_target"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope, "member")

      {:ok, first_message} =
        Chat.send_message(target_scope, workspace.default_channel_id, %{
          "content" => "first noisy"
        })

      {:ok, second_message} =
        Chat.send_message(target_scope, workspace.default_channel_id, %{
          "content" => "second noisy"
        })

      {:ok, owner_view, _html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(owner_view, "#message-#{first_message.id}-mute")
      assert has_element?(owner_view, "#message-#{second_message.id}-mute")

      owner_view
      |> element("#message-#{first_message.id}-mute")
      |> render_click()

      assert has_element?(owner_view, "#message-#{first_message.id}-unmute")
      assert has_element?(owner_view, "#message-#{second_message.id}-unmute")
      refute has_element?(owner_view, "#message-#{first_message.id}-mute")
      refute has_element?(owner_view, "#message-#{second_message.id}-mute")
    end

    test "timeout applies after selecting a preset from a message context menu", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      target_scope =
        %{username: "msg_timeout_target"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope, "member")

      {:ok, message} =
        Chat.send_message(target_scope, workspace.default_channel_id, %{"content" => "slow down"})

      {:ok, owner_view, _html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(owner_view, "#message-#{message.id}-timeout-5-minutes")

      owner_view
      |> element("#message-#{message.id}-timeout-5-minutes")
      |> render_click()

      assert has_element?(owner_view, "#message-#{message.id}-remove-timeout")

      assert {:ok, %{timed_out?: true}} =
               Workspaces.member_moderation_state(owner_scope, workspace.id, target_scope.user.id)
    end

    test "kick from a message context menu requires a reason and clears the author's menu", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      target_scope =
        %{username: "msg_kick_target"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope, "member")

      {:ok, message} =
        Chat.send_message(target_scope, workspace.default_channel_id, %{"content" => "spam city"})

      {:ok, owner_view, _html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(owner_view, "#message-#{message.id}-kick")

      blank_html =
        owner_view
        |> form("#message-#{message.id}-kick-form", %{reason: "   "})
        |> render_submit()

      assert blank_html =~ "reason is required"

      assert Repo.get_by(WorkspaceMembership,
               workspace_id: workspace.id,
               user_id: target_scope.user.id
             )

      owner_view
      |> form("#message-#{message.id}-kick-form", %{reason: "Repeated spam"})
      |> render_submit()

      refute Repo.get_by(WorkspaceMembership,
               workspace_id: workspace.id,
               user_id: target_scope.user.id
             )

      refute has_element?(owner_view, "#message-#{message.id}-delete")
      refute has_element?(owner_view, "#message-#{message.id}-mute")
      refute has_element?(owner_view, "#message-#{message.id}-kick")
      assert has_element?(owner_view, "#message-#{message.id}-reaction-palette")

      assert {:ok, events} = Workspaces.list_audit_events(owner_scope, workspace.id)

      assert Enum.any?(
               events,
               &(&1.event_type == "member_kicked" and &1.reason == "Repeated spam")
             )
    end

    test "ban from a message context menu requires a reason and applies the cleanup choice", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      target_scope =
        %{username: "msg_ban_target"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope, "member")

      {:ok, message} =
        Chat.send_message(target_scope, workspace.default_channel_id, %{"content" => "toxic post"})

      {:ok, owner_view, html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert html =~ "toxic post"

      assert has_element?(
               owner_view,
               "#message-#{message.id}-ban-form input[name='cleanup_window'][value='all']"
             )

      blank_html =
        owner_view
        |> form("#message-#{message.id}-ban-form", %{reason: "   "})
        |> render_submit()

      assert blank_html =~ "reason is required"
      refute Workspaces.workspace_banned?(workspace.id, target_scope.user.id)

      owner_view
      |> form("#message-#{message.id}-ban-form", %{
        reason: "Persistent abuse",
        cleanup_window: "all"
      })
      |> render_submit()

      assert Workspaces.workspace_banned?(workspace.id, target_scope.user.id)
      assert Repo.get(Message, message.id).deleted_at

      updated_html = render(owner_view)
      assert updated_html =~ "Message deleted"
      refute updated_html =~ "toxic post"

      assert {:ok, events} = Workspaces.list_audit_events(owner_scope, workspace.id)
      ban_event = Enum.find(events, &(&1.event_type == "member_banned"))
      assert ban_event.reason == "Persistent abuse"
      assert ban_event.metadata["cleanup_window"] == "all"
    end

    test "message ban form hides the all-messages cleanup option from admins", %{
      conn: admin_conn,
      scope: admin_scope
    } do
      owner_scope =
        %{username: "msg_ban_owner"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      member_scope =
        %{username: "msg_ban_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, admin_scope, "admin")
      add_workspace_member!(workspace, member_scope, "member")

      {:ok, message} =
        Chat.send_message(member_scope, workspace.default_channel_id, %{"content" => "borderline"})

      {:ok, admin_view, _html} =
        live(admin_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(
               admin_view,
               "#message-#{message.id}-ban-form input[name='cleanup_window'][value='24_hours']"
             )

      refute has_element?(
               admin_view,
               "#message-#{message.id}-ban-form input[name='cleanup_window'][value='all']"
             )
    end

    test "admins see moderation success feedback from a message menu without the audit log", %{
      conn: admin_conn,
      scope: admin_scope
    } do
      owner_scope =
        %{username: "msg_flash_owner"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      member_scope =
        %{username: "msg_flash_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, admin_scope, "admin")
      add_workspace_member!(workspace, member_scope, "member")

      {:ok, message} =
        Chat.send_message(member_scope, workspace.default_channel_id, %{
          "content" => "rule breaker"
        })

      {:ok, admin_view, _html} =
        live(admin_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      # Admins cannot view the audit log, so the flash is their only confirmation.
      assert {:error, _reason} = Workspaces.list_audit_events(admin_scope, workspace.id)

      admin_view
      |> form("#message-#{message.id}-kick-form", %{reason: "Spamming"})
      |> render_submit()

      assert render(admin_view) =~ "Member removed from the workspace"
    end
  end

  describe "/workspaces/:workspace_id/invites/new" do
    setup :register_and_log_in_user

    test "hides the invite action from non-owner members in owner-only workspaces", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> element("#workspace-#{workspace.id}-actions")
      |> render_click()

      refute has_element?(view, "#workspace-#{workspace.id}-invite-new")
    end

    test "shows the invite action to admins", %{
      conn: conn,
      scope: admin_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, admin_scope, "admin")

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      view
      |> element("#workspace-#{workspace.id}-actions")
      |> render_click()

      assert has_element?(view, "#workspace-#{workspace.id}-invite-new")
    end

    test "renders the workspace shell without creating an invite", %{conn: conn, scope: scope} do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/invites/new")

      view
      |> element("#workspace-#{workspace.id}-actions")
      |> render_click()

      assert has_element?(view, "#workspace-app-shell")
      assert has_element?(view, "#workspace-#{workspace.id}[aria-current='page']")
      assert has_element?(view, "#workspace-#{workspace.id}-invite-new")
      assert has_element?(view, "#channel-#{workspace.default_channel_id}")
      refute has_element?(view, "#channel-#{workspace.default_channel_id}[aria-current='page']")
      assert has_element?(view, "#workspace-invite-create-form")
      assert Repo.aggregate(WorkspaceInvite, :count) == 0
    end

    test "syncs sidebar read state across invite and channel sessions", %{
      conn: invite_conn,
      scope: admin_scope
    } do
      {_owner_scope, workspace, sibling_channel} =
        workspace_with_sibling_unread!(admin_scope, "admin")

      channel_conn = build_conn() |> log_in_user(admin_scope.user)

      {:ok, invite_view, _html} = live(invite_conn, ~p"/workspaces/#{workspace.id}/invites/new")

      {:ok, channel_view, _html} =
        live(
          channel_conn,
          ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
        )

      assert has_element?(invite_view, "#channel-#{sibling_channel.id}-unread-badge", "1")
      assert has_element?(channel_view, "#channel-#{sibling_channel.id}-unread-badge", "1")

      channel_view
      |> element("#channel-#{sibling_channel.id}-actions")
      |> render_click()

      channel_view
      |> element("#channel-#{sibling_channel.id}-mark-read")
      |> render_click()

      refute has_element?(invite_view, "#channel-#{sibling_channel.id}-unread-badge")
      refute has_element?(channel_view, "#channel-#{sibling_channel.id}-unread-badge")
    end

    test "renders durable workspace members in the invite shell", %{
      conn: conn,
      scope: admin_scope
    } do
      owner_scope =
        %{username: "invite_owner"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, admin_scope, "admin")

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/invites/new")

      assert has_element?(view, "#workspace-members-sidebar[aria-label='Workspace members']")

      assert has_element?(
               view,
               "#workspace-member-#{owner_scope.user.id}[data-presence-state='offline']",
               "invite_owner"
             )

      assert has_element?(
               view,
               "#workspace-member-#{admin_scope.user.id}",
               admin_scope.user.username
             )

      assert has_element?(view, "#workspace-invite-create-form")
    end

    test "marks the current member online after entering an invite surface", %{
      conn: conn,
      scope: admin_scope
    } do
      owner_scope =
        %{username: "invite_presence_owner"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, admin_scope, "admin")

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/invites/new")

      assert has_element?(
               view,
               "#workspace-member-#{admin_scope.user.id}[data-presence-state='online']",
               admin_scope.user.username
             )

      assert has_element?(
               view,
               "#workspace-member-#{admin_scope.user.id} [data-member-status='online']",
               "Online"
             )

      assert has_element?(
               view,
               "#workspace-member-#{owner_scope.user.id}[data-presence-state='offline']",
               "invite_presence_owner"
             )
    end

    test "marks another member online on the invite surface without refresh", %{
      conn: conn,
      scope: receiver_scope
    } do
      sender_scope =
        %{username: "invite_presence_sender"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(receiver_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, sender_scope)
      sender_conn = build_conn() |> log_in_user(sender_scope.user)

      {:ok, receiver_view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/invites/new")

      assert has_element?(
               receiver_view,
               "#workspace-member-#{sender_scope.user.id}[data-presence-state='offline']",
               "invite_presence_sender"
             )

      {:ok, _sender_view, _html} =
        live(
          sender_conn,
          ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
        )

      assert has_element?(
               receiver_view,
               "#workspace-member-#{sender_scope.user.id}[data-presence-state='online']",
               "invite_presence_sender"
             )
    end

    test "refreshes the channel sidebar when a channel is created elsewhere", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/invites/new")

      assert {:ok, channel} = Workspaces.create_channel(scope, workspace.id, %{name: "Logistics"})

      render(view)

      assert has_element?(view, "#channel-#{channel.id}", "# logistics")
    end

    test "refreshes the member list when a new member joins via invite", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, invite} = Workspaces.create_workspace_invite(scope, workspace.id)

      joiner_scope =
        DiscordClone.AccountsFixtures.user_fixture(%{username: "invite_screen_joiner"})
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/invites/new")

      refute has_element?(view, "#workspace-member-#{joiner_scope.user.id}")

      assert {:ok, _result} = Workspaces.accept_workspace_invite(joiner_scope, invite.code)

      render(view)

      assert has_element?(
               view,
               "#workspace-member-#{joiner_scope.user.id}",
               "invite_screen_joiner"
             )
    end

    test "shows and opens the workspace create action from the invite screen", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/invites/new")

      assert has_element?(view, "#workspace-create-toggle[title='Create workspace']")
      refute has_element?(view, "#workspace-create-form")

      view
      |> element("#workspace-create-toggle")
      |> render_click()

      assert has_element?(view, "#workspace-create-form")
    end

    test "cancels workspace creation from the invite screen", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/invites/new")

      view
      |> element("#workspace-create-toggle")
      |> render_click()

      view
      |> element("#workspace-create-cancel")
      |> render_click()

      refute has_element?(view, "#workspace-create-form")
      assert has_element?(view, "#workspace-invite-create-form")
    end

    test "submitting the form creates and displays a selectable absolute invite URL", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/invites/new")

      view
      |> form("#workspace-invite-create-form", invite: %{})
      |> render_submit()

      invite = Repo.one!(WorkspaceInvite)
      invite_url = DiscordCloneWeb.Endpoint.url() <> "/invites/#{invite.code}"

      assert has_element?(view, "#workspace-invite-url[value='#{invite_url}']")

      assert has_element?(
               view,
               "#workspace-invite-copy[phx-hook='ClipboardCopy'][phx-update='ignore'][data-copy-target='workspace-invite-url']"
             )
    end

    test "submitting twice replaces the displayed link with a fresh invite URL", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/invites/new")

      view
      |> form("#workspace-invite-create-form", invite: %{})
      |> render_submit()

      first_invite = Repo.one!(WorkspaceInvite)
      first_url = DiscordCloneWeb.Endpoint.url() <> "/invites/#{first_invite.code}"

      view
      |> form("#workspace-invite-create-form", invite: %{})
      |> render_submit()

      second_invite =
        WorkspaceInvite
        |> order_by([invite], desc: invite.inserted_at, desc: invite.id)
        |> limit(1)
        |> Repo.one!()

      second_url = DiscordCloneWeb.Endpoint.url() <> "/invites/#{second_invite.code}"

      assert first_invite.code != second_invite.code
      assert Repo.aggregate(WorkspaceInvite, :count) == 2
      assert has_element?(view, "#workspace-invite-url[value='#{second_url}']")
      refute has_element?(view, "#workspace-invite-url[value='#{first_url}']")
    end

    test "redirects disallowed members back to workspace entry with an error flash", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)

      assert {:error, {:redirect, %{to: path, flash: flash}}} =
               live(conn, ~p"/workspaces/#{workspace.id}/invites/new")

      assert path == ~p"/workspaces/#{workspace.id}"
      assert flash["error"] =~ "not allowed to create invites"
    end

    test "redirects non-members to the workspace app with the generic access flash", %{
      conn: conn
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      assert {:error, {:redirect, %{to: path, flash: flash}}} =
               live(conn, ~p"/workspaces/#{workspace.id}/invites/new")

      assert path == ~p"/workspaces"
      assert flash["error"] =~ "Workspace not found or you do not have access"
    end

    test "promotes a member from the invite-surface member menu", %{
      conn: conn,
      scope: owner_scope
    } do
      target_scope =
        DiscordClone.AccountsFixtures.user_fixture(%{username: "invite_promotable"})
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope, "member")

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/invites/new")

      view
      |> element("#workspace-member-#{target_scope.user.id}-promote-to-admin")
      |> render_click()

      assert Repo.get_by(WorkspaceMembership,
               workspace_id: workspace.id,
               user_id: target_scope.user.id
             ).role == "admin"

      assert has_element?(view, "#workspace-member-#{target_scope.user.id}-demote-to-member")
    end
  end

  describe "/workspaces/:workspace_id/audit-log" do
    setup :register_and_log_in_user

    test "lists newest audit events for owners", %{conn: conn, scope: owner_scope} do
      admin_scope =
        DiscordClone.AccountsFixtures.user_fixture(%{username: "admin_user"})
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      member_scope =
        DiscordClone.AccountsFixtures.user_fixture(%{username: "member_user"})
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
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

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/audit-log")

      assert has_element?(view, "#workspace-audit-log")
      assert has_element?(view, "#workspace-audit-events")
      assert has_element?(view, "#workspace-audit-events article:first-child", "admin_user")
      assert has_element?(view, "#workspace-audit-events article:first-child", "demoted")
      assert has_element?(view, "#workspace-audit-events article:last-child", "member_user")
      assert has_element?(view, "#workspace-audit-events article:last-child", "promoted")
    end

    test "shows the channel context for a moderator message delete", %{
      conn: conn,
      scope: owner_scope
    } do
      member_scope =
        DiscordClone.AccountsFixtures.user_fixture(%{username: "member_user"})
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope, "member")

      {:ok, message} =
        Chat.send_message(member_scope, workspace.default_channel_id, %{
          "content" => "needs moderation"
        })

      assert {:ok, _deleted} = Chat.delete_message(owner_scope, message.id)

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/audit-log")

      assert has_element?(
               view,
               "#workspace-audit-events article:first-child",
               "deleted a message by member_user in #general"
             )
    end

    test "redirects admins and members away from the audit log", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      admin_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      member_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, admin_scope, "admin")
      add_workspace_member!(workspace, member_scope, "member")

      admin_conn = build_conn() |> log_in_user(admin_scope.user)
      member_conn = build_conn() |> log_in_user(member_scope.user)

      assert {:error, {:redirect, %{to: admin_path, flash: admin_flash}}} =
               live(admin_conn, ~p"/workspaces/#{workspace.id}/audit-log")

      assert admin_path == ~p"/workspaces/#{workspace.id}"
      assert admin_flash["error"] =~ "Only workspace owners can view the audit log"

      assert {:error, {:redirect, %{to: member_path, flash: member_flash}}} =
               live(member_conn, ~p"/workspaces/#{workspace.id}/audit-log")

      assert member_path == ~p"/workspaces/#{workspace.id}"
      assert member_flash["error"] =~ "Only workspace owners can view the audit log"

      {:ok, _view, _html} = live(owner_conn, ~p"/workspaces/#{workspace.id}/audit-log")
    end

    test "owners can view banned members and unban them from the audit log", %{
      conn: conn,
      scope: owner_scope
    } do
      banned_scope =
        DiscordClone.AccountsFixtures.user_fixture(%{username: "banished_user"})
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, banned_scope, "member")

      assert {:ok, _ban} =
               Workspaces.ban_member(owner_scope, workspace.id, banned_scope.user.id, %{
                 "reason" => "Persistent spam"
               })

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/audit-log")

      assert has_element?(view, "#workspace-banned-members")
      assert has_element?(view, "#workspace-banned-members", "banished_user")

      view
      |> element("#workspace-banned-members button[phx-value-user_id='#{banned_scope.user.id}']")
      |> render_click()

      refute Workspaces.workspace_banned?(workspace.id, banned_scope.user.id)
      refute has_element?(view, "#workspace-banned-members", "banished_user")
      assert has_element?(view, "#workspace-banned-members-empty-state")
    end

    test "promotes a member from the audit-log member menu and logs the event", %{
      conn: conn,
      scope: owner_scope
    } do
      target_scope =
        DiscordClone.AccountsFixtures.user_fixture(%{username: "audit_promotable"})
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope, "member")

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/audit-log")

      view
      |> element("#workspace-member-#{target_scope.user.id}-promote-to-admin")
      |> render_click()

      assert Repo.get_by(WorkspaceMembership,
               workspace_id: workspace.id,
               user_id: target_scope.user.id
             ).role == "admin"

      assert has_element?(view, "#workspace-member-#{target_scope.user.id}-demote-to-member")
      assert has_element?(view, "#workspace-audit-events article:first-child", "promoted")
    end

    test "refreshes when an admin action creates an audit event elsewhere", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      admin_scope =
        DiscordClone.AccountsFixtures.user_fixture(%{username: "remote_admin_actor"})
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      target_scope =
        DiscordClone.AccountsFixtures.user_fixture(%{username: "remote_audit_target"})
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, admin_scope, "admin")
      add_workspace_member!(workspace, target_scope, "member")

      {:ok, audit_view, _html} = live(owner_conn, ~p"/workspaces/#{workspace.id}/audit-log")

      admin_conn = build_conn() |> log_in_user(admin_scope.user)

      {:ok, admin_view, _html} =
        live(admin_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      admin_view
      |> element("#workspace-member-#{target_scope.user.id}-mute")
      |> render_click()

      render(audit_view)

      assert has_element?(
               audit_view,
               "#workspace-audit-events article:first-child",
               "remote_admin_actor muted remote_audit_target"
             )
    end

    test "refreshes the channel sidebar when a channel is created elsewhere", %{
      conn: conn,
      scope: owner_scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/audit-log")

      assert {:ok, channel} =
               Workspaces.create_channel(owner_scope, workspace.id, %{name: "Logistics"})

      render(view)

      assert has_element?(view, "#channel-#{channel.id}", "# logistics")
    end

    test "refreshes the member list when a new member joins via invite", %{
      conn: conn,
      scope: owner_scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      {:ok, invite} = Workspaces.create_workspace_invite(owner_scope, workspace.id)

      joiner_scope =
        DiscordClone.AccountsFixtures.user_fixture(%{username: "audit_join_watcher"})
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/audit-log")

      refute has_element?(view, "#workspace-member-#{joiner_scope.user.id}")

      assert {:ok, _result} = Workspaces.accept_workspace_invite(joiner_scope, invite.code)

      render(view)

      assert has_element?(
               view,
               "#workspace-member-#{joiner_scope.user.id}",
               "audit_join_watcher"
             )
    end

    test "renders invite-join and unban audit entries", %{conn: conn, scope: owner_scope} do
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      {:ok, invite} = Workspaces.create_workspace_invite(owner_scope, workspace.id)

      joiner_scope =
        DiscordClone.AccountsFixtures.user_fixture(%{username: "history_member"})
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      assert {:ok, _result} = Workspaces.accept_workspace_invite(joiner_scope, invite.code)

      assert {:ok, _ban} =
               Workspaces.ban_member(owner_scope, workspace.id, joiner_scope.user.id, %{
                 "reason" => "spam"
               })

      assert {:ok, _unban} =
               Workspaces.unban_member(owner_scope, workspace.id, joiner_scope.user.id)

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/audit-log")

      assert has_element?(
               view,
               "#workspace-audit-events",
               "joined from an invite created by"
             )

      assert has_element?(view, "#workspace-audit-events article:first-child", "unbanned")
    end
  end

  describe "moderation live refresh and access-loss hardening" do
    setup :register_and_log_in_user

    test "re-enables the timed-out user's composer live when the timeout expires", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      target_scope =
        %{username: "expiring_timeout_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope, "member")

      {:ok, owner_view, _html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      owner_view
      |> element("#workspace-member-#{target_scope.user.id}-timeout-5-minutes")
      |> render_click()

      target_conn = build_conn() |> log_in_user(target_scope.user)

      {:ok, target_view, _html} =
        live(
          target_conn,
          ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
        )

      assert has_element?(target_view, "#message_content[disabled]")

      expire_active_timeout!(workspace.id, target_scope.user.id)

      render(target_view)
      refute has_element?(target_view, "#message_content[disabled]")
      refute has_element?(target_view, "#message-composer-muted-feedback")
    end

    test "re-enables the timed-out user's composer live when a moderator removes the timeout", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      target_scope =
        %{username: "manual_removed_timeout_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope, "member")

      {:ok, owner_view, _html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      owner_view
      |> element("#workspace-member-#{target_scope.user.id}-timeout-5-minutes")
      |> render_click()

      target_conn = build_conn() |> log_in_user(target_scope.user)

      {:ok, target_view, _html} =
        live(
          target_conn,
          ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
        )

      assert has_element?(target_view, "#message_content[disabled]")

      owner_view
      |> element("#workspace-member-#{target_scope.user.id}-remove-timeout")
      |> render_click()

      render(target_view)
      refute has_element?(target_view, "#message_content[disabled]")
      refute has_element?(target_view, "#message-composer-muted-feedback")
    end

    test "keeps the composer blocked after timeout expiry when a mute is still active", %{
      conn: owner_conn,
      scope: owner_scope
    } do
      target_scope =
        %{username: "muted_and_timed_out_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope, "member")

      {:ok, owner_view, _html} =
        live(owner_conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      owner_view
      |> element("#workspace-member-#{target_scope.user.id}-timeout-5-minutes")
      |> render_click()

      owner_view
      |> element("#workspace-member-#{target_scope.user.id}-mute")
      |> render_click()

      target_conn = build_conn() |> log_in_user(target_scope.user)

      {:ok, target_view, _html} =
        live(
          target_conn,
          ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}"
        )

      assert has_element?(target_view, "#message_content[disabled]")

      expire_active_timeout!(workspace.id, target_scope.user.id)

      render(target_view)
      assert has_element?(target_view, "#message_content[disabled]")
      assert has_element?(target_view, "#message-composer-muted-feedback", "muted")
    end

    test "moderation broadcasts to regular members carry no private moderation details", %{
      scope: owner_scope
    } do
      member_scope =
        %{username: "plain_member_subscriber"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      target_scope =
        %{username: "reported_member"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope, "member")
      add_workspace_member!(workspace, target_scope, "member")

      :ok = Workspaces.subscribe_to_workspace_moderation(member_scope, workspace.id)

      {:ok, _moderation} =
        Workspaces.mute_member(owner_scope, workspace.id, target_scope.user.id, %{
          "reason" => "leaking private channel secrets"
        })

      assert_receive {:workspace_moderation_changed, payload}

      assert payload == %{workspace_id: workspace.id, target_user_id: target_scope.user.id}
    end
  end

  # Simulates the runtime timer firing on a naturally expired timeout: backdate
  # the active timeout's expiry into the past, then run the same expiry the
  # WorkspaceServer timer invokes.
  defp expire_active_timeout!(workspace_id, target_user_id) do
    moderation =
      Repo.one!(
        from moderation in DiscordClone.Workspaces.WorkspaceModeration,
          where:
            moderation.workspace_id == ^workspace_id and
              moderation.target_user_id == ^target_user_id and
              moderation.type == "timeout" and
              moderation.active? == true
      )

    moderation
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(:second), -1, :second))
    |> Repo.update!()

    {:ok, _expired} = Workspaces.expire_member_timeout(moderation.id)
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

  defp workspace_with_sibling_unread!(member_scope, role \\ "member") do
    owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
    {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
    {:ok, sibling_channel} = Workspaces.create_channel(owner_scope, workspace.id, %{name: "ops"})

    add_workspace_member!(workspace, member_scope, role)
    :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)
    {:ok, _message} = Chat.send_message(owner_scope, sibling_channel.id, %{content: "ops update"})

    {owner_scope, workspace, sibling_channel}
  end

  defp rendered_message_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> then(& &1["#channel-messages > article"])
    |> LazyHTML.attribute("id")
  end

  defp insert_message!(channel_id, user_id, content, inserted_at) do
    inserted_at = %{inserted_at | microsecond: {elem(inserted_at.microsecond, 0), 6}}

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

  defp start_live_view_process do
    start_supervised!(%{
      id: System.unique_integer([:positive]),
      start:
        {Task, :start_link,
         [
           fn ->
             receive do
               :stop -> :ok
             end
           end
         ]}
    })
  end

  defp workspace_member_row_ids(view, user_id) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> then(& &1["#workspace-members > #workspace-member-#{user_id}"])
    |> LazyHTML.attribute("id")
  end
end
