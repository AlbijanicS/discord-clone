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

  test "current Friends exchange durable Direct Messages live in both sessions", %{
    conn: conn,
    user: user,
    scope: scope
  } do
    friend = user_fixture(username: "live_message_friend")
    friend_scope = user_scope_fixture(friend)

    assert {:ok, %{relationship: request}} =
             Friendships.send_friend_request(scope, %{username: friend.username})

    assert {:ok, _friendship} = Friendships.accept_friend_request(friend_scope, request.id)
    assert {:ok, direct_conversation} = Chat.open_direct_conversation(scope, friend.id)

    direct_path = ~p"/direct-messages/#{direct_conversation.id}"
    friend_conn = build_conn() |> log_in_user(friend)

    {:ok, sender_view, _html} = live(conn, direct_path)
    {:ok, recipient_view, _html} = live(friend_conn, direct_path)

    assert has_element?(sender_view, "#direct-message-form")
    assert has_element?(recipient_view, "#direct-message-form")

    sender_view
    |> form("#direct-message-form", message: %{content: "A durable hello"})
    |> render_submit()

    assert_eventually_has_message(sender_view, "A durable hello")
    assert_eventually_has_message(recipient_view, "A durable hello")

    assert {:ok, [message]} = Chat.list_direct_messages(scope, direct_conversation.id)
    assert has_element?(sender_view, "#direct-message-#{message.id}")
    assert has_element?(recipient_view, "#direct-message-#{message.id}")

    Process.unlink(sender_view.pid)
    ref = Process.monitor(sender_view.pid)
    GenServer.stop(sender_view.pid)
    assert_receive {:DOWN, ^ref, :process, _pid, :normal}

    {:ok, reconnected_view, _html} = live(conn, direct_path)
    assert has_element?(reconnected_view, "#direct-message-#{message.id}")
    assert has_element?(reconnected_view, "#direct-message-#{message.id}", "A durable hello")

    assert user.id == message.user_id
  end

  defp assert_eventually_has_message(view, content, attempts \\ 10)

  defp assert_eventually_has_message(view, content, attempts) when attempts > 0 do
    if has_element?(view, "[data-direct-message-content]", content) do
      :ok
    else
      _ = render(view)
      assert_eventually_has_message(view, content, attempts - 1)
    end
  end

  defp assert_eventually_has_message(_view, content, 0) do
    flunk("expected Direct Message content #{inspect(content)}")
  end
end
