defmodule DiscordClone.ChatTest do
  use DiscordClone.DataCase, async: true

  alias DiscordClone.Chat
  alias DiscordClone.Chat.Message
  alias DiscordClone.Workspaces

  import DiscordClone.AccountsFixtures

  describe "change_message/1" do
    test "returns a message changeset for composer forms" do
      changeset = Chat.change_message(%{content: "hello"})

      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_field(changeset, :content) == "hello"
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
end
