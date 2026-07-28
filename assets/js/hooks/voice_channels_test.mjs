import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import test from "node:test"

const hookSource = await readFile(new URL("./voice_channels.js", import.meta.url), "utf8")
const hookModuleUrl = `data:text/javascript;base64,${Buffer.from(hookSource.replace('import voiceController from "./voice_controller"', "const voiceController = null")).toString("base64")}`
const {createVoiceChannels} = await import(hookModuleUrl)

function eventTarget() {
  const listeners = new Map()

  return {
    addEventListener(name, listener) {
      listeners.set(name, listener)
    },
    removeEventListener(name) {
      listeners.delete(name)
    },
    dispatch(name, event = {}) {
      listeners.get(name)?.(event)
    },
  }
}

function mountVoiceChannels() {
  let currentState = {channelId: null, channelName: null, status: "idle"}
  let listener
  const calls = []
  const status = {textContent: ""}
  const controls = {hidden: true}
  const muteButton = {
    textContent: "",
    setAttribute(name, value) {
      this[name] = value
    },
  }

  globalThis.document = eventTarget()
  const controller = {
    join(channel) {
      calls.push({name: "join", value: channel})
    },
    leave() {
      calls.push({name: "leave"})
    },
    state() {
      return currentState
    },
    subscribe(nextListener) {
      listener = nextListener
      listener(currentState)
      return () => listener = null
    },
    toggleMute() {
      calls.push({name: "toggleMute"})
    },
  }
  const hook = {
    ...createVoiceChannels(controller),
    el: {
      querySelector(selector) {
        return {
          "[data-voice-channel-local-controls]": controls,
          "[data-voice-channel-mute]": muteButton,
          "[data-voice-channel-status]": status,
        }[selector]
      },
    },
  }

  hook.mounted()

  return {
    calls,
    controls,
    emit(state) {
      currentState = state
      listener(state)
    },
    hook,
    muteButton,
    status,
  }
}

test("the Voice Channel UI renders its controller lifecycle and sends a Voice Channel click to it", () => {
  const {calls, controls, emit, hook, muteButton, status} = mountVoiceChannels()

  assert.equal(status.textContent, "Voice is not connected.")
  assert.equal(controls.hidden, true)

  const joinButton = {
    dataset: {voiceChannelId: "voice-1", voiceChannelName: "lobby"},
    closest(selector) {
      return selector === "[data-voice-channel-join]" ? this : null
    },
  }

  document.dispatch("click", {target: joinButton})
  assert.deepEqual(calls, [{name: "join", value: {id: "voice-1", name: "lobby"}}])

  emit({channelId: "voice-1", channelName: "lobby", status: "requesting"})
  assert.equal(status.textContent, "Requesting microphone for lobby.")
  assert.equal(controls.hidden, true)

  emit({channelId: "voice-1", channelName: "lobby", status: "capturing"})
  assert.equal(status.textContent, "Capturing microphone in lobby.")
  assert.equal(controls.hidden, false)
  assert.equal(muteButton.textContent, "Mute")
  assert.equal(muteButton["aria-pressed"], "false")

  emit({channelId: "voice-1", channelName: "lobby", status: "muted"})
  assert.equal(status.textContent, "Microphone muted in lobby.")
  assert.equal(muteButton.textContent, "Unmute")
  assert.equal(muteButton["aria-pressed"], "true")

  emit({channelId: null, channelName: null, status: "idle"})
  assert.equal(status.textContent, "Voice is not connected.")
  assert.equal(controls.hidden, true)

  hook.destroyed()
})
