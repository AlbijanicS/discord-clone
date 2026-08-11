import assert from "node:assert/strict"
import test from "node:test"

import {createVoicePeerAttempt} from "./voice_peer_attempt.js"

class FakeMediaStream {
  constructor(tracks = []) {
    this.tracks = [...tracks]
  }

  addTrack(track) {
    if (!this.tracks.includes(track)) this.tracks.push(track)
  }

  getTracks() {
    return [...this.tracks]
  }

  removeTrack(track) {
    this.tracks = this.tracks.filter(candidate => candidate !== track)
  }
}

globalThis.MediaStream = FakeMediaStream

function deferred() {
  let resolve
  let reject
  const promise = new Promise((nextResolve, nextReject) => {
    resolve = nextResolve
    reject = nextReject
  })

  return {promise, reject, resolve}
}

function fakeClock() {
  let elapsed = 0
  let nextId = 0
  const timers = new Map()

  return {
    advance(milliseconds) {
      const target = elapsed + milliseconds

      while (true) {
        const due = [...timers.entries()]
          .filter(([, timer]) => timer.at <= target)
          .sort(([, left], [, right]) => left.at - right.at)[0]
        if (!due) break

        const [id, timer] = due
        timers.delete(id)
        elapsed = timer.at
        timer.callback()
      }

      elapsed = target
    },
    clearTimeout(id) { timers.delete(id) },
    setTimeout(callback, delay) {
      const id = ++nextId
      timers.set(id, {at: elapsed + delay, callback})
      return id
    },
  }
}

function fakePeerConnection() {
  const handlers = new Map()

  return {
    addedCandidates: [],
    addedTransceivers: [],
    closed: false,
    connectionState: "new",
    addEventListener(event, callback) { handlers.set(event, callback) },
    addIceCandidate(candidate) { this.addedCandidates.push(candidate); return Promise.resolve() },
    addTransceiver(kindOrTrack, init) {
      const transceiver = {
        direction: init.direction,
        receiver: {track: remoteTrack(`remote-${this.addedTransceivers.length}`)},
        sender: {track: typeof kindOrTrack === "string" ? null : kindOrTrack},
      }
      this.addedTransceivers.push(transceiver)
      return transceiver
    },
    close() { this.closed = true },
    createOffer() { return Promise.resolve({type: "offer", sdp: "browser-offer"}) },
    setLocalDescription(description) { this.localDescription = description; return Promise.resolve() },
    setRemoteDescription(description) { this.remoteDescription = description; return Promise.resolve() },
    emit(event, payload) { handlers.get(event)?.(payload) },
  }
}

function remoteTrack(id) {
  const handlers = new Map()

  return {
    id,
    kind: "audio",
    addEventListener(event, callback) { handlers.set(event, callback) },
    removeEventListener(event) { handlers.delete(event) },
    hasListener(event) { return handlers.has(event) },
    end() { handlers.get("ended")?.() },
  }
}

function remoteAudio({play = () => Promise.resolve()} = {}) {
  return {
    autoplay: false,
    pauseCalls: 0,
    play,
    playCalls: 0,
    playsInline: false,
    srcObject: null,
    pause() { this.pauseCalls += 1 },
  }
}

function attemptFixture() {
  const peer = fakePeerConnection()
  const serverIce = []
  const closes = []
  const rosterCues = []
  const sessionEnded = []
  const signaling = {
    joinVoiceChannel: async () => ({signaling_session_id: "server-session"}),
    leave() {},
    onClose(callback) { closes.push(callback); return 1 },
    onRosterCue(callback) { rosterCues.push(callback); return 1 },
    onVoiceSessionEnded(callback) { sessionEnded.push(callback); return 1 },
    onServerIce(callback) { serverIce.push(callback); return 1 },
    sendIce() {},
    sendOffer: async () => ({
      signaling_session_id: "server-session",
      negotiation_id: "browser-negotiation",
      description: {type: "answer", sdp: "server-answer"},
    }),
  }

  return {closes, peer, rosterCues, serverIce, sessionEnded, signaling}
}

test("preflights one microphone connection and four Audio Output Slots before admission", async () => {
  const {peer, signaling} = attemptFixture()
  const states = []
  let admissionPayload
  let joinedAfterPreflight = false
  signaling.joinVoiceChannel = async (_channelId, payload) => {
    admissionPayload = payload
    joinedAfterPreflight = peer.addedTransceivers.length === 5
    return {signaling_session_id: "server-session"}
  }
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    negotiationId: () => "browser-negotiation",
    onState: state => states.push(state),
    signaling,
  })

  await attempt.connect({channelId: "voice-1", track: {id: "microphone"}})

  assert.equal(joinedAfterPreflight, true)
  assert.deepEqual(admissionPayload, {
    negotiation_id: "browser-negotiation",
    description: {type: "offer", sdp: "browser-offer"},
  })
  assert.deepEqual(
    peer.addedTransceivers.map(({direction, sender}) => ({direction, track: sender.track})),
    [
      {direction: "sendonly", track: {id: "microphone"}},
      {direction: "recvonly", track: null},
      {direction: "recvonly", track: null},
      {direction: "recvonly", track: null},
      {direction: "recvonly", track: null},
    ]
  )
  assert.deepEqual(peer.localDescription, {type: "offer", sdp: "browser-offer"})
  assert.deepEqual(peer.remoteDescription, {type: "answer", sdp: "server-answer"})
  assert.deepEqual(states, ["joining"])

  peer.connectionState = "connected"
  peer.emit("connectionstatechange")
  assert.deepEqual(states, ["joining", "connected"])
})

test("a connected silent microphone remains active without an RTP inactivity timeout", async () => {
  const {peer, signaling} = attemptFixture()
  const failures = []
  const states = []
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    negotiationId: () => "browser-negotiation",
    onFailure: failure => failures.push(failure),
    onState: state => states.push(state),
    signaling,
  })

  await attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
  peer.connectionState = "connected"
  peer.emit("connectionstatechange")

  assert.deepEqual(states, ["joining", "connected"])
  assert.deepEqual(failures, [])
  assert.equal(peer.closed, false)
})

test("renews the active signaling session every thirty seconds while a background tab remains active", async () => {
  const {peer, signaling} = attemptFixture()
  const clock = fakeClock()
  const renewals = []
  signaling.renewVoiceSession = renewal => {
    renewals.push(renewal)
    return {receive() { return this }}
  }
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    clearTimeoutFn: clock.clearTimeout,
    negotiationId: () => "browser-negotiation",
    setTimeoutFn: clock.setTimeout,
    signaling,
  })

  await attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
  clock.advance(60_000)

  assert.deepEqual(renewals, [
    {signaling_session_id: "server-session"},
    {signaling_session_id: "server-session"},
  ])
  assert.equal(peer.closed, false)
})

test("a missing renewal acknowledgement interrupts control-plane presentation and a valid delayed acknowledgement recovers only connected media", async () => {
  const {peer, signaling} = attemptFixture()
  const clock = fakeClock()
  const states = []
  let acknowledge
  signaling.renewVoiceSession = () => ({
    receive(status, callback) {
      if (status === "ok") acknowledge = callback
      return this
    },
  })
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    clearTimeoutFn: clock.clearTimeout,
    negotiationId: () => "browser-negotiation",
    onState: state => states.push(state),
    setTimeoutFn: clock.setTimeout,
    signaling,
  })

  await attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
  peer.connectionState = "connected"
  peer.emit("connectionstatechange")
  clock.advance(40_000)
  assert.equal(states.at(-1), "interrupted")

  peer.connectionState = "disconnected"
  peer.emit("connectionstatechange")
  acknowledge({signaling_session_id: "server-session"})
  assert.equal(states.at(-1), "interrupted")

  peer.connectionState = "connected"
  peer.emit("connectionstatechange")
  assert.equal(states.at(-1), "connected")
})

test("unacknowledged renewal expires after seventy-five seconds, while a rejected renewal is immediately terminal and stale replies do nothing", async () => {
  for (const outcome of ["silent", "rejected"]) {
    const {peer, signaling} = attemptFixture()
    const clock = fakeClock()
    const failures = []
    let rejectRenewal
    let acknowledge
    signaling.leave = () => { signaling.left = (signaling.left || 0) + 1 }
    signaling.renewVoiceSession = () => ({
      receive(status, callback) {
        if (status === "ok") acknowledge = callback
        if (status === "error") rejectRenewal = callback
        return this
      },
    })
    const attempt = createVoicePeerAttempt({
      PeerConnection: class { constructor() { return peer } },
      clearTimeoutFn: clock.clearTimeout,
      negotiationId: () => "browser-negotiation",
      onFailure: failure => failures.push(failure),
      setTimeoutFn: clock.setTimeout,
      signaling,
    })

    await attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
    clock.advance(30_000)
    if (outcome === "silent") clock.advance(45_000)
    else rejectRenewal({reason: "invalid_session"})

    assert.equal(peer.closed, true)
    assert.equal(signaling.left, 1)
    assert.deepEqual(failures, ["connection_lost"])
    acknowledge?.({signaling_session_id: "server-session"})
    assert.deepEqual(failures, ["connection_lost"])
  }
})

test("terminal cleanup cancels renewal traffic after the controller releases its attempt", async () => {
  const {peer, signaling} = attemptFixture()
  const clock = fakeClock()
  const renewals = []
  signaling.renewVoiceSession = renewal => {
    renewals.push(renewal)
    return {receive() { return this }}
  }
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    clearTimeoutFn: clock.clearTimeout,
    negotiationId: () => "browser-negotiation",
    setTimeoutFn: clock.setTimeout,
    signaling,
  })

  await attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
  attempt.leave()
  clock.advance(75_000)

  assert.deepEqual(renewals, [])
  assert.equal(peer.closed, true)
})

test("ends and releases only the matching attempt when the server ends its Voice Session", async () => {
  const {peer, sessionEnded, signaling} = attemptFixture()
  const failures = []
  signaling.leave = () => { signaling.left = (signaling.left || 0) + 1 }
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    negotiationId: () => "browser-negotiation",
    onFailure: failure => failures.push(failure),
    signaling,
  })

  await attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
  sessionEnded[0]({signaling_session_id: "stale-session"})
  assert.equal(peer.closed, false)

  sessionEnded[0]({signaling_session_id: "server-session"})
  sessionEnded[0]({signaling_session_id: "server-session"})

  assert.equal(peer.closed, true)
  assert.equal(signaling.left, 1)
  assert.deepEqual(failures, ["connection_lost"])
})

test("ignores an ended event from a retired attempt after a replacement connects", async () => {
  const first = attemptFixture()
  const second = attemptFixture()
  first.signaling.sendOffer = async () => ({
    signaling_session_id: "server-session",
    negotiation_id: "first-negotiation",
    description: {type: "answer", sdp: "server-answer"},
  })
  second.signaling.sendOffer = async () => ({
    signaling_session_id: "server-session",
    negotiation_id: "second-negotiation",
    description: {type: "answer", sdp: "server-answer"},
  })
  const firstAttempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return first.peer } },
    negotiationId: () => "first-negotiation",
    signaling: first.signaling,
  })
  const secondAttempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return second.peer } },
    negotiationId: () => "second-negotiation",
    signaling: second.signaling,
  })

  await firstAttempt.connect({channelId: "voice-1", track: {id: "first-microphone"}})
  firstAttempt.leave()
  await secondAttempt.connect({channelId: "voice-1", track: {id: "second-microphone"}})

  first.sessionEnded[0]({signaling_session_id: "server-session"})

  assert.equal(first.peer.closed, true)
  assert.equal(second.peer.closed, false)
})

test("reports a disconnected peer as interrupted without ending its Voice Session", async () => {
  const {peer, signaling} = attemptFixture()
  const states = []
  const failures = []
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    negotiationId: () => "browser-negotiation",
    onFailure: failure => failures.push(failure),
    onState: state => states.push(state),
    signaling,
  })

  await attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
  peer.connectionState = "disconnected"
  peer.emit("connectionstatechange")

  assert.deepEqual(states, ["joining", "interrupted"])
  assert.deepEqual(failures, [])
  assert.equal(peer.closed, false)
})

test("recovers a disconnected peer before its thirty-second deadline and isolates a stale deadline", async () => {
  const {peer, signaling} = attemptFixture()
  const clock = fakeClock()
  const failures = []
  const states = []
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    clearTimeoutFn: clock.clearTimeout,
    negotiationId: () => "browser-negotiation",
    onFailure: failure => failures.push(failure),
    onState: state => states.push(state),
    setTimeoutFn: clock.setTimeout,
    signaling,
  })

  await attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
  peer.connectionState = "connected"
  peer.emit("connectionstatechange")
  peer.connectionState = "disconnected"
  peer.emit("connectionstatechange")
  clock.advance(29_999)
  peer.connectionState = "connected"
  peer.emit("connectionstatechange")
  peer.connectionState = "disconnected"
  peer.emit("connectionstatechange")
  clock.advance(1)
  assert.deepEqual(failures, [])
  clock.advance(29_999)

  assert.equal(states.at(-1), "interrupted")
  assert.deepEqual(failures, ["connection_lost"])
  assert.equal(peer.closed, true)
})

test("ends an unrecovered disconnected peer at its thirty-second deadline", async () => {
  const {peer, signaling} = attemptFixture()
  const clock = fakeClock()
  const failures = []
  signaling.leave = () => { signaling.left = (signaling.left || 0) + 1 }
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    clearTimeoutFn: clock.clearTimeout,
    negotiationId: () => "browser-negotiation",
    onFailure: failure => failures.push(failure),
    setTimeoutFn: clock.setTimeout,
    signaling,
  })

  await attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
  peer.connectionState = "disconnected"
  peer.emit("connectionstatechange")
  clock.advance(30_000)

  assert.deepEqual(failures, ["connection_lost"])
  assert.equal(peer.closed, true)
  assert.equal(signaling.left, 1)
})

test("forwards server roster cues to the active Voice Owner Tab", async () => {
  const {rosterCues, signaling} = attemptFixture()
  const cues = []
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return fakePeerConnection() } },
    negotiationId: () => "browser-negotiation",
    onCue: cue => cues.push(cue),
    signaling,
  })

  await attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
  rosterCues[0]({channel_id: "voice-1", cue: "join"})

  assert.deepEqual(cues, [{channelId: "voice-1", cue: "join"}])
})

test("keeps four remote tracks separate in one stable aggregate playback stream", async () => {
  const {peer, signaling} = attemptFixture()
  const audio = remoteAudio({
    play() { this.playCalls += 1; return Promise.resolve() },
  })
  const playback = []
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    negotiationId: () => "browser-negotiation",
    onPlayback: outcome => playback.push(outcome),
    remoteAudio: audio,
    signaling,
  })

  await attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
  const aggregateStream = audio.srcObject
  const remoteTracks = peer.addedTransceivers.slice(1).map(transceiver => transceiver.receiver.track)

  peer.addedTransceivers.slice(1).forEach((transceiver, index) => {
    peer.emit("track", {track: remoteTracks[index], transceiver})
  })
  await new Promise(resolve => setImmediate(resolve))

  assert.equal(audio.autoplay, true)
  assert.equal(audio.playsInline, true)
  assert.equal(audio.srcObject, aggregateStream)
  assert.deepEqual(aggregateStream.getTracks(), remoteTracks)
  assert.equal(audio.playCalls, 4)
  assert.deepEqual(playback, ["playing", "playing", "playing", "playing"])

  remoteTracks[1].end()
  assert.equal(audio.srcObject, aggregateStream)
  assert.deepEqual(aggregateStream.getTracks(), [remoteTracks[0], remoteTracks[2], remoteTracks[3]])
})

test("a failed four-slot preflight is retryable and never requests server admission", async () => {
  const {peer, signaling} = attemptFixture()
  const failures = []
  let joins = 0
  signaling.joinVoiceChannel = async () => { joins += 1 }
  peer.addTransceiver = function(kindOrTrack, init) {
    if (this.addedTransceivers.length === 4) throw new Error("fifth media lane unavailable")
    return fakePeerConnection().addTransceiver.call(this, kindOrTrack, init)
  }
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    negotiationId: () => "browser-negotiation",
    onFailure: failure => failures.push(failure),
    signaling,
  })

  await assert.rejects(attempt.connect({channelId: "voice-1", track: {id: "microphone"}}))

  assert.equal(joins, 0)
  assert.equal(peer.closed, true)
  assert.deepEqual(failures, ["incompatible_audio_output_slots"])
})

test("a blocked automatic playback keeps the attempt active and Enable audio retries only playback", async () => {
  const {peer, signaling} = attemptFixture()
  let offers = 0
  signaling.sendOffer = async () => {
    offers += 1
    return {
      signaling_session_id: "server-session",
      negotiation_id: "browser-negotiation",
      description: {type: "answer", sdp: "server-answer"},
    }
  }
  let remainingFailures = 1
  const audio = remoteAudio({
    play() {
      this.playCalls += 1
      if (remainingFailures > 0) {
        remainingFailures -= 1
        return Promise.reject(new Error("autoplay blocked"))
      }
      return Promise.resolve()
    },
  })
  const failures = []
  const playback = []
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    negotiationId: () => "browser-negotiation",
    onFailure: failure => failures.push(failure),
    onPlayback: outcome => playback.push(outcome),
    remoteAudio: audio,
    signaling,
  })

  await attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
  const transceiver = peer.addedTransceivers[1]
  peer.emit("track", {track: transceiver.receiver.track, transceiver})
  await new Promise(resolve => setImmediate(resolve))
  await attempt.enableAudio()

  assert.equal(audio.playCalls, 2)
  assert.deepEqual(playback, ["blocked", "playing"])
  assert.deepEqual(failures, [])
  assert.equal(peer.closed, false)
  assert.equal(offers, 1)
})

test("releases remote audio exactly once on explicit leave and terminal connection failure", async () => {
  for (const terminal of ["leave", "failed"]) {
    const {peer, signaling} = attemptFixture()
    const audio = remoteAudio({
      play() { this.playCalls += 1; return Promise.resolve() },
    })
    const attempt = createVoicePeerAttempt({
      PeerConnection: class { constructor() { return peer } },
      negotiationId: () => "browser-negotiation",
      remoteAudio: audio,
      signaling,
    })

    await attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
    const transceiver = peer.addedTransceivers[1]
    const remote = transceiver.receiver.track
    peer.emit("track", {track: remote, transceiver})
    await new Promise(resolve => setImmediate(resolve))
    assert.deepEqual(audio.srcObject.getTracks(), [remote])
    assert.equal(remote.hasListener("ended"), true)
    if (terminal === "leave") attempt.leave()
    else {
      peer.connectionState = "failed"
      peer.emit("connectionstatechange")
    }
    attempt.leave()

    assert.equal(audio.pauseCalls, 1)
    assert.equal(audio.srcObject, null)
    assert.equal(remote.hasListener("ended"), false)
    assert.equal(peer.closed, true)
  }
})

test("buffers matching server ICE until the answer is applied, then preserves arrival order", async () => {
  const {peer, serverIce, signaling} = attemptFixture()
  const answer = deferred()
  signaling.sendOffer = async () => answer.promise
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    negotiationId: () => "browser-negotiation",
    signaling,
  })

  const connecting = attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
  await new Promise(resolve => setImmediate(resolve))
  serverIce[0]({signaling_session_id: "server-session", negotiation_id: "browser-negotiation", candidate: {candidate: "first"}})
  serverIce[0]({signaling_session_id: "server-session", negotiation_id: "stale", candidate: {candidate: "stale"}})
  assert.deepEqual(peer.addedCandidates, [])

  answer.resolve({
    signaling_session_id: "server-session",
    negotiation_id: "browser-negotiation",
    description: {type: "answer", sdp: "server-answer"},
  })
  await connecting

  assert.deepEqual(peer.addedCandidates, [{candidate: "first"}])
})

test("buffers the correlated server end marker until the answer, then applies ExWebRTC's empty-candidate form", async () => {
  const {peer, serverIce, signaling} = attemptFixture()
  const answer = deferred()
  signaling.sendOffer = async () => answer.promise
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    negotiationId: () => "browser-negotiation",
    signaling,
  })

  const connecting = attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
  await new Promise(resolve => setImmediate(resolve))
  serverIce[0]({
    signaling_session_id: "server-session",
    negotiation_id: "browser-negotiation",
    end_of_candidates: true,
  })

  answer.resolve({
    signaling_session_id: "server-session",
    negotiation_id: "browser-negotiation",
    description: {type: "answer", sdp: "server-answer"},
  })
  await connecting

  assert.deepEqual(peer.addedCandidates, [{candidate: ""}])
})

test("applies a correlated server end marker received after the answer as an empty candidate", async () => {
  const {peer, serverIce, signaling} = attemptFixture()
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    negotiationId: () => "browser-negotiation",
    signaling,
  })

  await attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
  serverIce[0]({
    signaling_session_id: "server-session",
    negotiation_id: "browser-negotiation",
    end_of_candidates: true,
  })

  assert.deepEqual(peer.addedCandidates, [{candidate: ""}])
})

test("sends browser ICE candidates individually and never sends the null gathering event", async () => {
  const {peer, signaling} = attemptFixture()
  const sent = []
  signaling.sendIce = payload => sent.push(payload)
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    negotiationId: () => "browser-negotiation",
    signaling,
  })

  await attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
  peer.emit("icecandidate", {candidate: {candidate: "local-candidate"}})
  peer.emit("icecandidate", {candidate: null})

  assert.deepEqual(sent, [{
    signaling_session_id: "server-session",
    negotiation_id: "browser-negotiation",
    candidate: {candidate: "local-candidate"},
  }])
})

test("a rejected offer is terminal, closes the peer, and leaves signaling", async () => {
  const {peer, signaling} = attemptFixture()
  const failures = []
  let leaves = 0
  signaling.leave = () => { leaves += 1 }
  signaling.sendOffer = async () => { throw new Error("rejected") }
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    negotiationId: () => "browser-negotiation",
    onFailure: failure => failures.push(failure),
    signaling,
  })

  await assert.rejects(attempt.connect({channelId: "voice-1", track: {id: "microphone"}}))
  assert.equal(peer.closed, true)
  assert.equal(leaves, 1)
  assert.deepEqual(failures, ["connection_failed"])
})

test("an unexpected signaling-topic close is terminal and releases the browser peer", async () => {
  const {closes, peer, signaling} = attemptFixture()
  const failures = []
  let leaves = 0
  signaling.leave = () => { leaves += 1 }
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    negotiationId: () => "browser-negotiation",
    onFailure: failure => failures.push(failure),
    signaling,
  })

  await attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
  closes[0]()

  assert.equal(peer.closed, true)
  assert.equal(leaves, 1)
  assert.deepEqual(failures, ["connection_lost"])
})

test("explicit Leave closes one active browser peer and leaves its topic only once", async () => {
  const {peer, signaling} = attemptFixture()
  let leaves = 0
  signaling.leave = () => { leaves += 1 }
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    negotiationId: () => "browser-negotiation",
    signaling,
  })

  await attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
  attempt.leave()
  attempt.leave()

  assert.equal(peer.closed, true)
  assert.equal(leaves, 1)
})

test("Leave clears server ICE buffered before the answer", async () => {
  const {peer, serverIce, signaling} = attemptFixture()
  const answer = deferred()
  signaling.sendOffer = () => answer.promise
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    negotiationId: () => "browser-negotiation",
    signaling,
  })

  const connecting = attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
  await new Promise(resolve => setImmediate(resolve))
  serverIce[0]({
    signaling_session_id: "server-session",
    negotiation_id: "browser-negotiation",
    candidate: {candidate: "early-candidate"},
  })
  attempt.leave()
  answer.resolve({
    signaling_session_id: "server-session",
    negotiation_id: "browser-negotiation",
    description: {type: "answer", sdp: "server-answer"},
  })

  await assert.rejects(connecting, /cancelled/)
  assert.deepEqual(peer.addedCandidates, [])
})

test("failed and closed browser connection states are terminal and use the retryable lost-connection state", async () => {
  for (const state of ["failed", "closed"]) {
    const {peer, signaling} = attemptFixture()
    const failures = []
    const attempt = createVoicePeerAttempt({
      PeerConnection: class { constructor() { return peer } },
      negotiationId: () => "browser-negotiation",
      onFailure: failure => failures.push(failure),
      signaling,
    })

    await attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
    peer.connectionState = state
    peer.emit("connectionstatechange")

    assert.equal(peer.closed, true)
    assert.deepEqual(failures, ["connection_lost"])
  }
})

test("an offer reply that exceeds ten seconds is terminal", async () => {
  const {peer, signaling} = attemptFixture()
  let timeoutCallback
  const failures = []
  signaling.sendOffer = () => new Promise(() => {})
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    negotiationId: () => "browser-negotiation",
    onFailure: failure => failures.push(failure),
    setTimeoutFn(callback, delay) { assert.equal(delay, 10_000); timeoutCallback = callback; return 1 },
    clearTimeoutFn() {},
    signaling,
  })

  const connecting = attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
  await new Promise(resolve => setImmediate(resolve))
  timeoutCallback()

  await assert.rejects(connecting, /timed out/)
  assert.equal(peer.closed, true)
  assert.deepEqual(failures, ["connection_failed"])
})

test("Leave during topic admission closes the preflighted browser peer before a late reply", async () => {
  const {peer, signaling} = attemptFixture()
  const joined = deferred()
  let peerCreations = 0
  let leaves = 0
  signaling.joinVoiceChannel = () => joined.promise
  signaling.leave = () => { leaves += 1 }
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { peerCreations += 1; return peer } },
    signaling,
  })

  const connecting = attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
  const rejected = assert.rejects(connecting, /cancelled/)
  await new Promise(resolve => setImmediate(resolve))
  attempt.leave()
  joined.resolve({signaling_session_id: "server-session"})

  await rejected
  assert.equal(peerCreations, 1)
  assert.equal(peer.closed, true)
  assert.equal(leaves, 1)
})

test("bounds server ICE buffered before the answer at sixteen candidates", async () => {
  const {peer, serverIce, signaling} = attemptFixture()
  const answer = deferred()
  signaling.sendOffer = () => answer.promise
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    negotiationId: () => "browser-negotiation",
    signaling,
  })

  const connecting = attempt.connect({channelId: "voice-1", track: {id: "microphone"}})
  await new Promise(resolve => setImmediate(resolve))
  for (let number = 0; number < 17; number += 1) {
    serverIce[0]({
      signaling_session_id: "server-session",
      negotiation_id: "browser-negotiation",
      candidate: {candidate: `candidate-${number}`},
    })
  }
  answer.resolve({
    signaling_session_id: "server-session",
    negotiation_id: "browser-negotiation",
    description: {type: "answer", sdp: "server-answer"},
  })

  await connecting
  assert.equal(peer.addedCandidates.length, 16)
  assert.deepEqual(peer.addedCandidates[0], {candidate: "candidate-0"})
  assert.deepEqual(peer.addedCandidates.at(-1), {candidate: "candidate-15"})
})
