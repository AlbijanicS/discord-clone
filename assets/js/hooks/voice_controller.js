export function createVoiceController({mediaDevices = navigator.mediaDevices} = {}) {
  let activeRequest = 0
  let audioTracks = []
  let currentState = idleState()
  const listeners = new Set()

  function publish(nextState) {
    currentState = nextState
    listeners.forEach(listener => listener(currentState))
  }

  function stopTracks(tracks = audioTracks) {
    tracks.forEach(track => track.stop())
  }

  return {
    state() {
      return currentState
    },

    subscribe(listener) {
      listeners.add(listener)
      listener(currentState)
      return () => listeners.delete(listener)
    },

    async join(channel) {
      if (currentState.status === "requesting") {
        return
      }

      if (currentState.channelId === channel.id && audioTracks.length > 0) {
        return
      }

      this.leave()
      const request = ++activeRequest
      publish({channelId: channel.id, channelName: channel.name, status: "requesting"})

      try {
        const mediaStream = await mediaDevices.getUserMedia({audio: true})
        const tracks = mediaStream.getAudioTracks()

        if (request !== activeRequest) {
          stopTracks(tracks)
          return
        }

        audioTracks = tracks
        publish({channelId: channel.id, channelName: channel.name, status: "capturing"})
      } catch (_error) {
        if (request === activeRequest) {
          publish(idleState())
        }
      }
    },

    toggleMute() {
      if (currentState.status === "capturing") {
        audioTracks.forEach(track => track.enabled = false)
        publish({...currentState, status: "muted"})
      } else if (currentState.status === "muted") {
        audioTracks.forEach(track => track.enabled = true)
        publish({...currentState, status: "capturing"})
      }
    },

    leave() {
      activeRequest += 1
      stopTracks()
      audioTracks = []
      publish(idleState())
    },
  }
}

function idleState() {
  return {channelId: null, channelName: null, status: "idle"}
}

const voiceController = createVoiceController()

export default voiceController
