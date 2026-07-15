defmodule DiscordClone.Chat.ActivityTest do
  use DiscordClone.DataCase, async: false

  alias DiscordClone.Accounts
  alias DiscordClone.Accounts.Scope
  alias DiscordClone.Activities.ActivityItem
  alias DiscordClone.Chat
  alias DiscordClone.Repo
  alias DiscordClone.Workspaces
  alias DiscordClone.Workspaces.WorkspaceMembership

  import DiscordClone.AccountsFixtures

  describe "direct mention activity through the Chat context" do
    test "creates one unread item for each current mentioned member" do
      author_scope = user_scope_fixture(user_fixture(%{username: "sender_user"}))
      target_scope = user_scope_fixture(user_fixture(%{username: "target_user"}))
      second_scope = user_scope_fixture(user_fixture(%{username: "second_user"}))
      non_member_scope = user_scope_fixture(user_fixture(%{username: "outsider_user"}))
      {:ok, workspace} = Workspaces.create_workspace(author_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope)
      add_workspace_member!(workspace, second_scope)

      content =
        "Email sender_user@example.com; hi (@TARGET_USER), @target_user! " <>
          "@second_user. Ignore @unknown_user, @outsider_user, and @sender_user."

      assert {:ok, message} =
               Chat.send_message(author_scope, workspace.default_channel_id, %{content: content})

      assert message.content == content

      assert [target_item] = activity_items_for(target_scope.user.id)
      assert target_item.recipient_user_id == target_scope.user.id
      assert target_item.actor_user_id == author_scope.user.id
      assert target_item.source_message_id == message.id
      assert target_item.source_channel_id == workspace.default_channel_id
      assert target_item.workspace_id == workspace.id
      assert target_item.kind == "user_mention"
      assert is_nil(target_item.read_at)
      assert %DateTime{} = target_item.inserted_at

      assert [_second_item] = activity_items_for(second_scope.user.id)
      assert [] = activity_items_for(author_scope.user.id)
      assert [] = activity_items_for(non_member_scope.user.id)
      assert {:ok, 1} = Chat.unread_activity_count(target_scope)
      assert {:ok, 1} = Chat.unread_activity_count(second_scope)
      assert {:ok, 0} = Chat.unread_activity_count(author_scope)
    end

    test "keeps the original recipient when membership and usernames later change" do
      author_scope = user_scope_fixture(user_fixture(%{username: "message_author"}))
      original_scope = user_scope_fixture(user_fixture(%{username: "original_name"}))
      {:ok, workspace} = Workspaces.create_workspace(author_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, original_scope)

      assert {:ok, first_message} =
               Chat.send_message(author_scope, workspace.default_channel_id, %{
                 content: "hello @original_name"
               })

      original_membership =
        Repo.get_by!(WorkspaceMembership,
          workspace_id: workspace.id,
          user_id: original_scope.user.id
        )

      Repo.delete!(original_membership)

      assert [original_item] = activity_items_for(original_scope.user.id)
      assert original_item.source_message_id == first_message.id

      assert {:ok, renamed_user} =
               Accounts.update_user_username(original_scope, %{username: "renamed_user"})

      renamed_scope = Scope.for_user(renamed_user)
      replacement_scope = user_scope_fixture(user_fixture(%{username: "original_name"}))
      add_workspace_member!(workspace, replacement_scope)

      assert {:ok, second_message} =
               Chat.send_message(author_scope, workspace.default_channel_id, %{
                 content: "hello again @original_name"
               })

      assert [original_item] = activity_items_for(renamed_scope.user.id)
      assert original_item.source_message_id == first_message.id
      assert original_item.recipient_user_id == renamed_user.id

      assert [replacement_item] = activity_items_for(replacement_scope.user.id)
      assert replacement_item.source_message_id == second_message.id
      assert replacement_item.recipient_user_id == replacement_scope.user.id
    end

    test "rolls mention activity and sequencing back when reply validation fails" do
      author_scope = user_scope_fixture(user_fixture(%{username: "rollback_author"}))
      target_scope = user_scope_fixture(user_fixture(%{username: "rollback_target"}))
      {:ok, workspace} = Workspaces.create_workspace(author_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope)

      assert {:error, :invalid_message, changeset} =
               Chat.send_message(author_scope, workspace.default_channel_id, %{
                 content: "hello @rollback_target",
                 reply_to_message_id: Ecto.UUID.generate()
               })

      assert "is not an earlier message in this channel" in errors_on(changeset).reply_to_message_id
      assert [] = activity_items_for(target_scope.user.id)

      assert {:ok, message} =
               Chat.send_message(author_scope, workspace.default_channel_id, %{content: "first"})

      assert message.seq == 1
    end

    test "rolls message, sequence, activity, and unread fan-out back when activity insertion fails" do
      author_scope = user_scope_fixture(user_fixture(%{username: "failure_author"}))
      target_scope = user_scope_fixture(user_fixture(%{username: "failure_target"}))
      {:ok, workspace} = Workspaces.create_workspace(author_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope)

      Ecto.Adapters.SQL.query!(
        Repo,
        """
        ALTER TABLE activity_items
        ADD CONSTRAINT activity_items_test_reject_mentions
        CHECK (kind <> 'user_mention')
        """,
        []
      )

      assert_raise Ecto.ConstraintError, ~r/activity_items_test_reject_mentions/, fn ->
        Chat.send_message(author_scope, workspace.default_channel_id, %{
          content: "hello @failure_target"
        })
      end

      assert [] = activity_items_for(target_scope.user.id)
      assert {:ok, 0} = Chat.unread_activity_count(target_scope)
      assert {:ok, %{}} = Chat.list_unread_counts(target_scope, workspace.id)

      assert {:ok, message} =
               Chat.send_message(author_scope, workspace.default_channel_id, %{content: "first"})

      assert message.seq == 1
    end

    test "rolls inserted activity and message state back when unread fan-out fails" do
      author_scope = user_scope_fixture(user_fixture(%{username: "unread_failure_author"}))
      target_scope = user_scope_fixture(user_fixture(%{username: "unread_failure_target"}))
      {:ok, workspace} = Workspaces.create_workspace(author_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope)

      Ecto.Adapters.SQL.query!(
        Repo,
        """
        ALTER TABLE channel_read_states
        ADD CONSTRAINT channel_read_states_test_reject_unread
        CHECK (unread_count = 0)
        """,
        []
      )

      assert_raise Ecto.ConstraintError, ~r/channel_read_states_test_reject_unread/, fn ->
        Chat.send_message(author_scope, workspace.default_channel_id, %{
          content: "hello @unread_failure_target"
        })
      end

      assert [] = activity_items_for(target_scope.user.id)
      assert {:ok, 0} = Chat.unread_activity_count(target_scope)
      assert {:ok, %{}} = Chat.list_unread_counts(target_scope, workspace.id)

      Ecto.Adapters.SQL.query!(
        Repo,
        "ALTER TABLE channel_read_states DROP CONSTRAINT channel_read_states_test_reject_unread",
        []
      )

      assert {:ok, message} =
               Chat.send_message(author_scope, workspace.default_channel_id, %{content: "first"})

      assert message.seq == 1
    end

    test "rejects duplicate items for one recipient and source message" do
      author_scope = user_scope_fixture(user_fixture(%{username: "unique_author"}))
      target_scope = user_scope_fixture(user_fixture(%{username: "unique_target"}))
      {:ok, workspace} = Workspaces.create_workspace(author_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, target_scope)

      assert {:ok, message} =
               Chat.send_message(author_scope, workspace.default_channel_id, %{
                 content: "hello @unique_target"
               })

      assert {:error, changeset} =
               %ActivityItem{
                 recipient_user_id: target_scope.user.id,
                 actor_user_id: author_scope.user.id,
                 source_message_id: message.id,
                 source_channel_id: workspace.default_channel_id,
                 workspace_id: workspace.id
               }
               |> ActivityItem.create_changeset("future_kind")
               |> Repo.insert()

      assert %{recipient_user_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "requires an authenticated scope to read private activity" do
      assert Chat.unread_activity_count(nil) == {:error, :unauthenticated}
      assert Chat.unread_activity_count(%Scope{}) == {:error, :unauthenticated}
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

  defp activity_items_for(user_id) do
    Repo.all(
      from activity_item in ActivityItem,
        where: activity_item.recipient_user_id == ^user_id,
        order_by: [desc: activity_item.inserted_at, desc: activity_item.id]
    )
  end
end
