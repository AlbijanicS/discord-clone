defmodule DiscordCloneWeb.WorkspaceLive.HomeTest do
  use DiscordCloneWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DiscordClone.Workspaces
  alias DiscordClone.Workspaces.Channel
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
      assert has_element?(view, "#channel-create-toggle")
      assert has_element?(view, "#message-composer-placeholder[disabled]")
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
end
