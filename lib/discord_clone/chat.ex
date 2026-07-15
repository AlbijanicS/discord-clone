defmodule DiscordClone.Chat do
  @moduledoc """
  The Chat context.

  This context will own persisted message workflows, PubSub orchestration, and
  live channel processes as the chat phases are built.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias DiscordClone.Accounts.{Scope, User}
  alias DiscordClone.Activities.ActivityItem

  alias DiscordClone.Chat.{
    ChannelReadState,
    Emoji,
    Message,
    MentionParser,
    MessageReaction,
    MessageWindow,
    Runtime,
    Unread
  }

  alias DiscordClone.{Repo, UUIDIdentifier, Workspaces}

  alias DiscordClone.Workspaces.{
    Channel,
    Roles,
    WorkspaceAuditEvent,
    WorkspaceMembership,
    WorkspaceModeration
  }

  @recent_message_limit 100
  @message_page_size 50
  @small_unread_landing_limit 50
  @large_unread_landing_backtrack div(@message_page_size, 2) - 5

  @type reason :: atom()
  @type window_result :: {:ok, map()} | {:error, reason()}

  def change_message(attrs \\ %{}) do
    Message.changeset(%Message{}, attrs)
  end

  @doc "Returns the scoped user's global unread activity count."
  @spec unread_activity_count(term()) :: {:ok, non_neg_integer()} | {:error, :unauthenticated}
  def unread_activity_count(%Scope{user: %User{id: user_id}}) do
    count =
      Repo.aggregate(
        from(activity_item in ActivityItem,
          where: activity_item.recipient_user_id == ^user_id and is_nil(activity_item.read_at)
        ),
        :count
      )

    {:ok, count}
  end

  def unread_activity_count(_scope), do: {:error, :unauthenticated}

  @doc "Returns the scoped user's accessible global Activity Feed newest first."
  @spec list_activity_feed(term()) :: {:ok, [ActivityItem.t()]} | {:error, :unauthenticated}
  def list_activity_feed(%Scope{user: %User{id: user_id}}) do
    activity_items =
      Repo.all(
        from activity_item in ActivityItem,
          join: membership in WorkspaceMembership,
          on:
            membership.workspace_id == activity_item.workspace_id and
              membership.user_id == ^user_id,
          where: activity_item.recipient_user_id == ^user_id,
          order_by: [desc: activity_item.inserted_at, desc: activity_item.id],
          preload: [:workspace, :source_channel, :source_message, :actor_user]
      )

    {:ok, activity_items}
  end

  def list_activity_feed(_scope), do: {:error, :unauthenticated}

  @doc """
  Opens one Activity Item for the scoped recipient.

  The item is marked read only after its current Workspace membership, source
  Channel, and live source Message have been validated together. All invalid or
  inaccessible targets use `:not_found` so callers cannot infer source existence.
  """
  @spec open_activity_item(term(), term()) ::
          {:ok,
           %{workspace_id: Ecto.UUID.t(), channel_id: Ecto.UUID.t(), message_id: Ecto.UUID.t()}}
          | {:error, :unauthenticated | :not_found}
  def open_activity_item(%Scope{user: %User{id: user_id}}, activity_item_id) do
    with {:ok, activity_item_id} <- Ecto.UUID.cast(activity_item_id) do
      Repo.transaction(fn ->
        destination =
          Repo.one(
            from activity_item in ActivityItem,
              join: membership in WorkspaceMembership,
              on:
                membership.workspace_id == activity_item.workspace_id and
                  membership.user_id == ^user_id,
              join: channel in Channel,
              on:
                channel.id == activity_item.source_channel_id and
                  channel.workspace_id == activity_item.workspace_id,
              join: message in Message,
              on:
                message.id == activity_item.source_message_id and
                  message.channel_id == activity_item.source_channel_id and
                  is_nil(message.deleted_at),
              where:
                activity_item.id == ^activity_item_id and
                  activity_item.recipient_user_id == ^user_id,
              select: %{
                workspace_id: activity_item.workspace_id,
                channel_id: activity_item.source_channel_id,
                message_id: activity_item.source_message_id
              },
              lock: "FOR UPDATE"
          )

        if destination do
          Repo.update_all(
            from(activity_item in ActivityItem,
              where:
                activity_item.id == ^activity_item_id and
                  activity_item.recipient_user_id == ^user_id and
                  is_nil(activity_item.read_at)
            ),
            set: [read_at: DateTime.utc_now(:microsecond)]
          )

          destination
        else
          Repo.rollback(:not_found)
        end
      end)
    else
      :error -> {:error, :not_found}
    end
  end

  def open_activity_item(%Scope{user: %User{}}, _activity_item_id),
    do: {:error, :not_found}

  def open_activity_item(_scope, _activity_item_id), do: {:error, :unauthenticated}

  @doc "Initializes zero-unread read states for a user across a workspace's channels."
  @spec initialize_workspace_reads_for_user(Ecto.UUID.t(), Ecto.UUID.t()) ::
          :ok | {:error, reason()}
  defdelegate initialize_workspace_reads_for_user(user_id, workspace_id), to: Unread

  @doc "Initializes zero-unread read states for all existing members of a channel."
  @spec initialize_channel_reads_for_workspace_members(Ecto.UUID.t()) ::
          :ok | {:error, reason()}
  defdelegate initialize_channel_reads_for_workspace_members(channel_id), to: Unread

  @doc "Deletes a user's read states for every channel in a workspace."
  @spec delete_workspace_reads_for_user(Ecto.UUID.t(), Ecto.UUID.t()) ::
          :ok | {:error, reason()}
  defdelegate delete_workspace_reads_for_user(user_id, workspace_id), to: Unread

  @doc """
  Soft-deletes messages authored by `target_user_id` across all channels in the
  given workspace, optionally bounded to a time window.

  `bound` is either `:all` (every message) or a `%DateTime{}` cutoff (only
  messages inserted at or after the cutoff). Reactions on the affected messages
  are removed and each message keeps its content behind a `deleted_at`
  tombstone. Returns `{:ok, messages}` with the affected messages (author
  preloaded) so callers can broadcast refreshes after committing.
  """
  def soft_delete_user_workspace_messages(workspace_id, target_user_id, actor_user_id, bound) do
    deleted_at = DateTime.utc_now(:second)

    message_ids =
      Repo.all(cleanup_message_ids_query(workspace_id, target_user_id, bound))

    if message_ids == [] do
      {:ok, []}
    else
      Repo.delete_all(
        from reaction in MessageReaction, where: reaction.message_id in ^message_ids
      )

      Repo.update_all(
        from(message in Message, where: message.id in ^message_ids),
        set: [deleted_at: deleted_at, deleted_by_user_id: actor_user_id, updated_at: deleted_at]
      )

      messages =
        Repo.all(
          from message in Message,
            where: message.id in ^message_ids,
            order_by: [asc: message.channel_id, asc: message.seq],
            preload: [:user]
        )

      {:ok, messages}
    end
  end

  defp cleanup_message_ids_query(workspace_id, target_user_id, bound) do
    query =
      from message in Message,
        join: channel in Channel,
        on: channel.id == message.channel_id,
        where: channel.workspace_id == ^workspace_id,
        where: message.user_id == ^target_user_id,
        where: is_nil(message.deleted_at),
        select: message.id

    case bound do
      :all -> query
      %DateTime{} = cutoff -> from message in query, where: message.inserted_at >= ^cutoff
    end
  end

  @doc """
  Broadcasts `:message_deleted` refreshes for messages cleaned during a ban so
  connected channel viewers can re-render the affected placeholders.
  """
  def broadcast_cleaned_messages(messages) do
    Enum.each(messages, fn %Message{} = message ->
      Phoenix.PubSub.broadcast(
        DiscordClone.PubSub,
        channel_messages_topic(message.channel_id),
        {:message_deleted, %{channel_id: message.channel_id, message_id: message.id}}
      )
    end)

    :ok
  end

  def schedule_workspace_timeout_expiry(%WorkspaceModeration{} = moderation) do
    Runtime.schedule_timeout_expiry(moderation)
  end

  def cancel_workspace_timeout_expiry(%WorkspaceModeration{} = moderation) do
    Runtime.cancel_timeout_expiry(moderation)
  end

  def broadcast_workspace_user_joined(workspace_id, user_id) do
    Runtime.broadcast_user_joined(workspace_id, user_id)
  end

  defdelegate list_unread_counts(scope, workspace_id), to: Unread
  defdelegate list_channel_read_summaries(scope, workspace_id), to: Unread

  @doc """
  Opens an accessible channel and returns its persisted read state and landing target.

  Returns a normalized error when the scope is unauthenticated or the channel is inaccessible.
  """
  @spec open_channel(term(), Ecto.UUID.t()) :: {:ok, map()} | {:error, reason()}
  def open_channel(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id) do
      now = DateTime.utc_now(:second)

      Repo.transaction(fn ->
        Unread.ensure_channel_read_state!(user_id, channel_id)

        read_state =
          user_id
          |> Unread.lock_channel_read_state!(channel_id)
          |> Unread.change_read_state(%{last_opened_at: now})
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

  defdelegate jump_to_oldest_unread(scope, channel_id), to: Unread

  @doc """
  Marks an accessible channel read, persists its latest anchor, and returns the latest message window.

  Returns a normalized error when the scope is unauthenticated or the channel is inaccessible.
  """
  @spec jump_to_latest(term(), Ecto.UUID.t()) :: window_result()
  def jump_to_latest(%Scope{user: %User{id: user_id}} = scope, channel_id) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id),
         :ok <- mark_channel_read(scope, channel_id),
         {:ok, _read_state} <- Unread.ensure_channel_read_state!(user_id, channel_id) do
      channel =
        Repo.get!(Channel, channel.id)

      Unread.get_channel_read_state!(user_id, channel_id)
      |> Unread.change_read_state(%{last_viewed_anchor_seq: channel.last_message_seq})
      |> Repo.update!()

      {:ok,
       MessageWindow.load_for_channel(
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

  @doc """
  Persists a validated rendered-message sequence as the user's channel scroll anchor.

  Invalid sequences and inaccessible channels return normalized error reasons.
  """
  @spec persist_channel_anchor(term(), Ecto.UUID.t(), term()) ::
          {:ok, struct()} | {:error, reason()}
  def persist_channel_anchor(%Scope{user: %User{id: user_id}}, channel_id, anchor_seq)
      when is_integer(anchor_seq) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id),
         :ok <- validate_channel_anchor(channel, anchor_seq) do
      Repo.transaction(fn ->
        Unread.ensure_channel_read_state!(user_id, channel_id)

        user_id
        |> Unread.lock_channel_read_state!(channel_id)
        |> Unread.change_read_state(%{last_viewed_anchor_seq: anchor_seq})
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

  defdelegate mark_channel_read(scope, channel_id), to: Unread
  # Deliberate test seam: the only public way to inject an arbitrary unread
  # span. In production, unread spans arise solely from `send_message/3` fanout.
  @doc false
  defdelegate add_channel_unread_range(scope, channel_id, from_seq, to_seq), to: Unread

  @doc """
  Marks a visible sequence range read after authoritative validation in the Unread boundary.

  Returns `:ok` or a normalized error reason for invalid ranges, access, or authentication.
  """
  @spec subtract_visible_read_range(term(), Ecto.UUID.t(), term(), term()) ::
          :ok | {:error, reason()}
  defdelegate subtract_visible_read_range(scope, channel_id, from_seq, to_seq), to: Unread
  defdelegate subscribe_to_channel_read_state(scope, channel_id), to: Unread

  # Subscribes to a channel's message topic. Transient typing indicators
  # (`:typing_started` / `:typing_stopped`, broadcast by the channel runtime)
  # ride on this same topic, so a message subscriber also receives typing
  # events — there is deliberately no separate typing subscription.
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

  def subscribe_to_workspace_presence(%Scope{user: %User{id: user_id}}, workspace_id) do
    with :ok <- authorize_workspace_member(workspace_id, user_id) do
      Runtime.subscribe_workspace_presence(workspace_id)
    end
  end

  def subscribe_to_workspace_presence(_scope, _workspace_id), do: {:error, :unauthenticated}

  def list_online_workspace_user_ids(%Scope{user: %User{id: user_id}}, workspace_id) do
    with :ok <- authorize_workspace_member(workspace_id, user_id) do
      {:ok, Runtime.online_user_ids(workspace_id)}
    end
  end

  def list_online_workspace_user_ids(_scope, _workspace_id), do: {:error, :unauthenticated}

  def join_workspace_presence(scope, workspace_id, live_view_pid \\ self())

  def join_workspace_presence(%Scope{user: %User{id: user_id}}, workspace_id, live_view_pid)
      when is_pid(live_view_pid) do
    with :ok <- authorize_workspace_member(workspace_id, user_id) do
      Runtime.join_workspace_presence(workspace_id, user_id, live_view_pid)
    end
  end

  def join_workspace_presence(_scope, _workspace_id, _live_view_pid),
    do: {:error, :unauthenticated}

  def stop_workspace_presence(workspace_id) do
    Runtime.stop_workspace_presence(workspace_id)
  end

  def ensure_channel_runtime(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} <- get_member_channel(channel_id, user_id) do
      Runtime.ensure_channel(channel_id)
    else
      nil -> {:error, :not_found}
    end
  end

  def ensure_channel_runtime(_scope, _channel_id), do: {:error, :unauthenticated}

  # Deliberate test seam: the only public window into the runtime hot-message
  # cache, used to assert cache warm-up and reload behavior. Production reads
  # go through the message-window functions below.
  @doc false
  def list_recent_messages(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} <- get_member_channel(channel_id, user_id) do
      Runtime.list_recent_messages(channel_id)
    else
      nil -> {:error, :not_found}
    end
  end

  def list_recent_messages(_scope, _channel_id), do: {:error, :unauthenticated}

  def fetch_message(%Scope{user: %User{id: user_id}}, message_id) do
    case get_member_message(message_id, user_id) do
      %Message{} = message -> {:ok, preload_message_for_display(message)}
      nil -> {:error, :not_found}
    end
  end

  def fetch_message(_scope, _message_id), do: {:error, :unauthenticated}

  @doc """
  Loads the newest bounded message window for a channel visible to the current scope.

  Returns `{:ok, window}` or a normalized authorization/not-found reason.
  """
  @spec load_latest_message_window(term(), Ecto.UUID.t()) :: window_result()
  def load_latest_message_window(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id) do
      latest_seq = channel.last_message_seq
      oldest_requested_seq = max(1, latest_seq - @message_page_size + 1)
      {:ok, MessageWindow.load_for_channel(channel, oldest_requested_seq, latest_seq)}
    else
      nil -> {:error, :not_found}
    end
  end

  def load_latest_message_window(_scope, _channel_id), do: {:error, :unauthenticated}

  @doc """
  Loads a bounded message window centered around a sequence visible to the current scope.

  Invalid sequences and inaccessible channels return normalized error reasons.
  """
  @spec load_message_window_around(term(), Ecto.UUID.t(), term()) :: window_result()
  def load_message_window_around(%Scope{user: %User{id: user_id}}, channel_id, target_seq)
      when is_integer(target_seq) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id) do
      {:ok, MessageWindow.load_around_channel(channel, target_seq)}
    else
      nil -> {:error, :not_found}
    end
  end

  def load_message_window_around(%Scope{user: %User{}}, _channel_id, _target_seq),
    do: {:error, :invalid_sequence}

  def load_message_window_around(_scope, _channel_id, _target_seq),
    do: {:error, :unauthenticated}

  @doc """
  Resolves a live Message inside an accessible Channel and loads a bounded
  sequence-centered window containing it.

  Missing, deleted, cross-Channel, malformed, and inaccessible targets are all
  reported as `:not_found` so callers do not reveal Message existence.
  """
  @spec navigate_to_message(term(), Ecto.UUID.t(), Ecto.UUID.t()) :: window_result()
  def navigate_to_message(%Scope{user: %User{id: user_id}}, channel_id, message_id) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id) do
      Repo.transaction(fn ->
        case get_live_channel_message(channel.id, message_id) do
          %Message{} = target ->
            channel
            |> MessageWindow.load_around_channel(target.seq)
            |> Map.put(:target, preload_message_for_display(target))

          nil ->
            Repo.rollback(:not_found)
        end
      end)
    else
      nil -> {:error, :not_found}
    end
  end

  def navigate_to_message(_scope, _channel_id, _message_id),
    do: {:error, :unauthenticated}

  @doc """
  Loads the message window immediately before `before_seq` for an accessible channel.

  Invalid cursors and inaccessible channels return normalized error reasons.
  """
  @spec load_older_message_window(term(), Ecto.UUID.t(), term()) :: window_result()
  def load_older_message_window(%Scope{user: %User{id: user_id}}, channel_id, before_seq)
      when is_integer(before_seq) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id) do
      to_seq = min(channel.last_message_seq, before_seq - 1)
      from_seq = max(1, to_seq - @message_page_size + 1)
      {:ok, MessageWindow.load_for_channel(channel, from_seq, to_seq)}
    else
      nil -> {:error, :not_found}
    end
  end

  def load_older_message_window(%Scope{user: %User{}}, _channel_id, _before_seq),
    do: {:error, :invalid_sequence}

  def load_older_message_window(_scope, _channel_id, _before_seq),
    do: {:error, :unauthenticated}

  @doc """
  Loads the message window immediately after `after_seq` for an accessible channel.

  Invalid cursors and inaccessible channels return normalized error reasons.
  """
  @spec load_newer_message_window(term(), Ecto.UUID.t(), term()) :: window_result()
  def load_newer_message_window(%Scope{user: %User{id: user_id}}, channel_id, after_seq)
      when is_integer(after_seq) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id) do
      from_seq = max(1, after_seq + 1)
      to_seq = min(channel.last_message_seq, from_seq + @message_page_size - 1)
      {:ok, MessageWindow.load_for_channel(channel, from_seq, to_seq)}
    else
      nil -> {:error, :not_found}
    end
  end

  def load_newer_message_window(%Scope{user: %User{}}, _channel_id, _after_seq),
    do: {:error, :invalid_sequence}

  def load_newer_message_window(_scope, _channel_id, _after_seq),
    do: {:error, :unauthenticated}

  def list_typing_user_ids(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} <- get_member_channel(channel_id, user_id) do
      Runtime.list_typing_user_ids(channel_id)
    else
      nil -> {:error, :not_found}
    end
  end

  def list_typing_user_ids(_scope, _channel_id), do: {:error, :unauthenticated}

  def user_started_typing(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} = channel <- get_member_channel(channel_id, user_id),
         :ok <- Workspaces.member_participation_status(channel.workspace_id, user_id) do
      Runtime.user_started_typing(channel_id, user_id)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def user_started_typing(_scope, _channel_id), do: {:error, :unauthenticated}

  def user_stopped_typing(%Scope{user: %User{id: user_id}}, channel_id) do
    with %Channel{} <- get_member_channel(channel_id, user_id) do
      Runtime.user_stopped_typing(channel_id, user_id)
    else
      nil -> {:error, :not_found}
      {:error, :muted} -> {:error, :muted}
      {:error, :timeout} -> {:error, :timeout}
    end
  end

  def user_stopped_typing(_scope, _channel_id), do: {:error, :unauthenticated}

  # Deliberate test seam: simple `%Message{}`-cursor pagination retained for
  # message-loading tests. Production pagination uses the seq-based message
  # window functions (`load_older_message_window/3` and friends), which return
  # a `%{messages, meta}` window rather than a bare list.
  @doc false
  def list_older_messages(
        %Scope{user: %User{id: user_id}},
        channel_id,
        %Message{seq: cursor_seq}
      ) do
    with %Channel{} <- get_member_channel(channel_id, user_id) do
      messages =
        Message
        |> where([message], message.channel_id == ^channel_id)
        |> where([message], message.seq < ^cursor_seq)
        |> order_by([message], desc: message.seq)
        |> limit(^@recent_message_limit)
        |> preload(^Message.display_preloads())
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
         :ok <- Workspaces.member_participation_status(channel.workspace_id, user_id) do
      changeset =
        Message.changeset(%Message{}, %{
          "content" => Map.get(attrs, "content") || Map.get(attrs, :content),
          "channel_id" => channel_id,
          "user_id" => user_id
        })

      reply_to_message_id =
        Map.get(attrs, "reply_to_message_id") || Map.get(attrs, :reply_to_message_id)

      case insert_sequenced_message(changeset, user_id, channel, reply_to_message_id) do
        {:ok, {message, read_state_changes}} ->
          message = preload_message_for_display(message)
          :ok = Runtime.put_recent_message(message)
          :ok = Runtime.user_stopped_typing(channel_id, user_id)
          :ok = Unread.broadcast_changes(read_state_changes)
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

  defp insert_sequenced_message(
         changeset,
         user_id,
         %Channel{id: channel_id} = channel,
         reply_to_message_id
       ) do
    Repo.transaction(fn ->
      locked_channel = lock_channel_for_update!(channel_id)
      next_seq = locked_channel.last_message_seq + 1

      with {:ok, reply_to_message_id} <-
             validate_reply_target(changeset, channel_id, next_seq, reply_to_message_id),
           {:ok, message} <-
             changeset
             |> Ecto.Changeset.put_change(:seq, next_seq)
             |> Ecto.Changeset.put_change(:reply_to_message_id, reply_to_message_id)
             |> Repo.insert(),
           {:ok, _channel} <-
             locked_channel
             |> Ecto.Changeset.change(last_message_seq: next_seq)
             |> Repo.update() do
        insert_mention_activity!(message, channel, user_id)
        read_state_changes = Unread.fanout_on_send!(channel, user_id, next_seq)
        {message, read_state_changes}
      else
        {:error, %Ecto.Changeset{} = changeset} ->
          Repo.rollback({:invalid_message, changeset})
      end
    end)
  end

  defp insert_mention_activity!(%Message{} = message, %Channel{} = channel, actor_id) do
    usernames = MentionParser.usernames(message.content)
    everyone? = "everyone" in usernames

    activity_rows_query =
      from membership in WorkspaceMembership,
        join: user in assoc(membership, :user),
        join: actor_membership in WorkspaceMembership,
        on:
          actor_membership.workspace_id == membership.workspace_id and
            actor_membership.user_id == ^actor_id,
        where:
          membership.workspace_id == ^channel.workspace_id and user.id != ^actor_id and
            (user.username in ^usernames or
               (^everyone? and actor_membership.role in ^[Roles.owner(), Roles.admin()])),
        lock: "FOR SHARE",
        select: %{
          recipient_user_id: user.id,
          actor_user_id: type(^actor_id, :binary_id),
          source_message_id: type(^message.id, :binary_id),
          source_channel_id: type(^channel.id, :binary_id),
          workspace_id: type(^channel.workspace_id, :binary_id),
          kind:
            fragment(
              "CASE WHEN ? THEN ? ELSE ? END",
              user.username in ^usernames,
              ^ActivityItem.user_mention_kind(),
              ^ActivityItem.everyone_mention_kind()
            ),
          inserted_at: ^message.inserted_at,
          updated_at: ^message.inserted_at
        }

    Repo.insert_all(ActivityItem, activity_rows_query)
  end

  defp validate_reply_target(_changeset, _channel_id, _next_seq, nil), do: {:ok, nil}

  defp validate_reply_target(changeset, channel_id, next_seq, reply_to_message_id) do
    target =
      UUIDIdentifier.cast_or(reply_to_message_id, nil, fn reply_to_message_id ->
        Repo.one(
          from message in Message,
            where:
              message.id == ^reply_to_message_id and message.channel_id == ^channel_id and
                message.seq < ^next_seq and is_nil(message.deleted_at),
            lock: "FOR SHARE",
            select: message.id
        )
      end)

    case target do
      nil ->
        {:error,
         Ecto.Changeset.add_error(
           changeset,
           :reply_to_message_id,
           "is not an earlier message in this channel"
         )}

      target ->
        {:ok, target}
    end
  end

  defp preload_message_for_display(message) do
    Repo.preload(message, Message.display_preloads())
  end

  def toggle_reaction(%Scope{user: %User{id: user_id}}, message_id, emoji) do
    with {:ok, normalized_emoji} <- Emoji.validate_reaction(emoji),
         %Message{} = message <- get_member_message(message_id, user_id),
         :ok <- reject_deleted_message(message),
         :ok <- Workspaces.member_participation_status(message.channel.workspace_id, user_id) do
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
      {:error, :message_deleted} -> {:error, :message_deleted}
      {:error, :muted} -> {:error, :muted}
      {:error, :timeout} -> {:error, :timeout}
      {:error, reason} -> {:error, :invalid_emoji, reason}
    end
  end

  def toggle_reaction(_scope, _message_id, _emoji), do: {:error, :unauthenticated}

  def delete_message(%Scope{user: %User{id: user_id}}, message_id) do
    with %Message{} = message <- get_member_message(message_id, user_id),
         :ok <- authorize_delete_message(message, user_id) do
      delete_message_with_optional_audit(message, user_id)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def delete_message(_scope, _message_id), do: {:error, :unauthenticated}

  @doc """
  Answers whether the scoped user may delete `message`, reading roles from a
  `member_by_user_id` map the caller already holds (no DB round-trip).

  This is the UI-facing twin of the context's delete enforcement: both route
  through the same `Workspaces.can_delete_message?/2` rule, so the affordance the
  channel view shows can never drift from what `delete_message/2` will accept.
  """
  @spec can_delete_message?(term(), struct(), map()) :: boolean()
  def can_delete_message?(
        %Scope{user: %User{id: user_id}},
        %Message{} = message,
        member_by_user_id
      ) do
    actor_role = role_of(member_by_user_id, user_id)
    author_role = role_of(member_by_user_id, message.user_id)

    message.user_id == user_id or Workspaces.can_delete_message?(actor_role, author_role)
  end

  def can_delete_message?(_scope, _message, _member_by_user_id), do: false

  defp role_of(member_by_user_id, user_id) do
    case Map.get(member_by_user_id, user_id) do
      %{role: role} -> role
      _no_membership -> nil
    end
  end

  def list_reaction_summaries(%Scope{user: %User{}}, []), do: {:ok, %{}}

  def list_reaction_summaries(%Scope{user: %User{id: user_id}}, message_ids)
      when is_list(message_ids) do
    message_ids = Enum.uniq(message_ids)

    with :ok <- authorize_member_messages(message_ids, user_id) do
      summaries =
        MessageReaction
        |> where([reaction], reaction.message_id in type(^message_ids, {:array, :binary_id}))
        |> group_by([reaction], [reaction.message_id, reaction.emoji])
        |> order_by([reaction], asc: reaction.message_id, asc: reaction.emoji)
        |> select([reaction], %{
          message_id: reaction.message_id,
          emoji: reaction.emoji,
          count: count(reaction.id),
          reacted?: fragment("bool_or(? = ?)", reaction.user_id, type(^user_id, :binary_id))
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
    UUIDIdentifier.cast_or(channel_id, nil, fn channel_id ->
      Repo.one(
        from channel in Channel,
          join: membership in WorkspaceMembership,
          on:
            membership.workspace_id == channel.workspace_id and
              membership.user_id == ^user_id,
          where: channel.id == ^channel_id,
          limit: 1
      )
    end)
  end

  defp get_member_message(message_id, user_id) do
    UUIDIdentifier.cast_or(message_id, nil, fn message_id ->
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
    end)
  end

  defp get_live_channel_message(channel_id, message_id) do
    UUIDIdentifier.cast_or(message_id, nil, fn message_id ->
      Repo.one(
        from message in Message,
          where:
            message.id == ^message_id and message.channel_id == ^channel_id and
              is_nil(message.deleted_at),
          lock: "FOR SHARE",
          limit: 1
      )
    end)
  end

  defp authorize_member_messages(message_ids, user_id) do
    UUIDIdentifier.cast_or(message_ids, {:error, :not_found}, fn message_ids ->
      accessible_message_count =
        Repo.one(
          from message in Message,
            join: channel in Channel,
            on: channel.id == message.channel_id,
            join: membership in WorkspaceMembership,
            on:
              membership.workspace_id == channel.workspace_id and
                membership.user_id == ^user_id,
            where: message.id in type(^message_ids, {:array, :binary_id}),
            select: count(message.id)
        )

      if accessible_message_count == length(message_ids), do: :ok, else: {:error, :not_found}
    end)
  end

  defp authorize_delete_message(%Message{user_id: user_id}, user_id), do: :ok

  defp authorize_delete_message(%Message{} = message, user_id) do
    {actor, author} = actor_target_roles(message.channel.workspace_id, user_id, message.user_id)

    if Workspaces.can_delete_message?(role_of_membership(actor), role_of_membership(author)) do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  defp role_of_membership(%{role: role}), do: role
  defp role_of_membership(_no_membership), do: nil

  defp delete_message_with_optional_audit(%Message{} = message, user_id) do
    deleted_at = DateTime.utc_now(:second)

    multi =
      Multi.new()
      |> Multi.delete_all(
        :reactions,
        from(reaction in MessageReaction, where: reaction.message_id == ^message.id)
      )
      |> Multi.update(
        :message,
        Message.soft_delete_changeset(message, %{
          deleted_at: deleted_at,
          deleted_by_user_id: user_id
        })
      )
      |> maybe_insert_message_delete_audit(message, user_id)

    case Repo.transaction(multi) do
      {:ok, %{message: message}} ->
        message = Repo.preload(message, :user)
        :ok = Runtime.put_recent_message(message)
        :ok = broadcast_message_deleted(message)
        {:ok, message}

      {:error, :message, changeset, _changes_so_far} ->
        {:error, :invalid_message, changeset}

      {:error, :audit_event, changeset, _changes_so_far} ->
        {:error, :invalid_audit_event, changeset}
    end
  end

  defp maybe_insert_message_delete_audit(%Multi{} = multi, %Message{user_id: user_id}, user_id),
    do: multi

  defp maybe_insert_message_delete_audit(%Multi{} = multi, %Message{} = message, actor_user_id) do
    Multi.insert(multi, :audit_event, fn %{message: deleted_message} ->
      WorkspaceAuditEvent.changeset(%WorkspaceAuditEvent{}, %{
        workspace_id: message.channel.workspace_id,
        actor_user_id: actor_user_id,
        target_user_id: message.user_id,
        event_type: "moderator_message_deleted",
        metadata: %{
          "message_id" => deleted_message.id,
          "channel_id" => deleted_message.channel_id,
          "channel_name" => message.channel.name
        }
      })
    end)
  end

  defp actor_target_roles(workspace_id, actor_user_id, target_user_id) do
    memberships =
      Repo.all(
        from membership in WorkspaceMembership,
          where:
            membership.workspace_id == ^workspace_id and
              membership.user_id in ^[actor_user_id, target_user_id],
          select: {membership.user_id, membership}
      )
      |> Map.new()

    {Map.get(memberships, actor_user_id), Map.get(memberships, target_user_id)}
  end

  defp reject_deleted_message(%Message{deleted_at: %DateTime{}}), do: {:error, :message_deleted}
  defp reject_deleted_message(%Message{}), do: :ok

  defp authorize_workspace_member(workspace_id, user_id) do
    UUIDIdentifier.cast_or(workspace_id, {:error, :not_found}, fn workspace_id ->
      if Repo.exists?(
           from membership in WorkspaceMembership,
             where: membership.workspace_id == ^workspace_id and membership.user_id == ^user_id
         ) do
        :ok
      else
        {:error, :not_found}
      end
    end)
  end

  defp lock_channel_for_update!(channel_id) do
    Repo.one!(
      from channel in Channel,
        where: channel.id == ^channel_id,
        lock: "FOR UPDATE"
    )
  end

  defp validate_channel_anchor(%Channel{} = channel, anchor_seq) when is_integer(anchor_seq) do
    if anchor_seq >= 1 and anchor_seq <= channel.last_message_seq do
      :ok
    else
      {:error, :invalid_sequence}
    end
  end

  defp broadcast_message_created(%Message{} = message) do
    Phoenix.PubSub.broadcast_from(
      DiscordClone.PubSub,
      self(),
      channel_messages_topic(message.channel_id),
      {:message_created, message}
    )
  end

  defp broadcast_message_deleted(%Message{} = message) do
    Phoenix.PubSub.broadcast_from(
      DiscordClone.PubSub,
      self(),
      channel_messages_topic(message.channel_id),
      {:message_deleted, %{channel_id: message.channel_id, message_id: message.id}}
    )
  end

  defp channel_messages_topic(channel_id), do: "chat:channel:#{channel_id}"
  defp channel_reactions_topic(channel_id), do: "chat:channel:#{channel_id}:reactions"
  defp workspace_messages_topic(workspace_id), do: "chat:workspace:#{workspace_id}:messages"

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
