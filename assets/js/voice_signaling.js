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

    joinVoiceChannel(voiceChannelId) {
      return awaitReply(this.join(voiceChannelId))
    },

    sendOffer(offer) {
      const push = channel?.push("offer", offer)
      return push ? awaitReply(push) : Promise.reject(new Error("voice signaling is not joined"))
    },

    sendIce(ice) {
      return channel?.push("ice_candidate", ice) ?? null
    },

    sendHeartbeat(heartbeat) {
      return channel?.push("heartbeat", heartbeat) ?? null
    },

    onServerIce(callback) {
      return channel?.on("ice_candidate", callback) ?? null
    },

    onClose(callback) {
      return channel?.onClose(callback) ?? null
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

function awaitReply(push) {
  return new Promise((resolve, reject) => {
    push.receive("ok", resolve)
    push.receive("error", reject)
    push.receive("timeout", () => reject(new Error("voice signaling request timed out")))
  })
}
