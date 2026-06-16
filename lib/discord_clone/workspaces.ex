defmodule DiscordClone.Workspaces do
  @moduledoc """
  The Workspaces context.

  This context owns workspace structure, memberships, channels, and invites.
  Public workflow functions will be added as the app reaches the workspace and
  invite phases.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias DiscordClone.Accounts.{Scope, User}
  alias DiscordClone.Repo
  alias DiscordClone.Workspaces.{Channel, Workspace, WorkspaceMembership}

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

      {:error, :workspace, changeset, _changes_so_far} ->
        {:error, :invalid_workspace, changeset}

      {:error, failed_operation, failed_value, changes_so_far} ->
        {:error, :workspace_creation_failed, failed_operation, failed_value, changes_so_far}
    end
  end

  def create_workspace(%Scope{user: %User{}}, _attrs), do: {:error, :invalid_attrs}

  def create_workspace(_scope, _attrs), do: {:error, :unauthenticated}

  def change_channel(workspace_id, attrs \\ %{}) when is_map(attrs) do
    %Channel{}
    |> Channel.changeset(channel_attrs(workspace_id, attrs))
  end

  def create_channel(%Scope{user: %User{} = user}, workspace_id, attrs) when is_map(attrs) do
    with {:ok, workspace} <- fetch_workspace(workspace_id),
         :ok <- authorize_channel_creation(workspace, user) do
      insert_channel(workspace, attrs)
    end
  end

  def create_channel(%Scope{user: %User{}}, _workspace_id, _attrs), do: {:error, :invalid_attrs}

  def create_channel(_scope, _workspace_id, _attrs), do: {:error, :unauthenticated}

  defp get_attr(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp channel_attrs(workspace_id, attrs) do
    %{
      name: get_attr(attrs, :name),
      workspace_id: workspace_id
    }
  end

  defp fetch_workspace(workspace_id) do
    case Repo.get(Workspace, workspace_id) do
      %Workspace{} = workspace -> {:ok, workspace}
      nil -> {:error, :not_found}
    end
  end

  defp authorize_channel_creation(%Workspace{id: workspace_id}, %User{id: user_id}) do
    if workspace_member?(workspace_id, user_id),
      do: :ok,
      else: {:error, :unauthorized}
  end

  defp insert_channel(%Workspace{id: workspace_id}, attrs) do
    %Channel{}
    |> Channel.changeset(channel_attrs(workspace_id, attrs))
    |> Repo.insert()
    |> case do
      {:ok, channel} -> {:ok, channel}
      {:error, changeset} -> {:error, :invalid_channel, changeset}
    end
  end

  defp workspace_member?(workspace_id, user_id) do
    Repo.exists?(
      from membership in WorkspaceMembership,
        where: membership.workspace_id == ^workspace_id and membership.user_id == ^user_id
    )
  end
end
