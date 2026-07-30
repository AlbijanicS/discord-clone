defmodule DiscordCloneWeb.VoiceSignaling.PeerConnection do
  @moduledoc false

  alias DiscordCloneWeb.VoiceSignaling.Configuration
  alias ExWebRTC.{ICECandidate, PeerConnection, SessionDescription}

  defstruct [:peer_connection, remote_description?: false]

  @type t :: %__MODULE__{peer_connection: pid(), remote_description?: boolean()}

  @spec start() :: {:ok, t()} | {:error, :peer_connection_unavailable}
  def start do
    case PeerConnection.start_link(ice_servers: Configuration.ice_servers()) do
      {:ok, peer_connection} -> {:ok, %__MODULE__{peer_connection: peer_connection}}
      {:error, _reason} -> {:error, :peer_connection_unavailable}
    end
  end

  @spec accept_offer(t(), map()) :: {:ok, map(), t()} | {:error, :negotiation_failed}
  def accept_offer(%__MODULE__{} = state, description) do
    with :ok <-
           PeerConnection.set_remote_description(
             state.peer_connection,
             SessionDescription.from_json(description)
           ),
         {:ok, answer} <- PeerConnection.create_answer(state.peer_connection),
         :ok <- PeerConnection.set_local_description(state.peer_connection, answer) do
      {:ok, SessionDescription.to_json(answer), %{state | remote_description?: true}}
    else
      {:error, _reason} -> {:error, :negotiation_failed}
    end
  rescue
    _error -> {:error, :negotiation_failed}
  end

  @spec add_ice_candidate(t(), map()) :: :ok | {:error, :candidate_rejected}
  def add_ice_candidate(%__MODULE__{remote_description?: true} = state, candidate) do
    case PeerConnection.add_ice_candidate(
           state.peer_connection,
           ICECandidate.from_json(candidate)
         ) do
      :ok -> :ok
      {:error, _reason} -> {:error, :candidate_rejected}
    end
  rescue
    _error -> {:error, :candidate_rejected}
  end

  def add_ice_candidate(%__MODULE__{}, _candidate), do: {:error, :candidate_rejected}

  @spec signal(t(), term()) ::
          {:ice_candidate, map()} | {:connection_state_change, atom()} | :ignore
  def signal(
        %__MODULE__{peer_connection: peer_connection},
        {:ex_webrtc, peer_connection, {:ice_candidate, candidate}}
      ) do
    {:ice_candidate, ICECandidate.to_json(candidate)}
  end

  def signal(
        %__MODULE__{peer_connection: peer_connection},
        {:ex_webrtc, peer_connection, {:connection_state_change, state}}
      )
      when state in [:new, :connecting, :connected, :disconnected, :failed, :closed] do
    {:connection_state_change, state}
  end

  def signal(%__MODULE__{}, _message), do: :ignore

  @spec stop(t()) :: :ok
  def stop(%__MODULE__{peer_connection: peer_connection}) do
    PeerConnection.stop(peer_connection)
  catch
    :exit, _reason -> :ok
  end
end
