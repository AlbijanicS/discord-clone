defmodule DiscordClone.Repo.Migrations.CreateChannelReads do
  use Ecto.Migration

  def up do
    create table(:channel_reads) do
      add :channel_id, references(:channels, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :last_read_message_id, references(:messages, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:channel_reads, [:channel_id, :user_id])
    create index(:channel_reads, [:user_id])

    execute """
    INSERT INTO channel_reads (
      channel_id,
      user_id,
      last_read_message_id,
      inserted_at,
      updated_at
    )
    SELECT
      channels.id,
      workspace_memberships.user_id,
      latest_messages.last_read_message_id,
      date_trunc('second', now() AT TIME ZONE 'UTC'),
      date_trunc('second', now() AT TIME ZONE 'UTC')
    FROM channels
    INNER JOIN workspace_memberships
      ON workspace_memberships.workspace_id = channels.workspace_id
    LEFT JOIN (
      SELECT channel_id, max(id) AS last_read_message_id
      FROM messages
      GROUP BY channel_id
    ) AS latest_messages
      ON latest_messages.channel_id = channels.id
    """
  end

  def down do
    drop table(:channel_reads)
  end
end
