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
  return {
    enabled: true,
    stopped: false,
    stop() {
      this.stopped = true
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
  const mediaDevices = {
    getUserMedia(constraints) {
      assert.deepEqual(constraints, {audio: true})
      return capture.promise
    },
  }
  const controller = createVoiceController({mediaDevices})
  const microphoneTrack = track()
  const secondaryTrack = track()

  assert.deepEqual(controller.state(), {channelId: null, channelName: null, status: "idle"})

  const join = controller.join({id: "voice-1", name: "lobby"})
  assert.deepEqual(controller.state(), {
    channelId: "voice-1",
    channelName: "lobby",
    status: "requesting",
  })

  capture.resolve(stream(microphoneTrack, secondaryTrack))
  await join
  assert.equal(controller.state().status, "capturing")

  controller.toggleMute()
  assert.equal(controller.state().status, "muted")
  assert.equal(microphoneTrack.enabled, false)

  controller.toggleMute()
  assert.equal(controller.state().status, "capturing")
  assert.equal(microphoneTrack.enabled, true)

  controller.leave()
  assert.deepEqual(controller.state(), {channelId: null, channelName: null, status: "idle"})
  assert.equal(microphoneTrack.stopped, true)
  assert.equal(secondaryTrack.stopped, true)
})

test("leaving while permission is pending stops a late stream instead of restoring capture", async () => {
  const capture = deferred()
  const controller = createVoiceController({
    mediaDevices: {getUserMedia: () => capture.promise},
  })
  const microphoneTrack = track()

  const join = controller.join({id: "voice-1", name: "lobby"})
  controller.leave()
  capture.resolve(stream(microphoneTrack))
  await join

  assert.deepEqual(controller.state(), {channelId: null, channelName: null, status: "idle"})
  assert.equal(microphoneTrack.stopped, true)
})
