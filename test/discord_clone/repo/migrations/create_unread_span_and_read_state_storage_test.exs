Code.require_file(
  Path.expand(
    "../../../../priv/repo/migrations/20260702082150_create_unread_span_and_read_state_storage.exs",
    __DIR__
  )
)

defmodule DiscordClone.Repo.Migrations.CreateUnreadSpanAndReadStateStorageTest do
  use ExUnit.Case, async: false

  alias DiscordClone.Repo
  alias DiscordClone.Repo.Migrations.CreateUnreadSpanAndReadStateStorage
  alias DiscordClone.Workspaces

  import DiscordClone.AccountsFixtures

  @migration_version 20_260_702_082_150

  test "creates unread range storage with database constraints" do
    try do
      run_migrations(fn ->
        migrate_down()

        refute table_exists?("channel_unread_spans")
        refute table_exists?("channel_read_states")

        migrate_up()
      end)

      unboxed(fn ->
        truncate_domain_tables()

        scope = user_scope_fixture()
        {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

        {:ok, release_channel} =
          Workspaces.create_channel(scope, workspace.id, %{name: "release"})

        storage_user = user_fixture()

        insert_read_state!(workspace.default_channel_id, storage_user.id, 0, nil, nil)

        assert_raise Postgrex.Error, ~r/channel_read_states_unread_summary_consistent/, fn ->
          insert_read_state!(release_channel.id, storage_user.id, 1, nil, nil)
        end

        insert_unread_span!(workspace.default_channel_id, storage_user.id, 3, 5)

        assert_raise Postgrex.Error, ~r/channel_unread_spans_positive_bounds/, fn ->
          insert_unread_span!(workspace.default_channel_id, storage_user.id, 0, 2)
        end

        assert_raise Postgrex.Error, ~r/channel_unread_spans_no_overlap/, fn ->
          insert_unread_span!(workspace.default_channel_id, storage_user.id, 5, 6)
        end
      end)
    after
      run_migrations(fn ->
        ensure_migrated_up()
      end)

      unboxed(fn ->
        truncate_domain_tables()
      end)
    end
  end

  defp unboxed(fun) do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fun)
  end

  defp run_migrations(fun) do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)

    try do
      fun.()
    after
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
    end
  end

  defp migrate_down do
    Ecto.Migrator.down(
      Repo,
      @migration_version,
      CreateUnreadSpanAndReadStateStorage,
      log: false
    )
  end

  defp migrate_up do
    Ecto.Migrator.up(
      Repo,
      @migration_version,
      CreateUnreadSpanAndReadStateStorage,
      log: false
    )
  end

  defp ensure_migrated_up do
    unless table_exists?("channel_unread_spans") do
      migrate_up()
    end
  end

  defp table_exists?(table_name) do
    %{rows: [[exists?]]} =
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        SELECT EXISTS (
          SELECT 1
          FROM information_schema.tables
          WHERE table_schema = 'public'
            AND table_name = $1
        )
        """,
        [table_name]
      )

    exists?
  end

  defp truncate_domain_tables do
    Ecto.Adapters.SQL.query!(
      Repo,
      """
      TRUNCATE
        channel_read_states,
        channel_unread_spans,
        message_reactions,
        channel_reads,
        messages,
        workspace_invites,
        workspace_memberships,
        channels,
        workspaces,
        users_tokens,
        users
      CASCADE
      """,
      []
    )
  end

  defp insert_read_state!(channel_id, user_id, unread_count, first_unread_seq, last_unread_seq) do
    Ecto.Adapters.SQL.query!(
      Repo,
      """
      INSERT INTO channel_read_states (
        channel_id,
        user_id,
        unread_count,
        first_unread_seq,
        last_unread_seq,
        inserted_at,
        updated_at
      )
      VALUES ($1, $2, $3, $4, $5, now(), now())
      """,
      [channel_id, user_id, unread_count, first_unread_seq, last_unread_seq]
    )
  end

  defp insert_unread_span!(channel_id, user_id, from_seq, to_seq) do
    Ecto.Adapters.SQL.query!(
      Repo,
      """
      INSERT INTO channel_unread_spans (
        channel_id,
        user_id,
        from_seq,
        to_seq,
        inserted_at,
        updated_at
      )
      VALUES ($1, $2, $3, $4, now(), now())
      """,
      [channel_id, user_id, from_seq, to_seq]
    )
  end
end
