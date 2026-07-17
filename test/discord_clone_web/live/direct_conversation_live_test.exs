defmodule DiscordCloneWeb.DirectConversationLiveTest do
  use DiscordCloneWeb.ConnCase, async: false

  import DiscordClone.AccountsFixtures
  import Phoenix.LiveViewTest

  alias DiscordClone.Chat
  alias DiscordClone.Friendships

  setup :register_and_log_in_user

  test "Message opens one empty Direct Conversation and either participant can revisit it", %{
    conn: conn,
    user: user,
    scope: scope
  } do
    friend = user_fixture(username: "live_direct_friend")
    friend_scope = user_scope_fixture(friend)

    assert {:ok, %{relationship: request}} =
             Friendships.send_friend_request(scope, %{username: friend.username})

    assert {:ok, _friendship} = Friendships.accept_friend_request(friend_scope, request.id)

    {:ok, friends_view, _html} = live(conn, ~p"/friends")

    assert has_element?(friends_view, "#message-friend-#{friend.id}")

    friends_view
    |> element("#message-friend-#{friend.id}")
    |> render_click()

    assert {:ok, direct_conversation} = Chat.find_direct_conversation(scope, friend.id)
    direct_path = ~p"/direct-messages/#{direct_conversation.id}"
    assert_redirected(friends_view, direct_path)

    {:ok, direct_view, _html} = live(conn, direct_path)

    assert has_element?(direct_view, "#direct-conversation")
    assert has_element?(direct_view, "#direct-conversation-empty")
    assert has_element?(direct_view, "#direct-conversation-participant-#{friend.id}")

    friend_conn = build_conn() |> log_in_user(friend)
    assert {:ok, friend_view, _html} = live(friend_conn, direct_path)
    assert has_element?(friend_view, "#direct-conversation-participant-#{user.id}")
  end

  test "non-participants receive the same not-found navigation as a missing Conversation", %{
    conn: _conn,
    scope: scope
  } do
    friend = user_fixture(username: "private_route_friend")
    friend_scope = user_scope_fixture(friend)
    outsider = user_fixture(username: "private_route_outsider")

    assert {:ok, %{relationship: request}} =
             Friendships.send_friend_request(scope, %{username: friend.username})

    assert {:ok, _friendship} = Friendships.accept_friend_request(friend_scope, request.id)
    assert {:ok, direct_conversation} = Chat.open_direct_conversation(scope, friend.id)

    outsider_conn = build_conn() |> log_in_user(outsider)

    assert {:error, {:live_redirect, %{to: "/friends"}}} =
             live(outsider_conn, ~p"/direct-messages/#{direct_conversation.id}")

    assert {:error, {:live_redirect, %{to: "/friends"}}} =
             live(outsider_conn, ~p"/direct-messages/#{Ecto.UUID.generate()}")
  end

  test "Direct Conversation routes require the established authenticated session", %{conn: _conn} do
    conn = Phoenix.ConnTest.build_conn()

    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(conn, ~p"/direct-messages/#{Ecto.UUID.generate()}")
  end
end
