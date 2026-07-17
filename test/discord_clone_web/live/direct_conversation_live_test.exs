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

  test "current Friends reply and both sessions share author deletion placeholders", %{
    conn: conn,
    scope: scope
  } do
    {friend, friend_scope, direct_conversation, direct_path} =
      direct_conversation_fixture(scope, "live_reply")

    assert {:ok, parent} =
             Chat.send_direct_message(scope, direct_conversation.id, %{content: "reply target"})

    friend_conn = build_conn() |> log_in_user(friend)
    {:ok, author_view, _html} = live(conn, direct_path)
    {:ok, friend_view, _html} = live(friend_conn, direct_path)

    assert {:ok, stale_target} =
             Chat.send_direct_message(scope, direct_conversation.id, %{content: "stale target"})

    assert {:ok, _deleted_stale_target} = Chat.delete_message(scope, stale_target.id)

    render_click(author_view, "begin_direct_reply", %{"message-id" => stale_target.id})
    refute has_element?(author_view, "#direct-message-reply-target")
    assert has_element?(author_view, "#flash-error", "no longer available")

    author_view |> element("#direct-message-#{parent.id}-reply") |> render_click()

    assert has_element?(
             author_view,
             "#direct-message-reply-target[data-message-id='#{parent.id}']"
           )

    author_view
    |> form("#direct-message-form", message: %{content: "flat reply"})
    |> render_submit()

    assert {:ok, messages} = Chat.list_direct_messages(friend_scope, direct_conversation.id)
    reply = List.last(messages)

    assert reply.reply_to_message_id == parent.id
    assert_eventually_has_element(friend_view, "#direct-message-#{reply.id}-reply-preview")

    author_view |> element("#direct-message-#{parent.id}-delete") |> render_click()

    assert_eventually_has_element(author_view, "#direct-message-#{parent.id}-deleted")
    assert_eventually_has_element(friend_view, "#direct-message-#{parent.id}-deleted")
    refute has_element?(friend_view, "#direct-message-#{parent.id}", "reply target")

    assert_eventually_has_element(
      friend_view,
      "#direct-message-#{reply.id}-deleted-reply-preview"
    )

    refute has_element?(friend_view, "#direct-message-#{reply.id}-reply-preview", "reply target")
  end

  test "reactions synchronize and former Friends retain only cleanup controls", %{
    conn: conn,
    scope: scope
  } do
    {friend, friend_scope, direct_conversation, direct_path, friendship} =
      direct_conversation_fixture(scope, "live_reaction", include_friendship: true)

    assert {:ok, own_message} =
             Chat.send_direct_message(scope, direct_conversation.id, %{content: "react here"})

    assert {:ok, friend_message} =
             Chat.send_direct_message(friend_scope, direct_conversation.id, %{content: "cleanup"})

    friend_conn = build_conn() |> log_in_user(friend)
    {:ok, first_view, _html} = live(conn, direct_path)
    {:ok, second_view, _html} = live(friend_conn, direct_path)

    first_view
    |> element("#direct-message-#{own_message.id}-reaction-option-0")
    |> render_click()

    assert_eventually_has_element(
      second_view,
      "#direct-message-#{own_message.id}-reaction-0[data-current-user-reacted='false']"
    )

    second_view
    |> element("#direct-message-#{friend_message.id}-reaction-option-0")
    |> render_click()

    assert :ok = Friendships.remove_friend(friend_scope, friendship.id)
    _ = render(first_view)
    _ = render(second_view)

    assert_eventually_has_element(first_view, "#direct-conversation-read-only")
    refute has_element?(first_view, "#direct-message-form")
    refute has_element?(first_view, "#direct-message-#{own_message.id}-reply")
    refute has_element?(first_view, "#direct-message-#{own_message.id}-reaction-option-0")
    assert has_element?(first_view, "#direct-message-#{own_message.id}-delete")

    assert has_element?(second_view, "#direct-message-#{friend_message.id}-reaction-0")

    second_view
    |> element("#direct-message-#{friend_message.id}-reaction-0")
    |> render_click()

    assert_eventually_lacks_element(first_view, "#direct-message-#{friend_message.id}-reaction-0")
    assert has_element?(second_view, "#direct-message-#{friend_message.id}-delete")
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

  defp assert_eventually_has_element(view, selector, attempts \\ 10)

  defp assert_eventually_has_element(view, selector, attempts) when attempts > 0 do
    if has_element?(view, selector) do
      :ok
    else
      _ = render(view)
      assert_eventually_has_element(view, selector, attempts - 1)
    end
  end

  defp assert_eventually_has_element(_view, selector, 0) do
    flunk("expected element #{selector}")
  end

  defp assert_eventually_lacks_element(view, selector, attempts \\ 10)

  defp assert_eventually_lacks_element(view, selector, attempts) when attempts > 0 do
    if has_element?(view, selector) do
      _ = render(view)
      assert_eventually_lacks_element(view, selector, attempts - 1)
    else
      :ok
    end
  end

  defp assert_eventually_lacks_element(_view, selector, 0) do
    flunk("expected element #{selector} to disappear")
  end

  defp direct_conversation_fixture(scope, suffix, opts \\ []) do
    friend = user_fixture(username: "#{suffix}_friend")
    friend_scope = user_scope_fixture(friend)

    assert {:ok, %{relationship: request}} =
             Friendships.send_friend_request(scope, %{username: friend.username})

    assert {:ok, friendship} = Friendships.accept_friend_request(friend_scope, request.id)
    assert {:ok, direct_conversation} = Chat.open_direct_conversation(scope, friend.id)
    direct_path = ~p"/direct-messages/#{direct_conversation.id}"

    if Keyword.get(opts, :include_friendship, false) do
      {friend, friend_scope, direct_conversation, direct_path, friendship}
    else
      {friend, friend_scope, direct_conversation, direct_path}
    end
  end
end
