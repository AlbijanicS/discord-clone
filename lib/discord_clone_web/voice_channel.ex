defmodule DiscordCloneWeb.VoiceChannel do
  use DiscordCloneWeb, :channel

  alias DiscordClone.Workspaces
  alias DiscordCloneWeb.VoiceSignaling.{FakeHeartbeat, FakeIce, FakeOffer}

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
    with :ok <- validate_signaling_session_id(params, socket),
         {:ok, offer} <- FakeOffer.validate(params) do
      {:reply,
       {:ok,
        %{
          signaling_session_id: socket.assigns.signaling_session_id,
          label: "fake-answer",
          sequence: offer.sequence
        }}, socket}
    else
      :error -> {:reply, {:error, %{reason: "invalid_request"}}, socket}
      {:error, errors} -> {:reply, {:error, %{errors: errors}}, socket}
    end
  end

  def handle_in("ice_candidate", params, socket) do
    with :ok <- validate_signaling_session_id(params, socket),
         {:ok, ice} <- FakeIce.validate(params) do
      push(socket, "ice_candidate", %{
        signaling_session_id: socket.assigns.signaling_session_id,
        label: "fake-server-ice",
        sequence: ice.sequence
      })

      {:reply,
       {:ok,
        %{
          signaling_session_id: socket.assigns.signaling_session_id,
          label: "fake-client-ice-ack",
          sequence: ice.sequence
        }}, socket}
    else
      :error -> {:reply, {:error, %{reason: "invalid_request"}}, socket}
      {:error, errors} -> {:reply, {:error, %{errors: errors}}, socket}
    end
  end

  def handle_in("heartbeat", params, socket) do
    with :ok <- validate_signaling_session_id(params, socket),
         {:ok, heartbeat} <- FakeHeartbeat.validate(params) do
      {:reply,
       {:ok,
        %{
          signaling_session_id: socket.assigns.signaling_session_id,
          label: "fake-heartbeat-ack",
          sequence: heartbeat.sequence
        }}, socket}
    else
      :error -> {:reply, {:error, %{reason: "invalid_request"}}, socket}
      {:error, errors} -> {:reply, {:error, %{errors: errors}}, socket}
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
