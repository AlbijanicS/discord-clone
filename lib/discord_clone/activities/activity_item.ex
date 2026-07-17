defmodule DiscordClone.Activities.ActivityItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  @user_mention_kind "user_mention"
  @everyone_mention_kind "everyone_mention"
  @friend_request_received_kind "friend_request_received"
  @friend_request_accepted_kind "friend_request_accepted"

  schema "activity_items" do
    field :kind, :string
    field :read_at, :utc_datetime_usec

    belongs_to :recipient_user, DiscordClone.Accounts.User
    belongs_to :actor_user, DiscordClone.Accounts.User
    belongs_to :source_message, DiscordClone.Chat.Message
    belongs_to :source_friend_relationship, DiscordClone.Friendships.Relationship

    belongs_to :source_channel, DiscordClone.Workspaces.Channel,
      foreign_key: :source_channel_id,
      source: :source_conversation_id

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
    |> foreign_key_constraint(:source_channel_id,
      name: :activity_items_source_conversation_id_fkey
    )
    |> foreign_key_constraint(:workspace_id)
    |> unique_constraint([:recipient_user_id, :source_message_id])
    |> check_constraint(:kind, name: :activity_items_source_integrity)
  end

  def create_friend_relationship_changeset(activity_item, attrs, kind)
      when kind in [@friend_request_received_kind, @friend_request_accepted_kind] do
    activity_item
    |> change(attrs)
    |> change(kind: kind)
    |> validate_required([
      :recipient_user_id,
      :actor_user_id,
      :source_friend_relationship_id,
      :kind
    ])
    |> foreign_key_constraint(:recipient_user_id)
    |> foreign_key_constraint(:actor_user_id)
    |> foreign_key_constraint(:source_friend_relationship_id)
    |> unique_constraint([:recipient_user_id, :source_friend_relationship_id, :kind],
      name: :activity_items_recipient_friend_relationship_kind_index
    )
    |> check_constraint(:kind, name: :activity_items_source_integrity)
  end

  def user_mention_kind, do: @user_mention_kind
  def everyone_mention_kind, do: @everyone_mention_kind
  def friend_request_received_kind, do: @friend_request_received_kind
  def friend_request_accepted_kind, do: @friend_request_accepted_kind
end
