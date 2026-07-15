defmodule DiscordCloneWeb.ActivityLive do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias DiscordClone.Chat

  def on_mount(:assign_unread_count, _params, _session, socket) do
    {:ok, unread_count} = Chat.unread_activity_count(socket.assigns.current_scope)
    {:cont, assign(socket, :unread_activity_count, unread_count)}
  end
end
