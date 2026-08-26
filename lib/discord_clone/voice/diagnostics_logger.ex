defmodule DiscordClone.Voice.DiagnosticsLogger do
  @moduledoc false

  use GenServer

  require Logger

  @event [:discord_clone, :voice_signaling, :operation]
  @handler_id {__MODULE__, :voice_diagnostics}

  def start_link(_options), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    case :telemetry.attach(@handler_id, @event, &__MODULE__.handle_event/4, nil) do
      :ok -> {:ok, nil}
      {:error, :already_exists} -> {:ok, nil}
    end
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach(@handler_id)
    :ok
  end

  @doc false
  def handle_event(
        @event,
        _measurements,
        %{operation: "connection_state", outcome: outcome, connection_state: connection_state},
        _config
      )
      when outcome in [:accepted, :rejected, :failed] and
             connection_state in [:new, :connecting, :connected, :disconnected, :failed, :closed] do
    Logger.log(connection_log_level(connection_state), fn ->
      "Voice diagnostic operation=connection_state outcome=#{outcome} " <>
        "connection_state=#{connection_state}"
    end)
  end

  def handle_event(
        @event,
        %{duration_ms: duration_ms},
        %{
          operation: "ice_route",
          ice_mode: ice_mode,
          endpoint: endpoint,
          route_category: route_category,
          protocol: protocol,
          outcome: outcome
        },
        _config
      )
      when is_integer(duration_ms) and duration_ms in 0..60_000 and
             ice_mode in [:disabled, :standard, :turn_only] and endpoint in [:browser, :server] and
             route_category in [:host_direct, :reflexive_direct, :turn_relay, :unknown] and
             protocol in [:udp, :tcp, :tls, :unknown] and
             outcome in [:accepted, :rejected, :failed] do
    Logger.log(outcome_log_level(outcome), fn ->
      "Voice diagnostic operation=ice_route outcome=#{outcome} endpoint=#{endpoint} " <>
        "ice_mode=#{ice_mode} route_category=#{route_category} protocol=#{protocol} " <>
        "duration_ms=#{duration_ms}"
    end)
  end

  def handle_event(@event, _measurements, _metadata, _config), do: :ok

  defp connection_log_level(connection_state)
       when connection_state in [:disconnected, :failed, :closed],
       do: :warning

  defp connection_log_level(_healthy_state), do: :info

  defp outcome_log_level(outcome) when outcome in [:rejected, :failed], do: :warning
  defp outcome_log_level(:accepted), do: :info
end
