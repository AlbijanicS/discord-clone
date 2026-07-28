import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import test from "node:test"

const controllerSource = await readFile(new URL("./voice_controller.js", import.meta.url), "utf8")
const controllerModuleUrl = `data:text/javascript;base64,${Buffer.from(controllerSource).toString("base64")}`
const {createVoiceController} = await import(controllerModuleUrl)

function deferred() {
  let resolve
  let reject
  const promise = new Promise((nextResolve, nextReject) => {
    resolve = nextResolve
    reject = nextReject
  })

  return {promise, reject, resolve}
}

function track() {
  const listeners = new Map()

  return {
    enabled: true,
    stopped: false,
    stop() {
      this.stopped = true
    },
    addEventListener(name, listener) {
      listeners.set(name, listener)
    },
    removeEventListener(name) {
      listeners.delete(name)
    },
    end() {
      listeners.get("ended")?.()
    },
  }
}

function stream(...tracks) {
  return {
    getAudioTracks() {
      return tracks
    },
  }
}

test("a Voice Channel click requests capture, mutes, unmutes, and leaves without another prompt", async () => {
  const capture = deferred()
  let captureRequests = 0
  const mediaDevices = {
    getUserMedia(constraints) {
      captureRequests += 1
      assert.deepEqual(constraints, {audio: true})
      return capture.promise
    },
  }
  const controller = createVoiceController({mediaDevices})
  const microphoneTrack = track()
  const secondaryTrack = track()

  assert.deepEqual(controller.state(), {channelId: null, channelName: null, status: "idle", workspaceId: null})

  const join = controller.join({id: "voice-1", name: "lobby", workspaceId: "workspace-1"})
  assert.deepEqual(controller.state(), {
    channelId: "voice-1",
    channelName: "lobby",
    status: "requesting",
    workspaceId: "workspace-1",
  })

  capture.resolve(stream(microphoneTrack, secondaryTrack))
  await join
  assert.equal(controller.state().status, "capturing")

  const reattachedState = []
  const unsubscribe = controller.subscribe(state => reattachedState.push(state))
  assert.deepEqual(reattachedState, [controller.state()])
  assert.equal(captureRequests, 1)
  unsubscribe()

  controller.toggleMute()
  assert.equal(controller.state().status, "muted")
  assert.equal(microphoneTrack.enabled, false)

  controller.toggleMute()
  assert.equal(controller.state().status, "capturing")
  assert.equal(microphoneTrack.enabled, true)

  controller.leave()
  assert.deepEqual(controller.state(), {channelId: null, channelName: null, status: "idle", workspaceId: null})
  assert.equal(microphoneTrack.stopped, true)
  assert.equal(secondaryTrack.stopped, true)
})

test("leaving while permission is pending stops a late stream instead of restoring capture", async () => {
  const capture = deferred()
  const controller = createVoiceController({
    mediaDevices: {getUserMedia: () => capture.promise},
  })
  const microphoneTrack = track()

  const join = controller.join({id: "voice-1", name: "lobby", workspaceId: "workspace-1"})
  controller.leave()
  capture.resolve(stream(microphoneTrack))
  await join

  assert.deepEqual(controller.state(), {channelId: null, channelName: null, status: "idle", workspaceId: null})
  assert.equal(microphoneTrack.stopped, true)
})

test("a denied browser permission keeps the selected Voice Channel and offers a retry", async () => {
  const controller = createVoiceController({
    mediaDevices: {
      getUserMedia: () => Promise.reject({name: "NotAllowedError"}),
    },
  })

  await controller.join({id: "voice-1", name: "lobby", workspaceId: "workspace-1"})

  assert.deepEqual(controller.state(), {
    channelId: "voice-1",
    channelName: "lobby",
    error: "permission_denied",
    retryable: true,
    status: "permission_denied",
    workspaceId: "workspace-1",
  })
})

test("browser failures have safe understandable states", async () => {
  const cases = [
    [{name: "NotAllowedError"}, "permission_denied", true],
    [{name: "NotFoundError"}, "no_device", true],
    [{name: "SecurityError"}, "insecure_context", false],
    [{name: "NotSupportedError"}, "unsupported", false],
    [{name: "UnexpectedError"}, "unknown_error", true],
  ]

  for (const [error, expected, retryable] of cases) {
    const controller = createVoiceController({mediaDevices: {getUserMedia: () => Promise.reject(error)}})
    await controller.join({id: "voice-1", name: "lobby", workspaceId: "workspace-1"})
    assert.equal(controller.state().status, expected)
    assert.equal(controller.state().retryable, retryable)
  }

  const unsupported = createVoiceController({mediaDevices: undefined})
  await unsupported.join({id: "voice-1", name: "lobby", workspaceId: "workspace-1"})
  assert.equal(unsupported.state().status, "unsupported")
  assert.equal(unsupported.state().retryable, false)

  const insecure = createVoiceController({mediaDevices: {getUserMedia() { throw new Error("must not request") }}, secureContext: false})
  await insecure.join({id: "voice-1", name: "lobby", workspaceId: "workspace-1"})
  assert.equal(insecure.state().status, "insecure_context")
  assert.equal(insecure.state().retryable, false)
})

test("retry makes a fresh request for the failed Voice Channel", async () => {
  const capture = deferred()
  let requests = 0
  const controller = createVoiceController({
    mediaDevices: {
      getUserMedia() {
        requests += 1
        return requests === 1 ? Promise.reject({name: "NotAllowedError"}) : capture.promise
      },
    },
  })
  const microphoneTrack = track()

  await controller.join({id: "voice-1", name: "lobby", workspaceId: "workspace-1"})
  const retry = controller.retry()
  capture.resolve(stream(microphoneTrack))
  await retry

  assert.equal(requests, 2)
  assert.equal(controller.state().status, "capturing")
})

test("rejoining an active Voice Channel is idempotent and switching stops old tracks first", async () => {
  const first = deferred()
  const second = deferred()
  let requests = 0
  const controller = createVoiceController({
    mediaDevices: {getUserMedia: () => ++requests === 1 ? first.promise : second.promise},
  })
  const firstTrack = track()
  const secondTrack = track()

  const initialJoin = controller.join({id: "voice-1", name: "lobby", workspaceId: "workspace-1"})
  first.resolve(stream(firstTrack))
  await initialJoin
  await controller.join({id: "voice-1", name: "lobby", workspaceId: "workspace-1"})
  assert.equal(requests, 1)

  const switchJoin = controller.join({id: "voice-2", name: "standup", workspaceId: "workspace-1"})
  assert.equal(firstTrack.stopped, true)
  second.resolve(stream(secondTrack))
  await switchJoin
  assert.deepEqual(controller.state(), {channelId: "voice-2", channelName: "standup", status: "capturing", workspaceId: "workspace-1"})
})

test("conflicting Voice Channel clicks do not create more permission requests while one is pending", async () => {
  const capture = deferred()
  let requests = 0
  const controller = createVoiceController({
    mediaDevices: {getUserMedia: () => { requests += 1; return capture.promise }},
  })

  const firstJoin = controller.join({id: "voice-1", name: "lobby", workspaceId: "workspace-1"})
  await controller.join({id: "voice-2", name: "standup", workspaceId: "workspace-1"})
  await controller.join({id: "voice-3", name: "planning", workspaceId: "workspace-1"})

  assert.equal(requests, 1)
  assert.equal(controller.state().channelId, "voice-1")
  capture.resolve(stream(track()))
  await firstJoin
})

test("an externally ended track and repeated teardown release all local ownership", async () => {
  const microphoneTrack = track()
  const secondaryTrack = track()
  const controller = createVoiceController({mediaDevices: {getUserMedia: () => Promise.resolve(stream(microphoneTrack, secondaryTrack))}})

  await controller.join({id: "voice-1", name: "lobby", workspaceId: "workspace-1"})
  microphoneTrack.end()

  assert.deepEqual(controller.state(), {
    channelId: "voice-1",
    channelName: "lobby",
    error: "externally_ended",
    retryable: true,
    status: "externally_ended",
    workspaceId: "workspace-1",
  })
  assert.equal(microphoneTrack.stopped, true)
  assert.equal(secondaryTrack.stopped, true)

  controller.teardown()
  controller.teardown()
  assert.deepEqual(controller.state(), {channelId: null, channelName: null, status: "idle", workspaceId: null})
})
