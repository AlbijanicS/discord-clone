defmodule DiscordClone.Chat do
  @moduledoc """
  The Chat context.

  This context will own persisted message workflows, PubSub orchestration, and
  live channel processes as the chat phases are built.
  """

  import Ecto.Query

  alias DiscordClone.Accounts.{Scope, User}

  alias DiscordClone.Chat.{
    ChannelRead,
    ChannelSupervisor,
    ChannelServer,
    Emoji,
    Message,
    MessageReaction,
    WorkspacePresence,
    WorkspacePresenceRuntime
  }

  alias DiscordClone.Repo
  alias DiscordClone.Workspaces.{Channel, WorkspaceMembership}

  @recent_message_limit 50

  def change_message(attrs \\ %{}) do
    Message.changeset(%Message{}, attrs)
  end

  def initialize_workspace_reads_for_user(user_id, workspace_id) do
    with :ok <- authorize_workspace_member(workspace_id, user_id) do
      read_rows =
        Repo.all(
          from channel in Channel,
            left_join: latest_message in subquery(latest_message_per_channel_query()),
            on: latest_message.channel_id == channel.id,
            where: channel.workspace_id == ^workspace_id,
            select: %{
              channel_id: channel.id,
              last_read_message_id: latest_message.last_read_message_id
            }
        )

      Enum.reduce_while(read_rows, :ok, fn read_row, :ok ->
        case upsert_channel_read(user_id, read_row.channel_id, read_row.last_read_message_id) do
          {:ok, _channel_read} -> {:cont, :ok}
          {:error, changeset} -> {:halt, {:error, changeset}}
        end
      end)
    end
  end

  def initialize_channel_reads_for_workspace_members(channel_id) do
    if Repo.exists?(from channel in Channel, where: channel.id == ^channel_id) do
      now = DateTime.utc_now(:second)

      read_rows =
        Repo.all(
          from channel in Channel,
            join: membership in WorkspaceMembership,
            on: membership.workspace_id == channel.workspace_id,
            where: channel.id == ^channel_id,
            select: %{
              channel_id: channel.id,
              user_id: membership.user_id,
              last_read_message_id: nil,
              inserted_at: type(^now, :utc_datetime),
              updated_at: type(^now, :utc_datetime)
            }
        )

      Repo.insert_all(
        ChannelRead,
        read_rows,
        on_conflict: :nothing,
        conflict_target: [:channel_id, :user_id]
      )

      :ok
    else
      {:error, :not_found}
    end
  end

  def delete_workspace_reads_for_user(user_id, workspace_id) do
    Repo.delete_all(
      from read in ChannelRead,
        join: channel in Channel,
        on: channel.id == read.channel_id,
        where: channel.workspace_id == ^workspace_id,
        where: read.user_id == ^user_id
    )

    :ok
  end

  def list_unread_counts(%Scope{user: %User{id: user_id}}, workspace_id) do
    with :ok <- authorize_workspace_member(workspace_id, user_id) do
      unread_counts =
        Repo.all(
          from channel in Channel,
            join: membership in WorkspaceMembership,
            on:
              membership.workspace_id == channel.workspace_id and
                membership.user_id == ^user_id,
            join: message in Message,
            on: message.channel_id == channel.id,
            left_join: read in ChannelRead,
            on: read.channel_id == channel.id and read.user_id == ^user_id,
            where: channel.workspace_id == ^workspace_id,
            where: is_nil(message.user_id) or message.user_id != ^user_id,
            where:
              (not is_nil(read.last_read_message_id) and
                 message.id > read.last_read_message_id) or
                (is_nil(read.last_read_message_id) and
                   message.inserted_at >= membership.inserted_at),
            group_by: channel.id,
            select: {channel.id, count(message.id)}
        )
        |> Map.new()

      {:ok, unread_counts}
    end
  end

  def list_unread_counts(_scope, _workspace_id), do: {:error, :unauthenticated}

  def mark_channel_read(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} <- get_member_channel(channel_id, user_id) do
      latest_message_id = latest_message_id_for_channel(channel_id)

      upsert_channel_read(user_id, channel_id, latest_message_id)

      :ok
    else
      nil -> {:error, :not_found}
    end
  end

  def mark_channel_read(_scope, _channel_id), do: {:error, :unauthenticated}

  def subscribe_to_channel_messages(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} <- get_member_channel(channel_id, user_id) do
      Phoenix.PubSub.subscribe(DiscordClone.PubSub, channel_messages_topic(channel_id))
    else
      nil -> {:error, :not_found}
    end
  end

  def subscribe_to_channel_messages(_scope, _channel_id), do: {:error, :unauthenticated}

  def subscribe_to_workspace_messages(%Scope{user: %User{id: user_id}}, workspace_id) do
    with :ok <- authorize_workspace_member(workspace_id, user_id) do
      Phoenix.PubSub.subscribe(DiscordClone.PubSub, workspace_messages_topic(workspace_id))
    end
  end

  def subscribe_to_workspace_messages(_scope, _workspace_id), do: {:error, :unauthenticated}

  def subscribe_to_channel_typing(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} <- get_member_channel(channel_id, user_id) do
      Phoenix.PubSub.subscribe(DiscordClone.PubSub, channel_messages_topic(channel_id))
    else
      nil -> {:error, :not_found}
    end
  end

  def subscribe_to_channel_typing(_scope, _channel_id), do: {:error, :unauthenticated}

  def subscribe_to_workspace_presence(%Scope{user: %User{id: user_id}}, workspace_id) do
    with :ok <- authorize_workspace_member(workspace_id, user_id) do
      WorkspacePresence.subscribe(workspace_id)
    end
  end

  def subscribe_to_workspace_presence(_scope, _workspace_id), do: {:error, :unauthenticated}

  def list_online_workspace_user_ids(%Scope{user: %User{id: user_id}}, workspace_id) do
    with :ok <- authorize_workspace_member(workspace_id, user_id) do
      {:ok, WorkspacePresenceRuntime.online_user_ids(workspace_id)}
    end
  end

  def list_online_workspace_user_ids(_scope, _workspace_id), do: {:error, :unauthenticated}

  def join_workspace_presence(scope, workspace_id, live_view_pid \\ self())

  def join_workspace_presence(%Scope{user: %User{id: user_id}}, workspace_id, live_view_pid)
      when is_pid(live_view_pid) do
    with :ok <- authorize_workspace_member(workspace_id, user_id) do
      WorkspacePresenceRuntime.join(workspace_id, user_id, live_view_pid)
    end
  end

  def join_workspace_presence(_scope, _workspace_id, _live_view_pid),
    do: {:error, :unauthenticated}

  def stop_workspace_presence(workspace_id) do
    WorkspacePresenceRuntime.stop_workspace(workspace_id)
  end

  def ensure_channel_runtime(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} <- get_member_channel(channel_id, user_id) do
      ChannelSupervisor.start_channel(channel_id)
    else
      nil -> {:error, :not_found}
    end
  end

  def ensure_channel_runtime(_scope, _channel_id), do: {:error, :unauthenticated}

  def list_recent_messages(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} <- get_member_channel(channel_id, user_id),
         {:ok, pid} <- ChannelSupervisor.start_channel(channel_id) do
      ChannelServer.list_recent_messages(pid)
    else
      nil -> {:error, :not_found}
    end
  end

  def list_recent_messages(_scope, _channel_id), do: {:error, :unauthenticated}

  def list_typing_user_ids(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} <- get_member_channel(channel_id, user_id),
         {:ok, pid} <- ChannelSupervisor.start_channel(channel_id) do
      ChannelServer.list_typing_user_ids(pid)
    else
      nil -> {:error, :not_found}
    end
  end

  def list_typing_user_ids(_scope, _channel_id), do: {:error, :unauthenticated}

  def user_started_typing(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} <- get_member_channel(channel_id, user_id),
         {:ok, pid} <- ChannelSupervisor.start_channel(channel_id) do
      ChannelServer.user_started_typing(pid, user_id)
    else
      nil -> {:error, :not_found}
    end
  end

  def user_started_typing(_scope, _channel_id), do: {:error, :unauthenticated}

  def user_stopped_typing(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} <- get_member_channel(channel_id, user_id),
         {:ok, pid} <- ChannelSupervisor.start_channel(channel_id) do
      ChannelServer.user_stopped_typing(pid, user_id)
    else
      nil -> {:error, :not_found}
    end
  end

  def user_stopped_typing(_scope, _channel_id), do: {:error, :unauthenticated}

  def list_older_messages(
        %Scope{user: %User{id: user_id}},
        channel_id,
        %Message{id: cursor_id, inserted_at: cursor_inserted_at}
      ) do
    with %Channel{} <- get_member_channel(channel_id, user_id) do
      messages =
        Message
        |> where([message], message.channel_id == ^channel_id)
        |> where(
          [message],
          message.inserted_at < ^cursor_inserted_at or
            (message.inserted_at == ^cursor_inserted_at and message.id < ^cursor_id)
        )
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

  def list_older_messages(_scope, _channel_id, _cursor), do: {:error, :unauthenticated}

  def send_message(%Scope{user: %User{id: user_id}}, channel_id, attrs) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id) do
      %Message{}
      |> Message.changeset(%{
        "content" => Map.get(attrs, "content") || Map.get(attrs, :content),
        "channel_id" => channel_id,
        "user_id" => user_id
      })
      |> Repo.insert()
      |> case do
        {:ok, message} ->
          {:ok, _channel_read} = upsert_channel_read(user_id, channel_id, message.id)
          message = Repo.preload(message, :user)
          {:ok, pid} = ChannelSupervisor.start_channel(channel_id)
          :ok = ChannelServer.put_recent_message(pid, message)
          :ok = ChannelServer.user_stopped_typing(pid, user_id)
          :ok = broadcast_message_created(message)
          :ok = broadcast_workspace_message_created(channel.workspace_id, message)
          {:ok, message}

        {:error, changeset} ->
          {:error, :invalid_message, changeset}
      end
    else
      nil -> {:error, :not_found}
    end
  end

  def send_message(_scope, _channel_id, _attrs), do: {:error, :unauthenticated}

  def toggle_reaction(%Scope{user: %User{id: user_id}}, message_id, emoji) do
    with {:ok, normalized_emoji} <- Emoji.validate_reaction(emoji),
         %Message{} = message <- get_member_message(message_id, user_id) do
      case Repo.get_by(MessageReaction,
             message_id: message.id,
             user_id: user_id,
             emoji: normalized_emoji
           ) do
        nil ->
          %MessageReaction{}
          |> MessageReaction.changeset(%{
            message_id: message.id,
            user_id: user_id,
            emoji: normalized_emoji
          })
          |> Repo.insert()

        %MessageReaction{} = reaction ->
          Repo.delete(reaction)
      end
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, :invalid_emoji, reason}
    end
  end

  def toggle_reaction(_scope, _message_id, _emoji), do: {:error, :unauthenticated}

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

  defp get_member_message(message_id, user_id) do
    Repo.one(
      from message in Message,
        join: channel in Channel,
        on: channel.id == message.channel_id,
        join: membership in WorkspaceMembership,
        on:
          membership.workspace_id == channel.workspace_id and
            membership.user_id == ^user_id,
        where: message.id == ^message_id,
        limit: 1
    )
  end

  defp authorize_workspace_member(workspace_id, user_id) do
    if Repo.exists?(
         from membership in WorkspaceMembership,
           where: membership.workspace_id == ^workspace_id and membership.user_id == ^user_id
       ) do
      :ok
    else
      {:error, :not_found}
    end
  end

  defp latest_message_per_channel_query do
    from message in Message,
      group_by: message.channel_id,
      select: %{
        channel_id: message.channel_id,
        last_read_message_id: max(message.id)
      }
  end

  defp latest_message_id_for_channel(channel_id) do
    Repo.one(
      from message in Message,
        where: message.channel_id == ^channel_id,
        select: max(message.id)
    )
  end

  defp upsert_channel_read(user_id, channel_id, last_read_message_id) do
    case Repo.get_by(ChannelRead, channel_id: channel_id, user_id: user_id) do
      nil ->
        %ChannelRead{}
        |> ChannelRead.changeset(%{
          channel_id: channel_id,
          user_id: user_id,
          last_read_message_id: last_read_message_id
        })
        |> Repo.insert()

      %ChannelRead{} = channel_read ->
        if cursor_after?(last_read_message_id, channel_read.last_read_message_id) do
          channel_read
          |> ChannelRead.changeset(%{last_read_message_id: last_read_message_id})
          |> Repo.update()
        else
          {:ok, channel_read}
        end
    end
  end

  defp cursor_after?(nil, _current_cursor), do: false
  defp cursor_after?(_new_cursor, nil), do: true
  defp cursor_after?(new_cursor, current_cursor), do: new_cursor > current_cursor

  defp broadcast_message_created(%Message{} = message) do
    Phoenix.PubSub.broadcast_from(
      DiscordClone.PubSub,
      self(),
      channel_messages_topic(message.channel_id),
      {:message_created, message}
    )
  end

  defp channel_messages_topic(channel_id), do: "chat:channel:#{channel_id}"
  defp workspace_messages_topic(workspace_id), do: "chat:workspace:#{workspace_id}:messages"

  defp broadcast_workspace_message_created(workspace_id, %Message{} = message) do
    Phoenix.PubSub.broadcast(
      DiscordClone.PubSub,
      workspace_messages_topic(workspace_id),
      {:workspace_message_created,
       %{
         workspace_id: workspace_id,
         channel_id: message.channel_id,
         message_id: message.id,
         user_id: message.user_id
       }}
    )
  end
end
