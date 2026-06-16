defmodule DiscordClone.Workspaces do
  @moduledoc """
  The Workspaces context.

  This context owns workspace structure, memberships, channels, and invites.
  Public workflow functions will be added as the app reaches the workspace and
  invite phases.
  """

  alias Ecto.Multi
  alias DiscordClone.Accounts.{Scope, User}
  alias DiscordClone.Repo
  alias DiscordClone.Workspaces.{Workspace, WorkspaceMembership}

  def create_workspace(%Scope{user: %User{} = user}, attrs) when is_map(attrs) do
    workspace_attrs = %{
      name: get_attr(attrs, :name),
      owner_id: user.id,
      invite_policy: "owner_only"
    }

    Multi.new()
    |> Multi.insert(
      :workspace,
      Workspace.changeset(%Workspace{}, workspace_attrs)
    )
    |> Multi.insert(:owner_membership, fn %{workspace: workspace} ->
      WorkspaceMembership.changeset(%WorkspaceMembership{}, %{
        workspace_id: workspace.id,
        user_id: user.id,
        role: "owner"
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{workspace: workspace}} ->
        {:ok, workspace}

      error ->
        error
    end
  end

  def create_workspace(_scope, _attrs), do: {:error, :unauthenticated}

  defp get_attr(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end
end
