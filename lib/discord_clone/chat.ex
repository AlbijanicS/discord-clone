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
    ChannelReadState,
    ChannelSupervisor,
    ChannelServer,
    Emoji,
    Message,
    MessageReaction,
    ChannelUnreadSpan,
    WorkspacePresence,
    WorkspacePresenceRuntime,
    WorkspaceServer
  }

  alias DiscordClone.Repo
  alias DiscordClone.Workspaces.{Channel, WorkspaceMembership, WorkspaceModeration}

  @recent_message_limit 100
  @message_page_size 50
  @small_unread_landing_limit 50
  @large_unread_landing_backtrack div(@message_page_size, 2) - 5

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

      with :ok <-
             Enum.reduce_while(read_rows, :ok, fn read_row, :ok ->
               case upsert_channel_read(
                      user_id,
                      read_row.channel_id,
                      read_row.last_read_message_id
                    ) do
                 {:ok, _channel_read} -> {:cont, :ok}
                 {:error, changeset} -> {:halt, {:error, changeset}}
               end
             end) do
        insert_zero_unread_read_states(read_rows, user_id)
        :ok
      end
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

      insert_zero_unread_read_states(read_rows)

      :ok
    else
      {:error, :not_found}
    end
  end

  def delete_workspace_reads_for_user(user_id, workspace_id) do
    Repo.delete_all(
      from span in ChannelUnreadSpan,
        join: channel in Channel,
        on: channel.id == span.channel_id,
        where: channel.workspace_id == ^workspace_id,
        where: span.user_id == ^user_id
    )

    Repo.delete_all(
      from read_state in ChannelReadState,
        join: channel in Channel,
        on: channel.id == read_state.channel_id,
        where: channel.workspace_id == ^workspace_id,
        where: read_state.user_id == ^user_id
    )

    Repo.delete_all(
      from read in ChannelRead,
        join: channel in Channel,
        on: channel.id == read.channel_id,
        where: channel.workspace_id == ^workspace_id,
        where: read.user_id == ^user_id
    )

    :ok
  end

  def schedule_workspace_timeout_expiry(
        %WorkspaceModeration{workspace_id: workspace_id} = moderation
      ) do
    case WorkspaceServer.whereis(workspace_id) do
      pid when is_pid(pid) -> WorkspaceServer.schedule_timeout_expiry(pid, moderation)
      nil -> :ok
    end
  end

  def cancel_workspace_timeout_expiry(
        %WorkspaceModeration{workspace_id: workspace_id} = moderation
      ) do
    case WorkspaceServer.whereis(workspace_id) do
      pid when is_pid(pid) -> WorkspaceServer.cancel_timeout_expiry(pid, moderation.id)
      nil -> :ok
    end
  end

  def backfill_unread_ranges_from_channel_reads(workspace_id) do
    channel_ids =
      Repo.all(
        from channel in Channel,
          where: channel.workspace_id == ^workspace_id,
          select: channel.id
      )

    Repo.transaction(fn ->
      Repo.delete_all(
        from span in ChannelUnreadSpan,
          where: span.channel_id in ^channel_ids
      )

      Repo.delete_all(
        from read_state in ChannelReadState,
          where: read_state.channel_id in ^channel_ids
      )

      read_state_rows =
        Repo.all(
          from channel in Channel,
            join: membership in WorkspaceMembership,
            on: membership.workspace_id == channel.workspace_id,
            left_join: read in ChannelRead,
            on: read.channel_id == channel.id and read.user_id == membership.user_id,
            where: channel.workspace_id == ^workspace_id,
            select: %{
              channel_id: channel.id,
              user_id: membership.user_id,
              membership_inserted_at: membership.inserted_at,
              last_read_message_id: read.last_read_message_id
            }
        )

      Enum.each(read_state_rows, &backfill_channel_read_state!/1)
    end)
    |> case do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def list_unread_counts(%Scope{user: %User{id: user_id}}, workspace_id) do
    with {:ok, summaries} <-
           list_channel_read_summaries(%Scope{user: %User{id: user_id}}, workspace_id) do
      unread_counts =
        summaries
        |> Enum.filter(&(&1.unread_count > 0))
        |> Map.new(fn summary -> {summary.channel_id, summary.unread_count} end)

      {:ok, unread_counts}
    end
  end

  def list_unread_counts(_scope, _workspace_id), do: {:error, :unauthenticated}

  def list_channel_read_summaries(%Scope{user: %User{id: user_id}}, workspace_id) do
    with :ok <- authorize_workspace_member(workspace_id, user_id) do
      summaries =
        Repo.all(
          from read_state in ChannelReadState,
            join: channel in Channel,
            on: channel.id == read_state.channel_id,
            where: channel.workspace_id == ^workspace_id,
            where: read_state.user_id == ^user_id,
            order_by: [asc: channel.id],
            select: %{
              workspace_id: channel.workspace_id,
              channel_id: read_state.channel_id,
              unread_count: read_state.unread_count,
              first_unread_seq: read_state.first_unread_seq,
              last_unread_seq: read_state.last_unread_seq
            }
        )

      {:ok, summaries}
    end
  end

  def list_channel_read_summaries(_scope, _workspace_id), do: {:error, :unauthenticated}

  def open_channel(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id) do
      now = DateTime.utc_now(:second)

      Repo.transaction(fn ->
        ensure_channel_read_state!(user_id, channel_id)

        read_state =
          user_id
          |> lock_channel_read_state!(channel_id)
          |> ChannelReadState.changeset(%{last_opened_at: now})
          |> Repo.update!()

        %{channel: channel, read_state: read_state, landing: channel_open_landing(read_state)}
      end)
      |> case do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    else
      nil -> {:error, :not_found}
    end
  end

  def open_channel(_scope, _channel_id), do: {:error, :unauthenticated}

  def jump_to_oldest_unread(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id),
         {:ok, _read_state} <- ensure_channel_read_state!(user_id, channel_id),
         read_state = Repo.get_by!(ChannelReadState, channel_id: channel_id, user_id: user_id),
         true <- read_state.unread_count > 0 do
      first_unread_seq = read_state.first_unread_seq
      {:ok, load_message_window_around_channel(channel, first_unread_seq)}
    else
      nil -> {:error, :not_found}
      false -> {:error, :no_unread_messages}
    end
  end

  def jump_to_oldest_unread(_scope, _channel_id), do: {:error, :unauthenticated}

  def jump_to_latest(%Scope{user: %User{id: user_id}} = scope, channel_id) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id),
         :ok <- mark_channel_read(scope, channel_id),
         {:ok, _read_state} <- ensure_channel_read_state!(user_id, channel_id) do
      channel =
        Repo.get!(Channel, channel.id)

      Repo.get_by!(ChannelReadState, channel_id: channel_id, user_id: user_id)
      |> ChannelReadState.changeset(%{last_viewed_anchor_seq: channel.last_message_seq})
      |> Repo.update!()

      {:ok,
       load_message_window_for_channel(
         channel,
         max(1, channel.last_message_seq - @message_page_size + 1),
         channel.last_message_seq
       )}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def jump_to_latest(_scope, _channel_id), do: {:error, :unauthenticated}

  def persist_channel_anchor(%Scope{user: %User{id: user_id}}, channel_id, anchor_seq)
      when is_integer(anchor_seq) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id),
         :ok <- validate_channel_anchor(channel, anchor_seq) do
      Repo.transaction(fn ->
        ensure_channel_read_state!(user_id, channel_id)

        user_id
        |> lock_channel_read_state!(channel_id)
        |> ChannelReadState.changeset(%{last_viewed_anchor_seq: anchor_seq})
        |> Repo.update!()
      end)
      |> case do
        {:ok, read_state} -> {:ok, read_state}
        {:error, reason} -> {:error, reason}
      end
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def persist_channel_anchor(%Scope{user: %User{}}, _channel_id, _anchor_seq),
    do: {:error, :invalid_sequence}

  def persist_channel_anchor(_scope, _channel_id, _anchor_seq), do: {:error, :unauthenticated}

  defp channel_open_landing(%ChannelReadState{unread_count: unread_count} = read_state)
       when unread_count > 0 and unread_count <= @small_unread_landing_limit do
    %{type: :sequence, reason: :first_unread, target_seq: read_state.first_unread_seq}
  end

  defp channel_open_landing(%ChannelReadState{unread_count: unread_count} = read_state)
       when unread_count > @small_unread_landing_limit do
    target_seq = max(1, read_state.last_unread_seq - @large_unread_landing_backtrack)
    %{type: :sequence, reason: :recent_unread, target_seq: target_seq}
  end

  defp channel_open_landing(%ChannelReadState{last_viewed_anchor_seq: anchor_seq})
       when is_integer(anchor_seq) do
    %{type: :sequence, reason: :last_viewed_anchor, target_seq: anchor_seq}
  end

  defp channel_open_landing(%ChannelReadState{}) do
    %{type: :latest, reason: :latest}
  end

  def mark_channel_read(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id) do
      with {:ok, _read_state} <-
             mutate_channel_unread_spans(user_id, channel, fn _spans -> [] end) do
        :ok
      end
    else
      nil -> {:error, :not_found}
    end
  end

  def mark_channel_read(_scope, _channel_id), do: {:error, :unauthenticated}

  def add_channel_unread_range(%Scope{user: %User{id: user_id}}, channel_id, from_seq, to_seq) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id),
         :ok <- validate_unread_range(from_seq, to_seq) do
      mutate_channel_unread_spans(user_id, channel, fn spans ->
        merge_unread_spans([{from_seq, to_seq} | spans])
      end)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def add_channel_unread_range(_scope, _channel_id, _from_seq, _to_seq),
    do: {:error, :unauthenticated}

  def subtract_visible_read_range(%Scope{user: %User{id: user_id}}, channel_id, from_seq, to_seq) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id),
         :ok <- validate_visible_read_range(channel, from_seq, to_seq) do
      mutate_channel_unread_spans(user_id, channel, fn spans ->
        subtract_unread_spans(spans, from_seq, to_seq)
      end)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def subtract_visible_read_range(_scope, _channel_id, _from_seq, _to_seq),
    do: {:error, :unauthenticated}

  def clear_channel_unread(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id) do
      mutate_channel_unread_spans(user_id, channel, fn _spans -> [] end)
    else
      nil -> {:error, :not_found}
    end
  end

  def clear_channel_unread(_scope, _channel_id), do: {:error, :unauthenticated}

  def subscribe_to_channel_read_state(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} <- get_member_channel(channel_id, user_id) do
      Phoenix.PubSub.subscribe(DiscordClone.PubSub, channel_read_state_topic(user_id, channel_id))
    else
      nil -> {:error, :not_found}
    end
  end

  def subscribe_to_channel_read_state(_scope, _channel_id), do: {:error, :unauthenticated}

  def subscribe_to_channel_messages(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} <- get_member_channel(channel_id, user_id) do
      Phoenix.PubSub.subscribe(DiscordClone.PubSub, channel_messages_topic(channel_id))
    else
      nil -> {:error, :not_found}
    end
  end

  def subscribe_to_channel_messages(_scope, _channel_id), do: {:error, :unauthenticated}

  def subscribe_to_channel_reactions(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} <- get_member_channel(channel_id, user_id) do
      Phoenix.PubSub.subscribe(DiscordClone.PubSub, channel_reactions_topic(channel_id))
    else
      nil -> {:error, :not_found}
    end
  end

  def subscribe_to_channel_reactions(_scope, _channel_id), do: {:error, :unauthenticated}

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
      with :ok <- WorkspacePresenceRuntime.join(workspace_id, user_id, live_view_pid) do
        schedule_existing_workspace_timeout_expiries(workspace_id)
      end
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

  def load_latest_message_window(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id) do
      latest_seq = channel.last_message_seq
      oldest_requested_seq = max(1, latest_seq - @message_page_size + 1)
      {:ok, load_message_window_for_channel(channel, oldest_requested_seq, latest_seq)}
    else
      nil -> {:error, :not_found}
    end
  end

  def load_latest_message_window(_scope, _channel_id), do: {:error, :unauthenticated}

  def load_message_window_around(%Scope{user: %User{id: user_id}}, channel_id, target_seq)
      when is_integer(target_seq) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id) do
      {:ok, load_message_window_around_channel(channel, target_seq)}
    else
      nil -> {:error, :not_found}
    end
  end

  def load_message_window_around(%Scope{user: %User{}}, _channel_id, _target_seq),
    do: {:error, :invalid_sequence}

  def load_message_window_around(_scope, _channel_id, _target_seq),
    do: {:error, :unauthenticated}

  def load_older_message_window(%Scope{user: %User{id: user_id}}, channel_id, before_seq)
      when is_integer(before_seq) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id) do
      to_seq = min(channel.last_message_seq, before_seq - 1)
      from_seq = max(1, to_seq - @message_page_size + 1)
      {:ok, load_message_window_for_channel(channel, from_seq, to_seq)}
    else
      nil -> {:error, :not_found}
    end
  end

  def load_older_message_window(%Scope{user: %User{}}, _channel_id, _before_seq),
    do: {:error, :invalid_sequence}

  def load_older_message_window(_scope, _channel_id, _before_seq),
    do: {:error, :unauthenticated}

  def load_newer_message_window(%Scope{user: %User{id: user_id}}, channel_id, after_seq)
      when is_integer(after_seq) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id) do
      from_seq = max(1, after_seq + 1)
      to_seq = min(channel.last_message_seq, from_seq + @message_page_size - 1)
      {:ok, load_message_window_for_channel(channel, from_seq, to_seq)}
    else
      nil -> {:error, :not_found}
    end
  end

  def load_newer_message_window(%Scope{user: %User{}}, _channel_id, _after_seq),
    do: {:error, :invalid_sequence}

  def load_newer_message_window(_scope, _channel_id, _after_seq),
    do: {:error, :unauthenticated}

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
    with %Channel{} = channel <- get_member_channel(channel_id, user_id),
         :ok <- authorize_unmuted(channel.workspace_id, user_id),
         {:ok, pid} <- ChannelSupervisor.start_channel(channel_id) do
      ChannelServer.user_started_typing(pid, user_id)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def user_started_typing(_scope, _channel_id), do: {:error, :unauthenticated}

  def user_stopped_typing(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} <- get_member_channel(channel_id, user_id),
         {:ok, pid} <- ChannelSupervisor.start_channel(channel_id) do
      ChannelServer.user_stopped_typing(pid, user_id)
    else
      nil -> {:error, :not_found}
      {:error, :muted} -> {:error, :muted}
      {:error, :timeout} -> {:error, :timeout}
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
    with %Channel{} = channel <- get_member_channel(channel_id, user_id),
         :ok <- authorize_unmuted(channel.workspace_id, user_id) do
      changeset =
        Message.changeset(%Message{}, %{
          "content" => Map.get(attrs, "content") || Map.get(attrs, :content),
          "channel_id" => channel_id,
          "user_id" => user_id
        })

      case insert_sequenced_message(changeset, user_id, channel) do
        {:ok, {message, read_state_changes}} ->
          message = Repo.preload(message, :user)
          {:ok, pid} = ChannelSupervisor.start_channel(channel_id)
          :ok = ChannelServer.put_recent_message(pid, message)
          :ok = ChannelServer.user_stopped_typing(pid, user_id)
          :ok = broadcast_channel_read_state_changes(read_state_changes)
          :ok = broadcast_message_created(message)
          :ok = broadcast_workspace_message_created(channel.workspace_id, message)
          {:ok, message}

        {:error, {:invalid_message, changeset}} ->
          {:error, :invalid_message, changeset}
      end
    else
      nil -> {:error, :not_found}
      {:error, :muted} -> {:error, :muted}
      {:error, :timeout} -> {:error, :timeout}
    end
  end

  def send_message(_scope, _channel_id, _attrs), do: {:error, :unauthenticated}

  defp insert_sequenced_message(changeset, user_id, %Channel{id: channel_id} = channel) do
    Repo.transaction(fn ->
      locked_channel = lock_channel_for_update!(channel_id)
      next_seq = locked_channel.last_message_seq + 1

      with {:ok, message} <-
             changeset
             |> Ecto.Changeset.put_change(:seq, next_seq)
             |> Repo.insert(),
           {:ok, _channel} <-
             locked_channel
             |> Ecto.Changeset.change(last_message_seq: next_seq)
             |> Repo.update() do
        read_state_changes = apply_message_unread_fanout!(channel, user_id, next_seq)
        {message, read_state_changes}
      else
        {:error, changeset} -> Repo.rollback({:invalid_message, changeset})
      end
    end)
  end

  def toggle_reaction(%Scope{user: %User{id: user_id}}, message_id, emoji) do
    with {:ok, normalized_emoji} <- Emoji.validate_reaction(emoji),
         %Message{} = message <- get_member_message(message_id, user_id),
         :ok <- authorize_unmuted(message.channel.workspace_id, user_id) do
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
      |> case do
        {:ok, reaction_or_deleted_reaction} ->
          :ok = broadcast_reaction_changed(message, normalized_emoji)
          {:ok, reaction_or_deleted_reaction}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      nil -> {:error, :not_found}
      {:error, :muted} -> {:error, :muted}
      {:error, :timeout} -> {:error, :timeout}
      {:error, reason} -> {:error, :invalid_emoji, reason}
    end
  end

  def toggle_reaction(_scope, _message_id, _emoji), do: {:error, :unauthenticated}

  def list_reaction_summaries(%Scope{user: %User{}}, []), do: {:ok, %{}}

  def list_reaction_summaries(%Scope{user: %User{id: user_id}}, message_ids)
      when is_list(message_ids) do
    message_ids = Enum.uniq(message_ids)

    with :ok <- authorize_member_messages(message_ids, user_id) do
      summaries =
        MessageReaction
        |> where([reaction], reaction.message_id in ^message_ids)
        |> group_by([reaction], [reaction.message_id, reaction.emoji])
        |> order_by([reaction], asc: reaction.message_id, asc: reaction.emoji)
        |> select([reaction], %{
          message_id: reaction.message_id,
          emoji: reaction.emoji,
          count: count(reaction.id),
          reacted?: fragment("bool_or(? = ?)", reaction.user_id, ^user_id)
        })
        |> Repo.all()
        |> Enum.group_by(& &1.message_id, fn summary ->
          %{emoji: summary.emoji, count: summary.count, reacted?: summary.reacted?}
        end)

      {:ok, summaries}
    end
  end

  def list_reaction_summaries(_scope, _message_ids), do: {:error, :unauthenticated}

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
        limit: 1,
        preload: [channel: channel]
    )
  end

  defp authorize_unmuted(workspace_id, user_id) do
    muted? =
      Repo.exists?(
        from moderation in WorkspaceModeration,
          where:
            moderation.workspace_id == ^workspace_id and
              moderation.target_user_id == ^user_id and
              moderation.type == "mute" and
              moderation.active? == true
      )

    timed_out? =
      Repo.exists?(
        from moderation in WorkspaceModeration,
          where:
            moderation.workspace_id == ^workspace_id and
              moderation.target_user_id == ^user_id and
              moderation.type == "timeout" and
              moderation.active? == true and
              moderation.expires_at > ^DateTime.utc_now(:second)
      )

    cond do
      muted? -> {:error, :muted}
      timed_out? -> {:error, :timeout}
      true -> :ok
    end
  end

  defp schedule_existing_workspace_timeout_expiries(workspace_id) do
    case WorkspacePresenceRuntime.whereis(workspace_id) do
      pid when is_pid(pid) ->
        workspace_id
        |> DiscordClone.Workspaces.list_active_future_timeouts()
        |> Enum.each(&WorkspaceServer.schedule_timeout_expiry(pid, &1))

        :ok

      nil ->
        :ok
    end
  end

  defp authorize_member_messages(message_ids, user_id) do
    accessible_message_count =
      Repo.one(
        from message in Message,
          join: channel in Channel,
          on: channel.id == message.channel_id,
          join: membership in WorkspaceMembership,
          on:
            membership.workspace_id == channel.workspace_id and
              membership.user_id == ^user_id,
          where: message.id in ^message_ids,
          select: count(message.id)
      )

    if accessible_message_count == length(message_ids) do
      :ok
    else
      {:error, :not_found}
    end
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

  defp messages_between_sequences(channel_id, from_seq, to_seq) do
    Message
    |> where([message], message.channel_id == ^channel_id)
    |> where([message], message.seq >= ^from_seq and message.seq <= ^to_seq)
    |> order_by([message], asc: message.seq)
    |> preload(:user)
  end

  defp load_message_window_for_channel(%Channel{} = channel, from_seq, to_seq) do
    messages =
      channel.id
      |> messages_between_sequences(from_seq, to_seq)
      |> Repo.all()

    message_window(messages, channel.last_message_seq)
  end

  defp load_message_window_around_channel(%Channel{} = channel, target_seq) do
    from_seq = max(1, target_seq - 15)
    to_seq = min(channel.last_message_seq, target_seq + 35)
    load_message_window_for_channel(channel, from_seq, to_seq)
  end

  defp message_window(messages, latest_seq) do
    oldest_seq = messages |> List.first() |> message_seq()
    newest_seq = messages |> List.last() |> message_seq()

    %{
      messages: messages,
      meta: %{
        oldest_seq: oldest_seq,
        newest_seq: newest_seq,
        latest_seq: latest_seq,
        has_older?: older_history?(oldest_seq),
        has_newer?: newer_history?(newest_seq, latest_seq),
        at_latest?: at_latest?(newest_seq, latest_seq),
        at_or_near_latest?: at_or_near_latest?(newest_seq, latest_seq)
      }
    }
  end

  defp message_seq(%Message{seq: seq}), do: seq
  defp message_seq(nil), do: nil

  defp older_history?(oldest_seq) when is_integer(oldest_seq), do: oldest_seq > 1
  defp older_history?(nil), do: false

  defp newer_history?(newest_seq, latest_seq) when is_integer(newest_seq),
    do: newest_seq < latest_seq

  defp newer_history?(nil, latest_seq), do: latest_seq > 0

  defp at_latest?(newest_seq, latest_seq) when is_integer(newest_seq),
    do: newest_seq == latest_seq

  defp at_latest?(nil, 0), do: true
  defp at_latest?(nil, _latest_seq), do: false

  defp at_or_near_latest?(newest_seq, latest_seq) when is_integer(newest_seq),
    do: latest_seq - newest_seq <= @message_page_size

  defp at_or_near_latest?(nil, 0), do: true
  defp at_or_near_latest?(nil, _latest_seq), do: false

  defp lock_channel_for_update!(channel_id) do
    Repo.one!(
      from channel in Channel,
        where: channel.id == ^channel_id,
        lock: "FOR UPDATE"
    )
  end

  defp apply_message_unread_fanout!(%Channel{} = channel, sender_user_id, message_seq) do
    channel
    |> list_channel_recipient_user_ids(sender_user_id)
    |> Enum.reduce([], fn recipient_user_id, read_state_changes ->
      ensure_channel_read_state!(recipient_user_id, channel.id)
      read_state = lock_channel_read_state!(recipient_user_id, channel.id)

      current_spans = list_channel_unread_span_bounds(recipient_user_id, channel.id)
      next_spans = merge_unread_spans([{message_seq, message_seq} | current_spans])

      if current_spans == next_spans do
        read_state_changes
      else
        replace_channel_unread_spans!(recipient_user_id, channel.id, next_spans)
        read_state = update_read_state_summary!(read_state, next_spans)
        [{channel.workspace_id, recipient_user_id, read_state} | read_state_changes]
      end
    end)
    |> Enum.reverse()
  end

  defp list_channel_recipient_user_ids(%Channel{workspace_id: workspace_id}, sender_user_id) do
    Repo.all(
      from membership in WorkspaceMembership,
        where: membership.workspace_id == ^workspace_id and membership.user_id != ^sender_user_id,
        order_by: [asc: membership.user_id],
        select: membership.user_id
    )
  end

  defp mutate_channel_unread_spans(user_id, %Channel{} = channel, fun) do
    Repo.transaction(fn ->
      channel_id = channel.id
      ensure_channel_read_state!(user_id, channel_id)
      read_state = lock_channel_read_state!(user_id, channel_id)

      current_spans = list_channel_unread_span_bounds(user_id, channel_id)
      next_spans = fun.(current_spans)
      changed? = current_spans != next_spans

      read_state =
        if changed? do
          replace_channel_unread_spans!(user_id, channel_id, next_spans)
          update_read_state_summary!(read_state, next_spans)
        else
          read_state
        end

      {read_state, changed?}
    end)
    |> case do
      {:ok, {read_state, true}} ->
        :ok = broadcast_channel_read_state_changed(channel.workspace_id, user_id, read_state)
        {:ok, read_state}

      {:ok, {read_state, false}} ->
        {:ok, read_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_channel_read_state!(user_id, channel_id) do
    %ChannelReadState{}
    |> ChannelReadState.changeset(%{
      channel_id: channel_id,
      user_id: user_id,
      unread_count: 0
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:channel_id, :user_id]
    )
  end

  defp insert_zero_unread_read_states(channel_rows, user_id) do
    now = DateTime.utc_now(:second)

    read_state_rows =
      Enum.map(channel_rows, fn %{channel_id: channel_id} ->
        %{
          channel_id: channel_id,
          user_id: user_id,
          unread_count: 0,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(
      ChannelReadState,
      read_state_rows,
      on_conflict: :nothing,
      conflict_target: [:channel_id, :user_id]
    )
  end

  defp insert_zero_unread_read_states(channel_user_rows) do
    now = DateTime.utc_now(:second)

    read_state_rows =
      Enum.map(channel_user_rows, fn %{channel_id: channel_id, user_id: user_id} ->
        %{
          channel_id: channel_id,
          user_id: user_id,
          unread_count: 0,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(
      ChannelReadState,
      read_state_rows,
      on_conflict: :nothing,
      conflict_target: [:channel_id, :user_id]
    )
  end

  defp lock_channel_read_state!(user_id, channel_id) do
    Repo.one!(
      from read_state in ChannelReadState,
        where: read_state.channel_id == ^channel_id and read_state.user_id == ^user_id,
        lock: "FOR UPDATE"
    )
  end

  defp list_channel_unread_span_bounds(user_id, channel_id) do
    Repo.all(
      from span in ChannelUnreadSpan,
        where: span.channel_id == ^channel_id and span.user_id == ^user_id,
        order_by: [asc: span.from_seq],
        select: {span.from_seq, span.to_seq}
    )
  end

  defp replace_channel_unread_spans!(user_id, channel_id, spans) do
    Repo.delete_all(
      from span in ChannelUnreadSpan,
        where: span.channel_id == ^channel_id and span.user_id == ^user_id
    )

    Enum.each(spans, fn {from_seq, to_seq} ->
      Repo.insert!(
        ChannelUnreadSpan.changeset(%ChannelUnreadSpan{}, %{
          channel_id: channel_id,
          user_id: user_id,
          from_seq: from_seq,
          to_seq: to_seq
        })
      )
    end)
  end

  defp update_read_state_summary!(read_state, spans) do
    attrs = unread_summary_attrs(spans)

    read_state
    |> ChannelReadState.changeset(attrs)
    |> Repo.update!()
  end

  defp unread_summary_attrs([]) do
    %{unread_count: 0, first_unread_seq: nil, last_unread_seq: nil}
  end

  defp unread_summary_attrs(spans) do
    {first_seq, _first_to_seq} = List.first(spans)
    {_last_from_seq, last_seq} = List.last(spans)

    unread_count =
      Enum.reduce(spans, 0, fn {from_seq, to_seq}, count ->
        count + to_seq - from_seq + 1
      end)

    %{
      unread_count: unread_count,
      first_unread_seq: first_seq,
      last_unread_seq: last_seq
    }
  end

  defp merge_unread_spans(spans) do
    spans
    |> Enum.sort_by(fn {from_seq, to_seq} -> {from_seq, to_seq} end)
    |> Enum.reduce([], fn
      span, [] ->
        [span]

      {from_seq, to_seq}, [{current_from_seq, current_to_seq} | rest]
      when from_seq <= current_to_seq + 1 ->
        [{current_from_seq, max(current_to_seq, to_seq)} | rest]

      span, merged ->
        [span | merged]
    end)
    |> Enum.reverse()
  end

  defp subtract_unread_spans(spans, read_from_seq, read_to_seq) do
    spans
    |> Enum.flat_map(fn {from_seq, to_seq} ->
      cond do
        read_to_seq < from_seq or read_from_seq > to_seq ->
          [{from_seq, to_seq}]

        read_from_seq <= from_seq and read_to_seq >= to_seq ->
          []

        read_from_seq <= from_seq ->
          [{read_to_seq + 1, to_seq}]

        read_to_seq >= to_seq ->
          [{from_seq, read_from_seq - 1}]

        true ->
          [{from_seq, read_from_seq - 1}, {read_to_seq + 1, to_seq}]
      end
    end)
  end

  defp validate_visible_read_range(channel, from_seq, to_seq)
       when is_integer(from_seq) and is_integer(to_seq) do
    cond do
      from_seq < 1 ->
        {:error, :invalid_range}

      from_seq > to_seq ->
        {:error, :invalid_range}

      to_seq - from_seq + 1 > 50 ->
        {:error, :range_too_large}

      to_seq > channel.last_message_seq ->
        {:error, :invalid_range}

      true ->
        :ok
    end
  end

  defp validate_visible_read_range(_channel, _from_seq, _to_seq), do: {:error, :invalid_range}

  defp validate_channel_anchor(%Channel{} = channel, anchor_seq) when is_integer(anchor_seq) do
    if anchor_seq >= 1 and anchor_seq <= channel.last_message_seq do
      :ok
    else
      {:error, :invalid_sequence}
    end
  end

  defp validate_unread_range(from_seq, to_seq) when is_integer(from_seq) and is_integer(to_seq) do
    if from_seq >= 1 and from_seq <= to_seq do
      :ok
    else
      {:error, :invalid_range}
    end
  end

  defp validate_unread_range(_from_seq, _to_seq), do: {:error, :invalid_range}

  defp latest_message_per_channel_query do
    from message in Message,
      group_by: message.channel_id,
      select: %{
        channel_id: message.channel_id,
        last_read_message_id: max(message.id)
      }
  end

  defp backfill_channel_read_state!(read_state_row) do
    unread_sequences = unread_sequences_for_backfill(read_state_row)
    spans = sequences_to_spans(unread_sequences)
    unread_count = length(unread_sequences)

    attrs =
      %{
        channel_id: read_state_row.channel_id,
        user_id: read_state_row.user_id,
        unread_count: unread_count,
        first_unread_seq: List.first(unread_sequences),
        last_unread_seq: List.last(unread_sequences)
      }

    Repo.insert!(ChannelReadState.changeset(%ChannelReadState{}, attrs))

    Enum.each(spans, fn {from_seq, to_seq} ->
      Repo.insert!(
        ChannelUnreadSpan.changeset(%ChannelUnreadSpan{}, %{
          channel_id: read_state_row.channel_id,
          user_id: read_state_row.user_id,
          from_seq: from_seq,
          to_seq: to_seq
        })
      )
    end)
  end

  defp unread_sequences_for_backfill(%{last_read_message_id: last_read_message_id} = row)
       when is_integer(last_read_message_id) do
    Repo.all(
      from message in Message,
        where: message.channel_id == ^row.channel_id,
        where: message.id > ^last_read_message_id,
        where: is_nil(message.user_id) or message.user_id != ^row.user_id,
        order_by: [asc: message.seq],
        select: message.seq
    )
  end

  defp unread_sequences_for_backfill(row) do
    Repo.all(
      from message in Message,
        where: message.channel_id == ^row.channel_id,
        where: message.inserted_at >= ^row.membership_inserted_at,
        where: is_nil(message.user_id) or message.user_id != ^row.user_id,
        order_by: [asc: message.seq],
        select: message.seq
    )
  end

  defp sequences_to_spans([]), do: []

  defp sequences_to_spans([first_seq | rest]) do
    {spans, from_seq, to_seq} =
      Enum.reduce(rest, {[], first_seq, first_seq}, fn seq, {spans, from_seq, to_seq} ->
        if seq == to_seq + 1 do
          {spans, from_seq, seq}
        else
          {[{from_seq, to_seq} | spans], seq, seq}
        end
      end)

    Enum.reverse([{from_seq, to_seq} | spans])
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
  defp channel_reactions_topic(channel_id), do: "chat:channel:#{channel_id}:reactions"
  defp workspace_messages_topic(workspace_id), do: "chat:workspace:#{workspace_id}:messages"

  defp channel_read_state_topic(user_id, channel_id),
    do: "chat:user:#{user_id}:channel:#{channel_id}:read_state"

  defp broadcast_channel_read_state_changes(read_state_changes) do
    Enum.each(read_state_changes, fn {workspace_id, user_id, read_state} ->
      :ok = broadcast_channel_read_state_changed(workspace_id, user_id, read_state)
    end)

    :ok
  end

  defp broadcast_channel_read_state_changed(
         workspace_id,
         user_id,
         %ChannelReadState{} = read_state
       ) do
    Phoenix.PubSub.broadcast(
      DiscordClone.PubSub,
      channel_read_state_topic(user_id, read_state.channel_id),
      {:channel_read_state_changed,
       %{
         workspace_id: workspace_id,
         channel_id: read_state.channel_id,
         unread_count: read_state.unread_count,
         first_unread_seq: read_state.first_unread_seq,
         last_unread_seq: read_state.last_unread_seq
       }}
    )
  end

  defp broadcast_reaction_changed(%Message{} = message, emoji) do
    Phoenix.PubSub.broadcast_from(
      DiscordClone.PubSub,
      self(),
      channel_reactions_topic(message.channel_id),
      {:reaction_changed, %{message_id: message.id, emoji: emoji}}
    )
  end

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
