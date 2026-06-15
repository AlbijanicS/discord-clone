defmodule DiscordClone.Repo.Migrations.CreateWorkspaceInvites do
  use Ecto.Migration

  def change do
    create table(:workspace_invites) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :created_by_user_id, references(:users, on_delete: :nilify_all)
      add :code, :string, null: false
      add :expires_at, :utc_datetime
      add :max_uses, :integer
      add :uses_count, :integer, null: false, default: 0
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:workspace_invites, [:workspace_id])
    create index(:workspace_invites, [:created_by_user_id])
    create unique_index(:workspace_invites, [:code])
  end
end
