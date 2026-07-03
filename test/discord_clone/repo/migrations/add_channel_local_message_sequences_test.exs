Code.require_file(
  Path.expand(
    "../../../../priv/repo/migrations/20260702075141_add_channel_local_message_sequences.exs",
    __DIR__
  )
)

defmodule DiscordClone.Repo.Migrations.AddChannelLocalMessageSequencesTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias DiscordClone.Chat.Message
  alias DiscordClone.Repo
  alias DiscordClone.Repo.Migrations.AddChannelLocalMessageSequences
  alias DiscordClone.Workspaces
  alias DiscordClone.Workspaces.Channel

  import DiscordClone.AccountsFixtures

  @migration_version 20_260_702_075_141

  test "backfills channel-local message sequences and channel summaries" do
    try do
      ids =
        unboxed(fn ->
          truncate_domain_tables()

          scope = user_scope_fixture()
          {:ok, workspace} = Workspaces.create_workspace(scope, %{name: "Foundry"})

          {:ok, release_channel} =
            Workspaces.create_channel(scope, workspace.id, %{name: "release"})

          {:ok, empty_channel} = Workspaces.create_channel(scope, workspace.id, %{name: "empty"})

          general_message =
            insert_message!(
              workspace.default_channel_id,
              scope.user.id,
              "general first",
              ~U[2026-06-19 09:59:00Z]
            )

          first_release_message =
            insert_message!(
              release_channel.id,
              scope.user.id,
              "release same-time first",
              ~U[2026-06-19 10:00:00Z]
            )

          second_release_message =
            insert_message!(
              release_channel.id,
              scope.user.id,
              "release same-time second",
              ~U[2026-06-19 10:00:00Z]
            )

          later_release_message =
            insert_message!(
              release_channel.id,
              scope.user.id,
              "release later",
              ~U[2026-06-19 10:01:00Z]
            )

          %{
            general_channel_id: workspace.default_channel_id,
            release_channel_id: release_channel.id,
            empty_channel_id: empty_channel.id,
            general_message_id: general_message.id,
            first_release_message_id: first_release_message.id,
            second_release_message_id: second_release_message.id,
            later_release_message_id: later_release_message.id
          }
        end)

      run_migrations(fn ->
        migrate_down()
        migrate_up()
      end)

      unboxed(fn ->
        assert messages_for_channel(ids.general_channel_id) == [{ids.general_message_id, 1}]

        assert messages_for_channel(ids.release_channel_id) == [
                 {ids.first_release_message_id, 1},
                 {ids.second_release_message_id, 2},
                 {ids.later_release_message_id, 3}
               ]

        assert Repo.get!(Channel, ids.general_channel_id).last_message_seq == 1
        assert Repo.get!(Channel, ids.release_channel_id).last_message_seq == 3
        assert Repo.get!(Channel, ids.empty_channel_id).last_message_seq == 0
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
      AddChannelLocalMessageSequences,
      log: false
    )
  end

  defp migrate_up do
    Ecto.Migrator.up(
      Repo,
      @migration_version,
      AddChannelLocalMessageSequences,
      log: false
    )
  end

  defp ensure_migrated_up do
    unless column_exists?("messages", "seq") do
      migrate_up()
    end
  end

  defp column_exists?(table_name, column_name) do
    %{rows: [[count]]} =
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        SELECT count(*)
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = $1
          AND column_name = $2
        """,
        [table_name, column_name]
      )

    count == 1
  end

  defp truncate_domain_tables do
    Ecto.Adapters.SQL.query!(
      Repo,
      """
      TRUNCATE
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

  defp insert_message!(channel_id, user_id, content, inserted_at) do
    {:ok, message} =
      Repo.transaction(fn ->
        channel =
          Repo.one!(
            from channel in Channel,
              where: channel.id == ^channel_id,
              lock: "FOR UPDATE"
          )

        seq = channel.last_message_seq + 1

        message =
          Repo.insert!(%Message{
            channel_id: channel_id,
            user_id: user_id,
            content: content,
            seq: seq,
            inserted_at: inserted_at,
            updated_at: inserted_at
          })

        channel
        |> Ecto.Changeset.change(last_message_seq: seq)
        |> Repo.update!()

        message
      end)

    message
  end

  defp messages_for_channel(channel_id) do
    Message
    |> where([message], message.channel_id == ^channel_id)
    |> order_by([message], asc: message.seq)
    |> select([message], {message.id, message.seq})
    |> Repo.all()
  end
end
