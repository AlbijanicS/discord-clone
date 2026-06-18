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
        conn
        |> maybe_put_already_member_flash(landing)
        |> redirect(to: ~p"/workspaces/#{landing.workspace_id}/channels/#{landing.channel_id}")

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> render(:not_found)
    end
  end

  defp maybe_put_already_member_flash(conn, %{already_member?: true}),
    do: put_flash(conn, :info, "You're already in this workspace.")

  defp maybe_put_already_member_flash(conn, _landing), do: conn
end
