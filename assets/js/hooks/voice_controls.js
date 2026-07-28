import voiceController from "./voice_controller"

export function createVoiceControls(controller) {
  return {
    mounted() {
      this.handleClick = event => {
        if (event.target.closest("[data-voice-controls-mute]")) {
          controller.toggleMute()
          return
        }

        if (event.target.closest("[data-voice-controls-retry]")) {
          controller.retry()
          return
        }

        if (event.target.closest("[data-voice-controls-leave]")) controller.leave()
      }

      document.addEventListener("click", this.handleClick)
      this.handleOpen = () => {
        this.popoverOpen = true
        this.renderState(controller.state())
      }
      window.addEventListener("voice-controls:open", this.handleOpen)
      this.popoverOpen = false
      this.unsubscribe = controller.subscribe(state => this.renderState(state))
    },

    destroyed() {
      document.removeEventListener("click", this.handleClick)
      window.removeEventListener("voice-controls:open", this.handleOpen)
      this.unsubscribe()
    },

    renderState(state) {
      const visible = ["requesting", "capturing", "muted"].includes(state.status) || state.error
      const channel = this.el.querySelector("[data-voice-controls-channel]")
      const status = this.el.querySelector("[data-voice-controls-status]")
      const mute = this.el.querySelector("[data-voice-controls-mute]")
      const popover = this.el.querySelector("[data-voice-controls-popover]")
      const retry = this.el.querySelector("[data-voice-controls-retry]")
      const localActions = this.el.querySelector("[data-voice-controls-local-actions]")

      channel.textContent = state.channelName || "Voice Channel"
      status.textContent = railStatusMessage(state)
      mute.textContent = state.status === "muted" ? "Unmute" : "Mute"
      mute.setAttribute("aria-pressed", String(state.status === "muted"))

      retry.hidden = !state.retryable
      localActions.hidden = state.status === "taken_over"
      if (state.error) this.popoverOpen = true
      if (!visible) this.popoverOpen = false
      popover.hidden = !this.popoverOpen
    },
  }
}

function railStatusMessage(state) {
  if (state.status === "requesting") return "Requesting microphone"
  if (state.status === "capturing") return "Capturing microphone"
  if (state.status === "muted") return "Microphone muted"
  if (state.status === "permission_denied") return "Microphone permission was denied. Check browser settings, then retry."
  if (state.status === "no_device") return "No microphone was found. Connect an input, then retry."
  if (state.status === "insecure_context") return "Microphone capture needs HTTPS outside localhost."
  if (state.status === "unsupported") return "This browser does not support microphone capture."
  if (state.status === "externally_ended") return "Microphone capture ended unexpectedly. Retry to reconnect."
  if (state.status === "taken_over") return "Voice moved to another tab"
  if (state.status === "unknown_error") return "Microphone capture could not start. Retry to try again."
  return "Voice is not connected"
}

export default createVoiceControls(voiceController)
