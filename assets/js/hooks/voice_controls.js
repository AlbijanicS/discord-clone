import voiceController from "./voice_controller"

export function createVoiceControls(controller) {
  return {
    mounted() {
      this.handleClick = event => {
        if (event.target.closest("[data-voice-controls-mute]")) {
          controller.toggleMute()
          return
        }

        if (event.target.closest("[data-voice-controls-deafen]")) {
          controller.toggleDeafen()
          return
        }

        if (event.target.closest("[data-voice-controls-retry]")) {
          controller.retry()
          return
        }

        if (event.target.closest("[data-voice-controls-enable-audio]")) {
          controller.enableAudio()
          return
        }

        if (event.target.closest("[data-voice-controls-leave]")) controller.leave()
      }

      document.addEventListener("click", this.handleClick)
      this.unsubscribe = controller.subscribe(state => this.renderState(state))
    },

    destroyed() {
      document.removeEventListener("click", this.handleClick)
      this.unsubscribe()
    },

    renderState(state) {
      this.currentState = state
      const audioBlocked = state.audioPlayback === "blocked"
      const visible = ["requesting", "capturing", "joining", "connected", "muted"].includes(state.status) || state.error || audioBlocked
      const channel = this.el.querySelector("[data-voice-controls-channel]")
      const status = this.el.querySelector("[data-voice-controls-status]")
      const announcement = this.el.querySelector("[data-voice-controls-announcement]")
      const mute = this.el.querySelector("[data-voice-controls-mute]")
      const deafen = this.el.querySelector("[data-voice-controls-deafen]")
      const panel = this.el.querySelector("[data-voice-controls-panel]")
      const retry = this.el.querySelector("[data-voice-controls-retry]")
      const enableAudio = this.el.querySelector("[data-voice-controls-enable-audio]")
      const localActions = this.el.querySelector("[data-voice-controls-local-actions]")

      channel.textContent = state.channelName || "Voice Channel"
      status.textContent = railStatusMessage(state)
      status.setAttribute("aria-live", state.error ? "off" : "polite")
      mute.textContent = state.status === "muted" ? "Unmute" : "Mute"
      mute.setAttribute("aria-pressed", String(state.status === "muted"))
      deafen.textContent = state.deafened === true ? "Undeafen" : "Deafen"
      deafen.setAttribute("aria-pressed", String(state.deafened === true))

      retry.hidden = !state.retryable
      enableAudio.hidden = !audioBlocked
      localActions.hidden = state.status === "taken_over"
      panel.hidden = !visible
      announcement.textContent = state.error || audioBlocked ? railStatusMessage(state) : ""
    },
  }
}

function railStatusMessage(state) {
  if (state.audioPlayback === "blocked") return "Audio is ready — select Enable audio to hear it."
  if (state.status === "requesting") return "Allow microphone access"
  if (state.status === "joining" || state.status === "capturing") return "Joining voice…"
  if (state.status === "connected" || state.status === "muted") return "Connected"
  if (state.status === "connection_failed") return "Couldn’t connect — try again"
  if (state.status === "connection_lost") return "Connection lost — try again"
  if (state.status === "incompatible_audio_output_slots") return "This browser could not prepare group audio. Try again after checking browser support."
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
