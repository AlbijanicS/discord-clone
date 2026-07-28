import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import test from "node:test"

const hookSource = await readFile(new URL("./voice_workspace_badge.js", import.meta.url), "utf8")
const hookModuleUrl = `data:text/javascript;base64,${Buffer.from(hookSource.replace('import voiceController from "./voice_controller"', "const voiceController = null")).toString("base64")}`
const {createVoiceWorkspaceBadge} = await import(hookModuleUrl)

test("a Workspace badge only appears for its active Voice Channel Workspace and opens the shared controls", () => {
  let listener
  const events = []
  globalThis.window = {dispatchEvent(event) { events.push(event.type) }}
  const controller = {
    subscribe(nextListener) {
      listener = nextListener
      listener({channelId: "voice-1", channelName: "lobby", status: "capturing", workspaceId: "workspace-1"})
      return () => listener = null
    },
  }
  const hook = {
    ...createVoiceWorkspaceBadge(controller),
    el: {
      addEventListener() {},
      dataset: {workspaceId: "workspace-2"},
      hidden: true,
      removeEventListener() {},
      setAttribute(name, value) { this[name] = value },
    },
  }

  hook.mounted()
  assert.equal(hook.el.hidden, true)

  listener({channelId: "voice-1", channelName: "lobby", status: "muted", workspaceId: "workspace-2"})
  assert.equal(hook.el.hidden, false)

  hook.handleClick()
  assert.deepEqual(events, ["voice-controls:open"])
  assert.equal(hook.el["aria-expanded"], "true")

  listener({channelId: null, channelName: null, status: "idle", workspaceId: null})
  assert.equal(hook.el["aria-expanded"], "false")

  hook.destroyed()
  assert.equal(listener, null)
})
