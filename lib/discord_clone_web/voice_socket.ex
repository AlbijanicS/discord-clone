defmodule DiscordCloneWeb.VoiceSocket do
  use Phoenix.Socket

  alias DiscordClone.Accounts
  alias DiscordClone.Accounts.Scope

  channel "voice:*", DiscordCloneWeb.VoiceChannel

  @impl true
  def connect(_params, socket, %{session: %{"user_token" => user_token}}) do
    case Accounts.get_user_by_session_token(user_token) do
      {user, _token_inserted_at} -> {:ok, assign(socket, :current_scope, Scope.for_user(user))}
      nil -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(_socket), do: nil
end
