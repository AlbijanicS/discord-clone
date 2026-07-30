defmodule DiscordCloneWeb.VoiceSignaling.Configuration do
  @moduledoc false

  @localhost_ice_servers []

  @spec ice_servers() :: []
  def ice_servers, do: @localhost_ice_servers
end
