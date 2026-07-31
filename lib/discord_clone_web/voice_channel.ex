defmodule DiscordCloneWeb.VoiceChannel do
  use DiscordCloneWeb, :channel

  alias DiscordClone.Workspaces
  alias DiscordCloneWeb.VoiceSignaling.{Diagnostics, FakeHeartbeat, PeerConnection, RealMessage}

  @max_accepted_candidates 64
  @max_pending_candidates 16
  @max_pending_candidate_bytes @max_pending_candidates * 8 * 1024

  @impl true
  def join("voice:" <> voice_channel_id, _params, socket) do
    case Workspaces.authorize_voice_channel_for_signaling(
           socket.assigns.current_scope,
           voice_channel_id
         ) do
      {:ok, _voice_channel} ->
        with {:ok, peer_connection} <- PeerConnection.start() do
          signaling_session_id = new_signaling_session_id()

          {:ok, %{signaling_session_id: signaling_session_id},
           socket
           |> assign(:signaling_session_id, signaling_session_id)
           |> assign(:peer_connection, peer_connection)
           |> assign(:negotiation_id, nil)
           |> assign(:pending_candidates, [])
           |> assign(:accepted_candidate_count, 0)
           |> assign(:media_counts, empty_media_counts())}
        else
          {:error, :peer_connection_unavailable} -> {:error, %{reason: "unavailable"}}
        end

      {:error, :not_found} ->
        {:error, %{reason: "not_found"}}
    end
  end

  def join(_topic, _params, _socket), do: {:error, %{reason: "not_found"}}

  @impl true
  def handle_in("offer", params, socket) do
    with :ok <- validate_signaling_session_id(params, socket),
         {:ok, offer} <- RealMessage.offer(params),
         :ok <- accept_new_negotiation?(socket, offer.negotiation_id),
         {:ok, answer, peer_connection} <-
           PeerConnection.accept_offer(socket.assigns.peer_connection, offer.description) do
      {peer_connection, accepted_candidate_count} =
        apply_pending_candidates(peer_connection, socket, offer.negotiation_id)

      Diagnostics.emit("offer", :accepted, decoded_request_byte_count: offer.byte_count)

      {:reply,
       {:ok,
        %{
          signaling_session_id: socket.assigns.signaling_session_id,
          negotiation_id: offer.negotiation_id,
          description: answer
        }},
       socket
       |> assign(:peer_connection, peer_connection)
       |> assign(:negotiation_id, offer.negotiation_id)
       |> assign(:pending_candidates, [])
       |> assign(:accepted_candidate_count, accepted_candidate_count)}
    else
      :invalid_session ->
        reject("offer", "invalid_request", decoded_request_byte_count(params), socket)

      {:error, :negotiation_failed} ->
        reject_terminal_offer(decoded_request_byte_count(params), socket)

      {:error, error_code} ->
        reject("offer", error_code, decoded_request_byte_count(params), socket)
    end
  end

  def handle_in("ice_candidate", params, socket) do
    case {validate_signaling_session_id(params, socket), RealMessage.ice_candidate(params)} do
      {:ok, {:end_of_candidates, marker}} ->
        with :ok <- current_negotiation?(socket, marker.negotiation_id) do
          reject("ice_candidate", "end_of_candidates_unsupported", marker.byte_count, socket)
        else
          {:error, error_code} -> reject("ice_candidate", error_code, marker.byte_count, socket)
        end

      {:ok, {:ok, ice}} ->
        case negotiation_status(socket, ice.negotiation_id) do
          :pending -> queue_candidate(socket, ice)
          :current -> add_candidate(socket, ice)
          :mismatched -> reject("ice_candidate", "invalid_negotiation", ice.byte_count, socket)
        end

      {:invalid_session, _message} ->
        reject("ice_candidate", "invalid_request", decoded_request_byte_count(params), socket)

      {:ok, {:error, error_code}} ->
        reject("ice_candidate", error_code, decoded_request_byte_count(params), socket)
    end
  end

  def handle_in("heartbeat", params, socket) do
    byte_count = decoded_request_byte_count(params)

    with :ok <- validate_signaling_session_id(params, socket),
         {:ok, heartbeat} <- FakeHeartbeat.validate(params) do
      Diagnostics.emit("heartbeat", :accepted, decoded_request_byte_count: byte_count)

      {:reply,
       {:ok,
        %{
          signaling_session_id: socket.assigns.signaling_session_id,
          label: "fake-heartbeat-ack",
          sequence: heartbeat.sequence
        }}, socket}
    else
      :invalid_session -> reject("heartbeat", "invalid_request", byte_count, socket)
      {:error, _errors} -> reject("heartbeat", "invalid_heartbeat", byte_count, socket)
    end
  end

  def handle_in(_event, _params, socket),
    do: {:reply, {:error, %{reason: "unsupported_event"}}, socket}

  @impl true
  def handle_info(message, socket) do
    case PeerConnection.route_media(socket.assigns.peer_connection, message) do
      {:ignore, peer_connection} ->
        handle_peer_signal(peer_connection, message, socket)

      {outcome, peer_connection} ->
        {:noreply, record_media_outcome(socket, peer_connection, outcome)}
    end
  end

  defp handle_peer_signal(peer_connection, message, socket) do
    case PeerConnection.signal(peer_connection, message) do
      {:ice_candidate, candidate} when is_binary(socket.assigns.negotiation_id) ->
        push(socket, "ice_candidate", %{
          signaling_session_id: socket.assigns.signaling_session_id,
          negotiation_id: socket.assigns.negotiation_id,
          candidate: candidate
        })

        {:noreply, socket}

      :end_of_candidates when is_binary(socket.assigns.negotiation_id) ->
        push(socket, "ice_candidate", %{
          signaling_session_id: socket.assigns.signaling_session_id,
          negotiation_id: socket.assigns.negotiation_id,
          end_of_candidates: true
        })

        Diagnostics.emit("ice_candidate", :accepted, decoded_request_byte_count: 0)
        {:noreply, socket}

      {:connection_state_change, state} ->
        Diagnostics.emit("connection_state", :accepted, connection_state: state)
        {:noreply, socket}

      _other ->
        {:noreply, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if peer_connection = socket.assigns[:peer_connection] do
      PeerConnection.stop(peer_connection)
    end

    :ok
  end

  defp accept_new_negotiation?(%{assigns: %{negotiation_id: nil}}, _negotiation_id), do: :ok

  defp accept_new_negotiation?(_socket, _negotiation_id),
    do: {:error, "negotiation_already_active"}

  defp current_negotiation?(%{assigns: %{negotiation_id: negotiation_id}}, negotiation_id)
       when is_binary(negotiation_id), do: :ok

  defp current_negotiation?(_socket, _negotiation_id), do: {:error, "invalid_negotiation"}

  defp negotiation_status(%{assigns: %{negotiation_id: nil}}, _negotiation_id), do: :pending

  defp negotiation_status(socket, negotiation_id) do
    if current_negotiation?(socket, negotiation_id) == :ok, do: :current, else: :mismatched
  end

  defp queue_candidate(socket, ice) do
    pending_candidates = socket.assigns.pending_candidates

    if length(pending_candidates) < @max_pending_candidates and
         Enum.sum(Enum.map(pending_candidates, & &1.byte_count)) + ice.byte_count <=
           @max_pending_candidate_bytes do
      Diagnostics.emit("ice_candidate", :accepted, decoded_request_byte_count: ice.byte_count)

      {:reply, {:ok, %{negotiation_id: ice.negotiation_id}},
       assign(socket, :pending_candidates, [ice | pending_candidates])}
    else
      reject("ice_candidate", "pending_candidate_limit_reached", ice.byte_count, socket)
    end
  end

  defp add_candidate(socket, ice) do
    with :ok <- under_candidate_limit?(socket),
         :ok <- PeerConnection.add_ice_candidate(socket.assigns.peer_connection, ice.candidate) do
      Diagnostics.emit("ice_candidate", :accepted, decoded_request_byte_count: ice.byte_count)

      {:reply, {:ok, %{negotiation_id: ice.negotiation_id}},
       assign(socket, :accepted_candidate_count, socket.assigns.accepted_candidate_count + 1)}
    else
      {:error, error_code} -> reject("ice_candidate", error_code, ice.byte_count, socket)
    end
  end

  defp apply_pending_candidates(peer_connection, socket, negotiation_id) do
    socket.assigns.pending_candidates
    |> Enum.filter(&(&1.negotiation_id == negotiation_id))
    |> Enum.reverse()
    |> Enum.reduce({peer_connection, 0}, fn ice, {peer_connection, accepted_count} ->
      case PeerConnection.add_ice_candidate(peer_connection, ice.candidate) do
        :ok -> {peer_connection, accepted_count + 1}
        {:error, _error_code} -> {peer_connection, accepted_count}
      end
    end)
  end

  defp under_candidate_limit?(%{assigns: %{accepted_candidate_count: count}})
       when count < @max_accepted_candidates, do: :ok

  defp under_candidate_limit?(_socket), do: {:error, "candidate_limit_reached"}

  defp reject(operation, error_code, byte_count, socket) do
    Diagnostics.emit(operation, :rejected,
      error_code: error_code,
      decoded_request_byte_count: byte_count
    )

    {:reply, {:error, %{reason: error_code}}, socket}
  end

  defp reject_terminal_offer(byte_count, socket) do
    Diagnostics.emit("offer", :rejected,
      error_code: "negotiation_failed",
      decoded_request_byte_count: byte_count
    )

    {:stop, :normal, {:error, %{reason: "negotiation_failed"}}, socket}
  end

  defp decoded_request_byte_count(params) do
    case Jason.encode(params) do
      {:ok, encoded_params} -> byte_size(encoded_params)
      {:error, _reason} -> nil
    end
  end

  defp validate_signaling_session_id(%{"signaling_session_id" => signaling_session_id}, socket)
       when is_binary(signaling_session_id) do
    if signaling_session_id == socket.assigns.signaling_session_id,
      do: :ok,
      else: :invalid_session
  end

  defp validate_signaling_session_id(_params, _socket), do: :invalid_session

  defp new_signaling_session_id do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp empty_media_counts do
    %{
      inbound_packet_count: 0,
      echoed_packet_count: 0,
      dropped_packet_count: 0,
      dropped_media_count: 0
    }
  end

  defp increment_media_count(media_counts, count_name) do
    Map.update!(media_counts, count_name, &(&1 + 1))
  end

  defp record_media_outcome(socket, peer_connection, :accepted_inbound_track) do
    record_media(socket, peer_connection, :inbound_track_admitted, [])
  end

  defp record_media_outcome(socket, peer_connection, :echoed_rtp) do
    record_media(socket, peer_connection, :rtp_routed, [
      :inbound_packet_count,
      :echoed_packet_count
    ])
  end

  defp record_media_outcome(socket, peer_connection, :dropped_rtp) do
    record_media(socket, peer_connection, :unexpected_media_dropped, [:dropped_packet_count])
  end

  defp record_media_outcome(socket, peer_connection, :dropped_media) do
    record_media(socket, peer_connection, :unexpected_media_dropped, [:dropped_media_count])
  end

  defp record_media(socket, peer_connection, lifecycle, count_names) do
    media_counts =
      Enum.reduce(count_names, socket.assigns.media_counts, &increment_media_count(&2, &1))

    Diagnostics.emit_media(lifecycle, media_counts)

    socket
    |> assign(:peer_connection, peer_connection)
    |> assign(:media_counts, media_counts)
  end
end
