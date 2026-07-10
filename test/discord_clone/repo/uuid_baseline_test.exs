defmodule DiscordClone.Repo.UUIDBaselineTest do
  use DiscordClone.DataCase, async: false

  alias DiscordClone.Workspaces

  import DiscordClone.AccountsFixtures

  @tables ~w(
    users
    users_tokens
    workspaces
    channels
    workspace_memberships
    workspace_invites
    workspace_moderations
    workspace_bans
    workspace_audit_events
    messages
    message_reactions
    channel_reads
    channel_read_states
    channel_unread_spans
  )

  test "every persisted entity has a database-generated UUID primary key" do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        SELECT table_name, data_type, column_default
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND column_name = 'id'
          AND table_name = ANY($1)
        ORDER BY table_name
        """,
        [@tables]
      )

    assert rows ==
             @tables
             |> Enum.sort()
             |> Enum.map(&[&1, "uuid", "gen_random_uuid()"])
  end

  test "every foreign key is UUID-native and preserves its delete action" do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        SELECT con.conname,
               CASE con.confdeltype
                 WHEN 'c' THEN 'delete_all'
                 WHEN 'n' THEN 'nilify_all'
                 WHEN 'r' THEN 'restrict'
                 ELSE con.confdeltype::text
               END,
               pg_catalog.format_type(source_attribute.atttypid, source_attribute.atttypmod),
               pg_catalog.format_type(target_attribute.atttypid, target_attribute.atttypmod)
        FROM pg_constraint con
        JOIN pg_attribute source_attribute
          ON source_attribute.attrelid = con.conrelid
         AND source_attribute.attnum = con.conkey[1]
        JOIN pg_attribute target_attribute
          ON target_attribute.attrelid = con.confrelid
         AND target_attribute.attnum = con.confkey[1]
        WHERE con.contype = 'f'
        ORDER BY con.conname
        """,
        []
      )

    assert Enum.all?(rows, fn [_name, _delete_action, source_type, target_type] ->
             source_type == "uuid" and target_type == "uuid"
           end)

    delete_actions =
      Map.new(rows, fn [name, action, _source_type, _target_type] -> {name, action} end)

    assert delete_actions == expected_foreign_key_delete_actions()
  end

  test "the baseline preserves required unique, check, and exclusion constraints" do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        SELECT conname, contype::text
        FROM pg_constraint
        WHERE connamespace = 'public'::regnamespace
          AND contype IN ('u', 'c', 'x')
        ORDER BY conname
        """,
        []
      )

    constraints = Map.new(rows, fn [name, type] -> {name, type} end)

    for name <- ~w(
          channels_last_message_seq_non_negative
          messages_seq_positive
          channel_read_states_unread_count_non_negative
          channel_read_states_unread_summary_consistent
          channel_read_states_last_viewed_anchor_seq_positive
          channel_unread_spans_positive_bounds
          channel_unread_spans_ordered_bounds
        ) do
      assert constraints[name] == "c"
    end

    assert constraints["channel_unread_spans_no_overlap"] == "x"

    %{rows: unique_indexes} =
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'public'
          AND indexdef LIKE 'CREATE UNIQUE INDEX%'
        ORDER BY indexname
        """,
        []
      )

    unique_indexes = MapSet.new(unique_indexes, fn [name] -> name end)

    for name <- ~w(
          users_email_index
          users_username_index
          users_tokens_context_token_index
          channels_workspace_id_name_index
          workspace_memberships_workspace_id_user_id_index
          workspace_invites_code_index
          workspace_moderations_workspace_id_target_user_id_type_index
          workspace_bans_workspace_id_target_user_id_index
          messages_channel_id_seq_index
          message_reactions_message_id_user_id_emoji_index
          channel_reads_channel_id_user_id_index
          channel_read_states_channel_id_user_id_index
        ) do
      assert MapSet.member?(unique_indexes, name)
    end
  end

  test "raw inserts receive UUID defaults and unread summary checks are enforced" do
    %{rows: [[id]]} =
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        INSERT INTO users (email, username, inserted_at, updated_at)
        VALUES ('raw-default@example.com', 'raw_default', now(), now())
        RETURNING id::text
        """,
        []
      )

    assert {:ok, ^id} = Ecto.UUID.cast(id)

    scope = user_scope_fixture()
    other_user = user_fixture()
    {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Baseline checks"})

    assert_raise Postgrex.Error, ~r/channel_read_states_unread_summary_consistent/, fn ->
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        INSERT INTO channel_read_states (
          channel_id, user_id, unread_count, inserted_at, updated_at
        )
        VALUES ($1, $2, 1, now(), now())
        """,
        [Ecto.UUID.dump!(workspace.default_channel_id), Ecto.UUID.dump!(other_user.id)]
      )
    end
  end

  test "the unread-span exclusion constraint rejects overlaps" do
    scope = user_scope_fixture()
    other_user = user_fixture()
    {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Exclusion checks"})

    Ecto.Adapters.SQL.query!(
      Repo,
      """
      INSERT INTO channel_unread_spans (
        channel_id, user_id, from_seq, to_seq, inserted_at, updated_at
      )
      VALUES ($1, $2, 3, 5, now(), now())
      """,
      [Ecto.UUID.dump!(workspace.default_channel_id), Ecto.UUID.dump!(other_user.id)]
    )

    assert_raise Postgrex.Error, ~r/channel_unread_spans_no_overlap/, fn ->
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        INSERT INTO channel_unread_spans (
          channel_id, user_id, from_seq, to_seq, inserted_at, updated_at
        )
        VALUES ($1, $2, 5, 8, now(), now())
        """,
        [Ecto.UUID.dump!(workspace.default_channel_id), Ecto.UUID.dump!(other_user.id)]
      )
    end
  end

  defp expected_foreign_key_delete_actions do
    %{
      "channel_read_states_channel_id_fkey" => "delete_all",
      "channel_read_states_user_id_fkey" => "delete_all",
      "channel_reads_channel_id_fkey" => "delete_all",
      "channel_reads_last_read_message_id_fkey" => "nilify_all",
      "channel_reads_user_id_fkey" => "delete_all",
      "channel_unread_spans_channel_id_fkey" => "delete_all",
      "channel_unread_spans_user_id_fkey" => "delete_all",
      "channels_workspace_id_fkey" => "delete_all",
      "message_reactions_message_id_fkey" => "delete_all",
      "message_reactions_user_id_fkey" => "delete_all",
      "messages_channel_id_fkey" => "delete_all",
      "messages_deleted_by_user_id_fkey" => "nilify_all",
      "messages_user_id_fkey" => "nilify_all",
      "users_tokens_user_id_fkey" => "delete_all",
      "workspace_audit_events_actor_user_id_fkey" => "nilify_all",
      "workspace_audit_events_target_user_id_fkey" => "nilify_all",
      "workspace_audit_events_workspace_id_fkey" => "delete_all",
      "workspace_bans_banned_by_user_id_fkey" => "nilify_all",
      "workspace_bans_target_user_id_fkey" => "delete_all",
      "workspace_bans_workspace_id_fkey" => "delete_all",
      "workspace_invites_created_by_user_id_fkey" => "nilify_all",
      "workspace_invites_workspace_id_fkey" => "delete_all",
      "workspace_memberships_user_id_fkey" => "delete_all",
      "workspace_memberships_workspace_id_fkey" => "delete_all",
      "workspace_moderations_created_by_user_id_fkey" => "nilify_all",
      "workspace_moderations_ended_by_user_id_fkey" => "nilify_all",
      "workspace_moderations_target_user_id_fkey" => "delete_all",
      "workspace_moderations_workspace_id_fkey" => "delete_all",
      "workspaces_default_channel_id_fkey" => "nilify_all",
      "workspaces_owner_id_fkey" => "restrict"
    }
  end
end
