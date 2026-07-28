export function createVoiceController({
  mediaDevices = globalThis.navigator?.mediaDevices,
  secureContext = globalThis.isSecureContext,
} = {}) {
  let activeRequest = 0
  let audioTracks = []
  let currentState = idleState()
  const listeners = new Set()

  function publish(nextState) {
    currentState = nextState
    listeners.forEach(listener => listener(currentState))
  }

  function stopTracks(tracks = audioTracks) {
    tracks.forEach(track => {
      track.removeEventListener?.("ended", handleTrackEnded)
      track.stop()
    })
  }

  function clearCapture() {
    stopTracks()
    audioTracks = []
  }

  function handleTrackEnded() {
    if (audioTracks.length === 0) return

    const channel = currentState
    activeRequest += 1
    clearCapture()
    publish({...channel, error: "externally_ended", retryable: true, status: "externally_ended"})
  }

  function requestCapture(channel) {
    const request = ++activeRequest
    publish({...channel, status: "requesting"})

    if (!mediaDevices?.getUserMedia) {
      publish(failureState(channel, "unsupported"))
      return Promise.resolve()
    }

    if (secureContext === false) {
      publish(failureState(channel, "insecure_context"))
      return Promise.resolve()
    }

    return mediaDevices.getUserMedia({audio: true})
      .then(mediaStream => {
        const tracks = mediaStream.getAudioTracks()

        if (request !== activeRequest) {
          stopTracks(tracks)
          return
        }

        audioTracks = tracks
        audioTracks.forEach(track => track.addEventListener?.("ended", handleTrackEnded))
        publish({...channel, status: "capturing"})
      })
      .catch(error => {
        if (request === activeRequest) publish(failureState(channel, failureFor(error)))
      })
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

    join(channel) {
      if (currentState.status === "requesting") return Promise.resolve()
      if (currentState.channelId === channel.id) return Promise.resolve()

      this.leave()
      return requestCapture(normalizeChannel(channel))
    },

    retry() {
      if (!currentState.retryable || !currentState.channelId) return Promise.resolve()

      const channel = normalizeChannel(currentState)
      this.leave()
      return requestCapture(channel)
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
      clearCapture()
      publish(idleState())
    },

    teardown() {
      this.leave()
    },
  }
}

function normalizeChannel(channel) {
  return {channelId: channel.id || channel.channelId, channelName: channel.name || channel.channelName, workspaceId: channel.workspaceId || null}
}

function failureState(channel, error) {
  return {...channel, error, retryable: retryableFailure(error), status: error}
}

function retryableFailure(error) {
  return ["permission_denied", "no_device", "unknown_error"].includes(error)
}

function failureFor(error) {
  switch (error?.name) {
    case "NotAllowedError":
      return "permission_denied"
    case "NotFoundError":
    case "DevicesNotFoundError":
      return "no_device"
    case "SecurityError":
      return "insecure_context"
    case "NotSupportedError":
    case "TypeError":
      return "unsupported"
    default:
      return "unknown_error"
  }
}

function idleState() {
  return {channelId: null, channelName: null, status: "idle", workspaceId: null}
}

const voiceController = createVoiceController()

export default voiceController
