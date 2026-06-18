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
  alias DiscordClone.Workspaces.{Channel, Workspace, WorkspaceInvite, WorkspaceMembership}

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
      {:ok, default_channel(workspace) || oldest_channel(workspace)}
    end
  end

  def resolve_landing_channel(_scope, _workspace_id), do: {:error, :unauthenticated}

  def change_workspace(scope, attrs \\ %{})

  def change_workspace(%Scope{user: %User{} = user}, attrs) when is_map(attrs) do
    workspace_attrs = %{
      name: get_attr(attrs, :name),
      owner_id: user.id,
      invite_policy: "owner_only"
    }

    Workspace.changeset(%Workspace{}, workspace_attrs)
  end

  def change_workspace(_scope, _attrs), do: Workspace.changeset(%Workspace{}, %{})

  def create_workspace(%Scope{user: %User{} = user}, attrs) when is_map(attrs) do
    user
    |> create_workspace_multi(attrs)
    |> Repo.transaction()
    |> handle_create_workspace_result()
  end

  def create_workspace(%Scope{user: %User{}}, _attrs), do: {:error, :invalid_attrs}

  def create_workspace(_scope, _attrs), do: {:error, :unauthenticated}

  def rename_workspace(%Scope{} = scope, workspace_id, attrs) when is_map(attrs) do
    with {:ok, workspace} <- fetch_workspace(scope, workspace_id) do
      workspace
      |> Workspace.changeset(workspace_attrs(workspace, attrs))
      |> Repo.update()
      |> case do
        {:ok, workspace} -> {:ok, workspace}
        {:error, changeset} -> {:error, :invalid_workspace, changeset}
      end
    end
  end

  def rename_workspace(%Scope{user: %User{}}, _workspace_id, _attrs),
    do: {:error, :invalid_attrs}

  def rename_workspace(_scope, _workspace_id, _attrs), do: {:error, :unauthenticated}

  defp create_workspace_multi(%User{} = user, attrs) do
    Multi.new()
    |> Multi.insert(:workspace, Workspace.changeset(%Workspace{}, workspace_attrs(user, attrs)))
    |> Multi.insert(:owner_membership, fn %{workspace: workspace} ->
      owner_membership_changeset(workspace, user)
    end)
    |> Multi.insert(:default_channel, fn %{workspace: workspace} ->
      default_channel_changeset(workspace)
    end)
    |> Multi.update(:workspace_with_default_channel, fn %{
                                                          workspace: workspace,
                                                          default_channel: default_channel
                                                        } ->
      workspace_default_channel_changeset(workspace, default_channel)
    end)
  end

  defp workspace_attrs(%User{id: user_id}, attrs) do
    %{
      name: get_attr(attrs, :name),
      owner_id: user_id,
      invite_policy: "owner_only"
    }
  end

  defp workspace_attrs(%Workspace{} = workspace, attrs) do
    %{
      name: get_attr(attrs, :name),
      owner_id: workspace.owner_id,
      default_channel_id: workspace.default_channel_id,
      invite_policy: workspace.invite_policy
    }
  end

  defp owner_membership_changeset(%Workspace{id: workspace_id}, %User{id: user_id}) do
    WorkspaceMembership.changeset(%WorkspaceMembership{}, %{
      workspace_id: workspace_id,
      user_id: user_id,
      role: "owner"
    })
  end

  defp default_channel_changeset(%Workspace{id: workspace_id}) do
    Channel.changeset(%Channel{}, %{
      workspace_id: workspace_id,
      name: "general"
    })
  end

  defp workspace_default_channel_changeset(
         %Workspace{} = workspace,
         %Channel{id: default_channel_id}
       ) do
    Workspace.default_channel_changeset(workspace, %{
      default_channel_id: default_channel_id
    })
  end

  defp handle_create_workspace_result({:ok, %{workspace_with_default_channel: workspace}}) do
    {:ok, workspace}
  end

  defp handle_create_workspace_result({:error, :workspace, changeset, _changes_so_far}) do
    {:error, :invalid_workspace, changeset}
  end

  defp handle_create_workspace_result({:error, failed_operation, failed_value, changes_so_far}) do
    {:error, :workspace_creation_failed, failed_operation, failed_value, changes_so_far}
  end

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

  def change_workspace_invite(attrs \\ %{}) when is_map(attrs) do
    WorkspaceInvite.changeset(%WorkspaceInvite{}, invite_form_attrs(attrs))
  end

  def create_workspace_invite(scope, workspace_id, attrs \\ %{})

  def create_workspace_invite(%Scope{user: %User{} = user} = scope, workspace_id, attrs)
      when is_map(attrs) do
    with {:ok, %Workspace{id: workspace_id}} <- fetch_workspace(scope, workspace_id) do
      %WorkspaceInvite{}
      |> WorkspaceInvite.changeset(invite_creation_attrs(workspace_id, user, attrs))
      |> Repo.insert()
      |> case do
        {:ok, invite} -> {:ok, invite}
        {:error, changeset} -> {:error, :invalid_invite, changeset}
      end
    end
  end

  def create_workspace_invite(%Scope{user: %User{}}, _workspace_id, _attrs),
    do: {:error, :invalid_attrs}

  def create_workspace_invite(_scope, _workspace_id, _attrs), do: {:error, :unauthenticated}

  def rename_channel(%Scope{} = scope, workspace_id, channel_id, attrs) when is_map(attrs) do
    with {:ok, channel} <- fetch_channel(scope, workspace_id, channel_id) do
      channel
      |> Channel.changeset(channel_attrs(workspace_id, attrs))
      |> Repo.update()
      |> case do
        {:ok, channel} -> {:ok, channel}
        {:error, changeset} -> {:error, :invalid_channel, changeset}
      end
    end
  end

  def rename_channel(%Scope{user: %User{}}, _workspace_id, _channel_id, _attrs),
    do: {:error, :invalid_attrs}

  def rename_channel(_scope, _workspace_id, _channel_id, _attrs), do: {:error, :unauthenticated}

  def delete_channel(%Scope{} = scope, workspace_id, channel_id) do
    with {:ok, workspace} <- fetch_workspace(scope, workspace_id),
         {:ok, channel} <- fetch_channel(scope, workspace_id, channel_id),
         :ok <- reject_landing_channel_delete(workspace, channel) do
      Repo.delete(channel)
    end
  end

  def delete_channel(_scope, _workspace_id, _channel_id), do: {:error, :unauthenticated}

  def leave_workspace(%Scope{user: %User{id: user_id}}, workspace_id) do
    with {:ok, _workspace} <- get_workspace(workspace_id),
         {:ok, membership} <- get_workspace_membership(workspace_id, user_id),
         :ok <- reject_owner_leave(membership) do
      Repo.delete(membership)
    end
  end

  def leave_workspace(_scope, _workspace_id), do: {:error, :unauthenticated}

  def delete_workspace(%Scope{user: %User{id: user_id}}, workspace_id) do
    with {:ok, workspace} <- get_workspace(workspace_id),
         :ok <- authorize_workspace_owner(workspace, user_id) do
      Repo.delete(workspace)
    end
  end

  def delete_workspace(_scope, _workspace_id), do: {:error, :unauthenticated}

  defp get_attr(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp channel_attrs(workspace_id, attrs) do
    %{
      name: get_attr(attrs, :name),
      workspace_id: workspace_id
    }
  end

  defp invite_form_attrs(attrs) do
    %{
      expires_at: get_attr(attrs, :expires_at),
      max_uses: get_attr(attrs, :max_uses)
    }
  end

  defp invite_creation_attrs(workspace_id, user, attrs) do
    %{
      workspace_id: workspace_id,
      created_by_user_id: user.id,
      code: invite_code(),
      expires_at:
        get_attr(attrs, :expires_at) || DateTime.add(DateTime.utc_now(:second), 30, :minute),
      max_uses: get_attr(attrs, :max_uses),
      uses_count: 0,
      revoked_at: nil
    }
  end

  defp invite_code do
    24
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp get_workspace(workspace_id) do
    case Repo.get(Workspace, workspace_id) do
      %Workspace{} = workspace -> {:ok, workspace}
      nil -> {:error, :not_found}
    end
  end

  defp get_workspace_membership(workspace_id, user_id) do
    case Repo.get_by(WorkspaceMembership, workspace_id: workspace_id, user_id: user_id) do
      %WorkspaceMembership{} = membership -> {:ok, membership}
      nil -> {:error, :unauthorized}
    end
  end

  defp default_channel(%Workspace{default_channel_id: nil}), do: nil

  defp default_channel(%Workspace{id: workspace_id, default_channel_id: channel_id}) do
    Repo.get_by(Channel, id: channel_id, workspace_id: workspace_id)
  end

  defp oldest_channel(%Workspace{id: workspace_id}) do
    workspace_id
    |> channels_for_workspace_query()
    |> limit(1)
    |> Repo.one()
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

  defp authorize_workspace_owner(%Workspace{owner_id: owner_id}, user_id)
       when owner_id == user_id,
       do: :ok

  defp authorize_workspace_owner(_workspace, _user_id), do: {:error, :owner_required}

  defp insert_channel(%Workspace{id: workspace_id}, attrs) do
    %Channel{}
    |> Channel.changeset(channel_attrs(workspace_id, attrs))
    |> Repo.insert()
    |> case do
      {:ok, channel} -> {:ok, channel}
      {:error, changeset} -> {:error, :invalid_channel, changeset}
    end
  end

  defp reject_landing_channel_delete(
         %Workspace{default_channel_id: default_channel_id},
         %Channel{id: channel_id}
       )
       when default_channel_id == channel_id,
       do: {:error, :landing_channel_required}

  defp reject_landing_channel_delete(_workspace, _channel), do: :ok

  defp reject_owner_leave(%WorkspaceMembership{role: "owner"}), do: {:error, :owner_must_delete}
  defp reject_owner_leave(_membership), do: :ok

  defp workspace_member?(workspace_id, user_id) do
    Repo.exists?(
      from membership in WorkspaceMembership,
        where: membership.workspace_id == ^workspace_id and membership.user_id == ^user_id
    )
  end
end
