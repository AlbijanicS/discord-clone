defmodule DiscordClone.Chat do
  @moduledoc """
  The Chat context.

  This context will own persisted message workflows, PubSub orchestration, and
  live channel processes as the chat phases are built.
  """

  import Ecto.Query

  alias DiscordClone.Accounts.{Scope, User}
  alias DiscordClone.Chat.Message
  alias DiscordClone.Repo
  alias DiscordClone.Workspaces.{Channel, WorkspaceMembership}

  @recent_message_limit 50

  def list_recent_messages(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} <- get_member_channel(channel_id, user_id) do
      messages =
        Message
        |> where([message], message.channel_id == ^channel_id)
        |> order_by([message], desc: message.inserted_at, desc: message.id)
        |> limit(^@recent_message_limit)
        |> preload(:user)
        |> Repo.all()
        |> Enum.reverse()

      {:ok, messages}
    else
      nil -> {:error, :not_found}
    end
  end

  def list_recent_messages(_scope, _channel_id), do: {:error, :unauthenticated}

  defp get_member_channel(channel_id, user_id) do
    Repo.one(
      from channel in Channel,
        join: membership in WorkspaceMembership,
        on:
          membership.workspace_id == channel.workspace_id and
            membership.user_id == ^user_id,
        where: channel.id == ^channel_id,
        limit: 1
    )
  end
end
