defmodule DiscordCloneWeb.InviteController do
  use DiscordCloneWeb, :controller

  alias DiscordClone.Workspaces

  def show(conn, %{"code" => code}) do
    case Workspaces.preview_workspace_invite(conn.assigns.current_scope, code) do
      {:ok, preview} ->
        render(conn, :show, preview: preview)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> render(:not_found)
    end
  end

  def accept(conn, %{"code" => code}) do
    case Workspaces.accept_workspace_invite(conn.assigns.current_scope, code) do
      {:ok, landing} ->
        redirect(conn, to: ~p"/workspaces/#{landing.workspace_id}/channels/#{landing.channel_id}")

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> render(:not_found)
    end
  end
end
