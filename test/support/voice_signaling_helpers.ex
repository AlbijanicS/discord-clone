defmodule DiscordCloneWeb.VoiceSignalingHelpers do
  defmacro browser_offer do
    quote do
      peer_connection =
        start_supervised!(%{
          id: make_ref(),
          start:
            {ExWebRTC.PeerConnection, :start_link,
             [[ice_servers: [], controlling_process: self()]]}
        })

      assert {:ok, _transceiver} =
               ExWebRTC.PeerConnection.add_transceiver(peer_connection, :audio)

      assert {:ok, description} = ExWebRTC.PeerConnection.create_offer(peer_connection)
      assert :ok = ExWebRTC.PeerConnection.set_local_description(peer_connection, description)
      ExWebRTC.SessionDescription.to_json(description)
    end
  end
end
