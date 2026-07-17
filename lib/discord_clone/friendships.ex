defmodule DiscordClone.Friendships do
  @moduledoc """
  Owns global Friend Request and Friendship workflows.

  User discovery is deliberately limited to exact normalized usernames.
  """

  import Ecto.Query

  alias DiscordClone.Accounts.{Scope, User}
  alias DiscordClone.Friendships.Relationship
  alias DiscordClone.Repo

  @spec send_friend_request(term(), map()) ::
          {:ok, %{relationship: Relationship.t(), user: User.t()}}
          | {:error, :unauthenticated | :invalid_username | :unknown_user | :self_request}
          | {:error, Ecto.Changeset.t()}
  def send_friend_request(%Scope{user: %User{} = requester}, attrs) when is_map(attrs) do
    with {:ok, username} <- normalized_username(attrs),
         %User{} = target <- Repo.get_by(User, username: username),
         :ok <- reject_self(requester, target) do
      {user_low_id, user_high_id} = canonical_pair(requester.id, target.id)

      conflict_query =
        from relationship in Relationship,
          update: [
            set: [
              status:
                fragment(
                  "CASE WHEN ? = 'accepted' OR ? <> EXCLUDED.requested_by_user_id THEN 'accepted' ELSE 'pending' END",
                  relationship.status,
                  relationship.requested_by_user_id
                ),
              accepted_at:
                fragment(
                  "CASE WHEN ? = 'accepted' THEN ? WHEN ? <> EXCLUDED.requested_by_user_id THEN statement_timestamp() ELSE NULL END",
                  relationship.status,
                  relationship.accepted_at,
                  relationship.requested_by_user_id
                ),
              updated_at: fragment("statement_timestamp()")
            ]
          ]

      result =
        %Relationship{}
        |> Relationship.create_changeset(%{
          user_low_id: user_low_id,
          user_high_id: user_high_id,
          requested_by_user_id: requester.id
        })
        |> Repo.insert(
          on_conflict: conflict_query,
          conflict_target: [:user_low_id, :user_high_id],
          returning: true
        )

      case result do
        {:ok, relationship} -> {:ok, %{relationship: relationship, user: target}}
        {:error, changeset} -> {:error, changeset}
      end
    else
      nil -> {:error, :unknown_user}
      {:error, reason} -> {:error, reason}
    end
  end

  def send_friend_request(%Scope{user: %User{}}, _attrs), do: {:error, :invalid_username}
  def send_friend_request(_scope, _attrs), do: {:error, :unauthenticated}

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

    Enum.map(requests, &request_entry(&1, user_id))
  end

  defp requests_in_direction(query, user_id, :incoming) do
    from relationship in query, where: relationship.requested_by_user_id != ^user_id
  end

  defp requests_in_direction(query, user_id, :outgoing) do
    from relationship in query, where: relationship.requested_by_user_id == ^user_id
  end

  defp request_entry(%Relationship{user_low_id: user_id} = relationship, user_id) do
    %{relationship: relationship, user: relationship.user_high}
  end

  defp request_entry(%Relationship{} = relationship, _user_id) do
    %{relationship: relationship, user: relationship.user_low}
  end
end
