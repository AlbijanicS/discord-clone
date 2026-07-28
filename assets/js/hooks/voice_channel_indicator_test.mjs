import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import test from "node:test"

const hookSource = await readFile(new URL("./voice_channel_indicator.js", import.meta.url), "utf8")
const hookModuleUrl = `data:text/javascript;base64,${Buffer.from(hookSource.replace('import voiceController from "./voice_controller"', "const voiceController = null")).toString("base64")}`
const {createVoiceChannelIndicator} = await import(hookModuleUrl)

test("the active Voice Channel indicator immediately reflects controller state", () => {
  let listener
  const controller = {
    subscribe(nextListener) {
      listener = nextListener
      listener({channelId: "voice-1", channelName: "lobby", status: "capturing", workspaceId: "workspace-1"})
      return () => listener = null
    },
  }
  const hook = {...createVoiceChannelIndicator(controller), el: {dataset: {voiceChannelId: "voice-2"}, hidden: true}}

  hook.mounted()
  assert.equal(hook.el.hidden, true)

  listener({channelId: "voice-2", channelName: "standup", status: "muted", workspaceId: "workspace-1"})
  assert.equal(hook.el.hidden, false)

  hook.destroyed()
  assert.equal(listener, null)
})
