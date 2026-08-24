defmodule DiscordClone.Voice.DeploymentCapacity do
  @moduledoc false

  @max_active_sessions 20
  @udp_port_range 50_000..50_031

  @spec max_active_sessions() :: pos_integer()
  def max_active_sessions, do: @max_active_sessions

  @spec valid_configuration?(term(), term()) :: boolean()
  def valid_configuration?(@udp_port_range, @max_active_sessions) do
    Range.size(@udp_port_range) >= @max_active_sessions
  end

  def valid_configuration?(_udp_port_range, _max_active_sessions), do: false
end
