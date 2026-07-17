defmodule DiscordClone.FriendshipsTest do
  use DiscordClone.DataCase, async: false

  import DiscordClone.AccountsFixtures

  alias DiscordClone.Friendships

  describe "send_friend_request/2" do
    test "resolves only a canonical exact global username" do
      requester = user_fixture(username: "requester")
      target = user_fixture(username: "exact_target")
      scope = user_scope_fixture(requester)

      assert {:ok, %{relationship: request, user: resolved_target}} =
               Friendships.send_friend_request(scope, %{username: "  EXACT_TARGET  "})

      assert request.status == :pending
      assert request.requested_by_user_id == requester.id
      assert target.id in [request.user_low_id, request.user_high_id]
      assert resolved_target.id == target.id

      assert {:error, :unknown_user} =
               Friendships.send_friend_request(scope, %{username: "exact"})

      assert {:error, :unknown_user} =
               Friendships.send_friend_request(scope, %{username: "missing_user"})
    end

    test "rejects self-targeting and unauthenticated calls" do
      user = user_fixture(username: "self_target")

      assert {:error, :self_request} =
               Friendships.send_friend_request(user_scope_fixture(user), %{
                 username: user.username
               })

      assert {:error, :unauthenticated} =
               Friendships.send_friend_request(nil, %{username: user.username})
    end

    test "is idempotent for repeated pending requests" do
      requester = user_fixture(username: "repeat_sender")
      target = user_fixture(username: "repeat_target")
      scope = user_scope_fixture(requester)

      assert {:ok, %{relationship: first}} =
               Friendships.send_friend_request(scope, %{username: target.username})

      assert {:ok, %{relationship: repeated}} =
               Friendships.send_friend_request(scope, %{username: target.username})

      assert repeated.id == first.id
      assert repeated.status == :pending
    end

    test "crossed requests atomically resolve to one accepted relationship" do
      first_user = user_fixture(username: "crossed_first")
      second_user = user_fixture(username: "crossed_second")

      requests = [
        {user_scope_fixture(first_user), second_user.username},
        {user_scope_fixture(second_user), first_user.username}
      ]

      results =
        requests
        |> Task.async_stream(
          fn {scope, username} ->
            Friendships.send_friend_request(scope, %{username: username})
          end,
          ordered: false,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert [
               {:ok, %{relationship: first}},
               {:ok, %{relationship: second}}
             ] = results

      assert first.id == second.id
      relationship_id = first.id

      assert {:ok, %{id: ^relationship_id, status: :accepted}} =
               Friendships.get_relationship(user_scope_fixture(first_user), relationship_id)
    end
  end

  describe "pending request lists" do
    test "separates stable incoming and outgoing lists without workspace membership" do
      user = user_fixture(username: "list_owner")
      incoming_user = user_fixture(username: "incoming_user")
      outgoing_user = user_fixture(username: "outgoing_user")

      assert {:ok, %{relationship: incoming_request}} =
               Friendships.send_friend_request(user_scope_fixture(incoming_user), %{
                 username: user.username
               })

      assert {:ok, %{relationship: outgoing_request}} =
               Friendships.send_friend_request(user_scope_fixture(user), %{
                 username: outgoing_user.username
               })

      assert {:ok, [incoming]} =
               Friendships.list_incoming_requests(user_scope_fixture(user))

      assert {:ok, [outgoing]} =
               Friendships.list_outgoing_requests(user_scope_fixture(user))

      assert incoming.relationship.id == incoming_request.id
      assert incoming.user.username == incoming_user.username
      assert outgoing.relationship.id == outgoing_request.id
      assert outgoing.user.username == outgoing_user.username
    end

    test "does not expose another pair through lists or direct relationship lookup" do
      first_user = user_fixture(username: "private_first")
      second_user = user_fixture(username: "private_second")
      unrelated_user = user_fixture(username: "private_unrelated")

      assert {:ok, %{relationship: relationship}} =
               Friendships.send_friend_request(user_scope_fixture(first_user), %{
                 username: second_user.username
               })

      unrelated_scope = user_scope_fixture(unrelated_user)

      assert {:ok, []} = Friendships.list_incoming_requests(unrelated_scope)
      assert {:ok, []} = Friendships.list_outgoing_requests(unrelated_scope)

      assert {:error, :not_found} =
               Friendships.get_relationship(unrelated_scope, relationship.id)

      assert {:error, :unauthenticated} = Friendships.list_incoming_requests(nil)
      assert {:error, :unauthenticated} = Friendships.list_outgoing_requests(nil)
    end
  end
end
