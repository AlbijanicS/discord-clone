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

  def list_workspaces(%Scope{user: %User{id: user_id}}) do
    workspaces =
      Repo.all(
        from workspace in Workspace,
          join: membership in WorkspaceMembership,
          on: membership.workspace_id == workspace.id,
          where: membership.user_id == ^user_id,
          order_by: [desc: membership.inserted_at, desc: membership.id]
      )

    {:ok, workspaces}
  end

  def list_workspaces(_scope), do: {:error, :unauthenticated}

  def fetch_workspace(%Scope{user: %User{id: user_id}}, workspace_id) do
    with {:ok, workspace} <- get_workspace(workspace_id),
         :ok <- authorize_workspace_access(workspace, user_id) do
      {:ok, workspace}
    end
  end

  def fetch_workspace(_scope, _workspace_id), do: {:error, :unauthenticated}

  def list_channels(%Scope{} = scope, workspace_id) do
    with {:ok, %Workspace{id: workspace_id}} <- fetch_workspace(scope, workspace_id) do
      {:ok, Repo.all(channels_for_workspace_query(workspace_id))}
    end
  end

  def list_channels(_scope, _workspace_id), do: {:error, :unauthenticated}

  def fetch_channel(%Scope{} = scope, workspace_id, channel_id) do
    with {:ok, %Workspace{id: workspace_id}} <- fetch_workspace(scope, workspace_id),
         %Channel{} = channel <- Repo.get_by(Channel, id: channel_id, workspace_id: workspace_id) do
      {:ok, channel}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def fetch_channel(_scope, _workspace_id, _channel_id), do: {:error, :unauthenticated}

  def resolve_landing_channel(%Scope{} = scope, workspace_id) do
    with {:ok, %Workspace{} = workspace} <- fetch_workspace(scope, workspace_id) do
      case default_channel(workspace) do
        %Channel{} = channel -> {:ok, channel}
        nil -> {:error, :landing_channel_missing}
      end
    end
  end

  def resolve_landing_channel(_scope, _workspace_id), do: {:error, :unauthenticated}

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
    |> Multi.insert(:default_channel, fn %{workspace: workspace} ->
      Channel.changeset(%Channel{}, %{workspace_id: workspace.id, name: "general"})
    end)
    |> Multi.update(:workspace_with_default_channel, fn %{
                                                          workspace: workspace,
                                                          default_channel: default_channel
                                                        } ->
      Workspace.changeset(workspace, %{default_channel_id: default_channel.id})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{workspace_with_default_channel: workspace}} ->
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
    with {:ok, workspace} <- get_workspace(workspace_id),
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

  defp get_workspace(workspace_id) do
    case Repo.get(Workspace, workspace_id) do
      %Workspace{} = workspace -> {:ok, workspace}
      nil -> {:error, :not_found}
    end
  end

  defp default_channel(%Workspace{default_channel_id: nil}), do: nil

  defp default_channel(%Workspace{id: workspace_id, default_channel_id: channel_id}) do
    Repo.get_by(Channel, id: channel_id, workspace_id: workspace_id)
  end

  defp channels_for_workspace_query(workspace_id) do
    from channel in Channel,
      where: channel.workspace_id == ^workspace_id,
      order_by: [asc: channel.inserted_at, asc: channel.id]
  end

  defp authorize_workspace_access(%Workspace{id: workspace_id}, %User{id: user_id}) do
    authorize_workspace_access(workspace_id, user_id)
  end

  defp authorize_workspace_access(%Workspace{id: workspace_id}, user_id) do
    authorize_workspace_access(workspace_id, user_id)
  end

  defp authorize_workspace_access(workspace_id, user_id) do
    if workspace_member?(workspace_id, user_id),
      do: :ok,
      else: {:error, :unauthorized}
  end

  defp authorize_channel_creation(workspace, user),
    do: authorize_workspace_access(workspace, user)

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
