defmodule DiscordCloneWeb.VoiceSignaling.PeerConnection do
  @moduledoc false

  alias DiscordClone.Voice.PeerConnection, as: RuntimePeerConnection

  @command_timeout_ms 5_000

  defstruct [
    :peer_connection,
    :expected_inbound_track_id,
    :outbound_track_id,
    remote_description?: false
  ]

  @type t :: %__MODULE__{
          peer_connection: pid(),
          expected_inbound_track_id: integer() | nil,
          outbound_track_id: integer() | nil,
          remote_description?: boolean()
        }

  @spec start(keyword()) :: {:ok, t()} | {:error, :peer_connection_unavailable}
  def start(options \\ []) do
    with {:ok, state} <- RuntimePeerConnection.start(options) do
      {:ok, from_runtime(state)}
    end
  end

  @spec accept_offer(t(), map(), timeout()) ::
          {:ok, map(), t()} | {:error, :negotiation_failed}
  def accept_offer(state, description, timeout \\ @command_timeout_ms) do
    with {:ok, answer, state} <-
           RuntimePeerConnection.accept_offer(to_runtime(state), description, timeout) do
      {:ok, answer, from_runtime(state)}
    end
  end

  @spec add_ice_candidate(t(), map(), timeout()) :: :ok | {:error, :candidate_rejected}
  def add_ice_candidate(state, candidate, timeout \\ @command_timeout_ms),
    do: RuntimePeerConnection.add_ice_candidate(to_runtime(state), candidate, timeout)

  @spec route_media(t(), term()) ::
          {:accepted_inbound_track | :echoed_rtp | :dropped_rtp | :dropped_media | :ignore, t()}
  def route_media(state, message) do
    case RuntimePeerConnection.route_media(to_runtime(state), message) do
      {outcome, state} -> {outcome, from_runtime(state)}
    end
  end

  @spec signal(t(), term()) ::
          {:ice_candidate, map()}
          | {:connection_state_change, atom()}
          | :end_of_candidates
          | :ignore
  def signal(state, message), do: RuntimePeerConnection.signal(to_runtime(state), message)

  @spec stop(t()) :: :ok
  def stop(state), do: RuntimePeerConnection.stop(to_runtime(state))

  defp to_runtime(state), do: struct(RuntimePeerConnection, Map.from_struct(state))
  defp from_runtime(state), do: struct(__MODULE__, Map.from_struct(state))
end
