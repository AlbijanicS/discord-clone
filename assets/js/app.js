// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/discord_clone"
import topbar from "../vendor/topbar"
import ChannelMessages from "./hooks/channel_messages"
import ClipboardCopy from "./hooks/clipboard_copy"
import MessageComposer from "./hooks/message_composer"

const Hooks = {
  ChannelMessages,
  ClipboardCopy,
  MessageComposer,

  MessageActionsMenu: {
    mounted() {
      this.summary = this.el.querySelector("[data-message-menu-summary]")
      this.panel = this.el.querySelector("[data-message-menu-panel]")
      this.closeTimer = null

      this.position = () => positionMessageMenu(this.summary, this.panel)

      this.cancelClose = () => {
        if (this.closeTimer) {
          window.clearTimeout(this.closeTimer)
          this.closeTimer = null
        }
      }

      // Close once the pointer has left both the button and the panel for a
      // moment. The panel is a DOM descendant of the <details>, so hovering it
      // still counts as "inside" — the grace window only bridges the visual gap
      // between the button and the fixed panel.
      this.scheduleClose = () => {
        this.cancelClose()
        this.closeTimer = window.setTimeout(() => {
          this.el.open = false
        }, 250)
      }

      this.handleToggle = () => {
        if (this.el.open) {
          // Keep the button visible while open, independent of row hover, so
          // the menu never fades or flickers mid-interaction.
          this.summary.style.opacity = "1"
          this.position()
        } else {
          this.summary.style.removeProperty("opacity")
          this.cancelClose()
        }
      }

      this.handleEnter = () => this.cancelClose()
      this.handleLeave = () => {
        if (this.el.open) {
          this.scheduleClose()
        }
      }
      this.reposition = () => {
        if (this.el.open) {
          this.position()
        }
      }

      this.el.addEventListener("toggle", this.handleToggle)
      this.el.addEventListener("mouseenter", this.handleEnter)
      this.el.addEventListener("mouseleave", this.handleLeave)
      window.addEventListener("resize", this.reposition)
      window.addEventListener("scroll", this.reposition, true)
    },

    destroyed() {
      this.cancelClose()
      this.el.removeEventListener("toggle", this.handleToggle)
      this.el.removeEventListener("mouseenter", this.handleEnter)
      this.el.removeEventListener("mouseleave", this.handleLeave)
      window.removeEventListener("resize", this.reposition)
      window.removeEventListener("scroll", this.reposition, true)
    },
  },

  ContextMenu: {
    mounted() {
      this.handleContextMenu = event => {
        event.preventDefault()

        this.pushEvent("open_context_menu", {
          type: this.el.dataset.contextMenuType,
          id: this.el.dataset.contextMenuId,
          x: event.clientX,
          y: event.clientY,
        })
      }

      this.el.addEventListener("contextmenu", this.handleContextMenu)
    },

    destroyed() {
      this.el.removeEventListener("contextmenu", this.handleContextMenu)
    },
  },
}

function positionMessageMenu(summary, panel) {
  if (!summary || !panel) {
    return
  }

  const margin = 12
  const rect = summary.getBoundingClientRect()
  const panelRect = panel.getBoundingClientRect()
  const composer = document.getElementById("message-composer-panel")
  const composerTop = composer?.getBoundingClientRect().top ?? window.innerHeight
  const availableBottom = Math.min(window.innerHeight - margin, composerTop - margin)

  let left = rect.right - panelRect.width
  let top = rect.bottom + 8

  if (top + panelRect.height > availableBottom) {
    top = rect.top - panelRect.height - 8
  }

  left = Math.max(margin, Math.min(left, window.innerWidth - panelRect.width - margin))
  top = Math.max(margin, Math.min(top, window.innerHeight - panelRect.height - margin))

  panel.style.left = `${left}px`
  panel.style.top = `${top}px`
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
