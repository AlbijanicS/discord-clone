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

  alias DiscordClone.Workspaces.{
    Channel,
    Workspace,
    WorkspaceAuditEvent,
    WorkspaceBan,
    WorkspaceInvite,
    WorkspaceModeration,
    WorkspaceMembership
  }

  @owner_role "owner"
  @admin_role "admin"
  @member_role "member"
  @mute_type "mute"
  @timeout_type "timeout"
  @timeout_duration_presets %{
    "5_minutes" => {5, :minute},
    "1_hour" => {1, :hour},
    "24_hours" => {24, :hour},
    "7_days" => {7, :day}
  }

  @no_cleanup_window "none"
  @all_messages_cleanup_window "all"
  @ban_cleanup_windows %{
    @no_cleanup_window => :none,
    "1_hour" => {1, :hour},
    "24_hours" => {24, :hour},
    "7_days" => {7, :day},
    @all_messages_cleanup_window => :all
  }

  @owner_only_invites "owner_only"
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

  def rename_workspace(%Scope{user: %User{}} = scope, workspace_id, attrs)
      when is_map(attrs) do
    with {:ok, workspace} <- fetch_workspace(scope, workspace_id),
         :ok <- authorize_rename_workspace(scope, workspace) do
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
    |> Multi.run(:owner_channel_reads, fn _repo, %{workspace: workspace} ->
      case Chat.initialize_workspace_reads_for_user(user.id, workspace.id) do
        :ok -> {:ok, :initialized}
        {:error, reason} -> {:error, reason}
      end
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

  def create_channel(%Scope{user: %User{}} = scope, workspace_id, attrs) when is_map(attrs) do
    with {:ok, workspace} <- get_workspace(workspace_id),
         :ok <- authorize_create_channel(scope, workspace) do
      create_channel_with_reads(workspace, attrs)
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
         :ok <- authorize_create_invite(scope, workspace) do
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

  def can_rename_workspace?(%Scope{} = scope, %Workspace{} = workspace),
    do: has_workspace_role?(scope, workspace, [@owner_role])

  def can_rename_workspace?(_scope, _workspace), do: false

  def can_delete_workspace?(%Scope{} = scope, %Workspace{} = workspace),
    do: has_workspace_role?(scope, workspace, [@owner_role])

  def can_delete_workspace?(_scope, _workspace), do: false

  def can_create_channel?(%Scope{} = scope, %Workspace{} = workspace),
    do: has_workspace_role?(scope, workspace, [@owner_role, @admin_role])

  def can_create_channel?(_scope, _workspace), do: false

  def can_rename_channel?(%Scope{} = scope, %Workspace{} = workspace),
    do: has_workspace_role?(scope, workspace, [@owner_role, @admin_role])

  def can_rename_channel?(_scope, _workspace), do: false

  def can_delete_channel?(%Scope{} = scope, %Workspace{} = workspace),
    do: has_workspace_role?(scope, workspace, [@owner_role])

  def can_delete_channel?(_scope, _workspace), do: false

  def can_create_workspace_invite?(%Scope{} = scope, %Workspace{} = workspace),
    do: has_workspace_role?(scope, workspace, [@owner_role, @admin_role])

  def can_create_workspace_invite?(_scope, _workspace), do: false

  def can_view_audit_log?(%Scope{} = scope, %Workspace{} = workspace),
    do: has_workspace_role?(scope, workspace, [@owner_role])

  def can_view_audit_log?(_scope, _workspace), do: false

  def can_manage_roles?(%Scope{} = scope, %Workspace{} = workspace),
    do: has_workspace_role?(scope, workspace, [@owner_role])

  def can_manage_roles?(_scope, _workspace), do: false

  def can_purge_all_workspace_messages?(%Scope{} = scope, %Workspace{} = workspace),
    do: has_workspace_role?(scope, workspace, [@owner_role])

  def can_purge_all_workspace_messages?(_scope, _workspace), do: false

  def can_unban_member?(%Scope{} = scope, %Workspace{} = workspace),
    do: has_workspace_role?(scope, workspace, [@owner_role])

  def can_unban_member?(_scope, _workspace), do: false

  def available_member_actions(
        %Scope{} = scope,
        %Workspace{id: workspace_id} = workspace,
        %WorkspaceMembership{workspace_id: workspace_id} = target_membership
      ) do
    actions =
      case workspace_role(scope, workspace) do
        @owner_role -> owner_member_actions(target_membership)
        @admin_role -> admin_member_actions(target_membership)
        _role -> []
      end

    actions
    |> active_mute_actions(target_membership)
    |> active_timeout_actions(target_membership)
  end

  def available_member_actions(_scope, _workspace, _target_membership), do: []

  def mute_member(scope, workspace_id, target_user_id, attrs \\ %{})

  def mute_member(%Scope{user: %User{}} = scope, workspace_id, target_user_id, attrs)
      when is_map(attrs) do
    with {:ok, workspace} <- fetch_workspace(scope, workspace_id),
         {:ok, target_membership} <- get_workspace_membership(workspace.id, target_user_id),
         :ok <- authorize_mute_member(scope, workspace, target_membership) do
      mute_member_with_audit(scope, target_membership, attrs)
    end
  end

  def mute_member(%Scope{user: %User{}}, _workspace_id, _target_user_id, _attrs),
    do: {:error, :invalid_attrs}

  def mute_member(_scope, _workspace_id, _target_user_id, _attrs),
    do: {:error, :unauthenticated}

  def unmute_member(%Scope{user: %User{}} = scope, workspace_id, target_user_id) do
    with {:ok, workspace} <- fetch_workspace(scope, workspace_id),
         {:ok, target_membership} <- get_workspace_membership(workspace.id, target_user_id),
         :ok <- authorize_unmute_member(scope, workspace, target_membership),
         {:ok, moderation} <- fetch_active_moderation(workspace.id, target_user_id, @mute_type) do
      unmute_member_with_audit(scope, moderation)
    end
  end

  def unmute_member(_scope, _workspace_id, _target_user_id), do: {:error, :unauthenticated}

  def timeout_member(scope, workspace_id, target_user_id, duration, attrs \\ %{})

  def timeout_member(
        %Scope{user: %User{}} = scope,
        workspace_id,
        target_user_id,
        duration,
        attrs
      )
      when is_binary(duration) and is_map(attrs) do
    with {:ok, expires_at} <- timeout_expires_at(duration),
         {:ok, workspace} <- fetch_workspace(scope, workspace_id),
         {:ok, target_membership} <- get_workspace_membership(workspace.id, target_user_id),
         :ok <- authorize_timeout_member(scope, workspace, target_membership),
         {:ok, _expired_timeout} <- expire_due_timeout_for_target(workspace.id, target_user_id) do
      timeout_member_with_audit(scope, target_membership, duration, expires_at, attrs)
    end
  end

  def timeout_member(%Scope{user: %User{}}, _workspace_id, _target_user_id, _duration, _attrs),
    do: {:error, :invalid_attrs}

  def timeout_member(_scope, _workspace_id, _target_user_id, _duration, _attrs),
    do: {:error, :unauthenticated}

  def remove_member_timeout(%Scope{user: %User{}} = scope, workspace_id, target_user_id) do
    with {:ok, workspace} <- fetch_workspace(scope, workspace_id),
         {:ok, target_membership} <- get_workspace_membership(workspace.id, target_user_id),
         :ok <- authorize_remove_member_timeout(scope, workspace, target_membership),
         {:ok, moderation} <- fetch_active_moderation(workspace.id, target_user_id, @timeout_type) do
      remove_member_timeout_with_audit(scope, moderation)
    end
  end

  def remove_member_timeout(_scope, _workspace_id, _target_user_id),
    do: {:error, :unauthenticated}

  def kick_member(scope, workspace_id, target_user_id, attrs \\ %{})

  def kick_member(%Scope{user: %User{}} = scope, workspace_id, target_user_id, attrs)
      when is_map(attrs) do
    with {:ok, workspace} <- fetch_workspace(scope, workspace_id),
         {:ok, target_membership} <- get_workspace_membership(workspace.id, target_user_id),
         :ok <- authorize_kick_member(scope, workspace, target_membership),
         {:ok, reason} <- validate_required_reason(attrs) do
      kick_member_with_audit(scope, workspace, target_membership, reason)
    end
  end

  def kick_member(%Scope{user: %User{}}, _workspace_id, _target_user_id, _attrs),
    do: {:error, :invalid_attrs}

  def kick_member(_scope, _workspace_id, _target_user_id, _attrs),
    do: {:error, :unauthenticated}

  def ban_member(scope, workspace_id, target_user_id, attrs \\ %{})

  def ban_member(%Scope{user: %User{}} = scope, workspace_id, target_user_id, attrs)
      when is_map(attrs) do
    with {:ok, workspace} <- fetch_workspace(scope, workspace_id),
         {:ok, target_membership} <- get_workspace_membership(workspace.id, target_user_id),
         :ok <- authorize_ban_member(scope, workspace, target_membership),
         {:ok, reason} <- validate_required_reason(attrs),
         {:ok, cleanup_window} <- resolve_ban_cleanup_window(scope, workspace, attrs) do
      ban_member_with_audit(scope, workspace, target_membership, reason, cleanup_window)
    end
  end

  def ban_member(%Scope{user: %User{}}, _workspace_id, _target_user_id, _attrs),
    do: {:error, :invalid_attrs}

  def ban_member(_scope, _workspace_id, _target_user_id, _attrs),
    do: {:error, :unauthenticated}

  def workspace_banned?(workspace_id, user_id) do
    Repo.exists?(
      from ban in WorkspaceBan,
        where: ban.workspace_id == ^workspace_id and ban.target_user_id == ^user_id
    )
  end

  def unban_member(%Scope{user: %User{}} = scope, workspace_id, target_user_id) do
    with {:ok, workspace} <- fetch_workspace(scope, workspace_id),
         :ok <- authorize_unban_member(scope, workspace),
         {:ok, ban} <- get_workspace_ban(workspace.id, target_user_id) do
      unban_member_with_audit(scope, workspace, ban)
    end
  end

  def unban_member(_scope, _workspace_id, _target_user_id), do: {:error, :unauthenticated}

  def list_active_future_timeouts(workspace_id) do
    now = DateTime.utc_now(:second)

    Repo.all(
      from moderation in WorkspaceModeration,
        where:
          moderation.workspace_id == ^workspace_id and
            moderation.type == ^@timeout_type and
            moderation.active? == true and
            moderation.expires_at > ^now,
        order_by: [asc: moderation.expires_at, asc: moderation.id]
    )
  end

  def expire_member_timeout(moderation_id) do
    case Repo.get(WorkspaceModeration, moderation_id) do
      %WorkspaceModeration{
        type: @timeout_type,
        active?: true,
        expires_at: %DateTime{} = expires_at
      } =
          moderation ->
        if DateTime.compare(expires_at, DateTime.utc_now(:second)) in [:lt, :eq] do
          expire_member_timeout_with_audit(moderation)
        else
          {:ok, :not_due}
        end

      %WorkspaceModeration{type: @timeout_type, active?: false} ->
        {:ok, :already_inactive}

      %WorkspaceModeration{} ->
        {:error, :not_found}

      nil ->
        {:error, :not_found}
    end
  end

  def member_moderation_state(
        %Scope{user: %User{id: actor_user_id}} = scope,
        workspace_id,
        target_user_id
      ) do
    with {:ok, workspace} <- fetch_workspace(scope, workspace_id),
         {:ok, target_membership} <- get_workspace_membership(workspace.id, target_user_id),
         :ok <-
           authorize_view_member_moderation(scope, workspace, target_membership, actor_user_id) do
      mute = get_active_moderation(workspace.id, target_user_id, @mute_type)
      timeout = get_active_moderation(workspace.id, target_user_id, @timeout_type)

      {:ok,
       %{
         muted?: match?(%WorkspaceModeration{}, mute),
         mute_reason: moderation_reason(mute),
         timed_out?: match?(%WorkspaceModeration{}, timeout),
         timeout_reason: moderation_reason(timeout),
         timeout_ends_at: moderation_expires_at(timeout)
       }}
    end
  end

  def member_moderation_state(_scope, _workspace_id, _target_user_id),
    do: {:error, :unauthenticated}

  def change_member_role(
        %Scope{user: %User{}} = scope,
        workspace_id,
        target_user_id,
        role
      )
      when is_binary(role) do
    with {:ok, workspace} <- fetch_workspace(scope, workspace_id),
         :ok <- authorize_manage_roles(scope, workspace),
         {:ok, membership} <- get_workspace_membership(workspace.id, target_user_id),
         :ok <- reject_owner_role_change(membership),
         :ok <- authorize_role_transition(membership.role, role) do
      change_member_role_with_audit(scope, membership, role)
    end
  end

  def change_member_role(%Scope{user: %User{}}, _workspace_id, _target_user_id, _role),
    do: {:error, :invalid_attrs}

  def change_member_role(_scope, _workspace_id, _target_user_id, _role),
    do: {:error, :unauthenticated}

  def list_audit_events(%Scope{user: %User{}} = scope, workspace_id) do
    with {:ok, workspace} <- fetch_workspace(scope, workspace_id),
         :ok <- authorize_view_audit_events(scope, workspace) do
      audit_events =
        Repo.all(
          from audit_event in WorkspaceAuditEvent,
            where: audit_event.workspace_id == ^workspace.id,
            order_by: [desc: audit_event.inserted_at, desc: audit_event.id],
            preload: [:actor_user, :target_user]
        )

      {:ok, audit_events}
    end
  end

  def list_audit_events(_scope, _workspace_id), do: {:error, :unauthenticated}

  def list_banned_members(%Scope{user: %User{}} = scope, workspace_id) do
    with {:ok, workspace} <- fetch_workspace(scope, workspace_id),
         :ok <- authorize_unban_member(scope, workspace) do
      banned_members =
        Repo.all(
          from ban in WorkspaceBan,
            where: ban.workspace_id == ^workspace.id,
            order_by: [desc: ban.inserted_at, desc: ban.id],
            preload: [:target_user, :banned_by_user]
        )

      {:ok, banned_members}
    end
  end

  def list_banned_members(_scope, _workspace_id), do: {:error, :unauthenticated}

  def subscribe_to_workspace_moderation(%Scope{user: %User{id: user_id}}, workspace_id) do
    with :ok <- authorize_view_workspace(workspace_id, user_id) do
      Phoenix.PubSub.subscribe(DiscordClone.PubSub, workspace_moderation_topic(workspace_id))
    end
  end

  def subscribe_to_workspace_moderation(_scope, _workspace_id), do: {:error, :unauthenticated}

  def preview_workspace_invite(%Scope{user: %User{} = user}, code) when is_binary(code) do
    with {:ok, invite} <- get_invite_by_code(code),
         :ok <- validate_invite_usable(invite),
         :ok <- validate_not_banned(invite.workspace_id, user.id) do
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
    |> Multi.run(:not_banned, fn _repo, %{invite: invite} ->
      case validate_not_banned(invite.workspace_id, user.id) do
        :ok -> {:ok, :not_banned}
        {:error, reason} -> {:error, reason}
      end
    end)
    |> Multi.run(:membership, fn repo, %{invite: invite} ->
      ensure_invite_membership(repo, invite, user)
    end)
    |> Multi.run(:member_channel_reads, fn _repo,
                                           %{
                                             invite: invite,
                                             membership: membership_result
                                           } ->
      initialize_invite_member_reads(user, invite, membership_result)
    end)
    |> Multi.run(:invite_usage, fn repo, %{invite: invite, membership: membership_result} ->
      update_invite_usage(repo, invite, membership_result)
    end)
    |> Repo.transaction()
    |> handle_accept_invite_result(scope)
  end

  def accept_workspace_invite(%Scope{user: %User{}}, _code), do: {:error, :not_found}

  def accept_workspace_invite(_scope, _code), do: {:error, :unauthenticated}

  def rename_channel(%Scope{user: %User{}} = scope, workspace_id, channel_id, attrs)
      when is_map(attrs) do
    with {:ok, workspace} <- fetch_workspace(scope, workspace_id),
         :ok <- authorize_rename_channel(scope, workspace),
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

  def delete_channel(%Scope{user: %User{}} = scope, workspace_id, channel_id) do
    with {:ok, workspace} <- fetch_workspace(scope, workspace_id),
         :ok <- authorize_delete_channel(scope, workspace),
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
      Multi.new()
      |> Multi.run(:channel_reads, fn _repo, _changes ->
        :ok = Chat.delete_workspace_reads_for_user(user_id, workspace_id)
        {:ok, :deleted}
      end)
      |> Multi.delete(:membership, membership)
      |> Repo.transaction()
      |> case do
        {:ok, %{membership: membership}} ->
          {:ok, membership}

        {:error, failed_operation, failed_value, changes_so_far} ->
          {:error, :leave_workspace_failed, failed_operation, failed_value, changes_so_far}
      end
    end
  end

  def leave_workspace(_scope, _workspace_id), do: {:error, :unauthenticated}

  def delete_workspace(%Scope{user: %User{}} = scope, workspace_id) do
    with {:ok, workspace} <- get_workspace(workspace_id),
         :ok <- authorize_delete_workspace(scope, workspace),
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

  defp validate_not_banned(workspace_id, user_id) do
    if workspace_banned?(workspace_id, user_id), do: {:error, :banned}, else: :ok
  end

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

  defp initialize_invite_member_reads(
         %User{id: user_id},
         %WorkspaceInvite{workspace_id: workspace_id},
         {:new_member, _membership}
       ) do
    case Chat.initialize_workspace_reads_for_user(user_id, workspace_id) do
      :ok -> {:ok, :initialized}
      {:error, reason} -> {:error, reason}
    end
  end

  defp initialize_invite_member_reads(
         %User{},
         %WorkspaceInvite{},
         {:existing_member, _membership}
       ) do
    {:ok, :unchanged}
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

  defp authorize_rename_workspace(scope, workspace) do
    if can_rename_workspace?(scope, workspace), do: :ok, else: {:error, :owner_required}
  end

  defp authorize_create_channel(scope, workspace) do
    if can_create_channel?(scope, workspace), do: :ok, else: {:error, :unauthorized}
  end

  defp authorize_rename_channel(scope, workspace) do
    if can_rename_channel?(scope, workspace), do: :ok, else: {:error, :unauthorized}
  end

  defp authorize_delete_channel(scope, workspace) do
    if can_delete_channel?(scope, workspace), do: :ok, else: {:error, :owner_required}
  end

  defp authorize_create_invite(scope, workspace) do
    if can_create_workspace_invite?(scope, workspace),
      do: :ok,
      else: {:error, :invite_permission_required}
  end

  defp authorize_delete_workspace(scope, workspace) do
    if can_delete_workspace?(scope, workspace), do: :ok, else: {:error, :owner_required}
  end

  defp authorize_manage_roles(scope, workspace) do
    if can_manage_roles?(scope, workspace), do: :ok, else: {:error, :owner_required}
  end

  defp authorize_view_audit_events(scope, workspace) do
    if can_view_audit_log?(scope, workspace), do: :ok, else: {:error, :owner_required}
  end

  defp authorize_mute_member(scope, workspace, %WorkspaceMembership{} = target_membership) do
    if :mute in available_member_actions(scope, workspace, target_membership),
      do: :ok,
      else: {:error, :unauthorized}
  end

  defp authorize_unmute_member(scope, workspace, %WorkspaceMembership{} = target_membership) do
    if :unmute in available_member_actions(scope, workspace, target_membership),
      do: :ok,
      else: {:error, :unauthorized}
  end

  defp authorize_timeout_member(scope, workspace, %WorkspaceMembership{} = target_membership) do
    if :timeout in available_member_actions(scope, workspace, target_membership),
      do: :ok,
      else: {:error, :unauthorized}
  end

  defp authorize_remove_member_timeout(
         scope,
         workspace,
         %WorkspaceMembership{} = target_membership
       ) do
    if :remove_timeout in available_member_actions(scope, workspace, target_membership),
      do: :ok,
      else: {:error, :unauthorized}
  end

  defp authorize_kick_member(scope, workspace, %WorkspaceMembership{} = target_membership) do
    if :kick in available_member_actions(scope, workspace, target_membership),
      do: :ok,
      else: {:error, :unauthorized}
  end

  defp authorize_ban_member(scope, workspace, %WorkspaceMembership{} = target_membership) do
    if :ban in available_member_actions(scope, workspace, target_membership),
      do: :ok,
      else: {:error, :unauthorized}
  end

  defp authorize_unban_member(scope, workspace) do
    if can_unban_member?(scope, workspace), do: :ok, else: {:error, :owner_required}
  end

  defp authorize_view_member_moderation(
         _scope,
         _workspace,
         %WorkspaceMembership{user_id: target_user_id},
         actor_user_id
       )
       when target_user_id == actor_user_id,
       do: :ok

  defp authorize_view_member_moderation(scope, workspace, _target_membership, _actor_user_id) do
    if has_workspace_role?(scope, workspace, [@owner_role, @admin_role]),
      do: :ok,
      else: {:error, :unauthorized}
  end

  defp mute_member_with_audit(
         %Scope{user: %User{id: actor_user_id}},
         %WorkspaceMembership{} = target_membership,
         attrs
       ) do
    reason = moderation_reason_attrs(attrs)

    Multi.new()
    |> Multi.insert(
      :moderation,
      WorkspaceModeration.create_changeset(%WorkspaceModeration{}, %{
        workspace_id: target_membership.workspace_id,
        target_user_id: target_membership.user_id,
        created_by_user_id: actor_user_id,
        type: @mute_type,
        reason: reason
      })
    )
    |> Multi.insert(:audit_event, fn %{moderation: moderation} ->
      WorkspaceAuditEvent.changeset(%WorkspaceAuditEvent{}, %{
        workspace_id: moderation.workspace_id,
        actor_user_id: actor_user_id,
        target_user_id: moderation.target_user_id,
        event_type: "member_muted",
        reason: moderation.reason,
        metadata: %{"moderation_type" => moderation.type}
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{moderation: moderation}} ->
        :ok =
          broadcast_workspace_moderation_changed(
            moderation.workspace_id,
            moderation.target_user_id
          )

        {:ok, moderation}

      {:error, :moderation, changeset, _changes_so_far} ->
        {:error, :invalid_moderation, changeset}

      {:error, :audit_event, changeset, _changes_so_far} ->
        {:error, :invalid_audit_event, changeset}
    end
  end

  defp unmute_member_with_audit(
         %Scope{user: %User{id: actor_user_id}},
         %WorkspaceModeration{} = moderation
       ) do
    Multi.new()
    |> Multi.update(
      :moderation,
      WorkspaceModeration.end_changeset(moderation, %{
        active?: false,
        ended_at: DateTime.utc_now(:second),
        ended_by_user_id: actor_user_id
      })
    )
    |> Multi.insert(:audit_event, fn %{moderation: ended_moderation} ->
      WorkspaceAuditEvent.changeset(%WorkspaceAuditEvent{}, %{
        workspace_id: ended_moderation.workspace_id,
        actor_user_id: actor_user_id,
        target_user_id: ended_moderation.target_user_id,
        event_type: "member_unmuted",
        metadata: %{"moderation_type" => ended_moderation.type}
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{moderation: moderation}} ->
        :ok =
          broadcast_workspace_moderation_changed(
            moderation.workspace_id,
            moderation.target_user_id
          )

        {:ok, moderation}

      {:error, :moderation, changeset, _changes_so_far} ->
        {:error, :invalid_moderation, changeset}

      {:error, :audit_event, changeset, _changes_so_far} ->
        {:error, :invalid_audit_event, changeset}
    end
  end

  defp timeout_member_with_audit(
         %Scope{user: %User{id: actor_user_id}},
         %WorkspaceMembership{} = target_membership,
         duration,
         expires_at,
         attrs
       ) do
    reason = moderation_reason_attrs(attrs)

    Multi.new()
    |> Multi.insert(
      :moderation,
      WorkspaceModeration.create_changeset(%WorkspaceModeration{}, %{
        workspace_id: target_membership.workspace_id,
        target_user_id: target_membership.user_id,
        created_by_user_id: actor_user_id,
        type: @timeout_type,
        reason: reason,
        expires_at: expires_at
      })
    )
    |> Multi.insert(:audit_event, fn %{moderation: moderation} ->
      WorkspaceAuditEvent.changeset(%WorkspaceAuditEvent{}, %{
        workspace_id: moderation.workspace_id,
        actor_user_id: actor_user_id,
        target_user_id: moderation.target_user_id,
        event_type: "member_timed_out",
        reason: moderation.reason,
        metadata: %{
          "moderation_type" => moderation.type,
          "duration" => duration,
          "expires_at" => DateTime.to_iso8601(moderation.expires_at)
        }
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{moderation: moderation}} ->
        :ok = Chat.schedule_workspace_timeout_expiry(moderation)

        :ok =
          broadcast_workspace_moderation_changed(
            moderation.workspace_id,
            moderation.target_user_id
          )

        {:ok, moderation}

      {:error, :moderation, changeset, _changes_so_far} ->
        {:error, :invalid_moderation, changeset}

      {:error, :audit_event, changeset, _changes_so_far} ->
        {:error, :invalid_audit_event, changeset}
    end
  end

  defp remove_member_timeout_with_audit(
         %Scope{user: %User{id: actor_user_id}},
         %WorkspaceModeration{} = moderation
       ) do
    Multi.new()
    |> Multi.update(
      :moderation,
      WorkspaceModeration.end_changeset(moderation, %{
        active?: false,
        ended_at: DateTime.utc_now(:second),
        ended_by_user_id: actor_user_id
      })
    )
    |> Multi.insert(:audit_event, fn %{moderation: ended_moderation} ->
      WorkspaceAuditEvent.changeset(%WorkspaceAuditEvent{}, %{
        workspace_id: ended_moderation.workspace_id,
        actor_user_id: actor_user_id,
        target_user_id: ended_moderation.target_user_id,
        event_type: "member_timeout_removed",
        metadata: %{"moderation_type" => ended_moderation.type}
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{moderation: moderation}} ->
        :ok = Chat.cancel_workspace_timeout_expiry(moderation)

        :ok =
          broadcast_workspace_moderation_changed(
            moderation.workspace_id,
            moderation.target_user_id
          )

        {:ok, moderation}

      {:error, :moderation, changeset, _changes_so_far} ->
        {:error, :invalid_moderation, changeset}

      {:error, :audit_event, changeset, _changes_so_far} ->
        {:error, :invalid_audit_event, changeset}
    end
  end

  defp kick_member_with_audit(
         %Scope{user: %User{id: actor_user_id}},
         %Workspace{} = workspace,
         %WorkspaceMembership{} = target_membership,
         reason
       ) do
    target_user_id = target_membership.user_id
    active_timeouts = active_timeout_moderations(workspace.id, target_user_id)

    Multi.new()
    |> Multi.delete_all(
      :moderations,
      from(moderation in WorkspaceModeration,
        where:
          moderation.workspace_id == ^workspace.id and
            moderation.target_user_id == ^target_user_id
      )
    )
    |> Multi.run(:channel_reads, fn _repo, _changes ->
      :ok = Chat.delete_workspace_reads_for_user(target_user_id, workspace.id)
      {:ok, :deleted}
    end)
    |> Multi.delete(:membership, target_membership)
    |> Multi.insert(
      :audit_event,
      WorkspaceAuditEvent.changeset(%WorkspaceAuditEvent{}, %{
        workspace_id: workspace.id,
        actor_user_id: actor_user_id,
        target_user_id: target_user_id,
        event_type: "member_kicked",
        reason: reason,
        metadata: %{}
      })
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{membership: membership}} ->
        Enum.each(active_timeouts, &Chat.cancel_workspace_timeout_expiry/1)
        :ok = broadcast_workspace_access_revoked(workspace.id, target_user_id)
        {:ok, membership}

      {:error, :audit_event, changeset, _changes_so_far} ->
        {:error, :invalid_audit_event, changeset}

      {:error, _failed_operation, _failed_value, _changes_so_far} ->
        {:error, :kick_failed}
    end
  end

  defp ban_member_with_audit(
         %Scope{user: %User{id: actor_user_id}},
         %Workspace{} = workspace,
         %WorkspaceMembership{} = target_membership,
         reason,
         cleanup_window
       ) do
    target_user_id = target_membership.user_id
    active_timeouts = active_timeout_moderations(workspace.id, target_user_id)

    Multi.new()
    |> Multi.insert(
      :ban,
      WorkspaceBan.create_changeset(%WorkspaceBan{}, %{
        workspace_id: workspace.id,
        target_user_id: target_user_id,
        banned_by_user_id: actor_user_id,
        reason: reason
      })
    )
    |> Multi.delete_all(
      :moderations,
      from(moderation in WorkspaceModeration,
        where:
          moderation.workspace_id == ^workspace.id and
            moderation.target_user_id == ^target_user_id
      )
    )
    |> Multi.run(:channel_reads, fn _repo, _changes ->
      :ok = Chat.delete_workspace_reads_for_user(target_user_id, workspace.id)
      {:ok, :deleted}
    end)
    |> Multi.run(:message_cleanup, fn _repo, _changes ->
      clean_up_banned_member_messages(workspace, target_user_id, actor_user_id, cleanup_window)
    end)
    |> Multi.delete(:membership, target_membership)
    |> Multi.insert(:audit_event, fn %{message_cleanup: cleaned_messages} ->
      WorkspaceAuditEvent.changeset(%WorkspaceAuditEvent{}, %{
        workspace_id: workspace.id,
        actor_user_id: actor_user_id,
        target_user_id: target_user_id,
        event_type: "member_banned",
        reason: reason,
        metadata: ban_cleanup_metadata(cleanup_window, cleaned_messages)
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{ban: ban, message_cleanup: cleaned_messages}} ->
        Enum.each(active_timeouts, &Chat.cancel_workspace_timeout_expiry/1)
        :ok = Chat.broadcast_cleaned_messages(cleaned_messages)
        :ok = broadcast_workspace_access_revoked(workspace.id, target_user_id)
        {:ok, ban}

      {:error, :ban, changeset, _changes_so_far} ->
        {:error, :invalid_ban, changeset}

      {:error, :audit_event, changeset, _changes_so_far} ->
        {:error, :invalid_audit_event, changeset}

      {:error, _failed_operation, _failed_value, _changes_so_far} ->
        {:error, :ban_failed}
    end
  end

  defp get_workspace_ban(workspace_id, target_user_id) do
    case Repo.get_by(WorkspaceBan, workspace_id: workspace_id, target_user_id: target_user_id) do
      %WorkspaceBan{} = ban -> {:ok, ban}
      nil -> {:error, :not_banned}
    end
  end

  defp unban_member_with_audit(
         %Scope{user: %User{id: actor_user_id}},
         %Workspace{} = workspace,
         %WorkspaceBan{} = ban
       ) do
    Multi.new()
    |> Multi.delete(:unban, ban)
    |> Multi.insert(:audit_event, fn _changes ->
      WorkspaceAuditEvent.changeset(%WorkspaceAuditEvent{}, %{
        workspace_id: workspace.id,
        actor_user_id: actor_user_id,
        target_user_id: ban.target_user_id,
        event_type: "member_unbanned",
        metadata: %{}
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{unban: unban}} ->
        {:ok, unban}

      {:error, :audit_event, changeset, _changes_so_far} ->
        {:error, :invalid_audit_event, changeset}

      {:error, _failed_operation, _failed_value, _changes_so_far} ->
        {:error, :unban_failed}
    end
  end

  defp clean_up_banned_member_messages(_workspace, _target_user_id, _actor_user_id, :none),
    do: {:ok, []}

  defp clean_up_banned_member_messages(workspace, target_user_id, actor_user_id, cleanup_window) do
    Chat.soft_delete_user_workspace_messages(
      workspace.id,
      target_user_id,
      actor_user_id,
      ban_cleanup_bound(cleanup_window)
    )
  end

  defp ban_cleanup_bound(:all), do: :all

  defp ban_cleanup_bound({amount, unit}),
    do: DateTime.add(DateTime.utc_now(:second), -amount, unit)

  defp ban_cleanup_metadata(:none, _cleaned_messages), do: %{}

  defp ban_cleanup_metadata(cleanup_window, cleaned_messages) do
    %{
      "cleanup_window" => ban_cleanup_window_key(cleanup_window),
      "cleanup_message_count" => length(cleaned_messages)
    }
  end

  defp ban_cleanup_window_key(:all), do: @all_messages_cleanup_window

  defp ban_cleanup_window_key(spec) do
    Enum.find_value(@ban_cleanup_windows, fn {key, value} ->
      if value == spec, do: key
    end)
  end

  defp resolve_ban_cleanup_window(scope, workspace, attrs) do
    case get_attr(attrs, :cleanup_window) do
      nil ->
        {:ok, :none}

      window when is_binary(window) ->
        case Map.fetch(@ban_cleanup_windows, window) do
          {:ok, :all} -> authorize_all_message_cleanup(scope, workspace)
          {:ok, spec} -> {:ok, spec}
          :error -> {:error, :invalid_cleanup_window}
        end

      _window ->
        {:error, :invalid_cleanup_window}
    end
  end

  defp authorize_all_message_cleanup(scope, workspace) do
    if can_purge_all_workspace_messages?(scope, workspace),
      do: {:ok, :all},
      else: {:error, :cleanup_owner_required}
  end

  defp active_timeout_moderations(workspace_id, target_user_id) do
    Repo.all(
      from moderation in WorkspaceModeration,
        where:
          moderation.workspace_id == ^workspace_id and
            moderation.target_user_id == ^target_user_id and
            moderation.type == ^@timeout_type and
            moderation.active? == true
    )
  end

  defp expire_member_timeout_with_audit(%WorkspaceModeration{} = moderation) do
    Multi.new()
    |> Multi.update(
      :moderation,
      WorkspaceModeration.end_changeset(moderation, %{
        active?: false,
        ended_at: DateTime.utc_now(:second)
      })
    )
    |> Multi.insert(:audit_event, fn %{moderation: ended_moderation} ->
      WorkspaceAuditEvent.changeset(%WorkspaceAuditEvent{}, %{
        workspace_id: ended_moderation.workspace_id,
        actor_user_id: nil,
        target_user_id: ended_moderation.target_user_id,
        event_type: "member_timeout_expired",
        metadata: %{
          "moderation_type" => ended_moderation.type,
          "expires_at" => DateTime.to_iso8601(ended_moderation.expires_at)
        }
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{moderation: moderation}} ->
        :ok =
          broadcast_workspace_moderation_changed(
            moderation.workspace_id,
            moderation.target_user_id
          )

        {:ok, moderation}

      {:error, :moderation, changeset, _changes_so_far} ->
        {:error, :invalid_moderation, changeset}

      {:error, :audit_event, changeset, _changes_so_far} ->
        {:error, :invalid_audit_event, changeset}
    end
  end

  defp timeout_expires_at(duration) do
    case Map.fetch(@timeout_duration_presets, duration) do
      {:ok, {amount, unit}} -> {:ok, DateTime.add(DateTime.utc_now(:second), amount, unit)}
      :error -> {:error, :invalid_timeout_duration}
    end
  end

  defp validate_required_reason(attrs) do
    case moderation_reason_attrs(attrs) do
      nil -> {:error, :reason_required}
      reason -> {:ok, reason}
    end
  end

  defp moderation_reason_attrs(attrs) do
    attrs
    |> get_attr(:reason)
    |> case do
      reason when is_binary(reason) ->
        reason = String.trim(reason)
        if reason == "", do: nil, else: reason

      _reason ->
        nil
    end
  end

  defp get_active_moderation(workspace_id, target_user_id, @timeout_type) do
    now = DateTime.utc_now(:second)

    Repo.one(
      from moderation in WorkspaceModeration,
        where:
          moderation.workspace_id == ^workspace_id and
            moderation.target_user_id == ^target_user_id and
            moderation.type == ^@timeout_type and
            moderation.active? == true and
            moderation.expires_at > ^now,
        limit: 1
    )
  end

  defp get_active_moderation(workspace_id, target_user_id, type) do
    Repo.get_by(WorkspaceModeration,
      workspace_id: workspace_id,
      target_user_id: target_user_id,
      type: type,
      active?: true
    )
  end

  defp fetch_active_moderation(workspace_id, target_user_id, type) do
    case get_active_moderation(workspace_id, target_user_id, type) do
      %WorkspaceModeration{} = moderation -> {:ok, moderation}
      nil -> {:error, :not_found}
    end
  end

  defp moderation_reason(%WorkspaceModeration{reason: reason}), do: reason
  defp moderation_reason(_moderation), do: nil

  defp moderation_expires_at(%WorkspaceModeration{expires_at: expires_at}), do: expires_at
  defp moderation_expires_at(_moderation), do: nil

  defp expire_due_timeout_for_target(workspace_id, target_user_id) do
    now = DateTime.utc_now(:second)

    query =
      from moderation in WorkspaceModeration,
        where:
          moderation.workspace_id == ^workspace_id and
            moderation.target_user_id == ^target_user_id and
            moderation.type == ^@timeout_type and
            moderation.active? == true and
            moderation.expires_at <= ^now,
        limit: 1

    case Repo.one(query) do
      %WorkspaceModeration{id: moderation_id} -> expire_member_timeout(moderation_id)
      nil -> {:ok, nil}
    end
  end

  defp active_mute_actions(actions, %WorkspaceMembership{} = target_membership) do
    if :mute in actions and active_mute?(target_membership) do
      Enum.map(actions, fn
        :mute -> :unmute
        action -> action
      end)
    else
      actions
    end
  end

  defp active_mute?(%WorkspaceMembership{workspace_id: workspace_id, user_id: user_id}) do
    match?(%WorkspaceModeration{}, get_active_moderation(workspace_id, user_id, @mute_type))
  end

  defp active_timeout_actions(actions, %WorkspaceMembership{} = target_membership) do
    if :timeout in actions and active_timeout?(target_membership) do
      Enum.map(actions, fn
        :timeout -> :remove_timeout
        action -> action
      end)
    else
      actions
    end
  end

  defp active_timeout?(%WorkspaceMembership{workspace_id: workspace_id, user_id: user_id}) do
    match?(%WorkspaceModeration{}, get_active_moderation(workspace_id, user_id, @timeout_type))
  end

  defp broadcast_workspace_moderation_changed(workspace_id, target_user_id) do
    Phoenix.PubSub.broadcast(
      DiscordClone.PubSub,
      workspace_moderation_topic(workspace_id),
      {:workspace_moderation_changed,
       %{workspace_id: workspace_id, target_user_id: target_user_id}}
    )
  end

  defp broadcast_workspace_access_revoked(workspace_id, target_user_id) do
    Phoenix.PubSub.broadcast(
      DiscordClone.PubSub,
      workspace_moderation_topic(workspace_id),
      {:workspace_access_revoked, %{workspace_id: workspace_id, target_user_id: target_user_id}}
    )
  end

  defp workspace_moderation_topic(workspace_id), do: "workspaces:#{workspace_id}:moderation"

  defp change_member_role_with_audit(
         %Scope{user: %User{id: actor_user_id}},
         %WorkspaceMembership{} = membership,
         role
       ) do
    from_role = membership.role

    Multi.new()
    |> Multi.update(:membership, WorkspaceMembership.role_changeset(membership, %{role: role}))
    |> Multi.insert(:audit_event, fn %{membership: updated_membership} ->
      WorkspaceAuditEvent.changeset(%WorkspaceAuditEvent{}, %{
        workspace_id: updated_membership.workspace_id,
        actor_user_id: actor_user_id,
        target_user_id: updated_membership.user_id,
        event_type: role_change_event_type(from_role, updated_membership.role),
        metadata: %{"from_role" => from_role, "to_role" => updated_membership.role}
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{membership: membership}} ->
        {:ok, membership}

      {:error, :membership, changeset, _changes_so_far} ->
        {:error, :invalid_role, changeset}

      {:error, :audit_event, changeset, _changes_so_far} ->
        {:error, :invalid_audit_event, changeset}
    end
  end

  defp role_change_event_type("member", "admin"), do: "member_role_promoted"
  defp role_change_event_type("admin", "member"), do: "member_role_demoted"

  defp role_change_event_type(from_role, to_role),
    do: "member_role_changed:#{from_role}:#{to_role}"

  defp create_channel_with_reads(%Workspace{} = workspace, attrs) do
    Multi.new()
    |> Multi.insert(
      :channel,
      Channel.create_changeset(%Channel{}, channel_attrs(workspace.id, attrs))
    )
    |> Multi.run(:channel_reads, fn _repo, %{channel: channel} ->
      case Chat.initialize_channel_reads_for_workspace_members(channel.id) do
        :ok -> {:ok, :initialized}
        {:error, reason} -> {:error, reason}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{channel: channel}} ->
        {:ok, channel}

      {:error, :channel, changeset, _changes_so_far} ->
        {:error, :invalid_channel, changeset}

      {:error, failed_operation, failed_value, changes_so_far} ->
        {:error, :channel_creation_failed, failed_operation, failed_value, changes_so_far}
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

  defp reject_owner_role_change(%WorkspaceMembership{role: @owner_role}),
    do: {:error, :owner_role_locked}

  defp reject_owner_role_change(_membership), do: :ok

  defp authorize_role_transition("member", "admin"), do: :ok
  defp authorize_role_transition("admin", "member"), do: :ok
  defp authorize_role_transition(_from_role, _to_role), do: {:error, :unsupported_role_transition}

  defp has_workspace_role?(%Scope{user: %User{id: user_id}}, %Workspace{id: workspace_id}, roles) do
    case get_workspace_membership(workspace_id, user_id) do
      {:ok, %WorkspaceMembership{role: role}} -> role in roles
      {:error, _reason} -> false
    end
  end

  defp workspace_role(%Scope{user: %User{id: user_id}}, %Workspace{id: workspace_id}) do
    case get_workspace_membership(workspace_id, user_id) do
      {:ok, %WorkspaceMembership{role: role}} -> role
      {:error, _reason} -> nil
    end
  end

  defp workspace_role(_scope, _workspace), do: nil

  defp owner_member_actions(%WorkspaceMembership{role: @owner_role}), do: []

  defp owner_member_actions(%WorkspaceMembership{role: @admin_role}) do
    [:demote_to_member, :mute, :timeout, :kick, :ban]
  end

  defp owner_member_actions(%WorkspaceMembership{role: @member_role}) do
    [:promote_to_admin, :mute, :timeout, :kick, :ban]
  end

  defp owner_member_actions(_target_membership), do: []

  defp admin_member_actions(%WorkspaceMembership{role: @owner_role}), do: []

  defp admin_member_actions(%WorkspaceMembership{role: @admin_role}) do
    [:mute, :timeout]
  end

  defp admin_member_actions(%WorkspaceMembership{role: @member_role}) do
    [:mute, :timeout, :kick, :ban]
  end

  defp admin_member_actions(_target_membership), do: []

  defp workspace_member?(workspace_id, user_id) do
    Repo.exists?(
      from membership in WorkspaceMembership,
        where: membership.workspace_id == ^workspace_id and membership.user_id == ^user_id
    )
  end
end
