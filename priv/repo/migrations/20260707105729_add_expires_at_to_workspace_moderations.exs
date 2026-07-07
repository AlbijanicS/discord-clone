defmodule DiscordClone.Repo.Migrations.AddExpiresAtToWorkspaceModerations do
  use Ecto.Migration

  def change do
    alter table(:workspace_moderations) do
      add :expires_at, :utc_datetime
    end
  end
end
