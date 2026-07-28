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
  const status = {textContent: "", setAttribute(name, value) { this[name] = value }}
  const announcement = {textContent: ""}
  const mute = {textContent: "", setAttribute(name, value) { this[name] = value }}
  const popover = {hidden: true}
  const retry = {hidden: true}
  const localActions = {hidden: false}
  const close = {}
  const trigger = {
    focusCalls: 0,
    focus() { this.focusCalls += 1 },
    setAttribute(name, value) { this[name] = value },
  }
  globalThis.document = {...eventTarget(), activeElement: trigger}
  globalThis.window = eventTarget()
  const controller = {
    leave() { calls.push("leave") },
    retry() { calls.push("retry") },
    state() { return currentState },
    subscribe(nextListener) { listener = nextListener; listener(currentState); return () => listener = null },
    toggleMute() { calls.push("toggleMute") },
  }
  const elements = {
    "[data-voice-controls-channel]": channel,
    "[data-voice-controls-status]": status,
    "[data-voice-controls-announcement]": announcement,
    "[data-voice-controls-mute]": mute,
    "[data-voice-controls-popover]": popover,
    "[data-voice-controls-retry]": retry,
    "[data-voice-controls-local-actions]": localActions,
    "[data-voice-controls-close]": close,
  }
  const hook = {...createVoiceControls(controller), el: {querySelector: selector => elements[selector]}}
  hook.mounted()
  return {announcement, calls, channel, close, emit(nextState) { currentState = nextState; listener(nextState) }, hook, localActions, mute, popover, retry, status, trigger}
}

test("the rail adapter immediately renders an existing capture and controls it without requesting media again", () => {
  const mounted = mountVoiceControls({channelId: "voice-1", channelName: "lobby", status: "capturing", workspaceId: "workspace-1"})

  assert.equal(mounted.channel.textContent, "lobby")
  assert.equal(mounted.status.textContent, "Capturing microphone")
  assert.equal(mounted.announcement.textContent, "Capturing microphone")
  assert.equal(mounted.mute.textContent, "Mute")

  const muteButton = {closest: selector => selector === "[data-voice-controls-mute]" ? muteButton : null}
  document.dispatch("click", {target: muteButton})
  assert.deepEqual(mounted.calls, ["toggleMute"])

  const leaveButton = {closest: selector => selector === "[data-voice-controls-leave]" ? leaveButton : null}
  document.dispatch("click", {target: leaveButton})
  assert.deepEqual(mounted.calls, ["toggleMute", "leave"])

  window.dispatch("voice-controls:open")
  assert.equal(mounted.popover.hidden, false)
  assert.equal(mounted.announcement.textContent, "")

  mounted.hook.destroyed()
  document.dispatch("click", {target: muteButton})
  assert.deepEqual(mounted.calls, ["toggleMute", "leave"])
})

test("the rail renders a browser failure and delegates its explicit retry", () => {
  const mounted = mountVoiceControls({channelId: "voice-1", channelName: "lobby", error: "no_device", retryable: true, status: "no_device", workspaceId: "workspace-1"})

  assert.equal(mounted.status.textContent, "No microphone was found. Connect an input, then retry.")
  assert.equal(mounted.announcement.textContent, "No microphone was found. Connect an input, then retry.")
  assert.equal(mounted.status["aria-live"], "off")
  assert.equal(mounted.retry.hidden, false)
  assert.equal(mounted.popover.hidden, false)

  const retryButton = {closest: selector => selector === "[data-voice-controls-retry]" ? retryButton : null}
  document.dispatch("click", {target: retryButton})
  assert.deepEqual(mounted.calls, ["retry"])
  mounted.hook.destroyed()
})

test("the rail keeps a Voice Owner Tab takeover discoverable without active controls", () => {
  const mounted = mountVoiceControls({channelId: "voice-1", channelName: "lobby", error: "taken_over", retryable: false, status: "taken_over", workspaceId: "workspace-1"})

  assert.equal(mounted.channel.textContent, "lobby")
  assert.equal(mounted.status.textContent, "Voice moved to another tab")
  assert.equal(mounted.announcement.textContent, "Voice moved to another tab")
  assert.equal(mounted.status["aria-live"], "off")
  assert.equal(mounted.retry.hidden, true)
  assert.equal(mounted.popover.hidden, false)
  assert.equal(mounted.localActions.hidden, true)
  mounted.hook.destroyed()
})

test("Escape closes Voice controls, returns focus to its badge trigger, and leaves microphone state alone", () => {
  const mounted = mountVoiceControls({channelId: "voice-1", channelName: "lobby", status: "capturing", workspaceId: "workspace-1"})

  window.dispatch("voice-controls:open", {detail: {trigger: mounted.trigger}})
  assert.equal(mounted.popover.hidden, false)

  const escape = {key: "Escape", preventDefault() { this.prevented = true }}
  document.dispatch("keydown", escape)

  assert.equal(escape.prevented, true)
  assert.equal(mounted.popover.hidden, true)
  assert.equal(mounted.trigger["aria-expanded"], "false")
  assert.equal(mounted.trigger.focusCalls, 1)
  assert.deepEqual(mounted.calls, [])

  mounted.hook.destroyed()
  document.dispatch("keydown", {key: "Escape"})
  assert.equal(mounted.trigger.focusCalls, 1)
})

test("the explicit close button returns focus without reopening or stealing focus on controller updates", () => {
  const mounted = mountVoiceControls({channelId: "voice-1", channelName: "lobby", status: "capturing", workspaceId: "workspace-1"})

  window.dispatch("voice-controls:open", {detail: {trigger: mounted.trigger}})
  const closeButton = {closest: selector => selector === "[data-voice-controls-close]" ? closeButton : null}
  document.dispatch("click", {target: closeButton})

  assert.equal(mounted.popover.hidden, true)
  assert.equal(mounted.trigger.focusCalls, 1)
  assert.deepEqual(mounted.calls, [])

  mounted.emit({channelId: "voice-1", channelName: "lobby", status: "muted", workspaceId: "workspace-1"})
  assert.equal(mounted.popover.hidden, true)
  assert.equal(mounted.trigger.focusCalls, 1)
  mounted.hook.destroyed()
})
