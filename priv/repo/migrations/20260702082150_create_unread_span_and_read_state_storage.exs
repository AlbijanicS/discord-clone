defmodule DiscordClone.Repo.Migrations.CreateUnreadSpanAndReadStateStorage do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS btree_gist", "SELECT 1"

    create table(:channel_unread_spans) do
      add :channel_id, references(:channels, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :from_seq, :bigint, null: false
      add :to_seq, :bigint, null: false

      timestamps(type: :utc_datetime)
    end

    create constraint(:channel_unread_spans, :channel_unread_spans_positive_bounds,
             check: "from_seq > 0 AND to_seq > 0"
           )

    create constraint(:channel_unread_spans, :channel_unread_spans_ordered_bounds,
             check: "from_seq <= to_seq"
           )

    create index(:channel_unread_spans, [:user_id, :channel_id])
    create index(:channel_unread_spans, [:channel_id])

    execute(
      """
      ALTER TABLE channel_unread_spans
      ADD CONSTRAINT channel_unread_spans_no_overlap
      EXCLUDE USING gist (
        user_id WITH =,
        channel_id WITH =,
        int8range(from_seq, to_seq, '[]') WITH &&
      )
      """,
      "ALTER TABLE channel_unread_spans DROP CONSTRAINT channel_unread_spans_no_overlap"
    )

    create table(:channel_read_states) do
      add :channel_id, references(:channels, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :unread_count, :bigint, null: false, default: 0
      add :first_unread_seq, :bigint
      add :last_unread_seq, :bigint
      add :last_viewed_anchor_seq, :bigint
      add :last_opened_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:channel_read_states, [:channel_id, :user_id])
    create index(:channel_read_states, [:user_id, :channel_id])
    create index(:channel_read_states, [:channel_id])

    create constraint(:channel_read_states, :channel_read_states_unread_count_non_negative,
             check: "unread_count >= 0"
           )

    create constraint(:channel_read_states, :channel_read_states_unread_summary_consistent,
             check: """
             (
               unread_count = 0
               AND first_unread_seq IS NULL
               AND last_unread_seq IS NULL
             )
             OR
             (
               unread_count > 0
               AND first_unread_seq IS NOT NULL
               AND last_unread_seq IS NOT NULL
               AND first_unread_seq > 0
               AND last_unread_seq > 0
               AND first_unread_seq <= last_unread_seq
             )
             """
           )

    create constraint(:channel_read_states, :channel_read_states_last_viewed_anchor_seq_positive,
             check: "last_viewed_anchor_seq IS NULL OR last_viewed_anchor_seq > 0"
           )
  end
end
