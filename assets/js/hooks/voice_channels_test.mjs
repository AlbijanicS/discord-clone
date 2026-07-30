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
  let currentState = {channelId: null, channelName: null, status: "idle", workspaceId: null}
  let listener
  const calls = []
  const status = {textContent: ""}
  const controls = {hidden: true}
  const retryControls = {hidden: true}
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
    retry() {
      calls.push({name: "retry"})
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
          "[data-voice-channel-retry-controls]": retryControls,
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
    retryControls,
    status,
  }
}

test("the Voice Channel UI renders its controller lifecycle and sends a Voice Channel click to it", () => {
  const {calls, controls, emit, hook, muteButton, retryControls, status} = mountVoiceChannels()

  assert.equal(status.textContent, "Voice is not connected.")
  assert.equal(controls.hidden, true)
  assert.equal(retryControls.hidden, true)

  const joinButton = {
    dataset: {voiceChannelId: "voice-1", voiceChannelName: "lobby", workspaceId: "workspace-1"},
    closest(selector) {
      return selector === "[data-voice-channel-join]" ? this : null
    },
  }

  document.dispatch("click", {target: joinButton})
  assert.deepEqual(calls, [{name: "join", value: {id: "voice-1", name: "lobby", workspaceId: "workspace-1"}}])

  emit({channelId: "voice-1", channelName: "lobby", status: "requesting", workspaceId: "workspace-1"})
  assert.equal(status.textContent, "Allow microphone access")
  assert.equal(controls.hidden, true)

  emit({channelId: "voice-1", channelName: "lobby", retryable: true, status: "permission_denied", workspaceId: "workspace-1"})
  assert.equal(status.textContent, "Microphone permission was denied. Check your browser settings, then retry.")
  assert.equal(retryControls.hidden, false)

  const retryButton = {closest: selector => selector === "[data-voice-channel-retry]" ? retryButton : null}
  document.dispatch("click", {target: retryButton})
  assert.deepEqual(calls.at(-1), {name: "retry"})

  emit({channelId: "voice-1", channelName: "lobby", error: "taken_over", retryable: false, status: "taken_over", workspaceId: "workspace-1"})
  assert.equal(status.textContent, "Voice moved to another tab.")
  assert.equal(controls.hidden, true)
  assert.equal(retryControls.hidden, true)

  emit({channelId: "voice-1", channelName: "lobby", status: "joining", workspaceId: "workspace-1"})
  assert.equal(status.textContent, "Joining voice…")
  assert.equal(controls.hidden, false)
  assert.equal(muteButton.textContent, "Mute")
  assert.equal(muteButton["aria-pressed"], "false")

  emit({channelId: "voice-1", channelName: "lobby", status: "connected", workspaceId: "workspace-1"})
  assert.equal(status.textContent, "Connected")

  emit({channelId: "voice-1", channelName: "lobby", error: "connection_failed", retryable: true, status: "connection_failed", workspaceId: "workspace-1"})
  assert.equal(status.textContent, "Couldn’t connect — try again")

  emit({channelId: "voice-1", channelName: "lobby", error: "connection_lost", retryable: true, status: "connection_lost", workspaceId: "workspace-1"})
  assert.equal(status.textContent, "Connection lost — try again")

  emit({channelId: "voice-1", channelName: "lobby", status: "muted", workspaceId: "workspace-1"})
  assert.equal(status.textContent, "Connected")
  assert.equal(muteButton.textContent, "Unmute")
  assert.equal(muteButton["aria-pressed"], "true")

  emit({channelId: null, channelName: null, status: "idle", workspaceId: null})
  assert.equal(status.textContent, "Voice is not connected.")
  assert.equal(controls.hidden, true)

  hook.destroyed()
})
