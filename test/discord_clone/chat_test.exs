defmodule DiscordClone.ChatTest do
  use DiscordClone.DataCase, async: true

  alias DiscordClone.Chat
  alias DiscordClone.Chat.Message
  alias DiscordClone.Workspaces

  import DiscordClone.AccountsFixtures

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
