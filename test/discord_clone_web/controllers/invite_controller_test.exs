defmodule DiscordCloneWeb.InviteControllerTest do
  use DiscordCloneWeb.ConnCase

  alias DiscordClone.Workspaces

  import DiscordClone.AccountsFixtures

  describe "GET /invites/:code" do
    test "redirects anonymous visitors to login and stores return to", %{conn: conn} do
      conn = get(conn, ~p"/invites/missing-code")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "must log in"
      assert get_session(conn, :user_return_to) == ~p"/invites/missing-code"
    end

    test "renders a standalone preview page for a valid invite", %{conn: conn} do
      owner_scope = user_scope_fixture()
      invited_user = user_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      {:ok, _channel} =
        Workspaces.create_channel(owner_scope, workspace.id, %{name: "Secret Ops"})

      {:ok, invite} = Workspaces.create_workspace_invite(owner_scope, workspace.id)

      conn =
        conn
        |> log_in_user(invited_user)
        |> get(~p"/invites/#{invite.code}")

      response = html_response(conn, 200)

      assert response =~ "Join Foundry"
      assert response =~ owner_scope.user.username
      assert response =~ invited_user.username
      assert response =~ "Accept invite"
      refute response =~ "workspace-app-shell"
      refute response =~ "secret-ops"
      refute response =~ owner_scope.user.email
    end

    test "renders a clear failure state without an accept control for missing invites", %{
      conn: conn
    } do
      user = user_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/invites/missing-code")

      response = html_response(conn, 404)

      assert response =~ "This invite link cannot be used."
      assert response =~ "Ask for a fresh invite link"
      refute response =~ "Accept invite"
      refute response =~ "invite-preview-accept-form"
    end
  end
end
