const ICE_SERVERS = []
const MAX_PENDING_SERVER_CANDIDATES = 16
const MAX_PENDING_SERVER_CANDIDATE_BYTES = MAX_PENDING_SERVER_CANDIDATES * 8 * 1024
const OFFER_REPLY_TIMEOUT_MS = 10_000

export function createVoicePeerAttempt({
  PeerConnection = globalThis.RTCPeerConnection,
  negotiationId = createNegotiationId,
  onFailure = () => {},
  onPlayback = () => {},
  onState = () => {},
  remoteAudio = null,
  signaling,
  setTimeoutFn = globalThis.setTimeout,
  clearTimeoutFn = globalThis.clearTimeout,
} = {}) {
  let active = false
  let answerApplied = false
  let peerConnection = null
  let pendingServerCandidates = []
  let pendingServerCandidateBytes = 0
  let signalingSessionId = null
  let currentNegotiationId = null

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
    releaseRemoteAudio()
    peerConnection?.close()
    peerConnection = null
    signaling?.leave()
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
    if (!active || !remoteAudio) return

    const stream = event?.streams?.[0] || createRemoteStream(event?.track)
    if (!stream) return

    remoteAudio.autoplay = true
    remoteAudio.playsInline = true
    remoteAudio.srcObject = stream
    playRemoteAudio()
  }

  function releaseRemoteAudio() {
    if (!remoteAudio?.srcObject) return

    remoteAudio.pause?.()
    remoteAudio.srcObject = null
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

    if (peerConnection.connectionState === "connected") onState("connected")
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
      currentNegotiationId = negotiationId()
      onState("joining")

      try {
        const joined = await signaling.joinVoiceChannel(channelId)
        ensureActive()
        signalingSessionId = joined?.signaling_session_id
        if (!signalingSessionId) throw new Error("missing signaling session")

        peerConnection = new PeerConnection({iceServers: ICE_SERVERS})
        peerConnection.addEventListener("icecandidate", sendLocalIce)
        peerConnection.addEventListener("connectionstatechange", handleConnectionStateChange)
        peerConnection.addEventListener("track", receiveRemoteTrack)
        signaling.onServerIce(receiveServerIce)
        signaling.onClose(() => fail("connection_lost"))
        peerConnection.addTrack(track)

        const offer = await peerConnection.createOffer()
        ensureActive()
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
      } catch (error) {
        if (active) fail()
        throw error
      }
    },

    leave() {
      if (active || peerConnection) cleanup()
    },

    enableAudio() {
      return playRemoteAudio()
    },
  }
}

function createRemoteStream(track) {
  if (!track || typeof globalThis.MediaStream !== "function") return null
  return new globalThis.MediaStream([track])
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
