defmodule DiscordClone.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :content, :string

    belongs_to :channel, DiscordClone.Workspaces.Channel
    belongs_to :user, DiscordClone.Accounts.User

    has_many :message_reactions, DiscordClone.Chat.MessageReaction

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:channel_id, :user_id, :content])
    |> update_change(:content, &normalize_content/1)
    |> validate_required([:channel_id, :user_id, :content])
    |> validate_length(:content, min: 1, max: 4_000)
    |> foreign_key_constraint(:channel_id)
    |> foreign_key_constraint(:user_id)
  end

  defp normalize_content(content) when is_binary(content), do: String.trim(content)
  defp normalize_content(content), do: content
end
