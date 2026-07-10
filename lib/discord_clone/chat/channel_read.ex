defmodule DiscordClone.Chat.ChannelRead do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "channel_reads" do
    belongs_to :channel, DiscordClone.Workspaces.Channel
    belongs_to :user, DiscordClone.Accounts.User
    belongs_to :last_read_message, DiscordClone.Chat.Message

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(channel_read, attrs) do
    channel_read
    |> cast(attrs, [:channel_id, :user_id, :last_read_message_id])
    |> validate_required([:channel_id, :user_id])
    |> foreign_key_constraint(:channel_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:last_read_message_id)
    |> unique_constraint([:channel_id, :user_id])
  end
end
