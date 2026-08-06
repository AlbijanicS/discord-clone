defmodule DiscordCloneWeb.VoiceChannel do
  use DiscordCloneWeb, :channel

  alias DiscordClone.{Voice, Workspaces}
  alias DiscordClone.Voice.Diagnostics
  alias DiscordCloneWeb.VoiceSignaling.{FakeHeartbeat, RealMessage}

  @impl true
  def join("voice:" <> voice_channel_id, _params, socket) do
    case Workspaces.authorize_voice_channel_for_signaling(
           socket.assigns.current_scope,
           voice_channel_id
         ) do
      {:ok, _voice_channel} ->
        join_voice_channel(voice_channel_id, socket)

      {:error, :not_found} ->
        {:error, %{reason: "not_found"}}
    end
  end

  def join(_topic, _params, _socket), do: {:error, %{reason: "not_found"}}

  @impl true
  def handle_in("offer", params, socket) do
    with :ok <- validate_signaling_session_id(params, socket),
         {:ok, offer} <- RealMessage.offer(params),
         {:ok, answer} <-
           Voice.accept_offer(
             socket.assigns.current_scope,
             socket.assigns.voice_channel_id,
             socket.assigns.voice_session_id,
             offer.negotiation_id,
             offer.description
           ) do
      Diagnostics.emit("offer", :accepted, decoded_request_byte_count: offer.byte_count)

      {:reply,
       {:ok,
        %{
          signaling_session_id: socket.assigns.signaling_session_id,
          negotiation_id: offer.negotiation_id,
          description: answer
        }}, assign(socket, :negotiation_id, offer.negotiation_id)}
    else
      :invalid_session ->
        reject("offer", "invalid_request", decoded_request_byte_count(params), socket)

      {:error, :negotiation_failed} ->
        reject_terminal_offer("negotiation_failed", decoded_request_byte_count(params), socket)

      {:error, :incompatible_audio_output_slots} ->
        reject_terminal_offer(
          "incompatible_audio_output_slots",
          decoded_request_byte_count(params),
          socket
        )

      {:error, error_code} ->
        reject("offer", error_code, decoded_request_byte_count(params), socket)
    end
  end

  def handle_in("ice_candidate", params, socket) do
    case {validate_signaling_session_id(params, socket), RealMessage.ice_candidate(params)} do
      {:ok, {:end_of_candidates, marker}} ->
        case Voice.end_of_candidates(
               socket.assigns.current_scope,
               socket.assigns.voice_channel_id,
               socket.assigns.voice_session_id,
               marker.negotiation_id
             ) do
          {:error, :end_of_candidates_unsupported} ->
            reject("ice_candidate", "end_of_candidates_unsupported", marker.byte_count, socket)

          {:error, error_code} ->
            reject("ice_candidate", error_code, marker.byte_count, socket)
        end

      {:ok, {:ok, ice}} ->
        case Voice.add_ice_candidate(
               socket.assigns.current_scope,
               socket.assigns.voice_channel_id,
               socket.assigns.voice_session_id,
               ice.negotiation_id,
               ice
             ) do
          {:ok, reply} ->
            Diagnostics.emit("ice_candidate", :accepted,
              decoded_request_byte_count: ice.byte_count
            )

            {:reply, {:ok, reply}, socket}

          {:error, error_code} ->
            reject("ice_candidate", error_code, ice.byte_count, socket)
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
  def handle_info({:voice_session_event, voice_session_id, event}, socket) do
    if voice_session_id == socket.assigns[:voice_session_id] do
      handle_voice_session_event(event, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, socket) do
    leave_voice_session(socket)
    :ok
  end

  defp handle_voice_session_event(
         {:ice_candidate, negotiation_id, candidate},
         %{assigns: %{negotiation_id: negotiation_id}} = socket
       ) do
    push(socket, "ice_candidate", %{
      signaling_session_id: socket.assigns.signaling_session_id,
      negotiation_id: negotiation_id,
      candidate: candidate
    })

    {:noreply, socket}
  end

  defp handle_voice_session_event(
         {:end_of_candidates, negotiation_id},
         %{assigns: %{negotiation_id: negotiation_id}} = socket
       ) do
    push(socket, "ice_candidate", %{
      signaling_session_id: socket.assigns.signaling_session_id,
      negotiation_id: negotiation_id,
      end_of_candidates: true
    })

    Diagnostics.emit("ice_candidate", :accepted, decoded_request_byte_count: 0)
    {:noreply, socket}
  end

  defp handle_voice_session_event({:ice_candidate, _negotiation_id, _candidate}, socket),
    do: {:noreply, socket}

  defp handle_voice_session_event({:end_of_candidates, _negotiation_id}, socket),
    do: {:noreply, socket}

  defp handle_voice_session_event(
         {:connection_state_change, connection_state, negotiation_id},
         %{assigns: %{negotiation_id: negotiation_id}} = socket
       )
       when connection_state in [:failed, :closed] do
    {:stop, :normal, socket}
  end

  defp handle_voice_session_event(
         {:connection_state_change, _connection_state, _negotiation_id},
         socket
       ),
       do: {:noreply, socket}

  defp leave_voice_session(socket) do
    case {socket.assigns[:voice_channel_id], socket.assigns[:voice_session_id]} do
      {voice_channel_id, voice_session_id}
      when is_binary(voice_channel_id) and is_binary(voice_session_id) ->
        Voice.leave(voice_channel_id, voice_session_id)

      _missing_join ->
        :ok
    end
  end

  defp reject(operation, error_code, byte_count, socket) do
    error_code = normalize_error_code(error_code)

    Diagnostics.emit(operation, :rejected,
      error_code: error_code,
      decoded_request_byte_count: byte_count
    )

    {:reply, {:error, %{reason: error_code}}, socket}
  end

  defp reject_terminal_offer(error_code, byte_count, socket) do
    Diagnostics.emit("offer", :rejected,
      error_code: error_code,
      decoded_request_byte_count: byte_count
    )

    {:stop, :normal, {:error, %{reason: error_code}}, socket}
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

  defp join_voice_channel(voice_channel_id, socket) do
    signaling_session_id = new_signaling_session_id()

    case Voice.join(
           voice_channel_id,
           socket.assigns.current_scope.user.id,
           signaling_session_id,
           self()
         ) do
      {:ok, join_result} ->
        case join_payload(join_result, signaling_session_id) do
          {:ok, %{voice_session_id: voice_session_id} = payload} ->
            {:ok, payload,
             socket
             |> assign(:voice_channel_id, voice_channel_id)
             |> assign(:signaling_session_id, signaling_session_id)
             |> assign(:voice_session_id, voice_session_id)
             |> assign(:negotiation_id, nil)}

          :error ->
            rollback_voice_join(voice_channel_id, join_result)
            {:error, %{reason: "unavailable"}}
        end

      {:error, reason} ->
        normalize_join_error(reason)
    end
  end

  defp join_payload(
         %{voice_session_id: voice_session_id, occupancy: occupancy, capacity: capacity},
         signaling_session_id
       )
       when is_binary(voice_session_id) and is_binary(signaling_session_id) and
              is_integer(occupancy) and occupancy >= 0 and is_integer(capacity) and capacity > 0 and
              occupancy <= capacity do
    {:ok,
     %{
       signaling_session_id: signaling_session_id,
       voice_session_id: voice_session_id,
       occupancy: occupancy,
       capacity: capacity
     }}
  end

  defp join_payload(_join_result, _signaling_session_id), do: :error

  defp rollback_voice_join(voice_channel_id, %{voice_session_id: voice_session_id})
       when is_binary(voice_session_id) do
    Voice.leave(voice_channel_id, voice_session_id)
  end

  defp rollback_voice_join(_voice_channel_id, _join_result), do: :ok

  defp normalize_join_error(%{reason: :room_full, occupancy: occupancy, capacity: capacity})
       when is_integer(occupancy) and occupancy >= 0 and is_integer(capacity) and capacity > 0 and
              occupancy <= capacity do
    {:error, %{reason: "room_full", occupancy: occupancy, capacity: capacity}}
  end

  defp normalize_join_error(:not_found), do: {:error, %{reason: "not_found"}}
  defp normalize_join_error(:recovering), do: {:error, %{reason: "recovering"}}

  defp normalize_join_error(:recovery_timeout),
    do: {:error, %{reason: "recovery_timeout"}}

  defp normalize_join_error(_reason), do: {:error, %{reason: "unavailable"}}

  defp normalize_error_code(error_code) when is_binary(error_code), do: error_code
  defp normalize_error_code(error_code) when is_atom(error_code), do: Atom.to_string(error_code)
  defp normalize_error_code(_error_code), do: "unavailable"
end
