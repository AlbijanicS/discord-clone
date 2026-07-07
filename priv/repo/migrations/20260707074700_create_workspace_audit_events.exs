defmodule DiscordClone.Repo.Migrations.CreateWorkspaceAuditEvents do
  use Ecto.Migration

  def change do
    create table(:workspace_audit_events) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :actor_user_id, references(:users, on_delete: :nilify_all)
      add :target_user_id, references(:users, on_delete: :nilify_all)
      add :event_type, :string, null: false
      add :reason, :text
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:workspace_audit_events, [:workspace_id, :inserted_at, :id])
    create index(:workspace_audit_events, [:actor_user_id])
    create index(:workspace_audit_events, [:target_user_id])
    create index(:workspace_audit_events, [:event_type])
  end
end
