defmodule DiscordClone.Workspaces.WorkspaceMembership do
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(owner admin member)

  schema "workspace_memberships" do
    field :role, :string, default: "member"

    belongs_to :workspace, DiscordClone.Workspaces.Workspace
    belongs_to :user, DiscordClone.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:workspace_id, :user_id, :role])
    |> validate_required([:workspace_id, :user_id, :role])
    |> validate_inclusion(:role, @roles)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:workspace_id, :user_id])
  end

  def roles, do: @roles
end
