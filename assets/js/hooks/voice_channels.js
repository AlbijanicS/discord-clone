import voiceController from "./voice_controller"

export function createVoiceChannels(controller) {
  return {
  mounted() {
    this.handleClick = event => {
      const joinButton = event.target.closest("[data-voice-channel-join]")

      if (joinButton) {
        controller.join({
          id: joinButton.dataset.voiceChannelId,
          name: joinButton.dataset.voiceChannelName,
          workspaceId: joinButton.dataset.workspaceId,
        })
        return
      }

      if (event.target.closest("[data-voice-channel-mute]")) {
        controller.toggleMute()
        return
      }

      if (event.target.closest("[data-voice-channel-leave]")) {
        controller.leave()
        return
      }

      if (event.target.closest("[data-voice-channel-retry]")) {
        controller.retry()
      }
    }

    document.addEventListener("click", this.handleClick)
    this.unsubscribe = controller.subscribe(state => this.renderState(state))
  },

  updated() {
    this.renderState(controller.state())
  },

  destroyed() {
    document.removeEventListener("click", this.handleClick)
    this.unsubscribe()
  },

  renderState(state) {
    const status = this.el.querySelector("[data-voice-channel-status]")
    const controls = this.el.querySelector("[data-voice-channel-local-controls]")
    const retryControls = this.el.querySelector("[data-voice-channel-retry-controls]")
    const muteButton = this.el.querySelector("[data-voice-channel-mute]")

    status.textContent = statusMessage(state)
    controls.hidden = !["capturing", "muted"].includes(state.status)
    retryControls.hidden = !state.retryable
    muteButton.textContent = state.status === "muted" ? "Unmute" : "Mute"
    muteButton.setAttribute("aria-pressed", String(state.status === "muted"))

  },
  }
}

function statusMessage(state) {
  if (state.status === "requesting") return `Requesting microphone for ${state.channelName}.`
  if (state.status === "capturing") return `Capturing microphone in ${state.channelName}.`
  if (state.status === "muted") return `Microphone muted in ${state.channelName}.`
  if (state.status === "permission_denied") return "Microphone permission was denied. Check your browser settings, then retry."
  if (state.status === "no_device") return "No microphone was found. Connect or select an input device, then retry."
  if (state.status === "insecure_context") return "Microphone capture needs a secure connection. Use HTTPS outside localhost."
  if (state.status === "unsupported") return "This browser does not support microphone capture."
  if (state.status === "externally_ended") return `Microphone capture ended unexpectedly in ${state.channelName}. Retry to reconnect.`
  if (state.status === "taken_over") return "Voice moved to another tab."
  if (state.status === "unknown_error") return "Microphone capture could not start. Retry to try again."
  return "Voice is not connected."
}

export default createVoiceChannels(voiceController)
