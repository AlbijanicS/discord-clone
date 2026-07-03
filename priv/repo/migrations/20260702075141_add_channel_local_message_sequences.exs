defmodule DiscordClone.Repo.Migrations.AddChannelLocalMessageSequences do
  use Ecto.Migration

  def up do
    alter table(:messages) do
      add :seq, :bigint
    end

    alter table(:channels) do
      add :last_message_seq, :bigint, null: false, default: 0
    end

    execute """
    WITH sequenced_messages AS (
      SELECT
        id,
        row_number() OVER (
          PARTITION BY channel_id
          ORDER BY inserted_at ASC, id ASC
        ) AS seq
      FROM messages
    )
    UPDATE messages
    SET seq = sequenced_messages.seq
    FROM sequenced_messages
    WHERE messages.id = sequenced_messages.id
    """

    execute """
    UPDATE channels
    SET last_message_seq = COALESCE(channel_sequences.last_message_seq, 0)
    FROM (
      SELECT channel_id, max(seq) AS last_message_seq
      FROM messages
      GROUP BY channel_id
    ) AS channel_sequences
    WHERE channels.id = channel_sequences.channel_id
    """

    alter table(:messages) do
      modify :seq, :bigint, null: false
    end

    create constraint(:messages, :messages_seq_positive, check: "seq > 0")

    create constraint(:channels, :channels_last_message_seq_non_negative,
             check: "last_message_seq >= 0"
           )

    create unique_index(:messages, [:channel_id, :seq], name: :messages_channel_id_seq_index)
  end

  def down do
    drop index(:messages, [:channel_id, :seq], name: :messages_channel_id_seq_index)

    drop constraint(:channels, :channels_last_message_seq_non_negative)
    drop constraint(:messages, :messages_seq_positive)

    alter table(:channels) do
      remove :last_message_seq
    end

    alter table(:messages) do
      remove :seq
    end
  end
end
