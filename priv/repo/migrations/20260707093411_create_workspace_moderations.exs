defmodule DiscordClone.Repo.Migrations.CreateWorkspaceModerations do
  use Ecto.Migration

  def change do
    create table(:workspace_moderations) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :target_user_id, references(:users, on_delete: :delete_all), null: false
      add :created_by_user_id, references(:users, on_delete: :nilify_all)
      add :ended_by_user_id, references(:users, on_delete: :nilify_all)
      add :type, :string, null: false
      add :reason, :text
      add :active, :boolean, null: false, default: true
      add :ended_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:workspace_moderations, [:workspace_id])
    create index(:workspace_moderations, [:target_user_id])
    create index(:workspace_moderations, [:created_by_user_id])
    create index(:workspace_moderations, [:ended_by_user_id])

    create unique_index(:workspace_moderations, [:workspace_id, :target_user_id, :type],
             where: "active"
           )
  end
end
