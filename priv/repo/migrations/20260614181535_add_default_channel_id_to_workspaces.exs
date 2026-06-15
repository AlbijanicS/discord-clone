defmodule DiscordClone.Repo.Migrations.AddDefaultChannelIdToWorkspaces do
  use Ecto.Migration

  def change do
    alter table(:workspaces) do
      add :default_channel_id, references(:channels, on_delete: :nilify_all)
    end

    create index(:workspaces, [:default_channel_id])
  end
end
