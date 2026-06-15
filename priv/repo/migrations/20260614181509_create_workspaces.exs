defmodule DiscordClone.Repo.Migrations.CreateWorkspaces do
  use Ecto.Migration

  def change do
    create table(:workspaces) do
      add :name, :string, null: false
      add :owner_id, references(:users, on_delete: :restrict), null: false
      add :invite_policy, :string, null: false, default: "owner_only"

      timestamps(type: :utc_datetime)
    end

    create index(:workspaces, [:owner_id])
  end
end
