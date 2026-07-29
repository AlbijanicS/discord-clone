defmodule DiscordCloneWeb.VoiceChannel do
  use DiscordCloneWeb, :channel

  alias DiscordClone.Workspaces
  alias DiscordCloneWeb.VoiceSignaling.{Diagnostics, FakeHeartbeat, FakeIce, FakeOffer}

  @impl true
  def join("voice:" <> voice_channel_id, _params, socket) do
    case Workspaces.authorize_voice_channel_for_signaling(
           socket.assigns.current_scope,
           voice_channel_id
         ) do
      {:ok, _voice_channel} ->
        signaling_session_id = new_signaling_session_id()

        {:ok, %{signaling_session_id: signaling_session_id},
         assign(socket, :signaling_session_id, signaling_session_id)}

      {:error, :not_found} ->
        {:error, %{reason: "not_found"}}
    end
  end

  def join(_topic, _params, _socket), do: {:error, %{reason: "not_found"}}

  @impl true
  def handle_in("offer", params, socket) do
    handle_fake_message("offer", params, socket, FakeOffer, fn offer ->
      %{
        signaling_session_id: socket.assigns.signaling_session_id,
        label: "fake-answer",
        sequence: offer.sequence
      }
    end)
  end

  def handle_in("ice_candidate", params, socket) do
    handle_fake_message("ice_candidate", params, socket, FakeIce, fn ice ->
      push(socket, "ice_candidate", %{
        signaling_session_id: socket.assigns.signaling_session_id,
        label: "fake-server-ice",
        sequence: ice.sequence
      })

      %{
        signaling_session_id: socket.assigns.signaling_session_id,
        label: "fake-client-ice-ack",
        sequence: ice.sequence
      }
    end)
  end

  def handle_in("heartbeat", params, socket) do
    handle_fake_message("heartbeat", params, socket, FakeHeartbeat, fn heartbeat ->
      %{
        signaling_session_id: socket.assigns.signaling_session_id,
        label: "fake-heartbeat-ack",
        sequence: heartbeat.sequence
      }
    end)
  end

  def handle_in(_event, _params, socket),
    do: {:reply, {:error, %{reason: "unsupported_event"}}, socket}

  defp handle_fake_message(operation, params, socket, validator, response) do
    byte_count = decoded_request_byte_count(params)

    with :ok <- validate_signaling_session_id(params, socket),
         {:ok, message} <- validator.validate(params) do
      Diagnostics.emit(operation, :accepted, decoded_request_byte_count: byte_count)
      {:reply, {:ok, response.(message)}, socket}
    else
      :error ->
        Diagnostics.emit(operation, :rejected,
          error_code: "invalid_request",
          decoded_request_byte_count: byte_count
        )

        {:reply, {:error, %{reason: "invalid_request"}}, socket}

      {:error, errors} ->
        Diagnostics.emit(operation, :rejected,
          error_code: "invalid_payload",
          decoded_request_byte_count: byte_count
        )

        {:reply, {:error, %{errors: errors}}, socket}
    end
  end

  defp decoded_request_byte_count(params) do
    case Jason.encode(params) do
      {:ok, encoded_params} -> byte_size(encoded_params)
      {:error, _reason} -> nil
    end
  end

  defp validate_signaling_session_id(
         %{"signaling_session_id" => signaling_session_id},
         socket
       )
       when is_binary(signaling_session_id) do
    if signaling_session_id == socket.assigns.signaling_session_id, do: :ok, else: :error
  end

  defp validate_signaling_session_id(_params, _socket), do: :error

  defp new_signaling_session_id do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
