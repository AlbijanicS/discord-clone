defmodule DiscordClone.ChatTest do
  use DiscordClone.DataCase, async: false

  alias DiscordClone.Chat
  alias DiscordClone.Chat.{Message, WorkspaceServer}
  alias DiscordClone.Workspaces

  import DiscordClone.AccountsFixtures

  describe "change_message/1" do
    test "returns a message changeset for composer forms" do
      changeset = Chat.change_message(%{content: "hello"})

      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_field(changeset, :content) == "hello"
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
