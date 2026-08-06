defmodule DiscordCloneWeb.VoiceSignalingHelpers do
  defmacro browser_offer(output_slot_count \\ 4) do
    quote do
      peer_connection =
        start_supervised!(%{
          id: make_ref(),
          start:
            {ExWebRTC.PeerConnection, :start_link,
             [[ice_servers: [], controlling_process: self()]]}
        })

      assert {:ok, _microphone_transceiver} =
               ExWebRTC.PeerConnection.add_transceiver(
                 peer_connection,
                 ExWebRTC.MediaStreamTrack.new(:audio),
                 direction: :sendonly
               )

      Enum.each(List.duplicate(:audio_output_slot, unquote(output_slot_count)), fn _slot ->
        assert {:ok, _audio_output_transceiver} =
                 ExWebRTC.PeerConnection.add_transceiver(
                   peer_connection,
                   :audio,
                   direction: :recvonly
                 )
      end)

      assert {:ok, description} = ExWebRTC.PeerConnection.create_offer(peer_connection)
      assert :ok = ExWebRTC.PeerConnection.set_local_description(peer_connection, description)
      ExWebRTC.SessionDescription.to_json(description)
    end
  end
end
