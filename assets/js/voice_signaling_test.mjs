import assert from "node:assert/strict"
import test from "node:test"

import {createVoiceSignaling} from "./voice_signaling.js"

test("joins the dedicated Voice topic and leaves through Phoenix's built-in lifecycle", () => {
  const events = []
  const joinPush = {receive() { return joinPush }}
  const leavePush = {receive() { return leavePush }}

  class FakeSocket {
    constructor(path) { events.push(["new", path]) }
    connect() { events.push(["connect"]) }
    channel(topic, params) {
      events.push(["channel", topic, params])
      return {join() { return joinPush }, leave() { events.push(["leave"]); return leavePush }}
    }
    disconnect() { events.push(["disconnect"]) }
  }

  const signaling = createVoiceSignaling({Socket: FakeSocket})

  assert.equal(signaling.join("voice-channel-id"), joinPush)
  assert.deepEqual(events, [
    ["new", "/voice"],
    ["connect"],
    ["channel", "voice:voice-channel-id", {}],
  ])

  assert.equal(signaling.leave(), leavePush)
  assert.deepEqual(events.at(-1), ["leave"])
})
