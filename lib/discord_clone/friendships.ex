defmodule DiscordClone.Friendships do
  @moduledoc """
  Owns global Friend Request and Friendship workflows.

  User discovery is deliberately limited to exact normalized usernames.
  """

  import Ecto.Query

  alias DiscordClone.Accounts.{Scope, User}
  alias DiscordClone.Friendships.Relationship
  alias DiscordClone.Repo
  alias DiscordClone.Workspaces

  @type mutation_error :: :unauthenticated | :unauthorized | :not_found | :stale_state

  @doc "Subscribes the scoped User to private Friendship change facts."
  @spec subscribe(term()) :: :ok | {:error, :unauthenticated}
  def subscribe(%Scope{user: %User{id: user_id}}) do
    Phoenix.PubSub.subscribe(DiscordClone.PubSub, user_topic(user_id))
  end

  def subscribe(_scope), do: {:error, :unauthenticated}

  @spec send_friend_request(term(), map()) ::
          {:ok, %{relationship: Relationship.t(), user: User.t()}}
          | {:error, :unauthenticated | :invalid_username | :unknown_user | :self_request}
          | {:error, Ecto.Changeset.t()}
  def send_friend_request(%Scope{user: %User{} = requester}, attrs) when is_map(attrs) do
    with {:ok, username} <- normalized_username(attrs),
         %User{} = target <- Repo.get_by(User, username: username),
         :ok <- reject_self(requester, target) do
      persist_friend_request(requester, target)
    else
      nil -> {:error, :unknown_user}
      {:error, reason} -> {:error, reason}
    end
  end

  def send_friend_request(%Scope{user: %User{}}, _attrs), do: {:error, :invalid_username}
  def send_friend_request(_scope, _attrs), do: {:error, :unauthenticated}

  @doc "Sends a Friend Request to a known Workspace Member after re-authorizing membership."
  @spec send_friend_request_to_workspace_member(term(), term(), term()) ::
          {:ok, %{relationship: Relationship.t(), user: User.t()}}
          | {:error, :unauthenticated | :unauthorized | :not_found | :self_request}
          | {:error, Ecto.Changeset.t()}
  def send_friend_request_to_workspace_member(
        %Scope{user: %User{} = requester},
        workspace_id,
        target_user_id
      ) do
    with {:ok, %User{} = target} <-
           Workspaces.fetch_member_user(
             %Scope{user: requester},
             workspace_id,
             target_user_id
           ),
         :ok <- reject_self(requester, target) do
      persist_friend_request(requester, target)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def send_friend_request_to_workspace_member(_scope, _workspace_id, _target_user_id),
    do: {:error, :unauthenticated}

  @doc "Returns a relationship only when the scoped User belongs to its pair."
  @spec get_relationship(term(), term()) ::
          {:ok, Relationship.t()} | {:error, :unauthenticated | :not_found}
  def get_relationship(%Scope{user: %User{id: user_id}}, relationship_id) do
    with {:ok, relationship_id} <- Ecto.UUID.cast(relationship_id),
         %Relationship{} = relationship <-
           Repo.one(
             from relationship in Relationship,
               where:
                 relationship.id == ^relationship_id and
                   (relationship.user_low_id == ^user_id or
                      relationship.user_high_id == ^user_id)
           ) do
      {:ok, relationship}
    else
      _other -> {:error, :not_found}
    end
  end

  def get_relationship(_scope, _relationship_id), do: {:error, :unauthenticated}

  @doc "Accepts an incoming Friend Request for the scoped User."
  @spec accept_friend_request(term(), term()) ::
          {:ok, Relationship.t()} | {:error, mutation_error()}
  def accept_friend_request(%Scope{user: %User{id: user_id}}, relationship_id) do
    update_relationship(user_id, relationship_id, :accept)
  end

  def accept_friend_request(_scope, _relationship_id), do: {:error, :unauthenticated}

  @doc "Declines an incoming Friend Request for the scoped User."
  @spec decline_friend_request(term(), term()) :: :ok | {:error, mutation_error()}
  def decline_friend_request(%Scope{user: %User{id: user_id}}, relationship_id) do
    delete_relationship(user_id, relationship_id, :decline)
  end

  def decline_friend_request(_scope, _relationship_id), do: {:error, :unauthenticated}

  @doc "Cancels an outgoing Friend Request for the scoped User."
  @spec cancel_friend_request(term(), term()) :: :ok | {:error, mutation_error()}
  def cancel_friend_request(%Scope{user: %User{id: user_id}}, relationship_id) do
    delete_relationship(user_id, relationship_id, :cancel)
  end

  def cancel_friend_request(_scope, _relationship_id), do: {:error, :unauthenticated}

  @doc "Removes an accepted Friendship for either User in the pair."
  @spec remove_friend(term(), term()) :: :ok | {:error, mutation_error()}
  def remove_friend(%Scope{user: %User{id: user_id}}, relationship_id) do
    delete_relationship(user_id, relationship_id, :remove)
  end

  def remove_friend(_scope, _relationship_id), do: {:error, :unauthenticated}

  @doc "Lists pending Friend Requests received by the scoped User."
  @spec list_incoming_requests(term()) ::
          {:ok, [%{relationship: Relationship.t(), user: User.t()}]}
          | {:error, :unauthenticated}
  def list_incoming_requests(%Scope{user: %User{id: user_id}}) do
    {:ok, list_pending_requests(user_id, :incoming)}
  end

  def list_incoming_requests(_scope), do: {:error, :unauthenticated}

  @doc "Lists pending Friend Requests sent by the scoped User."
  @spec list_outgoing_requests(term()) ::
          {:ok, [%{relationship: Relationship.t(), user: User.t()}]}
          | {:error, :unauthenticated}
  def list_outgoing_requests(%Scope{user: %User{id: user_id}}) do
    {:ok, list_pending_requests(user_id, :outgoing)}
  end

  def list_outgoing_requests(_scope), do: {:error, :unauthenticated}

  @doc "Lists accepted mutual Friendships for the scoped User."
  @spec list_friends(term()) ::
          {:ok, [%{relationship: Relationship.t(), user: User.t()}]}
          | {:error, :unauthenticated}
  def list_friends(%Scope{user: %User{id: user_id}}) do
    friendships =
      Relationship
      |> where(
        [relationship],
        relationship.status == :accepted and
          (relationship.user_low_id == ^user_id or relationship.user_high_id == ^user_id)
      )
      |> order_by([relationship], asc: relationship.accepted_at, asc: relationship.id)
      |> preload([:user_low, :user_high])
      |> Repo.all()
      |> Enum.map(&relationship_entry(&1, user_id))

    {:ok, friendships}
  end

  def list_friends(_scope), do: {:error, :unauthenticated}

  defp normalized_username(attrs) do
    case Map.get(attrs, :username) || Map.get(attrs, "username") do
      username when is_binary(username) ->
        case username |> String.trim() |> String.downcase() do
          "" -> {:error, :invalid_username}
          normalized -> {:ok, normalized}
        end

      _other ->
        {:error, :invalid_username}
    end
  end

  defp reject_self(%User{id: id}, %User{id: id}), do: {:error, :self_request}
  defp reject_self(%User{}, %User{}), do: :ok

  defp canonical_pair(first_id, second_id) do
    if first_id < second_id, do: {first_id, second_id}, else: {second_id, first_id}
  end

  defp persist_friend_request(requester, target) do
    {user_low_id, user_high_id} = canonical_pair(requester.id, target.id)
    candidate_id = Ecto.UUID.generate()

    transaction_result =
      Repo.transaction(fn ->
        candidate =
          %Relationship{id: candidate_id}
          |> Relationship.create_changeset(%{
            user_low_id: user_low_id,
            user_high_id: user_high_id,
            requested_by_user_id: requester.id
          })
          |> Repo.insert(
            on_conflict: :nothing,
            conflict_target: [:user_low_id, :user_high_id]
          )
          |> case do
            {:ok, relationship} -> relationship
            {:error, changeset} -> Repo.rollback(changeset)
          end

        relationship =
          Repo.one!(
            from relationship in Relationship,
              where:
                relationship.user_low_id == ^user_low_id and
                  relationship.user_high_id == ^user_high_id,
              lock: "FOR UPDATE"
          )

        cond do
          relationship.id == candidate.id ->
            {relationship, :requested}

          relationship.status == :pending and
              relationship.requested_by_user_id != requester.id ->
            relationship =
              relationship
              |> Relationship.accept_changeset()
              |> Repo.update!()

            {relationship, :accepted}

          true ->
            {relationship, nil}
        end
      end)

    case transaction_result do
      {:ok, {relationship, action}} ->
        if action, do: :ok = broadcast_change(relationship, action)
        {:ok, %{relationship: relationship, user: target}}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp pending_requests_for(user_id) do
    from relationship in Relationship,
      where:
        relationship.status == :pending and
          (relationship.user_low_id == ^user_id or relationship.user_high_id == ^user_id)
  end

  defp list_pending_requests(user_id, direction) do
    requests =
      user_id
      |> pending_requests_for()
      |> requests_in_direction(user_id, direction)
      |> order_by([relationship],
        asc: relationship.inserted_at,
        asc: relationship.id
      )
      |> preload([:user_low, :user_high, :requested_by_user])
      |> Repo.all()

    Enum.map(requests, &relationship_entry(&1, user_id))
  end

  defp requests_in_direction(query, user_id, :incoming) do
    from relationship in query, where: relationship.requested_by_user_id != ^user_id
  end

  defp requests_in_direction(query, user_id, :outgoing) do
    from relationship in query, where: relationship.requested_by_user_id == ^user_id
  end

  defp relationship_entry(%Relationship{user_low_id: user_id} = relationship, user_id) do
    %{relationship: relationship, user: relationship.user_high}
  end

  defp relationship_entry(%Relationship{} = relationship, _user_id) do
    %{relationship: relationship, user: relationship.user_low}
  end

  defp update_relationship(user_id, relationship_id, operation) do
    case mutate_relationship(
           user_id,
           relationship_id,
           operation,
           fn relationship ->
             case relationship |> Relationship.accept_changeset() |> Repo.update() do
               {:ok, accepted} -> accepted
               {:error, changeset} -> Repo.rollback(changeset)
             end
           end
         ) do
      {:ok, relationship} ->
        :ok = broadcast_change(relationship, operation_action(operation))
        {:ok, relationship}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp delete_relationship(user_id, relationship_id, operation) do
    case mutate_relationship(
           user_id,
           relationship_id,
           operation,
           fn relationship ->
             Repo.delete!(relationship)
           end
         ) do
      {:ok, relationship} ->
        :ok = broadcast_change(relationship, operation_action(operation))
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp mutate_relationship(user_id, relationship_id, operation, mutation) do
    %{expected_status: expected_status, actor_role: actor_role} = operation_policy(operation)

    with {:ok, relationship_id} <- Ecto.UUID.cast(relationship_id) do
      Repo.transaction(fn ->
        relationship =
          Repo.one(
            from relationship in Relationship,
              where:
                relationship.id == ^relationship_id and
                  (relationship.user_low_id == ^user_id or
                     relationship.user_high_id == ^user_id),
              lock: "FOR UPDATE"
          )

        cond do
          is_nil(relationship) ->
            Repo.rollback(:not_found)

          relationship.status != expected_status ->
            Repo.rollback(:stale_state)

          not authorized_role?(relationship, user_id, actor_role) ->
            Repo.rollback(:unauthorized)

          true ->
            mutation.(relationship)
        end
      end)
    else
      :error -> {:error, :not_found}
    end
  end

  defp authorized_role?(_relationship, _user_id, :either_friend), do: true

  defp authorized_role?(relationship, user_id, :requester) do
    relationship.requested_by_user_id == user_id
  end

  defp authorized_role?(relationship, user_id, :recipient) do
    relationship.requested_by_user_id != user_id
  end

  defp operation_policy(:accept),
    do: %{expected_status: :pending, actor_role: :recipient, action: :accepted}

  defp operation_policy(:decline),
    do: %{expected_status: :pending, actor_role: :recipient, action: :declined}

  defp operation_policy(:cancel),
    do: %{expected_status: :pending, actor_role: :requester, action: :cancelled}

  defp operation_policy(:remove),
    do: %{expected_status: :accepted, actor_role: :either_friend, action: :removed}

  defp operation_action(operation), do: operation_policy(operation).action

  defp broadcast_change(%Relationship{} = relationship, action) do
    event =
      {:friendships_changed,
       %{
         action: action,
         relationship_id: relationship.id
       }}

    [relationship.user_low_id, relationship.user_high_id]
    |> Enum.each(fn user_id ->
      :ok = Phoenix.PubSub.broadcast(DiscordClone.PubSub, user_topic(user_id), event)
    end)

    :ok
  end

  defp user_topic(user_id), do: "friendships:user:#{user_id}"
end
