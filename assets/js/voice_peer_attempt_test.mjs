import assert from "node:assert/strict"
import test from "node:test"

import {createVoicePeerAttempt} from "./voice_peer_attempt.js"

function deferred() {
  let resolve
  let reject
  const promise = new Promise((nextResolve, nextReject) => {
    resolve = nextResolve
    reject = nextReject
  })

  return {promise, reject, resolve}
}

function fakePeerConnection() {
  const handlers = new Map()

  return {
    addedCandidates: [],
    addedTracks: [],
    closed: false,
    connectionState: "new",
    addEventListener(event, callback) { handlers.set(event, callback) },
    addIceCandidate(candidate) { this.addedCandidates.push(candidate); return Promise.resolve() },
    addTrack(track) { this.addedTracks.push(track) },
    close() { this.closed = true },
    createOffer() { return Promise.resolve({type: "offer", sdp: "browser-offer"}) },
    setLocalDescription(description) { this.localDescription = description; return Promise.resolve() },
    setRemoteDescription(description) { this.remoteDescription = description; return Promise.resolve() },
    emit(event, payload) { handlers.get(event)?.(payload) },
  }
}

function attemptFixture() {
  const peer = fakePeerConnection()
  const serverIce = []
  const signaling = {
    joinVoiceChannel: async () => ({signaling_session_id: "server-session"}),
    leave() {},
    onServerIce(callback) { serverIce.push(callback); return 1 },
    sendIce() {},
    sendOffer: async () => ({
      signaling_session_id: "server-session",
      negotiation_id: "browser-negotiation",
      description: {type: "answer", sdp: "server-answer"},
    }),
  }

  return {peer, serverIce, signaling}
}

test("negotiates one supplied audio track and waits for connected before reporting success", async () => {
  const {peer, signaling} = attemptFixture()
  const states = []
  const attempt = createVoicePeerAttempt({
    PeerConnection: class { constructor() { return peer } },
    negotiationId: () => "browser-negotiation",
    onState: state => states.push(state),
    signaling,
  })

  await attempt.connect({channelId: "voice-1", track: {id: "microphone"}})

  assert.deepEqual(peer.addedTracks, [{id: "microphone"}])
  assert.deepEqual(peer.localDescription, {type: "offer", sdp: "browser-offer"})
  assert.deepEqual(peer.remoteDescription, {type: "answer", sdp: "server-answer"})
  assert.deepEqual(states, ["joining"])

  peer.connectionState = "connected"
  peer.emit("connectionstatechange")
  assert.deepEqual(states, ["joining", "connected"])
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

test("Leave during topic admission prevents a late reply from creating a browser peer", async () => {
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
  attempt.leave()
  joined.resolve({signaling_session_id: "server-session"})

  await rejected
  assert.equal(peerCreations, 0)
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
