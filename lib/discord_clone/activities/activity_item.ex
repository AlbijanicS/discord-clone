defmodule DiscordClone.Activities.ActivityItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  @user_mention_kind "user_mention"

  schema "activity_items" do
    field :kind, :string
    field :read_at, :utc_datetime_usec

    belongs_to :recipient_user, DiscordClone.Accounts.User
    belongs_to :actor_user, DiscordClone.Accounts.User
    belongs_to :source_message, DiscordClone.Chat.Message
    belongs_to :source_channel, DiscordClone.Workspaces.Channel
    belongs_to :workspace, DiscordClone.Workspaces.Workspace

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(activity_item, kind) do
    activity_item
    |> change(kind: kind)
    |> validate_required([
      :recipient_user_id,
      :source_message_id,
      :source_channel_id,
      :kind
    ])
    |> foreign_key_constraint(:recipient_user_id)
    |> foreign_key_constraint(:actor_user_id)
    |> foreign_key_constraint(:source_message_id)
    |> foreign_key_constraint(:source_channel_id)
    |> foreign_key_constraint(:workspace_id)
    |> unique_constraint([:recipient_user_id, :source_message_id])
  end

  def user_mention_kind, do: @user_mention_kind
end
