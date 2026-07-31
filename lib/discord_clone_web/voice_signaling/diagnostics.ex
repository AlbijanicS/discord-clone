defmodule DiscordCloneWeb.VoiceSignaling.Diagnostics do
  @moduledoc false

  @event [:discord_clone, :voice_signaling, :operation]

  @type outcome :: :accepted | :rejected | :failed

  @type media_counts :: %{
          inbound_packet_count: non_neg_integer(),
          echoed_packet_count: non_neg_integer(),
          dropped_packet_count: non_neg_integer(),
          dropped_media_count: non_neg_integer()
        }

  @spec emit(String.t(), outcome(), keyword()) :: :ok
  def emit(operation, outcome, options \\ [])
      when operation in ["offer", "ice_candidate", "heartbeat", "connection_state"] and
             outcome in [:accepted, :rejected, :failed] do
    metadata =
      %{operation: operation, outcome: outcome}
      |> maybe_put(:error_code, Keyword.get(options, :error_code))
      |> maybe_put(:decoded_request_byte_count, Keyword.get(options, :decoded_request_byte_count))
      |> maybe_put(:connection_state, Keyword.get(options, :connection_state))

    :telemetry.execute(@event, %{}, metadata)
  end

  @spec emit_media(
          :inbound_track_admitted | :unexpected_media_dropped | :rtp_routed,
          media_counts()
        ) ::
          :ok
  def emit_media(lifecycle, counts)
      when lifecycle in [:inbound_track_admitted, :unexpected_media_dropped, :rtp_routed] do
    :telemetry.execute(@event, %{}, Map.put(counts, :media_lifecycle, lifecycle))
  end

  defp maybe_put(metadata, _key, nil), do: metadata
  defp maybe_put(metadata, key, value), do: Map.put(metadata, key, value)
end
