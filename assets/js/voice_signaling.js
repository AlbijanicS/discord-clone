export function createVoiceSignaling({Socket} = {}) {
  let socket = null
  let channel = null

  function ensureSocket() {
    if (socket) return socket

    socket = new Socket("/voice")
    socket.connect()
    return socket
  }

  return {
    join(voiceChannelId) {
      if (channel) this.leave()

      channel = ensureSocket().channel(`voice:${voiceChannelId}`, {})
      return channel.join()
    },

    sendFakeOffer(offer) {
      return channel?.push("offer", offer) ?? null
    },

    sendFakeIce(ice) {
      return channel?.push("ice_candidate", ice) ?? null
    },

    sendHeartbeat(heartbeat) {
      return channel?.push("heartbeat", heartbeat) ?? null
    },

    onFakeServerIce(callback) {
      return channel?.on("ice_candidate", callback) ?? null
    },

    leave() {
      if (!channel) return null

      const leave = channel.leave()
      channel = null
      return leave
    },

    disconnect() {
      this.leave()
      socket?.disconnect()
      socket = null
    },
  }
}
