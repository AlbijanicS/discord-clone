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

test("pushes a fake offer so callers receive Phoenix's correlated reply", () => {
  const pushes = []
  const receives = []
  const offerPush = {
    receive(status, callback) {
      receives.push([status, callback])
      return offerPush
    },
  }

  class FakeSocket {
    connect() {}
    channel() {
      return {
        join() { return {receive() { return this }} },
        leave() { return {receive() { return this }} },
        push(event, payload) {
          pushes.push([event, payload])
          return offerPush
        },
      }
    }
  }

  const signaling = createVoiceSignaling({Socket: FakeSocket})
  signaling.join("voice-channel-id")

  const offer = {
    signaling_session_id: "current-signaling-session",
    label: "fake-offer",
    sequence: 7,
  }

  const returnedPush = signaling.sendFakeOffer(offer)

  assert.equal(returnedPush, offerPush)
  assert.deepEqual(pushes, [["offer", offer]])

  const answer = {
    signaling_session_id: "current-signaling-session",
    label: "fake-answer",
    sequence: 7,
  }
  let receivedAnswer = null

  returnedPush.receive("ok", reply => { receivedAnswer = reply })
  receives[0][1](answer)

  assert.deepEqual(receivedAnswer, answer)
})
