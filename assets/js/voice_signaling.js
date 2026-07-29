export function createVoiceSignaling({Socket, socketPath = "/voice"} = {}) {
  let socket = null
  let channel = null

  function ensureSocket() {
    if (socket) return socket

    socket = new Socket(socketPath)
    socket.connect()
    return socket
  }

  return {
    join(voiceChannelId) {
      if (channel) this.leave()

      channel = ensureSocket().channel(`voice:${voiceChannelId}`, {})
      return channel.join()
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
