defmodule DiscordCloneWeb.PageControllerTest do
  use DiscordCloneWeb.ConnCase

  import DiscordClone.AccountsFixtures

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
  end

  test "GET / redirects authenticated users to the workspace app", %{conn: conn} do
    user = user_fixture()

    conn =
      conn
      |> log_in_user(user)
      |> get(~p"/")

    assert redirected_to(conn) == ~p"/workspaces"
  end
end
