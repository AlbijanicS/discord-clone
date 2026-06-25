defmodule DiscordCloneWeb.WorkspaceLive.HomeTest do
  use DiscordCloneWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias DiscordClone.Workspaces
  alias DiscordClone.Chat
  alias DiscordClone.Chat.Message
  alias DiscordClone.Chat.{ChannelServer, WorkspaceServer}
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

      assert path =~ ~r|^/workspaces/\d+$|
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
               live(conn, ~p"/workspaces/-1")

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

    test "starts a channel runtime after connected channel entry", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert ChannelServer.whereis(workspace.default_channel_id) == nil

      {:ok, _view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert is_pid(ChannelServer.whereis(workspace.default_channel_id))
    end

    test "does not start a channel runtime during disconnected static render", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      conn = get(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert html_response(conn, 200)
      assert ChannelServer.whereis(workspace.default_channel_id) == nil
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
      workspace_pid = WorkspaceServer.whereis(workspace.id)
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

      workspace_server = WorkspaceServer.whereis(workspace.id)
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

      workspace_server = WorkspaceServer.whereis(workspace.id)
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

      workspace_server = WorkspaceServer.whereis(workspace.id)
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
      assert has_element?(view, "#message-#{message.id} time[datetime='2026-06-19T10:30:00Z']")
      assert has_element?(view, "#message-#{message.id}-content", message.content)
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

      replacement_pid = ChannelServer.whereis(channel_id)
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
      assert has_element?(view, "#message-#{message.id}-content", "hello from liveview")
      refute has_element?(view, "#message_content[value='  hello from liveview  ']")

      assert_push_event(view, "clear_message_composer", %{input_id: "message_content"})

      assert_push_event(view, "scroll_channel_messages_to_bottom", %{
        container_id: "channel-messages"
      })
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
          owner_scope.user.id,
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
        |> order_by([message], desc: message.id)
        |> limit(1)
        |> Repo.one!()

      assert has_element?(receiver_view, "#message-#{message.id}")

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
        |> order_by([message], desc: message.id)
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
        |> order_by([message], desc: message.id)
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
        |> order_by([message], desc: message.id)
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

      assert pid = ChannelServer.whereis(channel_id)
      assert %{typing_users: %{^sender_id => deadline}} = :sys.get_state(pid)

      send(pid, {:typing_expired, sender_id, deadline})

      assert_receive {:typing_stopped, %{channel_id: ^channel_id, user_id: ^sender_id}}

      refute has_element?(
               receiver_view,
               "#channel-typing-indicator [data-typing-user-id='#{sender_id}']"
             )
    end

    test "shows load older when the initial message page is full", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      for index <- 1..50 do
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "message #{index}",
          DateTime.add(~U[2026-06-19 10:00:00Z], index, :second)
        )
      end

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#load-older-messages", "Load older")
    end

    test "hides load older for empty and short channels", %{conn: conn, scope: scope} do
      {:ok, empty_workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, empty_view, _html} =
        live(
          conn,
          ~p"/workspaces/#{empty_workspace.id}/channels/#{empty_workspace.default_channel_id}"
        )

      refute has_element?(empty_view, "#load-older-messages")

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
    end

    test "loads older messages above the current stream without duplicating the cursor", %{
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
      refute has_element?(view, "#message-#{hd(messages).id}")

      view
      |> element("#load-older-messages")
      |> render_click()

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
      refute has_element?(view, "#load-older-messages")

      refute_push_event(view, "scroll_channel_messages_to_bottom", %{
        container_id: _container_id
      })
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
               live(conn, ~p"/workspaces/#{workspace.id}/channels/-1")

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
      assert expected_path =~ ~r|^/workspaces/#{workspace.id}/channels/\d+$|

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

      refute has_element?(view, "#workspace-#{workspace.id}-invite-new")
    end

    test "shows the invite action to members in members-can-invite workspaces", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      workspace = set_invite_policy!(workspace, "members_can_invite")
      add_workspace_member!(workspace, member_scope)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{workspace.id}/channels/#{workspace.default_channel_id}")

      assert has_element?(view, "#workspace-#{workspace.id}-invite-new")
    end

    test "renders the workspace shell without creating an invite", %{conn: conn, scope: scope} do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/invites/new")

      assert has_element?(view, "#workspace-app-shell")
      assert has_element?(view, "#workspace-#{workspace.id}[aria-current='page']")
      assert has_element?(view, "#workspace-#{workspace.id}-invite-new")
      assert has_element?(view, "#channel-#{workspace.default_channel_id}")
      refute has_element?(view, "#channel-#{workspace.default_channel_id}[aria-current='page']")
      assert has_element?(view, "#workspace-invite-create-form")
      assert Repo.aggregate(WorkspaceInvite, :count) == 0
    end

    test "renders durable workspace members in the invite shell", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope =
        %{username: "invite_owner"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      workspace = set_invite_policy!(workspace, "members_can_invite")
      add_workspace_member!(workspace, member_scope)

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/invites/new")

      assert has_element?(view, "#workspace-members-sidebar[aria-label='Workspace members']")

      assert has_element?(
               view,
               "#workspace-member-#{owner_scope.user.id}[data-presence-state='offline']",
               "invite_owner"
             )

      assert has_element?(
               view,
               "#workspace-member-#{member_scope.user.id}",
               member_scope.user.username
             )

      assert has_element?(view, "#workspace-invite-create-form")
    end

    test "marks the current member online after entering an invite surface", %{
      conn: conn,
      scope: member_scope
    } do
      owner_scope =
        %{username: "invite_presence_owner"}
        |> DiscordClone.AccountsFixtures.user_fixture()
        |> DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      workspace = set_invite_policy!(workspace, "members_can_invite")
      add_workspace_member!(workspace, member_scope)

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}/invites/new")

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
      workspace = set_invite_policy!(workspace, "members_can_invite")
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
        |> order_by([invite], desc: invite.id)
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
  end

  defp add_workspace_member!(workspace, scope) do
    %WorkspaceMembership{}
    |> WorkspaceMembership.changeset(%{
      workspace_id: workspace.id,
      user_id: scope.user.id,
      role: "member"
    })
    |> Repo.insert!()
  end

  defp insert_message!(channel_id, user_id, content, inserted_at) do
    Repo.insert!(%Message{
      channel_id: channel_id,
      user_id: user_id,
      content: content,
      inserted_at: inserted_at,
      updated_at: inserted_at
    })
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

  defp set_invite_policy!(workspace, invite_policy) do
    workspace
    |> Ecto.Changeset.change(invite_policy: invite_policy)
    |> Repo.update!()
  end

  defp workspace_member_row_ids(view, user_id) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> then(& &1["#workspace-members > #workspace-member-#{user_id}"])
    |> LazyHTML.attribute("id")
  end
end
