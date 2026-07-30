import voiceController from "./voice_controller"

export function createVoiceChannelIndicator(controller) {
  return {
    mounted() {
      this.unsubscribe = controller.subscribe(state => this.renderState(state))
    },

    destroyed() {
      this.unsubscribe()
    },

    renderState(state) {
      this.el.hidden =
        state.channelId !== this.el.dataset.voiceChannelId ||
          !["requesting", "joining", "connected", "muted"].includes(state.status)
    },
  }
}

export default createVoiceChannelIndicator(voiceController)
