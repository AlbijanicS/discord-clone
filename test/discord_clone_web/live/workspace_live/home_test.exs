defmodule DiscordCloneWeb.WorkspaceLive.HomeTest do
  use DiscordCloneWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias DiscordClone.Workspaces
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

    test "shows existing workspaces and keeps creation behind a compact action", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      {:ok, view, _html} = live(conn, ~p"/workspaces")

      assert has_element?(view, "#workspaces [aria-label='Open #{workspace.name}']")
      assert has_element?(view, "#workspace-create-toggle")
      refute has_element?(view, "#workspace-create-form")
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

    test "renders an empty-channel shell when no landing channel exists", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      Repo.delete_all(Channel)

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      assert has_element?(view, "#workspace-app-shell")
      assert has_element?(view, "#channel-empty-state")
      assert has_element?(view, "#channel-create-form")
      assert has_element?(view, "#workspace-main-empty-channel")
    end

    test "creates the first channel from an empty workspace entry", %{conn: conn, scope: scope} do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      Repo.delete_all(Channel)

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      {:error, {:live_redirect, %{to: path}}} =
        view
        |> form("#channel-create-form", channel: %{name: "Planning"})
        |> render_submit()

      assert %{path: expected_path} = URI.parse(path)
      assert expected_path =~ ~r|^/workspaces/#{workspace.id}/channels/\d+$|
    end

    test "renames the selected workspace from an empty-channel shell", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      Repo.delete_all(Channel)

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

      view
      |> element("#workspace-#{workspace.id}-actions")
      |> render_click()

      view
      |> element("#workspace-#{workspace.id}-rename")
      |> render_click()

      view
      |> form("#workspace-#{workspace.id}-rename-form", workspace: %{name: "Design Guild"})
      |> render_submit()

      assert has_element?(view, "#workspace-#{workspace.id}", "Design Guild")
      assert has_element?(view, "#selected-workspace-name", "Design Guild")
      assert has_element?(view, "#workspace-main-empty-channel")
    end

    test "deletes the selected workspace from an empty-channel shell", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      Repo.delete_all(Channel)

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

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

    test "opens the workspace action menu from a context menu event in an empty-channel shell", %{
      conn: conn,
      scope: scope
    } do
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      Repo.delete_all(Channel)

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.id}")

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
      assert has_element?(view, "#message-composer-placeholder[disabled]")
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

      assert has_element?(view, "#workspace-#{workspace.id}", "Design Guild")
      assert has_element?(view, "#selected-workspace-name", "Design Guild")
      assert has_element?(view, "#channel-main", "Messages are coming soon")
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
      assert has_element?(view, "#channel-main", "Messages are coming soon")
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
  end

  describe "/workspaces/:workspace_id/invites/new" do
    setup :register_and_log_in_user

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
      assert has_element?(view, "#workspace-invite-copy")
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
end
