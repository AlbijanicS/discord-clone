defmodule DiscordCloneWeb.VoiceSocket do
  use Phoenix.Socket

  alias DiscordClone.Accounts
  alias DiscordClone.Accounts.Scope
  alias DiscordCloneWeb.UserAuth

  channel "voice:*", DiscordCloneWeb.VoiceChannel

  @impl true
  def connect(_params, socket, %{session: %{"user_token" => user_token}}) do
    case Accounts.get_user_by_session_token(user_token) do
      {user, _token_inserted_at} ->
        {:ok,
         socket
         |> assign(:current_scope, Scope.for_user(user))
         |> assign(:user_session_topic, UserAuth.user_session_topic(user_token))}

      nil ->
        :error
    end
  end

  def connect(_params, _socket, %{session: _session}), do: :error

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: socket.assigns.user_session_topic
end
