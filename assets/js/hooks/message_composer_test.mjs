import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import test from "node:test"

const hookSource = await readFile(new URL("./message_composer.js", import.meta.url), "utf8")
const hookModuleUrl = `data:text/javascript;base64,${Buffer.from(hookSource).toString("base64")}`
const {default: MessageComposer} = await import(hookModuleUrl)

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

function mountComposer({mentionsEnabled}) {
  const input = {
    ...eventTarget(),
    selectionStart: 5,
    value: "hello",
  }
  const pushedEvents = []
  const el = {
    dataset: {mentionsEnabled},
    querySelector(selector) {
      return selector === "input, textarea" ? input : null
    },
  }
  const hook = {
    ...MessageComposer,
    el,
    handleEvent() {},
    pushEvent(name, payload) {
      pushedEvents.push({name, payload})
    },
  }

  hook.mounted()

  return {hook, input, pushedEvents}
}

test("a Direct Message composer does not push Workspace mention queries", () => {
  const {hook, input, pushedEvents} = mountComposer({mentionsEnabled: "false"})

  input.dispatch("input")

  assert.deepEqual(pushedEvents, [{name: "message_typing", payload: {}}])
  hook.destroyed()
})

test("a Workspace composer keeps mention queries enabled", () => {
  const {hook, input, pushedEvents} = mountComposer({mentionsEnabled: "true"})

  input.dispatch("input")

  assert.deepEqual(pushedEvents, [
    {
      name: "mention_query",
      payload: {after_cursor: "", before_cursor: "hello"},
    },
    {name: "message_typing", payload: {}},
  ])
  hook.destroyed()
})
