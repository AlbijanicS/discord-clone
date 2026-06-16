defmodule DiscordClone.Workspaces.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  schema "channels" do
    field :name, :string

    belongs_to :workspace, DiscordClone.Workspaces.Workspace

    has_many :messages, DiscordClone.Chat.Message

    timestamps(type: :utc_datetime)
  end

  def changeset(channel, attrs) do
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

  defp normalize_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/\s+/, "-")
  end

  defp normalize_name(name), do: name
end
