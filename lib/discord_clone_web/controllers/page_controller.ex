defmodule DiscordCloneWeb.PageController do
  use DiscordCloneWeb, :controller

  alias DiscordClone.Accounts.Scope

  def home(conn, _params) do
    case conn.assigns.current_scope do
      %Scope{user: %DiscordClone.Accounts.User{}} ->
        redirect(conn, to: ~p"/workspaces")

      _scope ->
        render(conn, :home)
    end
  end
end
