defmodule DiscordClone.Chat.DirectConversationsTest do
  use DiscordClone.DataCase, async: false

  import DiscordClone.AccountsFixtures

  alias DiscordClone.Chat
  alias DiscordClone.Chat.{Conversation, DirectConversation}
  alias DiscordClone.Friendships
  alias DiscordClone.Repo
  alias DiscordClone.Workspaces

  describe "open_direct_conversation/2" do
    test "creates one empty Direct Conversation lazily for an accepted Friendship" do
      {first_user, second_user, first_scope, _second_scope, _friendship} = accepted_friendship()

      assert {:error, :not_found} =
               Chat.find_direct_conversation(first_scope, second_user.id)

      assert {:ok, direct_conversation} =
               Chat.open_direct_conversation(first_scope, second_user.id)

      assert direct_conversation.user_low_id in [first_user.id, second_user.id]
      assert direct_conversation.user_high_id in [first_user.id, second_user.id]
      assert direct_conversation.user_low_id < direct_conversation.user_high_id
      assert direct_conversation.conversation.kind == :direct_conversation
      assert direct_conversation.conversation.last_message_seq == 0

      assert {:ok, found} = Chat.find_direct_conversation(first_scope, second_user.id)
      assert found.id == direct_conversation.id
    end

    test "does not create a Direct Conversation for a pending request or by accepting alone" do
      first_user = user_fixture(username: "lazy_pending_first")
      second_user = user_fixture(username: "lazy_pending_second")
      first_scope = user_scope_fixture(first_user)
      second_scope = user_scope_fixture(second_user)

      assert {:ok, %{relationship: request}} =
               Friendships.send_friend_request(first_scope, %{username: second_user.username})

      assert {:error, :not_friends} = Chat.open_direct_conversation(first_scope, second_user.id)

      assert {:error, :not_found} =
               Chat.find_direct_conversation(first_scope, second_user.id)

      assert {:ok, _friendship} = Friendships.accept_friend_request(second_scope, request.id)

      assert {:error, :not_found} =
               Chat.find_direct_conversation(first_scope, second_user.id)

      assert {:error, :not_found} =
               Chat.find_direct_conversation(second_scope, first_user.id)
    end

    test "simultaneous first opens converge on the canonical pair" do
      {_first_user, second_user, first_scope, second_scope, _friendship} =
        accepted_friendship("concurrent")

      parent = self()

      workers =
        [
          {first_scope, second_user.id},
          {second_scope, first_scope.user.id},
          {first_scope, second_user.id},
          {second_scope, first_scope.user.id}
        ]
        |> Enum.with_index()
        |> Enum.map(fn {{scope, friend_user_id}, index} ->
          pid =
            start_supervised!(%{
              id: {__MODULE__, index},
              start:
                {Task, :start_link,
                 [
                   fn ->
                     send(parent, {:ready, self()})

                     receive do
                       {:open, ^parent} ->
                         send(
                           parent,
                           {:opened, Chat.open_direct_conversation(scope, friend_user_id)}
                         )
                     end
                   end
                 ]}
            })

          assert_receive {:ready, ^pid}
          pid
        end)

      Enum.each(workers, &send(&1, {:open, parent}))

      results =
        for _worker <- workers do
          assert_receive {:opened, {:ok, direct_conversation}}
          direct_conversation
        end

      assert results |> Enum.map(& &1.id) |> Enum.uniq() |> length() == 1

      assert {:ok, one_direct_conversation} =
               Chat.find_direct_conversation(first_scope, second_user.id)

      assert one_direct_conversation.id == hd(results).id
    end

    test "preserves history identity after removal and reuses it after restoration" do
      {_first_user, second_user, first_scope, second_scope, friendship} =
        accepted_friendship("restored")

      assert {:ok, original} = Chat.open_direct_conversation(first_scope, second_user.id)
      assert :ok = Friendships.remove_friend(first_scope, friendship.id)

      assert {:ok, preserved} = Chat.get_direct_conversation(second_scope, original.id)
      assert preserved.direct_conversation.id == original.id
      assert {:ok, still_accessible} = Chat.open_direct_conversation(first_scope, second_user.id)
      assert still_accessible.id == original.id

      assert {:ok, %{relationship: request}} =
               Friendships.send_friend_request(first_scope, %{username: second_user.username})

      assert {:ok, _restored_friendship} =
               Friendships.accept_friend_request(second_scope, request.id)

      assert {:ok, reopened} = Chat.open_direct_conversation(second_scope, first_scope.user.id)
      assert reopened.id == original.id
    end

    test "rejects unauthenticated, self, missing, and non-Friend opens" do
      user = user_fixture(username: "invalid_open_user")
      other_user = user_fixture(username: "invalid_open_other")
      scope = user_scope_fixture(user)

      assert {:error, :unauthenticated} = Chat.open_direct_conversation(nil, other_user.id)
      assert {:error, :invalid_participant} = Chat.open_direct_conversation(scope, user.id)
      assert {:error, :not_found} = Chat.open_direct_conversation(scope, Ecto.UUID.generate())
      assert {:error, :not_friends} = Chat.open_direct_conversation(scope, other_user.id)
    end
  end

  describe "get_direct_conversation/2" do
    test "returns the same private Conversation to either participant and not-found to others" do
      {_first_user, second_user, first_scope, second_scope, _friendship} =
        accepted_friendship("private")

      outsider_scope = user_scope_fixture(user_fixture(username: "private_outsider"))
      {:ok, direct_conversation} = Chat.open_direct_conversation(first_scope, second_user.id)

      assert {:ok, first_view} =
               Chat.get_direct_conversation(first_scope, direct_conversation.id)

      assert {:ok, second_view} =
               Chat.get_direct_conversation(second_scope, direct_conversation.id)

      assert first_view.direct_conversation.id == second_view.direct_conversation.id
      assert first_view.other_participant.id == second_scope.user.id
      assert second_view.other_participant.id == first_scope.user.id

      assert {:error, :not_found} =
               Chat.get_direct_conversation(outsider_scope, direct_conversation.id)

      assert {:error, :not_found} =
               Chat.get_direct_conversation(outsider_scope, Ecto.UUID.generate())

      assert {:error, :unauthenticated} =
               Chat.get_direct_conversation(nil, direct_conversation.id)
    end

    test "participant foreign keys restrict hard User deletion" do
      {first_user, second_user, first_scope, _second_scope, friendship} =
        accepted_friendship("delete")

      assert {:ok, _direct_conversation} =
               Chat.open_direct_conversation(first_scope, second_user.id)

      assert :ok = Friendships.remove_friend(first_scope, friendship.id)
      assert_raise Ecto.ConstraintError, fn -> Repo.delete!(first_user) end
    end
  end

  describe "Direct Conversation persistence invariants" do
    test "rejects a bare Direct Conversation base and a subtype with the wrong kind" do
      assert_raise Postgrex.Error, ~r/conversations_require_matching_subtype/, fn ->
        Repo.transaction(fn ->
          %Conversation{}
          |> Conversation.direct_conversation_changeset()
          |> Repo.insert!()

          Ecto.Adapters.SQL.query!(Repo, "SET CONSTRAINTS ALL IMMEDIATE", [])
        end)
      end

      first_user = user_fixture(username: "wrong_kind_first")
      second_user = user_fixture(username: "wrong_kind_second")

      {:ok, workspace} =
        Workspaces.create_workspace(user_scope_fixture(first_user), %{name: "Wrong subtype"})

      assert_raise Postgrex.Error, ~r/direct_conversations_require_direct_kind/, fn ->
        %DirectConversation{id: workspace.default_channel_id}
        |> DirectConversation.create_changeset(%{
          user_low_id: min(first_user.id, second_user.id),
          user_high_id: max(first_user.id, second_user.id)
        })
        |> Repo.insert!()
      end
    end

    test "rejects a repeated User and has no Workspace identity" do
      user = user_fixture(username: "same_direct_participant")

      assert_raise Postgrex.Error, ~r/direct_conversations_canonical_pair/, fn ->
        Repo.transaction(fn ->
          conversation =
            %Conversation{}
            |> Conversation.direct_conversation_changeset()
            |> Repo.insert!()

          Ecto.Adapters.SQL.query!(
            Repo,
            """
            INSERT INTO direct_conversations (
              conversation_id, user_low_id, user_high_id, inserted_at, updated_at
            ) VALUES ($1, $2, $2, now(), now())
            """,
            [Ecto.UUID.dump!(conversation.id), Ecto.UUID.dump!(user.id)]
          )
        end)
      end

      refute :workspace_id in DirectConversation.__schema__(:fields)
    end

    test "rejects deleting the subtype while its Conversation base remains" do
      {_first_user, second_user, first_scope, _second_scope, _friendship} =
        accepted_friendship("orphan")

      {:ok, direct_conversation} =
        Chat.open_direct_conversation(first_scope, second_user.id)

      assert_raise Postgrex.Error, ~r/conversations_require_matching_subtype/, fn ->
        Repo.transaction(fn ->
          Repo.delete!(direct_conversation)
          Ecto.Adapters.SQL.query!(Repo, "SET CONSTRAINTS ALL IMMEDIATE", [])
        end)
      end

      assert Repo.get(Conversation, direct_conversation.id)
    end
  end

  defp accepted_friendship(suffix \\ "lazy") do
    first_user = user_fixture(username: "#{suffix}_first")
    second_user = user_fixture(username: "#{suffix}_second")
    first_scope = user_scope_fixture(first_user)
    second_scope = user_scope_fixture(second_user)

    assert {:ok, %{relationship: request}} =
             Friendships.send_friend_request(first_scope, %{username: second_user.username})

    assert {:ok, friendship} = Friendships.accept_friend_request(second_scope, request.id)

    {first_user, second_user, first_scope, second_scope, friendship}
  end
end
