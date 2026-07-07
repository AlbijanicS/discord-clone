defmodule DiscordClone.Repo.Migrations.AddSoftDeleteFieldsToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :deleted_at, :utc_datetime
      add :deleted_by_user_id, references(:users, on_delete: :nilify_all)
    end

    create index(:messages, [:deleted_by_user_id])
  end
end
