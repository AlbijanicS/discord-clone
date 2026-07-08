defmodule DiscordClone.Repo.Migrations.CreateWorkspaceBans do
  use Ecto.Migration

  def change do
    create table(:workspace_bans) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :target_user_id, references(:users, on_delete: :delete_all), null: false
      add :banned_by_user_id, references(:users, on_delete: :nilify_all)
      add :reason, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:workspace_bans, [:target_user_id])

    create unique_index(:workspace_bans, [:workspace_id, :target_user_id],
             name: :workspace_bans_workspace_id_target_user_id_index
           )
  end
end
