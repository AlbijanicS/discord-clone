import voiceController from "./voice_controller"

export function createVoiceChannels(controller) {
  return {
  mounted() {
    this.handleClick = event => {
      const joinButton = event.target.closest("[data-voice-channel-join]")

      if (joinButton) {
        controller.join({id: joinButton.dataset.voiceChannelId, name: joinButton.dataset.voiceChannelName})
        return
      }

      if (event.target.closest("[data-voice-channel-mute]")) {
        controller.toggleMute()
        return
      }

      if (event.target.closest("[data-voice-channel-leave]")) {
        controller.leave()
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
    const muteButton = this.el.querySelector("[data-voice-channel-mute]")

    status.textContent = statusMessage(state)
    controls.hidden = !["capturing", "muted"].includes(state.status)
    muteButton.textContent = state.status === "muted" ? "Unmute" : "Mute"
    muteButton.setAttribute("aria-pressed", String(state.status === "muted"))
  },
  }
}

function statusMessage(state) {
  if (state.status === "requesting") return `Requesting microphone for ${state.channelName}.`
  if (state.status === "capturing") return `Capturing microphone in ${state.channelName}.`
  if (state.status === "muted") return `Microphone muted in ${state.channelName}.`
  return "Voice is not connected."
}

export default createVoiceChannels(voiceController)
