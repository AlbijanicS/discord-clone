export function createVoiceController({
  mediaDevices = globalThis.navigator?.mediaDevices,
  secureContext = globalThis.isSecureContext,
  now = () => Date.now(),
  tabCoordination = createBroadcastTabCoordination(),
  tabId = createTabId(),
  connectionFactory = null,
  audioElementFactory = createRemoteAudioElement,
} = {}) {
  let activeRequest = 0
  let audioTracks = []
  let currentState = idleState()
  let currentClaim = null
  let activeConnection = null
  let statusBeforeMute = null
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

  function closeConnection() {
    activeConnection?.leave?.()
    activeConnection = null
  }

  function releaseForTakeover() {
    if (!ownsLocalCapture()) return

    const channel = currentState
    activeRequest += 1
    currentClaim = null
    closeConnection()
    clearCapture()
    publish({...channel, error: "taken_over", retryable: false, status: "taken_over"})
  }

  function ownsLocalCapture() {
    return ["requesting", "capturing", "joining", "connected", "muted"].includes(currentState.status)
  }

  function handleClaim(claim) {
    if (claim?.tabId === tabId || !ownsLocalCapture() || !claimIsNewer(claim, currentClaim)) return

    releaseForTakeover()
  }

  function publishClaim(claim) {
    try {
      tabCoordination?.publish?.(claim)
    } catch (_) {
      // Same-tab capture remains usable when browser-local coordination is unavailable.
    }
  }

  function startCapture(channel) {
    const claim = {tabId, timestamp: now()}
    currentClaim = claim
    const capture = requestCapture(channel)
    publishClaim(claim)
    return capture
  }

  function handleTrackEnded() {
    if (audioTracks.length === 0) return

    const channel = currentState
    activeRequest += 1
    closeConnection()
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
        startConnection(channel, tracks[0], request)
      })
      .catch(error => {
        if (request === activeRequest) publish(failureState(channel, failureFor(error)))
      })
  }

  function startConnection(channel, track, request) {
    if (!connectionFactory || !track || request !== activeRequest) return

    const remoteAudio = audioElementFactory()
    const connection = connectionFactory({
      channel,
      remoteAudio,
      track,
      onFailure(error) {
        if (connection !== activeConnection || request !== activeRequest) return

        activeConnection = null
        clearCapture()
        publish({...channel, error, retryable: true, status: error})
      },
      onState(status) {
        if (connection !== activeConnection || request !== activeRequest) return
        publish({...channel, status})
      },
      onPlayback(outcome) {
        if (connection !== activeConnection || request !== activeRequest) return

        if (outcome === "blocked") publish({...currentState, audioPlayback: "blocked"})
        if (outcome === "playing") {
          const {audioPlayback: _audioPlayback, ...state} = currentState
          publish(state)
        }
      },
    })

    activeConnection = connection
    publish({...channel, status: "joining"})
    connection?.connect?.({channelId: channel.channelId, track})?.catch?.(() => {})
  }

  try {
    tabCoordination?.subscribe?.(handleClaim)
  } catch (_) {
    // Browser-local coordination is best effort; capture does not depend on it.
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
      if (currentState.channelId === channel.id && ownsLocalCapture()) return Promise.resolve()

      this.leave()
      return startCapture(normalizeChannel(channel))
    },

    retry() {
      if (!currentState.retryable || !currentState.channelId) return Promise.resolve()

      const channel = normalizeChannel(currentState)
      this.leave()
      return startCapture(channel)
    },

    enableAudio() {
      if (currentState.audioPlayback !== "blocked") return Promise.resolve()
      return activeConnection?.enableAudio?.() || Promise.resolve()
    },

    toggleMute() {
      if (["capturing", "connected"].includes(currentState.status)) {
        statusBeforeMute = currentState.status
        audioTracks.forEach(track => track.enabled = false)
        publish({...currentState, status: "muted"})
      } else if (currentState.status === "muted") {
        audioTracks.forEach(track => track.enabled = true)
        publish({...currentState, status: statusBeforeMute || "capturing"})
        statusBeforeMute = null
      }
    },

    leave() {
      activeRequest += 1
      currentClaim = null
      closeConnection()
      clearCapture()
      publish(idleState())
    },

    teardown() {
      this.leave()
      try {
        tabCoordination?.close?.()
      } catch (_) {
        // Browser teardown must not fail because a coordination channel cannot close.
      }
    },

    configure({connectionFactory: nextConnectionFactory} = {}) {
      connectionFactory = nextConnectionFactory || null
    },
  }
}

function createRemoteAudioElement() {
  return globalThis.document?.createElement?.("audio") || null
}

function claimIsNewer(candidate, current) {
  if (!current || typeof candidate?.timestamp !== "number" || typeof candidate?.tabId !== "string") return false
  if (candidate.timestamp !== current.timestamp) return candidate.timestamp > current.timestamp
  return candidate.tabId > current.tabId
}

function createTabId() {
  return globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random()}`
}

function createBroadcastTabCoordination() {
  if (typeof globalThis.BroadcastChannel !== "function") return null

  try {
    const channel = new globalThis.BroadcastChannel("discord-clone-voice-owner-tab")
    channel.unref?.()

    return {
      publish(claim) {
        channel.postMessage(claim)
      },
      subscribe(listener) {
        const handleMessage = event => listener(event.data)
        channel.addEventListener("message", handleMessage)
        return () => channel.removeEventListener("message", handleMessage)
      },
      close() {
        channel.close()
      },
    }
  } catch (_) {
    return null
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
