import voiceController from "./voice_controller"

export function createVoiceControls(controller) {
  return {
    mounted() {
      this.handleClick = event => {
        if (event.target.closest("[data-voice-controls-mute]")) {
          controller.toggleMute()
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
      const active = ["requesting", "capturing", "muted"].includes(state.status)
      const channel = this.el.querySelector("[data-voice-controls-channel]")
      const status = this.el.querySelector("[data-voice-controls-status]")
      const mute = this.el.querySelector("[data-voice-controls-mute]")
      const popover = this.el.querySelector("[data-voice-controls-popover]")

      channel.textContent = state.channelName || "Voice Channel"
      status.textContent = railStatusMessage(state)
      mute.textContent = state.status === "muted" ? "Unmute" : "Mute"
      mute.setAttribute("aria-pressed", String(state.status === "muted"))

      if (!active) this.popoverOpen = false
      popover.hidden = !this.popoverOpen
    },
  }
}

function railStatusMessage(state) {
  if (state.status === "requesting") return "Requesting microphone"
  if (state.status === "capturing") return "Capturing microphone"
  if (state.status === "muted") return "Microphone muted"
  return "Voice is not connected"
}

export default createVoiceControls(voiceController)
