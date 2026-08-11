const ICE_SERVERS = []
const MAX_PENDING_SERVER_CANDIDATES = 16
const MAX_PENDING_SERVER_CANDIDATE_BYTES = MAX_PENDING_SERVER_CANDIDATES * 8 * 1024
const OFFER_REPLY_TIMEOUT_MS = 10_000
const RENEWAL_INTERVAL_MS = 30_000
const RENEWAL_ACK_TIMEOUT_MS = 10_000
const RENEWAL_GRACE_MS = 75_000
const PEER_CONNECTION_RECOVERY_GRACE_MS = 30_000
const AUDIO_OUTPUT_SLOT_COUNT = 4
const INCOMPATIBLE_AUDIO_OUTPUT_SLOTS = "incompatible_audio_output_slots"

export function createVoicePeerAttempt({
  PeerConnection = globalThis.RTCPeerConnection,
  MediaStream = globalThis.MediaStream,
  negotiationId = createNegotiationId,
  onFailure = () => {},
  onCue = () => {},
  onPlayback = () => {},
  onState = () => {},
  remoteAudio = null,
  signaling,
  setTimeoutFn = globalThis.setTimeout,
  clearTimeoutFn = globalThis.clearTimeout,
} = {}) {
  let active = false
  let answerApplied = false
  let aggregatePlaybackStream = null
  let audioOutputSlots = []
  let peerConnection = null
  let pendingServerCandidates = []
  let pendingServerCandidateBytes = 0
  let signalingSessionId = null
  let signalingActive = false
  let currentNegotiationId = null
  let mediaState = "joining"
  let peerConnectionRecoveryDeadline = null
  let renewalAckTimeout = null
  let renewalDeadline = null
  let renewalInterval = null
  let controlPlaneInterrupted = false

  function fail(error = "connection_failed") {
    if (!active) return

    cleanup()
    onFailure(error)
  }

  function cleanup() {
    active = false
    answerApplied = false
    pendingServerCandidates = []
    pendingServerCandidateBytes = 0
    clearRenewalTimers()
    clearPeerConnectionRecoveryDeadline()
    releaseRemoteAudio()
    peerConnection?.close()
    peerConnection = null
    if (signalingActive) signaling?.leave()
    signalingActive = false
  }

  function clearRenewalTimers() {
    clearTimeoutFn(renewalAckTimeout)
    clearTimeoutFn(renewalDeadline)
    clearTimeoutFn(renewalInterval)
    renewalAckTimeout = null
    renewalDeadline = null
    renewalInterval = null
  }

  function clearPeerConnectionRecoveryDeadline() {
    clearTimeoutFn(peerConnectionRecoveryDeadline)
    peerConnectionRecoveryDeadline = null
  }

  function startPeerConnectionRecoveryDeadline() {
    if (peerConnectionRecoveryDeadline) return

    peerConnectionRecoveryDeadline = schedule(
      () => fail("connection_lost"),
      PEER_CONNECTION_RECOVERY_GRACE_MS
    )
  }

  function schedule(callback, delay) {
    const timeout = setTimeoutFn(callback, delay)
    timeout?.unref?.()
    return timeout
  }

  function publishConnectionState() {
    onState(controlPlaneInterrupted || mediaState === "disconnected" ? "interrupted" : mediaState)
  }

  function scheduleRenewal() {
    renewalInterval = schedule(() => {
      renewalInterval = null
      renewVoiceSession()
      if (active) scheduleRenewal()
    }, RENEWAL_INTERVAL_MS)
  }

  function setRenewalDeadline() {
    clearTimeoutFn(renewalDeadline)
    renewalDeadline = schedule(() => fail("connection_lost"), RENEWAL_GRACE_MS)
  }

  function receiveRenewalAcknowledgement(reply) {
    if (!active || reply?.signaling_session_id !== signalingSessionId) return

    clearTimeoutFn(renewalAckTimeout)
    renewalAckTimeout = null
    controlPlaneInterrupted = false
    setRenewalDeadline()
    publishConnectionState()
  }

  function receiveVoiceSessionEnded(message) {
    if (!active || message?.signaling_session_id !== signalingSessionId) return

    fail("connection_lost")
  }

  function interruptControlPlane() {
    if (!active || controlPlaneInterrupted) return

    controlPlaneInterrupted = true
    publishConnectionState()
  }

  function renewVoiceSession() {
    if (!active || !signalingSessionId) return

    const renewal = signaling?.renewVoiceSession?.({signaling_session_id: signalingSessionId})
    clearTimeoutFn(renewalAckTimeout)
    renewalAckTimeout = schedule(interruptControlPlane, RENEWAL_ACK_TIMEOUT_MS)
    renewal?.receive?.("ok", receiveRenewalAcknowledgement)?.receive?.("error", () => fail("connection_lost"))
  }

  function startRenewals() {
    controlPlaneInterrupted = false
    setRenewalDeadline()
    scheduleRenewal()
  }

  async function playRemoteAudio() {
    if (!active || !remoteAudio?.srcObject) return

    try {
      await remoteAudio.play()
      if (active) onPlayback("playing")
    } catch (_) {
      if (active) onPlayback("blocked")
    }
  }

  function receiveRemoteTrack(event) {
    if (!active || !aggregatePlaybackStream || event?.track?.kind !== "audio") return

    const slot = audioOutputSlots.find(candidate =>
      candidate.transceiver === event.transceiver ||
      candidate.transceiver.receiver?.track === event.track
    )
    if (!slot || slot.track === event.track) return

    releaseSlotTrack(slot)
    slot.track = event.track
    slot.onEnded = () => releaseSlotTrack(slot, event.track)
    event.track.addEventListener?.("ended", slot.onEnded)
    aggregatePlaybackStream.addTrack(event.track)
    playRemoteAudio()
  }

  function releaseRemoteAudio() {
    audioOutputSlots.forEach(slot => releaseSlotTrack(slot))
    audioOutputSlots = []
    aggregatePlaybackStream = null

    if (!remoteAudio?.srcObject) return

    remoteAudio.pause?.()
    remoteAudio.srcObject = null
  }

  function releaseSlotTrack(slot, expectedTrack = slot.track) {
    if (!slot.track || slot.track !== expectedTrack) return

    slot.track.removeEventListener?.("ended", slot.onEnded)
    aggregatePlaybackStream?.removeTrack(slot.track)
    slot.track = null
    slot.onEnded = null
  }

  function preflight(track) {
    try {
      if (!PeerConnection || !MediaStream) throw new Error("required WebRTC APIs are unavailable")

      peerConnection = new PeerConnection({iceServers: ICE_SERVERS})
      if (typeof peerConnection.addTransceiver !== "function") {
        throw new Error("audio transceivers are unavailable")
      }

      peerConnection.addTransceiver(track, {direction: "sendonly"})
      audioOutputSlots = Array.from({length: AUDIO_OUTPUT_SLOT_COUNT}, (_unused, index) => {
        const transceiver = peerConnection.addTransceiver("audio", {direction: "recvonly"})
        if (!transceiver?.receiver?.track || transceiver.receiver.track.kind !== "audio") {
          throw new Error(`audio output slot ${index} is unavailable`)
        }

        return {index, onEnded: null, track: null, transceiver}
      })

      aggregatePlaybackStream = new MediaStream()
      if (remoteAudio) {
        remoteAudio.autoplay = true
        remoteAudio.playsInline = true
        remoteAudio.srcObject = aggregatePlaybackStream
      }
    } catch (error) {
      const compatibilityError = new Error("four Audio Output Slots are required", {cause: error})
      compatibilityError.voiceFailure = INCOMPATIBLE_AUDIO_OUTPUT_SLOTS
      throw compatibilityError
    }
  }

  async function addServerCandidate(candidate) {
    try {
      await peerConnection?.addIceCandidate(candidate)
    } catch (_) {
      fail()
    }
  }

  function receiveServerIce(message) {
    if (
      !active ||
      message?.signaling_session_id !== signalingSessionId ||
      message?.negotiation_id !== currentNegotiationId ||
      (!message?.candidate && message?.end_of_candidates !== true)
    ) return

    const candidate = message.end_of_candidates === true ? {candidate: ""} : message.candidate
    const byteSize = message.end_of_candidates === true ? 0 : candidateByteSize(candidate)

    if (!answerApplied) {
      if (
        pendingServerCandidates.length < MAX_PENDING_SERVER_CANDIDATES &&
        pendingServerCandidateBytes + byteSize <= MAX_PENDING_SERVER_CANDIDATE_BYTES
      ) {
        pendingServerCandidates.push(candidate)
        pendingServerCandidateBytes += byteSize
      }
      return
    }

    addServerCandidate(candidate)
  }

  function handleConnectionStateChange() {
    if (!active) return

    if (peerConnection.connectionState === "connected") {
      mediaState = "connected"
      clearPeerConnectionRecoveryDeadline()
      publishConnectionState()
    }
    if (peerConnection.connectionState === "disconnected") {
      mediaState = "disconnected"
      startPeerConnectionRecoveryDeadline()
      publishConnectionState()
    }
    if (["failed", "closed"].includes(peerConnection.connectionState)) fail("connection_lost")
  }

  function sendLocalIce(event) {
    if (!active || !event.candidate) return

    signaling.sendIce({
      signaling_session_id: signalingSessionId,
      negotiation_id: currentNegotiationId,
      candidate: event.candidate.toJSON?.() || event.candidate,
    })
  }

  function ensureActive() {
    if (!active) throw new Error("voice connection cancelled")
  }

  return {
    async connect({channelId, track}) {
      if (!PeerConnection || !signaling || !track) throw new Error("voice connection unavailable")

      active = true
      mediaState = "joining"
      currentNegotiationId = negotiationId()
      onState("joining")

      try {
        preflight(track)
        peerConnection.addEventListener("icecandidate", sendLocalIce)
        peerConnection.addEventListener("connectionstatechange", handleConnectionStateChange)
        peerConnection.addEventListener("track", receiveRemoteTrack)

        const offer = await peerConnection.createOffer()
        ensureActive()

        signalingActive = true
        const joined = await signaling.joinVoiceChannel(channelId, {
          negotiation_id: currentNegotiationId,
          description: offer,
        })
        ensureActive()
        signalingSessionId = joined?.signaling_session_id
        if (!signalingSessionId) throw new Error("missing signaling session")

        signaling.onServerIce(receiveServerIce)
        signaling.onClose(() => fail("connection_lost"))
        signaling.onVoiceSessionEnded?.(receiveVoiceSessionEnded)
        signaling.onRosterCue?.(payload => {
          if (active && payload?.channel_id === channelId && ["join", "leave"].includes(payload?.cue)) {
            onCue({channelId, cue: payload.cue})
          }
        })

        await peerConnection.setLocalDescription(offer)
        ensureActive()
        const answer = await withDeadline(
          signaling.sendOffer({
            signaling_session_id: signalingSessionId,
            negotiation_id: currentNegotiationId,
            description: peerConnection.localDescription || offer,
          }),
          OFFER_REPLY_TIMEOUT_MS,
          setTimeoutFn,
          clearTimeoutFn
        )
        ensureActive()

        if (
          answer?.signaling_session_id !== signalingSessionId ||
          answer?.negotiation_id !== currentNegotiationId ||
          answer?.description?.type !== "answer" ||
          typeof answer.description.sdp !== "string"
        ) throw new Error("invalid answer")

        await peerConnection.setRemoteDescription(answer.description)
        ensureActive()
        answerApplied = true

        for (const candidate of pendingServerCandidates) {
          await peerConnection.addIceCandidate(candidate)
        }
        pendingServerCandidates = []
        pendingServerCandidateBytes = 0
        startRenewals()
      } catch (error) {
        if (active) fail(voiceFailure(error))
        throw error
      }
    },

    leave() {
      if (active || peerConnection) cleanup()
    },

    enableAudio() {
      return playRemoteAudio()
    },

    setDeafened(deafened) {
      if (remoteAudio) remoteAudio.muted = deafened === true
    },

    updateLocalVoiceState(state) {
      if (active) signaling?.sendLocalVoiceState?.(state)
    },
  }
}

function voiceFailure(error) {
  if (error?.voiceFailure === INCOMPATIBLE_AUDIO_OUTPUT_SLOTS) return error.voiceFailure
  if (error?.reason === INCOMPATIBLE_AUDIO_OUTPUT_SLOTS) return error.reason
  return "connection_failed"
}

function candidateByteSize(candidate) {
  try {
    return new TextEncoder().encode(JSON.stringify(candidate)).byteLength
  } catch (_) {
    return MAX_PENDING_SERVER_CANDIDATE_BYTES + 1
  }
}

function withDeadline(promise, timeoutMs, setTimeoutFn, clearTimeoutFn) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeoutFn(() => reject(new Error("offer reply timed out")), timeoutMs)
    Promise.resolve(promise).then(
      result => { clearTimeoutFn(timeout); resolve(result) },
      error => { clearTimeoutFn(timeout); reject(error) }
    )
  })
}

function createNegotiationId() {
  return globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random()}`
}
