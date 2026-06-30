defmodule DiscordClone.ChatTest do
  use DiscordClone.DataCase, async: false

  alias DiscordClone.Chat
  alias DiscordClone.Accounts.User
  alias DiscordClone.Chat.{ChannelRead, ChannelServer, Message, MessageReaction, WorkspaceServer}
  alias DiscordClone.Workspaces
  alias DiscordClone.Workspaces.Channel
  alias DiscordClone.Workspaces.WorkspaceMembership

  import DiscordClone.AccountsFixtures

  describe "change_message/1" do
    test "returns a message changeset for composer forms" do
      changeset = Chat.change_message(%{content: "hello"})

      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_field(changeset, :content) == "hello"
    end
  end

  describe "initialize_workspace_reads_for_user/2" do
    test "backfills a workspace member through each channel's latest message" do
      owner_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      {:ok, release_channel} =
        Workspaces.create_channel(owner_scope, workspace.id, %{name: "release"})

      {:ok, empty_channel} =
        Workspaces.create_channel(owner_scope, workspace.id, %{name: "empty"})

      general_message =
        insert_message!(
          workspace.default_channel_id,
          owner_scope.user.id,
          "general latest",
          ~U[2026-06-19 10:00:00Z]
        )

      first_release_message =
        insert_message!(
          release_channel.id,
          owner_scope.user.id,
          "release first",
          ~U[2026-06-19 10:01:00Z]
        )

      latest_release_message =
        insert_message!(
          release_channel.id,
          owner_scope.user.id,
          "release latest",
          ~U[2026-06-19 10:02:00Z]
        )

      add_workspace_member!(workspace, member_scope)

      assert :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)

      read_rows =
        Repo.all(
          from read in "channel_reads",
            where: read.user_id == ^member_scope.user.id,
            select: {read.channel_id, read.last_read_message_id}
        )
        |> Map.new()

      assert read_rows == %{
               workspace.default_channel_id => general_message.id,
               release_channel.id => latest_release_message.id,
               empty_channel.id => nil
             }

      refute first_release_message.id in Map.values(read_rows)
    end

    test "requires an existing workspace membership" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      assert Chat.initialize_workspace_reads_for_user(non_member_scope.user.id, workspace.id) ==
               {:error, :not_found}

      refute Repo.get_by(ChannelRead, user_id: non_member_scope.user.id)
    end

    test "keeps one read row per channel and user" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert :ok = Chat.initialize_workspace_reads_for_user(scope.user.id, workspace.id)

      duplicate_changeset =
        ChannelRead.changeset(%ChannelRead{}, %{
          channel_id: workspace.default_channel_id,
          user_id: scope.user.id
        })

      assert {:error, changeset} = Repo.insert(duplicate_changeset)
      assert %{channel_id: ["has already been taken"]} = errors_on(changeset)
      assert Repo.aggregate(ChannelRead, :count) == 1
    end

    test "does not move an existing read cursor backward" do
      owner_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      {:ok, release_channel} =
        Workspaces.create_channel(owner_scope, workspace.id, %{name: "release"})

      {:ok, other_channel} =
        Workspaces.create_channel(owner_scope, workspace.id, %{name: "other"})

      release_message =
        insert_message!(
          release_channel.id,
          owner_scope.user.id,
          "release",
          ~U[2026-06-19 10:00:00Z]
        )

      later_global_message =
        insert_message!(
          other_channel.id,
          owner_scope.user.id,
          "other",
          ~U[2026-06-19 10:01:00Z]
        )

      add_workspace_member!(workspace, member_scope)

      put_channel_read!(release_channel.id, member_scope.user.id, later_global_message.id)

      assert :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)

      assert %ChannelRead{last_read_message_id: last_read_message_id} =
               Repo.get_by(ChannelRead,
                 channel_id: release_channel.id,
                 user_id: member_scope.user.id
               )

      assert last_read_message_id == later_global_message.id
      refute last_read_message_id == release_message.id
    end

    test "removes read rows when a channel is deleted" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, channel} = Workspaces.create_channel(scope, workspace.id, %{name: "scratch"})

      assert :ok = Chat.initialize_workspace_reads_for_user(scope.user.id, workspace.id)
      assert Repo.get_by(ChannelRead, channel_id: channel.id, user_id: scope.user.id)

      Repo.delete!(channel)

      refute Repo.get_by(ChannelRead, channel_id: channel.id, user_id: scope.user.id)
    end

    test "removes read rows when a user is deleted" do
      owner_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)

      assert :ok = Chat.initialize_workspace_reads_for_user(member_scope.user.id, workspace.id)
      assert Repo.get_by(ChannelRead, user_id: member_scope.user.id)

      member = Repo.get!(User, member_scope.user.id)
      Repo.delete!(member)

      refute Repo.get_by(ChannelRead, user_id: member_scope.user.id)
    end

    test "nilifies the cursor when the last-read message is deleted" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "temporary cursor",
          ~U[2026-06-19 10:00:00Z]
        )

      assert :ok = Chat.initialize_workspace_reads_for_user(scope.user.id, workspace.id)

      assert %ChannelRead{last_read_message_id: last_read_message_id} =
               Repo.get_by(ChannelRead,
                 channel_id: workspace.default_channel_id,
                 user_id: scope.user.id
               )

      assert last_read_message_id == message.id

      Repo.delete!(message)

      assert %ChannelRead{last_read_message_id: nil} =
               Repo.get_by(ChannelRead,
                 channel_id: workspace.default_channel_id,
                 user_id: scope.user.id
               )
    end

    test "stores workspace scope through the channel instead of a read column" do
      assert :workspace_id not in ChannelRead.__schema__(:fields)
      assert :channel_reads in Channel.__schema__(:associations)
    end
  end

  describe "list_unread_counts/2" do
    test "counts newer messages from other users and ignores the current user's messages" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, release_channel} = Workspaces.create_channel(scope, workspace.id, %{name: "release"})

      add_workspace_member!(workspace, other_scope)

      older_message =
        insert_message!(
          release_channel.id,
          other_scope.user.id,
          "already read",
          ~U[2026-06-19 10:00:00Z]
        )

      put_channel_read!(release_channel.id, scope.user.id, older_message.id)

      insert_message!(
        release_channel.id,
        other_scope.user.id,
        "please review",
        ~U[2026-06-19 10:01:00Z]
      )

      insert_message!(
        release_channel.id,
        other_scope.user.id,
        "one more thing",
        ~U[2026-06-19 10:02:00Z]
      )

      insert_message!(
        release_channel.id,
        scope.user.id,
        "my follow-up",
        ~U[2026-06-19 10:03:00Z]
      )

      insert_message!(
        workspace.default_channel_id,
        scope.user.id,
        "quiet self note",
        ~U[2026-06-19 10:04:00Z]
      )

      assert {:ok, unread_counts} = Chat.list_unread_counts(scope, workspace.id)
      assert unread_counts == %{release_channel.id => 2}
      assert is_integer(Map.fetch!(unread_counts, release_channel.id))
    end

    test "rejects anonymous scopes" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert Chat.list_unread_counts(nil, workspace.id) == {:error, :unauthenticated}

      assert Chat.list_unread_counts(%DiscordClone.Accounts.Scope{}, workspace.id) ==
               {:error, :unauthenticated}
    end

    test "rejects logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      insert_message!(
        workspace.default_channel_id,
        owner_scope.user.id,
        "private update",
        ~U[2026-06-19 10:00:00Z]
      )

      assert Chat.list_unread_counts(non_member_scope, workspace.id) == {:error, :not_found}
    end

    test "counts only channels in the requested workspace" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, other_workspace} = Workspaces.create_workspace(scope, %{name: "Library"})

      add_workspace_member!(workspace, other_scope)
      add_workspace_member!(other_workspace, other_scope)

      assert :ok = Chat.initialize_workspace_reads_for_user(scope.user.id, workspace.id)
      assert :ok = Chat.initialize_workspace_reads_for_user(scope.user.id, other_workspace.id)

      post_membership_time = DateTime.add(DateTime.utc_now(:second), 10, :second)

      insert_message!(
        workspace.default_channel_id,
        other_scope.user.id,
        "foundry update",
        post_membership_time
      )

      other_workspace_message =
        insert_message!(
          other_workspace.default_channel_id,
          other_scope.user.id,
          "library update",
          DateTime.add(post_membership_time, 1, :second)
        )

      assert {:ok, unread_counts} = Chat.list_unread_counts(scope, workspace.id)
      assert unread_counts == %{workspace.default_channel_id => 1}
      refute Map.has_key?(unread_counts, other_workspace.default_channel_id)
      refute other_workspace_message.channel_id == workspace.default_channel_id
    end

    test "counts unread messages whose author has been deleted" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      add_workspace_member!(workspace, other_scope)

      older_message =
        insert_message!(
          workspace.default_channel_id,
          other_scope.user.id,
          "read before author deletion",
          ~U[2026-06-19 10:00:00Z]
        )

      put_channel_read!(workspace.default_channel_id, scope.user.id, older_message.id)

      deleted_author_message =
        insert_message!(
          workspace.default_channel_id,
          other_scope.user.id,
          "author will be deleted",
          ~U[2026-06-19 10:01:00Z]
        )

      other_user = Repo.get!(User, other_scope.user.id)
      Repo.delete!(other_user)

      assert Repo.get!(Message, deleted_author_message.id).user_id == nil

      assert Chat.list_unread_counts(scope, workspace.id) ==
               {:ok, %{workspace.default_channel_id => 1}}
    end

    test "falls back to membership time for missing and nil read cursors" do
      owner_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      {:ok, release_channel} =
        Workspaces.create_channel(owner_scope, workspace.id, %{name: "release"})

      insert_message!(
        workspace.default_channel_id,
        owner_scope.user.id,
        "old general history",
        ~U[2026-06-19 10:00:00Z]
      )

      insert_message!(
        release_channel.id,
        owner_scope.user.id,
        "old release history",
        ~U[2026-06-19 10:01:00Z]
      )

      add_workspace_member!(workspace, member_scope)

      put_channel_read!(release_channel.id, member_scope.user.id, nil)

      post_membership_time = DateTime.add(DateTime.utc_now(:second), 10, :second)

      insert_message!(
        workspace.default_channel_id,
        owner_scope.user.id,
        "new general update",
        post_membership_time
      )

      insert_message!(
        release_channel.id,
        owner_scope.user.id,
        "new release update",
        DateTime.add(post_membership_time, 1, :second)
      )

      assert Chat.list_unread_counts(member_scope, workspace.id) ==
               {:ok, %{workspace.default_channel_id => 1, release_channel.id => 1}}
    end
  end

  describe "mark_channel_read/2" do
    test "clears unread counts for a workspace member in that channel" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, release_channel} = Workspaces.create_channel(scope, workspace.id, %{name: "release"})

      add_workspace_member!(workspace, other_scope)

      older_message =
        insert_message!(
          release_channel.id,
          other_scope.user.id,
          "already read",
          ~U[2026-06-19 10:00:00Z]
        )

      put_channel_read!(release_channel.id, scope.user.id, older_message.id)

      insert_message!(
        release_channel.id,
        other_scope.user.id,
        "new release update",
        ~U[2026-06-19 10:01:00Z]
      )

      assert Chat.list_unread_counts(scope, workspace.id) == {:ok, %{release_channel.id => 1}}

      assert :ok = Chat.mark_channel_read(scope, release_channel.id)

      assert Chat.list_unread_counts(scope, workspace.id) == {:ok, %{}}
    end

    test "does not move an existing read cursor backward" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, release_channel} = Workspaces.create_channel(scope, workspace.id, %{name: "release"})

      add_workspace_member!(workspace, other_scope)

      release_message =
        insert_message!(
          release_channel.id,
          other_scope.user.id,
          "release update",
          ~U[2026-06-19 10:00:00Z]
        )

      later_general_message =
        insert_message!(
          workspace.default_channel_id,
          other_scope.user.id,
          "later general update",
          ~U[2026-06-19 10:01:00Z]
        )

      assert later_general_message.id > release_message.id

      put_channel_read!(release_channel.id, scope.user.id, later_general_message.id)

      assert :ok = Chat.mark_channel_read(scope, release_channel.id)

      assert %ChannelRead{last_read_message_id: last_read_message_id} =
               Repo.get_by(ChannelRead, channel_id: release_channel.id, user_id: scope.user.id)

      assert last_read_message_id == later_general_message.id
    end

    test "creates a nil read cursor for an empty channel" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, empty_channel} = Workspaces.create_channel(scope, workspace.id, %{name: "empty"})

      assert :ok = Chat.mark_channel_read(scope, empty_channel.id)

      assert %ChannelRead{last_read_message_id: nil} =
               Repo.get_by(ChannelRead, channel_id: empty_channel.id, user_id: scope.user.id)
    end

    test "repairs a missing read row for a workspace member" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      add_workspace_member!(workspace, other_scope)

      latest_message =
        insert_message!(
          workspace.default_channel_id,
          other_scope.user.id,
          "latest update",
          ~U[2026-06-19 10:00:00Z]
        )

      Repo.delete_all(
        from read in ChannelRead,
          where:
            read.channel_id == ^workspace.default_channel_id and
              read.user_id == ^scope.user.id
      )

      assert Repo.get_by(ChannelRead,
               channel_id: workspace.default_channel_id,
               user_id: scope.user.id
             ) == nil

      assert :ok = Chat.mark_channel_read(scope, workspace.default_channel_id)

      assert %ChannelRead{last_read_message_id: last_read_message_id} =
               Repo.get_by(ChannelRead,
                 channel_id: workspace.default_channel_id,
                 user_id: scope.user.id
               )

      assert last_read_message_id == latest_message.id
    end

    test "rejects anonymous scopes and logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      assert Chat.mark_channel_read(nil, workspace.default_channel_id) ==
               {:error, :unauthenticated}

      assert Chat.mark_channel_read(%DiscordClone.Accounts.Scope{}, workspace.default_channel_id) ==
               {:error, :unauthenticated}

      assert Chat.mark_channel_read(non_member_scope, workspace.default_channel_id) ==
               {:error, :not_found}
    end

    test "does not broadcast read-position changes" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      add_workspace_member!(workspace, other_scope)

      insert_message!(
        workspace.default_channel_id,
        other_scope.user.id,
        "quietly read",
        ~U[2026-06-19 10:00:00Z]
      )

      assert :ok = Chat.subscribe_to_channel_messages(scope, workspace.default_channel_id)
      assert :ok = Chat.mark_channel_read(scope, workspace.default_channel_id)

      refute_receive {:message_created, _message}
    end

    test "keeps read state after channel runtime loss" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id
      add_workspace_member!(workspace, other_scope)

      insert_message!(
        channel_id,
        other_scope.user.id,
        "durable read state",
        DateTime.add(DateTime.utc_now(:second), 10, :second)
      )

      assert {:ok, %{^channel_id => 1}} = Chat.list_unread_counts(scope, workspace.id)
      assert :ok = Chat.mark_channel_read(scope, channel_id)

      assert {:ok, first_pid} = Chat.ensure_channel_runtime(scope, channel_id)
      ref = Process.monitor(first_pid)
      Process.exit(first_pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^first_pid, :killed}
      _ = :sys.get_state(DiscordClone.Chat.ChannelSupervisor)

      assert Chat.list_unread_counts(scope, workspace.id) == {:ok, %{}}
      assert {:ok, second_pid} = Chat.ensure_channel_runtime(scope, channel_id)
      assert second_pid != first_pid
    end
  end

  describe "subscribe_to_channel_messages/2" do
    test "subscribed workspace members receive persisted message-created events" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      subscriber =
        start_subscriber(scope, workspace.default_channel_id)

      assert_receive {:subscribed, ^subscriber}

      assert {:ok, sent_message} =
               Chat.send_message(scope, workspace.default_channel_id, %{"content" => "hello live"})

      assert_receive {:subscriber_received, ^subscriber, {:message_created, received_message}}
      assert received_message.id == sent_message.id
      assert received_message.content == "hello live"
      assert received_message.channel_id == workspace.default_channel_id
      assert Ecto.assoc_loaded?(received_message.user)
      assert received_message.user.username == scope.user.username
    end

    test "rejects anonymous scopes" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert Chat.subscribe_to_channel_messages(nil, workspace.default_channel_id) ==
               {:error, :unauthenticated}

      assert Chat.subscribe_to_channel_messages(
               %DiscordClone.Accounts.Scope{},
               workspace.default_channel_id
             ) == {:error, :unauthenticated}
    end

    test "rejects logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      assert Chat.subscribe_to_channel_messages(non_member_scope, workspace.default_channel_id) ==
               {:error, :not_found}
    end

    test "rejects missing channels" do
      scope = user_scope_fixture()

      assert Chat.subscribe_to_channel_messages(scope, -1) == {:error, :not_found}
    end

    test "does not broadcast invalid message sends" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      :ok = Chat.subscribe_to_channel_messages(scope, workspace.default_channel_id)

      assert {:error, :invalid_message, _changeset} =
               Chat.send_message(scope, workspace.default_channel_id, %{"content" => "   "})

      refute_receive {:message_created, _message}
    end

    test "does not broadcast successful sends back to the sender process" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      :ok = Chat.subscribe_to_channel_messages(scope, workspace.default_channel_id)

      assert {:ok, message} =
               Chat.send_message(scope, workspace.default_channel_id, %{
                 "content" => "sender copy"
               })

      assert message.content == "sender copy"
      refute_receive {:message_created, _message}
    end

    test "does not broadcast unauthorized message sends" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      :ok = Chat.subscribe_to_channel_messages(owner_scope, workspace.default_channel_id)

      assert Chat.send_message(non_member_scope, workspace.default_channel_id, %{
               "content" => "private hello"
             }) == {:error, :not_found}

      refute_receive {:message_created, _message}
    end

    test "does not broadcast read or history-loading workflows" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "stored",
          ~U[2026-06-19 10:00:00Z]
        )

      :ok = Chat.subscribe_to_channel_messages(scope, workspace.default_channel_id)

      assert {:ok, [_message]} = Chat.list_recent_messages(scope, workspace.default_channel_id)
      assert {:ok, []} = Chat.list_older_messages(scope, workspace.default_channel_id, message)

      refute_receive {:message_created, _message}
    end
  end

  describe "subscribe_to_workspace_messages/2" do
    test "subscribed workspace members receive compact message refresh events including sender sessions" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert :ok = Chat.subscribe_to_workspace_messages(scope, workspace.id)

      assert {:ok, sent_message} =
               Chat.send_message(scope, workspace.default_channel_id, %{
                 "content" => "refresh unread badges"
               })

      assert_receive {:workspace_message_created, payload}
      assert payload.workspace_id == workspace.id
      assert payload.channel_id == workspace.default_channel_id
      assert payload.message_id == sent_message.id
      assert payload.user_id == scope.user.id
      refute Map.has_key?(payload, :message)
    end

    test "rejects anonymous scopes and logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      assert Chat.subscribe_to_workspace_messages(nil, workspace.id) ==
               {:error, :unauthenticated}

      assert Chat.subscribe_to_workspace_messages(%DiscordClone.Accounts.Scope{}, workspace.id) ==
               {:error, :unauthenticated}

      assert Chat.subscribe_to_workspace_messages(non_member_scope, workspace.id) ==
               {:error, :not_found}
    end
  end

  describe "toggle_reaction/3" do
    test "allows a workspace member to add a reaction to an accessible message" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "ship it",
          ~U[2026-06-30 10:00:00Z]
        )

      assert {:ok, reaction} = Chat.toggle_reaction(scope, message.id, " 👍 ")

      assert reaction.message_id == message.id
      assert reaction.user_id == scope.user.id
      assert reaction.emoji == "👍"
      assert Repo.get_by(MessageReaction, message_id: message.id, user_id: scope.user.id)
      assert count_reactions(message.id, scope.user.id, "👍") == 1
    end

    test "toggles the current user's existing reaction off" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      message = insert_message!(workspace.default_channel_id, scope.user.id, "done", now())

      assert {:ok, reaction} = Chat.toggle_reaction(scope, message.id, "👍")
      assert {:ok, deleted_reaction} = Chat.toggle_reaction(scope, message.id, "👍")

      assert deleted_reaction.id == reaction.id
      refute Repo.get(MessageReaction, reaction.id)
      refute Repo.get_by(MessageReaction, message_id: message.id, user_id: scope.user.id)
    end

    test "keeps different users' matching emoji reactions as separate rows" do
      owner_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)

      message =
        insert_message!(workspace.default_channel_id, owner_scope.user.id, "ship it", now())

      assert {:ok, owner_reaction} = Chat.toggle_reaction(owner_scope, message.id, "👍")
      assert {:ok, member_reaction} = Chat.toggle_reaction(member_scope, message.id, "👍")

      assert owner_reaction.id != member_reaction.id

      reaction_users =
        MessageReaction
        |> where([reaction], reaction.message_id == ^message.id and reaction.emoji == "👍")
        |> select([reaction], reaction.user_id)
        |> Repo.all()
        |> Enum.sort()

      assert reaction_users == Enum.sort([owner_scope.user.id, member_scope.user.id])
    end

    test "allows one user to react with different emoji to the same message" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      message = insert_message!(workspace.default_channel_id, scope.user.id, "choices", now())

      assert {:ok, thumbs_up} = Chat.toggle_reaction(scope, message.id, "👍")
      assert {:ok, heart} = Chat.toggle_reaction(scope, message.id, "❤️")

      assert thumbs_up.id != heart.id

      reaction_emoji =
        MessageReaction
        |> where(
          [reaction],
          reaction.message_id == ^message.id and reaction.user_id == ^scope.user.id
        )
        |> select([reaction], reaction.emoji)
        |> Repo.all()
        |> Enum.sort()

      assert reaction_emoji == Enum.sort(["👍", "❤️"])
    end

    test "rejects anonymous scopes" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      message = insert_message!(workspace.default_channel_id, scope.user.id, "private", now())

      assert Chat.toggle_reaction(nil, message.id, "👍") == {:error, :unauthenticated}

      assert Chat.toggle_reaction(%DiscordClone.Accounts.Scope{}, message.id, "👍") ==
               {:error, :unauthenticated}

      refute Repo.get_by(MessageReaction, message_id: message.id)
    end

    test "rejects logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      message =
        insert_message!(workspace.default_channel_id, owner_scope.user.id, "private", now())

      assert Chat.toggle_reaction(non_member_scope, message.id, "👍") == {:error, :not_found}

      refute Repo.get_by(MessageReaction,
               message_id: message.id,
               user_id: non_member_scope.user.id
             )
    end

    test "rejects invalid emoji payloads before storing reaction state" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      message = insert_message!(workspace.default_channel_id, scope.user.id, "payloads", now())

      assert Chat.toggle_reaction(scope, message.id, "👍❤️") ==
               {:error, :invalid_emoji, :multiple_graphemes}

      assert Chat.toggle_reaction(scope, message.id, "   ") == {:error, :invalid_emoji, :blank}
      assert Chat.toggle_reaction(scope, message.id, nil) == {:error, :invalid_emoji, :invalid}

      refute Repo.get_by(MessageReaction, message_id: message.id)
    end

    test "removes related reaction rows when the message is deleted" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      message = insert_message!(workspace.default_channel_id, scope.user.id, "cleanup", now())

      assert {:ok, reaction} = Chat.toggle_reaction(scope, message.id, "👍")
      Repo.delete!(message)

      refute Repo.get(MessageReaction, reaction.id)
    end

    test "removes related reaction rows when the user is deleted" do
      owner_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)

      message =
        insert_message!(workspace.default_channel_id, owner_scope.user.id, "cleanup", now())

      assert {:ok, reaction} = Chat.toggle_reaction(member_scope, message.id, "👍")
      Repo.delete!(member_scope.user)

      refute Repo.get(MessageReaction, reaction.id)
    end
  end

  describe "list_reaction_summaries/2" do
    test "returns emoji counts keyed by accessible message ID" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      message = insert_message!(workspace.default_channel_id, scope.user.id, "ship it", now())

      assert {:ok, _reaction} = Chat.toggle_reaction(scope, message.id, "👍")

      assert {:ok, summaries} = Chat.list_reaction_summaries(scope, [message.id])

      assert summaries == %{
               message.id => [
                 %{emoji: "👍", count: 1, reacted?: true}
               ]
             }
    end

    test "marks reacted state for the current viewer only" do
      owner_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)

      message =
        insert_message!(workspace.default_channel_id, owner_scope.user.id, "ship it", now())

      assert {:ok, _reaction} = Chat.toggle_reaction(owner_scope, message.id, "👍")

      assert {:ok, owner_summaries} = Chat.list_reaction_summaries(owner_scope, [message.id])
      assert {:ok, member_summaries} = Chat.list_reaction_summaries(member_scope, [message.id])

      assert owner_summaries == %{
               message.id => [
                 %{emoji: "👍", count: 1, reacted?: true}
               ]
             }

      assert member_summaries == %{
               message.id => [
                 %{emoji: "👍", count: 1, reacted?: false}
               ]
             }
    end

    test "groups counts by requested message and emoji" do
      owner_scope = user_scope_fixture()
      member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      add_workspace_member!(workspace, member_scope)

      first_message =
        insert_message!(workspace.default_channel_id, owner_scope.user.id, "first", now())

      second_message =
        insert_message!(workspace.default_channel_id, owner_scope.user.id, "second", now())

      assert {:ok, _reaction} = Chat.toggle_reaction(owner_scope, first_message.id, "👍")
      assert {:ok, _reaction} = Chat.toggle_reaction(member_scope, first_message.id, "👍")
      assert {:ok, _reaction} = Chat.toggle_reaction(member_scope, first_message.id, "❤️")
      assert {:ok, _reaction} = Chat.toggle_reaction(member_scope, second_message.id, "👀")

      assert {:ok, summaries} =
               Chat.list_reaction_summaries(owner_scope, [first_message.id, second_message.id])

      assert summaries == %{
               first_message.id => [
                 %{emoji: "❤️", count: 1, reacted?: false},
                 %{emoji: "👍", count: 2, reacted?: true}
               ],
               second_message.id => [
                 %{emoji: "👀", count: 1, reacted?: false}
               ]
             }
    end

    test "only returns summaries for the bounded message list" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      requested_message =
        insert_message!(workspace.default_channel_id, scope.user.id, "in", now())

      other_message = insert_message!(workspace.default_channel_id, scope.user.id, "out", now())

      assert {:ok, _reaction} = Chat.toggle_reaction(scope, requested_message.id, "👍")
      assert {:ok, _reaction} = Chat.toggle_reaction(scope, other_message.id, "❤️")

      assert {:ok, summaries} = Chat.list_reaction_summaries(scope, [requested_message.id])

      assert Map.keys(summaries) == [requested_message.id]
      assert summaries[requested_message.id] == [%{emoji: "👍", count: 1, reacted?: true}]
    end

    test "rejects anonymous scopes and logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      message =
        insert_message!(workspace.default_channel_id, owner_scope.user.id, "private", now())

      assert {:ok, _reaction} = Chat.toggle_reaction(owner_scope, message.id, "👍")

      assert Chat.list_reaction_summaries(nil, [message.id]) == {:error, :unauthenticated}

      assert Chat.list_reaction_summaries(%DiscordClone.Accounts.Scope{}, [message.id]) ==
               {:error, :unauthenticated}

      assert Chat.list_reaction_summaries(non_member_scope, [message.id]) ==
               {:error, :not_found}
    end
  end

  describe "channel typing workflows" do
    test "workspace members can subscribe, start typing, and list raw typing user IDs" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id

      subscriber = start_typing_subscriber(scope, channel_id)
      assert_receive {:subscribed, ^subscriber}

      assert :ok = Chat.user_started_typing(scope, channel_id)

      assert_receive {:subscriber_received, ^subscriber,
                      {:typing_started, %{channel_id: ^channel_id, user_id: user_id} = payload}}

      assert user_id == scope.user.id
      assert Map.keys(payload) |> Enum.sort() == [:channel_id, :user_id]
      assert {:ok, [user_id]} = Chat.list_typing_user_ids(scope, channel_id)
      assert user_id == scope.user.id
    end

    test "rejects anonymous scopes and logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id

      assert Chat.subscribe_to_channel_typing(nil, channel_id) == {:error, :unauthenticated}
      assert Chat.user_started_typing(nil, channel_id) == {:error, :unauthenticated}
      assert Chat.user_stopped_typing(nil, channel_id) == {:error, :unauthenticated}
      assert Chat.list_typing_user_ids(nil, channel_id) == {:error, :unauthenticated}

      assert Chat.subscribe_to_channel_typing(non_member_scope, channel_id) ==
               {:error, :not_found}

      assert Chat.user_started_typing(non_member_scope, channel_id) == {:error, :not_found}
      assert Chat.user_stopped_typing(non_member_scope, channel_id) == {:error, :not_found}
      assert Chat.list_typing_user_ids(non_member_scope, channel_id) == {:error, :not_found}
    end

    test "broadcasts typing started only when the member was not already typing" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id

      assert :ok = Chat.subscribe_to_channel_typing(scope, channel_id)

      assert :ok = Chat.user_started_typing(scope, channel_id)
      assert_receive {:typing_started, %{channel_id: ^channel_id, user_id: user_id}}
      assert user_id == scope.user.id

      assert :ok = Chat.user_started_typing(scope, channel_id)
      refute_receive {:typing_started, %{channel_id: ^channel_id, user_id: ^user_id}}, 50
      assert {:ok, [^user_id]} = Chat.list_typing_user_ids(scope, channel_id)
    end

    test "workspace members can stop typing and subscribers receive one stopped event" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id

      assert :ok = Chat.subscribe_to_channel_typing(scope, channel_id)

      assert :ok = Chat.user_started_typing(scope, channel_id)
      assert_receive {:typing_started, %{channel_id: ^channel_id, user_id: user_id}}
      assert user_id == scope.user.id

      assert :ok = Chat.user_stopped_typing(scope, channel_id)
      assert_receive {:typing_stopped, %{channel_id: ^channel_id, user_id: ^user_id} = payload}
      assert Map.keys(payload) |> Enum.sort() == [:channel_id, :user_id]
      assert {:ok, []} = Chat.list_typing_user_ids(scope, channel_id)

      assert :ok = Chat.user_stopped_typing(scope, channel_id)
      refute_receive {:typing_stopped, %{channel_id: ^channel_id, user_id: ^user_id}}, 50
    end

    test "typing expires automatically and subscribers receive a stopped event" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id

      put_channel_typing_timeout(0)

      assert :ok = Chat.subscribe_to_channel_typing(scope, channel_id)

      assert :ok = Chat.user_started_typing(scope, channel_id)
      assert_receive {:typing_started, %{channel_id: ^channel_id, user_id: user_id}}
      assert user_id == scope.user.id

      assert_receive {:typing_stopped, %{channel_id: ^channel_id, user_id: ^user_id} = payload}
      assert Map.keys(payload) |> Enum.sort() == [:channel_id, :user_id]
      assert {:ok, []} = Chat.list_typing_user_ids(scope, channel_id)
    end

    test "typing state is temporary across channel runtime loss and works again after restart" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id

      assert :ok = Chat.subscribe_to_channel_typing(scope, channel_id)
      assert :ok = Chat.user_started_typing(scope, channel_id)
      assert_receive {:typing_started, %{channel_id: ^channel_id, user_id: user_id}}
      assert user_id == scope.user.id
      assert {:ok, [^user_id]} = Chat.list_typing_user_ids(scope, channel_id)

      first_pid = ChannelServer.whereis(channel_id)
      ref = Process.monitor(first_pid)
      Process.exit(first_pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^first_pid, :killed}
      _ = :sys.get_state(DiscordClone.Chat.ChannelSupervisor)

      assert {:ok, []} = Chat.list_typing_user_ids(scope, channel_id)

      assert :ok = Chat.user_started_typing(scope, channel_id)
      assert_receive {:typing_started, %{channel_id: ^channel_id, user_id: ^user_id}}
      assert {:ok, [^user_id]} = Chat.list_typing_user_ids(scope, channel_id)

      second_pid = ChannelServer.whereis(channel_id)
      assert is_pid(second_pid)
      assert second_pid != first_pid
    end
  end

  describe "subscribe_to_workspace_presence/2" do
    test "subscribes workspace members without starting the workspace runtime" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert :ok = Chat.subscribe_to_workspace_presence(scope, workspace.id)
      assert WorkspaceServer.whereis(workspace.id) == nil
    end

    test "rejects anonymous scopes" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert Chat.subscribe_to_workspace_presence(nil, workspace.id) ==
               {:error, :unauthenticated}

      assert Chat.subscribe_to_workspace_presence(%DiscordClone.Accounts.Scope{}, workspace.id) ==
               {:error, :unauthenticated}
    end

    test "rejects logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      assert Chat.subscribe_to_workspace_presence(non_member_scope, workspace.id) ==
               {:error, :not_found}
    end
  end

  describe "list_online_workspace_user_ids/2" do
    test "returns an empty list for workspace members without starting an absent runtime" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert {:ok, []} = Chat.list_online_workspace_user_ids(scope, workspace.id)
      assert WorkspaceServer.whereis(workspace.id) == nil
    end

    test "rejects anonymous scopes" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert Chat.list_online_workspace_user_ids(nil, workspace.id) ==
               {:error, :unauthenticated}

      assert Chat.list_online_workspace_user_ids(%DiscordClone.Accounts.Scope{}, workspace.id) ==
               {:error, :unauthenticated}
    end

    test "rejects logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      assert Chat.list_online_workspace_user_ids(non_member_scope, workspace.id) ==
               {:error, :not_found}
    end
  end

  describe "join_workspace_presence/3" do
    test "starts the workspace runtime and tracks the supplied live view pid" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      live_view_pid = start_live_view_process()

      assert :ok = Chat.join_workspace_presence(scope, workspace.id, live_view_pid)

      assert is_pid(WorkspaceServer.whereis(workspace.id))
      assert {:ok, [user_id]} = Chat.list_online_workspace_user_ids(scope, workspace.id)
      assert user_id == scope.user.id
    end

    test "defaults to tracking the caller process" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert :ok = Chat.join_workspace_presence(scope, workspace.id)
      assert {:ok, [user_id]} = Chat.list_online_workspace_user_ids(scope, workspace.id)
      assert user_id == scope.user.id
    end

    test "broadcasts user-level presence events to public subscribers" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      live_view_pid = start_live_view_process()

      assert :ok = Chat.subscribe_to_workspace_presence(scope, workspace.id)
      assert :ok = Chat.join_workspace_presence(scope, workspace.id, live_view_pid)

      assert_receive {:workspace_user_joined,
                      %{workspace_id: workspace_id, user_id: user_id} = payload}

      assert workspace_id == workspace.id
      assert user_id == scope.user.id
      refute Map.has_key?(payload, :user)
      refute Map.has_key?(payload, :members)
    end

    test "rejects anonymous scopes" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert Chat.join_workspace_presence(nil, workspace.id) == {:error, :unauthenticated}

      assert Chat.join_workspace_presence(%DiscordClone.Accounts.Scope{}, workspace.id) ==
               {:error, :unauthenticated}
    end

    test "rejects logged-in users who are not workspace members without starting a runtime" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      assert Chat.join_workspace_presence(non_member_scope, workspace.id) == {:error, :not_found}
      assert WorkspaceServer.whereis(workspace.id) == nil
    end

    test "runtime crash does not interrupt persisted chat workflows or rejoining presence" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      live_view_pid = start_live_view_process()

      assert :ok = Chat.join_workspace_presence(scope, workspace.id, live_view_pid)
      workspace_pid = WorkspaceServer.whereis(workspace.id)
      assert is_pid(workspace_pid)

      ref = Process.monitor(workspace_pid)
      Process.exit(workspace_pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^workspace_pid, :killed}
      _ = :sys.get_state(DiscordClone.Chat.WorkspaceSupervisor)

      subscriber = start_subscriber(scope, workspace.default_channel_id)
      assert_receive {:subscribed, ^subscriber}

      assert {:ok, sent_message} =
               Chat.send_message(scope, workspace.default_channel_id, %{"content" => "still here"})

      assert_receive {:subscriber_received, ^subscriber, {:message_created, received_message}}
      assert received_message.id == sent_message.id

      assert {:ok, [loaded_message]} =
               Chat.list_recent_messages(scope, workspace.default_channel_id)

      assert loaded_message.id == sent_message.id

      recovered_live_view_pid = start_live_view_process()
      assert :ok = Chat.join_workspace_presence(scope, workspace.id, recovered_live_view_pid)
      assert {:ok, [user_id]} = Chat.list_online_workspace_user_ids(scope, workspace.id)
      assert user_id == scope.user.id
    end
  end

  describe "ensure_channel_runtime/2" do
    test "starts a channel runtime for a workspace member" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert {:ok, pid} = Chat.ensure_channel_runtime(scope, workspace.default_channel_id)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "reuses the active channel runtime when ensured twice" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert {:ok, first_pid} = Chat.ensure_channel_runtime(scope, workspace.default_channel_id)
      assert {:ok, second_pid} = Chat.ensure_channel_runtime(scope, workspace.default_channel_id)

      assert second_pid == first_pid
    end

    test "rejects anonymous scopes" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert Chat.ensure_channel_runtime(nil, workspace.default_channel_id) ==
               {:error, :unauthenticated}

      assert Chat.ensure_channel_runtime(
               %DiscordClone.Accounts.Scope{},
               workspace.default_channel_id
             ) == {:error, :unauthenticated}
    end

    test "rejects logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      assert Chat.ensure_channel_runtime(non_member_scope, workspace.default_channel_id) ==
               {:error, :not_found}
    end

    test "rejects missing channels" do
      scope = user_scope_fixture()

      assert Chat.ensure_channel_runtime(scope, -1) == {:error, :not_found}
    end
  end

  describe "list_recent_messages/2" do
    test "loads the latest channel messages oldest-to-newest with authors preloaded" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, other_channel} = Workspaces.create_channel(scope, workspace.id, %{name: "off-topic"})

      base_time = ~U[2026-06-19 10:00:00Z]

      messages =
        for index <- 1..55 do
          insert_message!(
            workspace.default_channel_id,
            scope.user.id,
            "message #{index}",
            DateTime.add(base_time, index, :second)
          )
        end

      insert_message!(
        other_channel.id,
        scope.user.id,
        "wrong channel",
        DateTime.add(base_time, 56, :second)
      )

      assert {:ok, recent_messages} =
               Chat.list_recent_messages(scope, workspace.default_channel_id)

      assert Enum.map(recent_messages, & &1.id) == messages |> Enum.drop(5) |> Enum.map(& &1.id)
      assert Enum.map(recent_messages, & &1.content) == Enum.map(6..55, &"message #{&1}")
      assert Enum.all?(recent_messages, &Ecto.assoc_loaded?(&1.user))
      assert Enum.all?(recent_messages, &(&1.user.username == scope.user.username))
    end

    test "reads from the active channel runtime cache" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      cached_message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "cached",
          ~U[2026-06-19 10:00:00Z]
        )

      assert {:ok, [loaded_message]} =
               Chat.list_recent_messages(scope, workspace.default_channel_id)

      assert loaded_message.id == cached_message.id

      uncached_message =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "not in runtime cache yet",
          ~U[2026-06-19 10:01:00Z]
        )

      assert {:ok, cached_messages} =
               Chat.list_recent_messages(scope, workspace.default_channel_id)

      assert Enum.map(cached_messages, & &1.id) == [cached_message.id]
      refute uncached_message.id in Enum.map(cached_messages, & &1.id)
    end

    test "recovers persisted recent messages after channel runtime loss" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id

      first_message =
        insert_message!(
          channel_id,
          scope.user.id,
          "before runtime loss",
          ~U[2026-06-19 10:00:00Z]
        )

      assert {:ok, [loaded_message]} = Chat.list_recent_messages(scope, channel_id)
      assert loaded_message.id == first_message.id

      assert {:ok, first_pid} = Chat.ensure_channel_runtime(scope, channel_id)
      ref = Process.monitor(first_pid)
      Process.exit(first_pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^first_pid, :killed}
      _ = :sys.get_state(DiscordClone.Chat.ChannelSupervisor)

      second_message =
        insert_message!(
          channel_id,
          scope.user.id,
          "after runtime loss",
          ~U[2026-06-19 10:01:00Z]
        )

      assert {:ok, recovered_messages} = Chat.list_recent_messages(scope, channel_id)
      assert Enum.map(recovered_messages, & &1.id) == [first_message.id, second_message.id]

      assert {:ok, second_pid} = Chat.ensure_channel_runtime(scope, channel_id)
      assert second_pid != first_pid
      assert %{channel_id: ^channel_id} = :sys.get_state(second_pid)
    end

    test "rejects anonymous scopes" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert Chat.list_recent_messages(nil, workspace.default_channel_id) ==
               {:error, :unauthenticated}

      assert Chat.list_recent_messages(
               %DiscordClone.Accounts.Scope{},
               workspace.default_channel_id
             ) ==
               {:error, :unauthenticated}
    end

    test "rejects logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      insert_message!(
        workspace.default_channel_id,
        owner_scope.user.id,
        "private message",
        ~U[2026-06-19 10:00:00Z]
      )

      assert Chat.list_recent_messages(non_member_scope, workspace.default_channel_id) ==
               {:error, :not_found}
    end
  end

  describe "list_older_messages/3" do
    test "loads messages older than the cursor oldest-to-newest with authors preloaded" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      base_time = ~U[2026-06-19 10:00:00Z]

      messages =
        for index <- 1..55 do
          insert_message!(
            workspace.default_channel_id,
            scope.user.id,
            "message #{index}",
            DateTime.add(base_time, index, :second)
          )
        end

      {:ok, recent_messages} = Chat.list_recent_messages(scope, workspace.default_channel_id)
      cursor = hd(recent_messages)

      assert {:ok, older_messages} =
               Chat.list_older_messages(scope, workspace.default_channel_id, cursor)

      assert Enum.map(older_messages, & &1.id) == messages |> Enum.take(5) |> Enum.map(& &1.id)
      assert Enum.map(older_messages, & &1.content) == Enum.map(1..5, &"message #{&1}")
      refute cursor.id in Enum.map(older_messages, & &1.id)
      assert Enum.all?(older_messages, &Ecto.assoc_loaded?(&1.user))
      assert Enum.all?(older_messages, &(&1.user.username == scope.user.username))
    end

    test "does not load older messages from another channel" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, other_channel} = Workspaces.create_channel(scope, workspace.id, %{name: "off-topic"})

      base_time = ~U[2026-06-19 10:00:00Z]

      messages =
        for index <- 1..55 do
          insert_message!(
            workspace.default_channel_id,
            scope.user.id,
            "message #{index}",
            DateTime.add(base_time, index, :second)
          )
        end

      other_channel_message =
        insert_message!(
          other_channel.id,
          scope.user.id,
          "wrong older channel",
          DateTime.add(base_time, 3, :second)
        )

      {:ok, recent_messages} = Chat.list_recent_messages(scope, workspace.default_channel_id)
      cursor = hd(recent_messages)

      assert {:ok, older_messages} =
               Chat.list_older_messages(scope, workspace.default_channel_id, cursor)

      assert Enum.map(older_messages, & &1.id) == messages |> Enum.take(5) |> Enum.map(& &1.id)
      refute other_channel_message.id in Enum.map(older_messages, & &1.id)
    end

    test "paginates messages that share a timestamp without duplicates or skips" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      shared_time = ~U[2026-06-19 10:00:00Z]

      messages =
        for index <- 1..55 do
          insert_message!(
            workspace.default_channel_id,
            scope.user.id,
            "message #{index}",
            shared_time
          )
        end

      {:ok, recent_messages} = Chat.list_recent_messages(scope, workspace.default_channel_id)
      cursor = hd(recent_messages)

      assert {:ok, older_messages} =
               Chat.list_older_messages(scope, workspace.default_channel_id, cursor)

      assert Enum.map(recent_messages, & &1.id) == messages |> Enum.drop(5) |> Enum.map(& &1.id)
      assert Enum.map(older_messages, & &1.id) == messages |> Enum.take(5) |> Enum.map(& &1.id)

      assert MapSet.disjoint?(
               MapSet.new(recent_messages, & &1.id),
               MapSet.new(older_messages, & &1.id)
             )
    end

    test "rejects anonymous scopes" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      cursor =
        insert_message!(
          workspace.default_channel_id,
          scope.user.id,
          "message",
          ~U[2026-06-19 10:00:00Z]
        )

      assert Chat.list_older_messages(nil, workspace.default_channel_id, cursor) ==
               {:error, :unauthenticated}

      assert Chat.list_older_messages(
               %DiscordClone.Accounts.Scope{},
               workspace.default_channel_id,
               cursor
             ) == {:error, :unauthenticated}
    end

    test "rejects logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      cursor =
        insert_message!(
          workspace.default_channel_id,
          owner_scope.user.id,
          "private message",
          ~U[2026-06-19 10:00:00Z]
        )

      assert Chat.list_older_messages(non_member_scope, workspace.default_channel_id, cursor) ==
               {:error, :not_found}
    end
  end

  describe "send_message/3" do
    test "persists trimmed content in the selected channel with the author preloaded" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      {:ok, other_channel} = Workspaces.create_channel(scope, workspace.id, %{name: "off-topic"})

      assert {:ok, message} =
               Chat.send_message(scope, workspace.default_channel_id, %{
                 "channel_id" => other_channel.id,
                 "content" => "  hello channel  "
               })

      assert message.content == "hello channel"
      assert message.channel_id == workspace.default_channel_id
      assert message.user_id == scope.user.id
      assert Ecto.assoc_loaded?(message.user)
      assert message.user.username == scope.user.username
      assert Repo.get!(Message, message.id).content == "hello channel"
    end

    test "advances the sender read cursor to the sent message" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id

      assert {:ok, sent_message} =
               Chat.send_message(scope, channel_id, %{"content" => "bookmark this"})

      assert %ChannelRead{last_read_message_id: last_read_message_id} =
               Repo.get_by(ChannelRead, channel_id: channel_id, user_id: scope.user.id)

      assert last_read_message_id == sent_message.id
    end

    test "advances the sender read cursor before broadcasting the sent message" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id

      subscriber = start_read_cursor_subscriber(scope, channel_id)
      assert_receive {:subscribed, ^subscriber}

      assert {:ok, sent_message} =
               Chat.send_message(scope, channel_id, %{"content" => "visible after cursor"})

      assert_receive {:subscriber_read_cursor, ^subscriber, received_message,
                      last_read_message_id}

      assert received_message.id == sent_message.id
      assert last_read_message_id == sent_message.id
    end

    test "does not create self-unread counts when the sender refreshes counts" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert {:ok, _sent_message} =
               Chat.send_message(scope, workspace.default_channel_id, %{
                 "content" => "not unread for me"
               })

      assert Chat.list_unread_counts(scope, workspace.id) == {:ok, %{}}
    end

    test "updates the runtime cache before broadcasting the persisted message" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      subscriber = start_cache_reading_subscriber(scope, workspace.default_channel_id)

      assert_receive {:subscribed, ^subscriber}

      assert {:ok, sent_message} =
               Chat.send_message(scope, workspace.default_channel_id, %{
                 "content" => "cache before broadcast"
               })

      assert_receive {:subscriber_recent_messages, ^subscriber, received_message, recent_messages}

      assert received_message.id == sent_message.id
      assert Enum.map(recent_messages, & &1.id) == [sent_message.id]
      assert Ecto.assoc_loaded?(received_message.user)
      assert Ecto.assoc_loaded?(hd(recent_messages).user)
    end

    test "clears the sender's typing state when a message is sent" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id

      assert :ok = Chat.subscribe_to_channel_typing(scope, channel_id)
      assert :ok = Chat.user_started_typing(scope, channel_id)
      assert_receive {:typing_started, %{channel_id: ^channel_id, user_id: user_id}}

      assert {:ok, message} =
               Chat.send_message(scope, channel_id, %{"content" => "typing resolved"})

      assert message.content == "typing resolved"
      assert_receive {:typing_stopped, %{channel_id: ^channel_id, user_id: ^user_id}}
      assert {:ok, []} = Chat.list_typing_user_ids(scope, channel_id)
    end

    test "restarts the runtime and caches the persisted message when sending after runtime loss" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id

      stored_message =
        insert_message!(channel_id, scope.user.id, "stored", ~U[2026-06-19 10:00:00Z])

      assert {:ok, [cached_message]} = Chat.list_recent_messages(scope, channel_id)
      assert cached_message.id == stored_message.id

      assert {:ok, first_pid} = Chat.ensure_channel_runtime(scope, channel_id)
      ref = Process.monitor(first_pid)
      Process.exit(first_pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^first_pid, :killed}
      _ = :sys.get_state(DiscordClone.Chat.ChannelSupervisor)

      subscriber = start_subscriber(scope, channel_id)
      assert_receive {:subscribed, ^subscriber}

      assert {:ok, sent_message} =
               Chat.send_message(scope, channel_id, %{"content" => "after runtime loss"})

      assert_receive {:subscriber_received, ^subscriber, {:message_created, received_message}}
      assert received_message.id == sent_message.id

      assert {:ok, recent_messages} = Chat.list_recent_messages(scope, channel_id)
      assert Enum.map(recent_messages, & &1.id) == [stored_message.id, sent_message.id]

      assert {:ok, second_pid} = Chat.ensure_channel_runtime(scope, channel_id)
      assert second_pid != first_pid
    end

    test "rejects whitespace-only content with an invalid message changeset" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert {:error, :invalid_message, changeset} =
               Chat.send_message(scope, workspace.default_channel_id, %{
                 "content" => "   "
               })

      refute changeset.valid?
      assert %{content: ["can't be blank"]} = errors_on(changeset)
      assert Repo.aggregate(Message, :count) == 0
    end

    test "does not update the runtime cache or broadcast invalid message sends" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id

      stored_message =
        insert_message!(channel_id, scope.user.id, "stored", ~U[2026-06-19 10:00:00Z])

      assert {:ok, [cached_message]} = Chat.list_recent_messages(scope, channel_id)
      assert cached_message.id == stored_message.id
      assert :ok = Chat.subscribe_to_channel_messages(scope, channel_id)

      assert {:error, :invalid_message, _changeset} =
               Chat.send_message(scope, channel_id, %{"content" => "   "})

      assert {:ok, cached_messages} = Chat.list_recent_messages(scope, channel_id)
      assert Enum.map(cached_messages, & &1.id) == [stored_message.id]
      refute_receive {:message_created, _message}
    end

    test "accepts atom-keyed content attributes" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert {:ok, message} =
               Chat.send_message(scope, workspace.default_channel_id, %{content: "atom attrs"})

      assert message.content == "atom attrs"
    end

    test "rejects content longer than four thousand characters" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert {:error, :invalid_message, changeset} =
               Chat.send_message(scope, workspace.default_channel_id, %{
                 "content" => String.duplicate("a", 4_001)
               })

      refute changeset.valid?
      assert %{content: ["should be at most 4000 character(s)"]} = errors_on(changeset)
      assert Repo.aggregate(Message, :count) == 0
    end

    test "rejects anonymous scopes" do
      scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

      assert Chat.send_message(nil, workspace.default_channel_id, %{"content" => "hello"}) ==
               {:error, :unauthenticated}

      assert Chat.send_message(
               %DiscordClone.Accounts.Scope{},
               workspace.default_channel_id,
               %{"content" => "hello"}
             ) == {:error, :unauthenticated}

      assert Repo.aggregate(Message, :count) == 0
    end

    test "rejects logged-in users who are not workspace members" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})

      assert Chat.send_message(non_member_scope, workspace.default_channel_id, %{
               "content" => "private hello"
             }) == {:error, :not_found}

      assert Repo.aggregate(Message, :count) == 0
    end

    test "does not update the runtime cache or broadcast unauthorized message sends" do
      owner_scope = user_scope_fixture()
      non_member_scope = user_scope_fixture()
      {:ok, workspace} = Workspaces.create_workspace(owner_scope, %{name: "Foundry"})
      channel_id = workspace.default_channel_id

      stored_message =
        insert_message!(channel_id, owner_scope.user.id, "stored", ~U[2026-06-19 10:00:00Z])

      assert {:ok, [cached_message]} = Chat.list_recent_messages(owner_scope, channel_id)
      assert cached_message.id == stored_message.id
      assert :ok = Chat.subscribe_to_channel_messages(owner_scope, channel_id)

      assert Chat.send_message(non_member_scope, channel_id, %{"content" => "private hello"}) ==
               {:error, :not_found}

      assert {:ok, cached_messages} = Chat.list_recent_messages(owner_scope, channel_id)
      assert Enum.map(cached_messages, & &1.id) == [stored_message.id]
      refute_receive {:message_created, _message}
    end
  end

  defp insert_message!(channel_id, user_id, content, inserted_at) do
    Repo.insert!(%Message{
      channel_id: channel_id,
      user_id: user_id,
      content: content,
      inserted_at: inserted_at,
      updated_at: inserted_at
    })
  end

  defp now, do: DateTime.utc_now(:second)

  defp count_reactions(message_id, user_id, emoji) do
    Repo.one(
      from reaction in MessageReaction,
        where:
          reaction.message_id == ^message_id and reaction.user_id == ^user_id and
            reaction.emoji == ^emoji,
        select: count(reaction.id)
    )
  end

  defp put_channel_read!(channel_id, user_id, last_read_message_id) do
    case Repo.get_by(ChannelRead, channel_id: channel_id, user_id: user_id) do
      nil ->
        Repo.insert!(%ChannelRead{
          channel_id: channel_id,
          user_id: user_id,
          last_read_message_id: last_read_message_id
        })

      %ChannelRead{} = channel_read ->
        channel_read
        |> Ecto.Changeset.change(last_read_message_id: last_read_message_id)
        |> Repo.update!()
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

  defp start_subscriber(scope, channel_id) do
    parent = self()

    spawn_link(fn ->
      assert :ok = Chat.subscribe_to_channel_messages(scope, channel_id)
      send(parent, {:subscribed, self()})

      receive do
        event -> send(parent, {:subscriber_received, self(), event})
      after
        1_000 -> send(parent, {:subscriber_timeout, self()})
      end
    end)
  end

  defp start_cache_reading_subscriber(scope, channel_id) do
    parent = self()

    spawn_link(fn ->
      assert :ok = Chat.subscribe_to_channel_messages(scope, channel_id)
      send(parent, {:subscribed, self()})

      receive do
        {:message_created, message} ->
          assert {:ok, recent_messages} = Chat.list_recent_messages(scope, channel_id)
          send(parent, {:subscriber_recent_messages, self(), message, recent_messages})
      after
        1_000 -> send(parent, {:subscriber_timeout, self()})
      end
    end)
  end

  defp start_read_cursor_subscriber(scope, channel_id) do
    parent = self()

    spawn_link(fn ->
      assert :ok = Chat.subscribe_to_channel_messages(scope, channel_id)
      send(parent, {:subscribed, self()})

      receive do
        {:message_created, message} ->
          channel_read = Repo.get_by(ChannelRead, channel_id: channel_id, user_id: scope.user.id)

          send(
            parent,
            {:subscriber_read_cursor, self(), message, channel_read.last_read_message_id}
          )
      after
        1_000 -> send(parent, {:subscriber_timeout, self()})
      end
    end)
  end

  defp start_typing_subscriber(scope, channel_id) do
    parent = self()

    spawn_link(fn ->
      assert :ok = Chat.subscribe_to_channel_typing(scope, channel_id)
      send(parent, {:subscribed, self()})

      receive do
        event -> send(parent, {:subscriber_received, self(), event})
      after
        1_000 -> send(parent, {:subscriber_timeout, self()})
      end
    end)
  end

  defp put_channel_typing_timeout(timeout_ms) do
    previous = Application.get_env(:discord_clone, :channel_runtime_typing_timeout_ms)
    Application.put_env(:discord_clone, :channel_runtime_typing_timeout_ms, timeout_ms)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:discord_clone, :channel_runtime_typing_timeout_ms)
      else
        Application.put_env(:discord_clone, :channel_runtime_typing_timeout_ms, previous)
      end
    end)
  end

  defp start_live_view_process do
    start_supervised!(%{
      id: System.unique_integer([:positive]),
      start:
        {Task, :start_link,
         [
           fn ->
             receive do
               :stop -> :ok
             end
           end
         ]}
    })
  end
end
