defmodule DiscordCloneWeb.FriendsLiveTest do
  use DiscordCloneWeb.ConnCase, async: false

  import DiscordClone.AccountsFixtures
  import Phoenix.LiveViewTest

  alias DiscordClone.Friendships

  setup :register_and_log_in_user

  test "authenticated User sees stable incoming and outgoing request streams", %{
    conn: conn,
    user: user
  } do
    sender = user_fixture(username: "friends_sender")
    recipient = user_fixture(username: "friends_recipient")

    assert {:ok, %{relationship: incoming}} =
             Friendships.send_friend_request(user_scope_fixture(sender), %{
               username: user.username
             })

    assert {:ok, %{relationship: outgoing}} =
             Friendships.send_friend_request(user_scope_fixture(user), %{
               username: recipient.username
             })

    {:ok, view, _html} = live(conn, ~p"/friends")

    assert has_element?(view, "#friends-home")
    assert has_element?(view, "#friend-request-form")
    assert has_element?(view, "#incoming-requests[phx-update='stream']")
    assert has_element?(view, "#incoming-request-#{incoming.id}")
    assert has_element?(view, "#outgoing-requests[phx-update='stream']")
    assert has_element?(view, "#outgoing-request-#{outgoing.id}")
  end

  test "exact-username form reports validation outcomes and refreshes outgoing requests", %{
    conn: conn,
    user: user
  } do
    target = user_fixture(username: "form_target")
    {:ok, view, _html} = live(conn, ~p"/friends")

    view
    |> form("#friend-request-form", friend_request: %{username: "form"})
    |> render_submit()

    assert has_element?(view, "#friend-request-outcome[data-kind='error']")
    refute has_element?(view, "#outgoing-requests [id^='outgoing-request-']")

    view
    |> form("#friend-request-form", friend_request: %{username: target.username})
    |> render_submit()

    assert has_element?(view, "#friend-request-outcome[data-kind='success']")
    assert has_element?(view, "#outgoing-requests [id^='outgoing-request-']")

    view
    |> form("#friend-request-form", friend_request: %{username: user.username})
    |> render_submit()

    assert has_element?(view, "#friend-request-outcome[data-kind='error']")
  end

  test "unauthenticated visitors follow the established login redirect", %{conn: _conn} do
    conn = Phoenix.ConnTest.build_conn()

    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/friends")
  end
end
