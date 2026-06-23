defmodule DiscordClone.Workspaces do
  @moduledoc """
  The Workspaces context.

  Owns workspace structure, memberships, channels, and workspace invites.

  Current product-stage permissions are intentionally simple: workspace members
  may manage workspaces and channels, while invite creation follows each
  workspace's invite policy. More granular role-based permissions can replace
  the capability helpers later without changing the public context boundary.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias DiscordClone.Accounts.{Scope, User}
  alias DiscordClone.Chat
  alias DiscordClone.Repo
  alias DiscordClone.Workspaces.{Channel, Workspace, WorkspaceInvite, WorkspaceMembership}

  @owner_role "owner"
  @member_role "member"

  @owner_only_invites "owner_only"
  @members_can_invite "members_can_invite"

  @default_channel_name "general"
  @invite_code_bytes 24
  @default_invite_ttl_minutes 30

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
         :ok <- authorize_view_workspace(workspace, user_id) do
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

  def list_members(%Scope{} = scope, workspace_id) do
    with {:ok, %Workspace{id: workspace_id}} <- fetch_workspace(scope, workspace_id) do
      members =
        Repo.all(
          from membership in WorkspaceMembership,
            where: membership.workspace_id == ^workspace_id,
            order_by: [asc: membership.inserted_at, asc: membership.id],
            preload: [:user]
        )

      {:ok, members}
    end
  end

  def list_members(_scope, _workspace_id), do: {:error, :unauthenticated}

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
    with {:ok, %Workspace{} = workspace} <- fetch_workspace(scope, workspace_id),
         {:ok, %Channel{} = channel} <- fetch_landing_channel(workspace) do
      {:ok, channel}
    end
  end

  def resolve_landing_channel(_scope, _workspace_id), do: {:error, :unauthenticated}

  def change_workspace(scope, attrs \\ %{})

  def change_workspace(%Scope{user: %User{} = user}, attrs) when is_map(attrs) do
    workspace_attrs = %{
      name: get_attr(attrs, :name),
      owner_id: user.id,
      invite_policy: @owner_only_invites
    }

    Workspace.create_changeset(%Workspace{}, workspace_attrs)
  end

  def change_workspace(_scope, _attrs), do: Workspace.create_changeset(%Workspace{}, %{})

  def create_workspace(%Scope{user: %User{} = user}, attrs) when is_map(attrs) do
    user
    |> create_workspace_multi(attrs)
    |> Repo.transaction()
    |> handle_create_workspace_result()
  end

  def create_workspace(%Scope{user: %User{}}, _attrs), do: {:error, :invalid_attrs}

  def create_workspace(_scope, _attrs), do: {:error, :unauthenticated}

  def rename_workspace(%Scope{user: %User{} = user} = scope, workspace_id, attrs)
      when is_map(attrs) do
    with {:ok, workspace} <- fetch_workspace(scope, workspace_id),
         :ok <- authorize_manage_workspace(workspace, user) do
      workspace
      |> Workspace.rename_changeset(workspace_rename_attrs(attrs))
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
    |> Multi.insert(
      :workspace,
      Workspace.create_changeset(%Workspace{}, workspace_attrs(user, attrs))
    )
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
      invite_policy: @owner_only_invites
    }
  end

  defp workspace_rename_attrs(attrs) do
    %{
      name: get_attr(attrs, :name)
    }
  end

  defp owner_membership_changeset(%Workspace{id: workspace_id}, %User{id: user_id}) do
    WorkspaceMembership.changeset(%WorkspaceMembership{}, %{
      workspace_id: workspace_id,
      user_id: user_id,
      role: @owner_role
    })
  end

  defp default_channel_changeset(%Workspace{id: workspace_id}) do
    Channel.create_changeset(%Channel{}, %{
      workspace_id: workspace_id,
      name: @default_channel_name
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
    |> Channel.create_changeset(channel_attrs(workspace_id, attrs))
  end

  def create_channel(%Scope{user: %User{} = user}, workspace_id, attrs) when is_map(attrs) do
    with {:ok, workspace} <- get_workspace(workspace_id),
         :ok <- authorize_manage_channels(workspace, user) do
      insert_channel(workspace, attrs)
    end
  end

  def create_channel(%Scope{user: %User{}}, _workspace_id, _attrs), do: {:error, :invalid_attrs}

  def create_channel(_scope, _workspace_id, _attrs), do: {:error, :unauthenticated}

  def change_workspace_invite(attrs \\ %{}) when is_map(attrs) do
    WorkspaceInvite.create_changeset(%WorkspaceInvite{}, invite_form_attrs(attrs))
  end

  def create_workspace_invite(scope, workspace_id, attrs \\ %{})

  def create_workspace_invite(%Scope{user: %User{} = user} = scope, workspace_id, attrs)
      when is_map(attrs) do
    with {:ok, %Workspace{id: workspace_id} = workspace} <- fetch_workspace(scope, workspace_id),
         :ok <- authorize_create_invite(workspace, user) do
      %WorkspaceInvite{}
      |> WorkspaceInvite.create_changeset(invite_creation_attrs(workspace_id, user, attrs))
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

  def can_create_workspace_invite?(%Scope{user: %User{} = user}, %Workspace{} = workspace) do
    workspace_member?(workspace.id, user.id) and
      workspace_invite_policy_allows?(workspace, user)
  end

  def can_create_workspace_invite?(_scope, _workspace), do: false

  def preview_workspace_invite(%Scope{user: %User{} = user}, code) when is_binary(code) do
    with {:ok, invite} <- get_invite_by_code(code),
         :ok <- validate_invite_usable(invite) do
      {:ok,
       %{
         invite_code: invite.code,
         workspace_name: invite.workspace.name,
         inviter_username: inviter_username(invite),
         accepting_username: user.username
       }}
    end
  end

  def preview_workspace_invite(%Scope{user: %User{}}, _code), do: {:error, :not_found}

  def preview_workspace_invite(_scope, _code), do: {:error, :unauthenticated}

  def accept_workspace_invite(%Scope{user: %User{} = user} = scope, code) when is_binary(code) do
    Multi.new()
    |> Multi.run(:invite, fn repo, _changes ->
      get_invite_by_code_for_update(repo, code)
    end)
    |> Multi.run(:invite_usable, fn _repo, %{invite: invite} ->
      case validate_invite_usable(invite) do
        :ok -> {:ok, invite}
        {:error, reason} -> {:error, reason}
      end
    end)
    |> Multi.run(:membership, fn repo, %{invite: invite} ->
      ensure_invite_membership(repo, invite, user)
    end)
    |> Multi.run(:invite_usage, fn repo, %{invite: invite, membership: membership_result} ->
      update_invite_usage(repo, invite, membership_result)
    end)
    |> Repo.transaction()
    |> handle_accept_invite_result(scope)
  end

  def accept_workspace_invite(%Scope{user: %User{}}, _code), do: {:error, :not_found}

  def accept_workspace_invite(_scope, _code), do: {:error, :unauthenticated}

  def rename_channel(%Scope{user: %User{} = user} = scope, workspace_id, channel_id, attrs)
      when is_map(attrs) do
    with {:ok, workspace} <- fetch_workspace(scope, workspace_id),
         :ok <- authorize_manage_channels(workspace, user),
         {:ok, channel} <- get_channel(workspace.id, channel_id) do
      channel
      |> Channel.rename_changeset(channel_rename_attrs(attrs))
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

  def delete_channel(%Scope{user: %User{} = user} = scope, workspace_id, channel_id) do
    with {:ok, workspace} <- fetch_workspace(scope, workspace_id),
         :ok <- authorize_manage_channels(workspace, user),
         {:ok, channel} <- get_channel(workspace.id, channel_id),
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
         :ok <- authorize_delete_workspace(workspace, user_id),
         {:ok, deleted_workspace} <- Repo.delete(workspace) do
      :ok = Chat.stop_workspace_presence(deleted_workspace.id)
      {:ok, deleted_workspace}
    end
  end

  def delete_workspace(_scope, _workspace_id), do: {:error, :unauthenticated}

  defp get_attr(attrs, key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(attrs, key) -> Map.fetch!(attrs, key)
      Map.has_key?(attrs, string_key) -> Map.fetch!(attrs, string_key)
      true -> nil
    end
  end

  defp channel_attrs(workspace_id, attrs) do
    %{
      name: get_attr(attrs, :name),
      workspace_id: workspace_id
    }
  end

  defp channel_rename_attrs(attrs) do
    %{
      name: get_attr(attrs, :name)
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
        get_attr(attrs, :expires_at) ||
          DateTime.add(DateTime.utc_now(:second), @default_invite_ttl_minutes, :minute),
      max_uses: get_attr(attrs, :max_uses),
      uses_count: 0,
      revoked_at: nil
    }
  end

  defp invite_code do
    @invite_code_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp get_workspace(workspace_id) do
    case Repo.get(Workspace, workspace_id) do
      %Workspace{} = workspace -> {:ok, workspace}
      nil -> {:error, :not_found}
    end
  end

  defp get_channel(workspace_id, channel_id) do
    case Repo.get_by(Channel, id: channel_id, workspace_id: workspace_id) do
      %Channel{} = channel -> {:ok, channel}
      nil -> {:error, :not_found}
    end
  end

  defp get_invite_by_code(code) do
    query =
      from invite in WorkspaceInvite,
        where: invite.code == ^code,
        preload: [:workspace, :created_by_user]

    case Repo.one(query) do
      %WorkspaceInvite{} = invite -> {:ok, invite}
      nil -> {:error, :not_found}
    end
  end

  defp get_invite_by_code_for_update(repo, code) do
    query =
      from invite in WorkspaceInvite,
        where: invite.code == ^code,
        lock: "FOR UPDATE"

    case repo.one(query) do
      %WorkspaceInvite{} = invite -> {:ok, invite}
      nil -> {:error, :not_found}
    end
  end

  defp validate_invite_usable(%WorkspaceInvite{revoked_at: %DateTime{}}),
    do: {:error, :revoked}

  defp validate_invite_usable(%WorkspaceInvite{expires_at: %DateTime{} = expires_at} = invite) do
    if DateTime.compare(expires_at, DateTime.utc_now(:second)) == :gt do
      validate_invite_capacity(invite)
    else
      {:error, :expired}
    end
  end

  defp validate_invite_usable(%WorkspaceInvite{} = invite), do: validate_invite_capacity(invite)

  defp validate_invite_capacity(%WorkspaceInvite{max_uses: max_uses, uses_count: uses_count})
       when is_integer(max_uses) and uses_count >= max_uses,
       do: {:error, :full}

  defp validate_invite_capacity(%WorkspaceInvite{}), do: :ok

  defp ensure_invite_membership(
         repo,
         %WorkspaceInvite{workspace_id: workspace_id},
         %User{id: user_id}
       ) do
    case repo.get_by(WorkspaceMembership, workspace_id: workspace_id, user_id: user_id) do
      %WorkspaceMembership{} = membership ->
        {:ok, {:existing_member, membership}}

      nil ->
        insert_invite_membership(repo, workspace_id, user_id)
    end
  end

  defp insert_invite_membership(
         repo,
         workspace_id,
         user_id
       ) do
    %WorkspaceMembership{}
    |> WorkspaceMembership.changeset(%{
      workspace_id: workspace_id,
      user_id: user_id,
      role: @member_role
    })
    |> repo.insert()
    |> case do
      {:ok, membership} -> {:ok, {:new_member, membership}}
      {:error, changeset} -> {:error, {:invalid_membership, changeset}}
    end
  end

  defp update_invite_usage(repo, %WorkspaceInvite{} = invite, {:new_member, _membership}) do
    invite
    |> WorkspaceInvite.increment_usage_changeset()
    |> repo.update()
  end

  defp update_invite_usage(_repo, %WorkspaceInvite{} = invite, {:existing_member, _membership}) do
    {:ok, invite}
  end

  defp already_member?({:existing_member, _membership}), do: true
  defp already_member?({:new_member, _membership}), do: false

  defp handle_accept_invite_result(
         {:ok, %{invite: invite, membership: membership_result}},
         %Scope{} = scope
       ) do
    with {:ok, channel} <- resolve_landing_channel(scope, invite.workspace_id) do
      {:ok,
       %{
         workspace_id: invite.workspace_id,
         channel_id: channel.id,
         already_member?: already_member?(membership_result)
       }}
    end
  end

  defp handle_accept_invite_result({:error, _operation, reason, _changes_so_far}, _scope) do
    normalize_accept_invite_error(reason)
  end

  defp normalize_accept_invite_error({:invalid_membership, changeset}),
    do: {:error, :invalid_membership, changeset}

  defp normalize_accept_invite_error(reason), do: {:error, reason}

  defp inviter_username(%WorkspaceInvite{created_by_user: %User{username: username}}),
    do: username

  defp inviter_username(_invite), do: nil

  defp get_workspace_membership(workspace_id, user_id) do
    case Repo.get_by(WorkspaceMembership, workspace_id: workspace_id, user_id: user_id) do
      %WorkspaceMembership{} = membership -> {:ok, membership}
      nil -> {:error, :unauthorized}
    end
  end

  defp fetch_landing_channel(%Workspace{} = workspace) do
    case default_channel(workspace) do
      %Channel{} = channel -> {:ok, channel}
      nil -> {:error, :landing_channel_not_found}
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

  defp authorize_view_workspace(%Workspace{id: workspace_id}, %User{id: user_id}) do
    authorize_view_workspace(workspace_id, user_id)
  end

  defp authorize_view_workspace(%Workspace{id: workspace_id}, user_id) do
    authorize_view_workspace(workspace_id, user_id)
  end

  defp authorize_view_workspace(workspace_id, user_id) do
    if workspace_member?(workspace_id, user_id),
      do: :ok,
      else: {:error, :unauthorized}
  end

  defp authorize_manage_workspace(workspace, user),
    do: authorize_view_workspace(workspace, user)

  defp authorize_manage_channels(workspace, user),
    do: authorize_view_workspace(workspace, user)

  defp authorize_create_invite(workspace, user) do
    if workspace_invite_policy_allows?(workspace, user),
      do: :ok,
      else: {:error, :invite_permission_required}
  end

  defp workspace_invite_policy_allows?(
         %Workspace{invite_policy: @owner_only_invites, owner_id: owner_id},
         %User{id: user_id}
       ),
       do: owner_id == user_id

  defp workspace_invite_policy_allows?(%Workspace{invite_policy: @members_can_invite}, %User{}),
    do: true

  defp workspace_invite_policy_allows?(_workspace, _user), do: false

  defp authorize_delete_workspace(%Workspace{owner_id: owner_id}, user_id)
       when owner_id == user_id,
       do: :ok

  defp authorize_delete_workspace(_workspace, _user_id), do: {:error, :owner_required}

  defp insert_channel(%Workspace{id: workspace_id}, attrs) do
    %Channel{}
    |> Channel.create_changeset(channel_attrs(workspace_id, attrs))
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

  defp reject_owner_leave(%WorkspaceMembership{role: @owner_role}),
    do: {:error, :owner_must_delete}

  defp reject_owner_leave(_membership), do: :ok

  defp workspace_member?(workspace_id, user_id) do
    Repo.exists?(
      from membership in WorkspaceMembership,
        where: membership.workspace_id == ^workspace_id and membership.user_id == ^user_id
    )
  end
end
