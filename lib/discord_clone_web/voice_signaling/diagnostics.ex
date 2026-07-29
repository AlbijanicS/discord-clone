defmodule DiscordCloneWeb.VoiceSignaling.Diagnostics do
  @moduledoc false

  @event [:discord_clone, :voice_signaling, :operation]

  @type outcome :: :accepted | :rejected | :failed

  @spec emit(String.t(), outcome(), keyword()) :: :ok
  def emit(operation, outcome, options \\ [])
      when operation in ["offer", "ice_candidate", "heartbeat"] and
             outcome in [:accepted, :rejected, :failed] do
    metadata =
      %{operation: operation, outcome: outcome}
      |> maybe_put(:error_code, Keyword.get(options, :error_code))
      |> maybe_put(:decoded_request_byte_count, Keyword.get(options, :decoded_request_byte_count))

    :telemetry.execute(@event, %{}, metadata)
  end

  defp maybe_put(metadata, _key, nil), do: metadata
  defp maybe_put(metadata, key, value), do: Map.put(metadata, key, value)
end
