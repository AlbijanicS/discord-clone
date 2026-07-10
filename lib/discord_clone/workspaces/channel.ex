defmodule DiscordClone.Workspaces.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "channels" do
    field :name, :string
    field :last_message_seq, :integer, default: 0

    belongs_to :workspace, DiscordClone.Workspaces.Workspace

    has_many :messages, DiscordClone.Chat.Message
    has_many :channel_reads, DiscordClone.Chat.ChannelRead
    has_many :channel_read_states, DiscordClone.Chat.ChannelReadState
    has_many :channel_unread_spans, DiscordClone.Chat.ChannelUnreadSpan

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(channel, attrs) do
    create_changeset(channel, attrs)
  end

  def create_changeset(channel, attrs) do
    channel
    |> cast(attrs, [:workspace_id, :name])
    |> update_change(:name, &normalize_name/1)
    |> validate_required([:workspace_id, :name])
    |> validate_length(:name, min: 1, max: 80)
    |> validate_format(:name, ~r/^[a-z0-9][a-z0-9_-]*$/,
      message:
        "must start with a letter or number and use lowercase letters, numbers, dashes, or underscores"
    )
    |> foreign_key_constraint(:workspace_id)
    |> unique_constraint(:name, name: :channels_workspace_id_name_index)
  end

  def rename_changeset(channel, attrs) do
    channel
    |> cast(attrs, [:name])
    |> update_change(:name, &normalize_name/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 80)
    |> validate_format(:name, ~r/^[a-z0-9][a-z0-9_-]*$/,
      message:
        "must start with a letter or number and use lowercase letters, numbers, dashes, or underscores"
    )
    |> unique_constraint(:name, name: :channels_workspace_id_name_index)
  end

  defp normalize_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/\s+/, "-")
  end

  defp normalize_name(name), do: name
end
