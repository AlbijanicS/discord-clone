import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import test from "node:test"

const hookSource = await readFile(new URL("./voice_controls.js", import.meta.url), "utf8")
const hookModuleUrl = `data:text/javascript;base64,${Buffer.from(hookSource.replace('import voiceController from "./voice_controller"', "const voiceController = null")).toString("base64")}`
const {createVoiceControls} = await import(hookModuleUrl)

function eventTarget() {
  const listeners = new Map()

  return {
    addEventListener(name, listener) { listeners.set(name, listener) },
    removeEventListener(name) { listeners.delete(name) },
    dispatch(name, event = {}) { listeners.get(name)?.(event) },
  }
}

function mountVoiceControls(state) {
  let currentState = state
  let listener
  const calls = []
  const channel = {textContent: ""}
  const status = {textContent: ""}
  const mute = {textContent: "", setAttribute(name, value) { this[name] = value }}
  const popover = {hidden: true}
  globalThis.document = eventTarget()
  globalThis.window = eventTarget()
  const controller = {
    leave() { calls.push("leave") },
    state() { return currentState },
    subscribe(nextListener) { listener = nextListener; listener(currentState); return () => listener = null },
    toggleMute() { calls.push("toggleMute") },
  }
  const elements = {
    "[data-voice-controls-channel]": channel,
    "[data-voice-controls-status]": status,
    "[data-voice-controls-mute]": mute,
    "[data-voice-controls-popover]": popover,
  }
  const hook = {...createVoiceControls(controller), el: {querySelector: selector => elements[selector]}}
  hook.mounted()
  return {calls, channel, emit(nextState) { currentState = nextState; listener(nextState) }, hook, mute, popover, status}
}

test("the rail adapter immediately renders an existing capture and controls it without requesting media again", () => {
  const mounted = mountVoiceControls({channelId: "voice-1", channelName: "lobby", status: "capturing", workspaceId: "workspace-1"})

  assert.equal(mounted.channel.textContent, "lobby")
  assert.equal(mounted.status.textContent, "Capturing microphone")
  assert.equal(mounted.mute.textContent, "Mute")

  const muteButton = {closest: selector => selector === "[data-voice-controls-mute]" ? muteButton : null}
  document.dispatch("click", {target: muteButton})
  assert.deepEqual(mounted.calls, ["toggleMute"])

  const leaveButton = {closest: selector => selector === "[data-voice-controls-leave]" ? leaveButton : null}
  document.dispatch("click", {target: leaveButton})
  assert.deepEqual(mounted.calls, ["toggleMute", "leave"])

  window.dispatch("voice-controls:open")
  assert.equal(mounted.popover.hidden, false)

  mounted.hook.destroyed()
  document.dispatch("click", {target: muteButton})
  assert.deepEqual(mounted.calls, ["toggleMute", "leave"])
})
