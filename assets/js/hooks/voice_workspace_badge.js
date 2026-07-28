import voiceController from "./voice_controller"

export function createVoiceWorkspaceBadge(controller) {
  return {
    mounted() {
      this.handleClick = () => {
        this.el.setAttribute("aria-expanded", "true")
        window.dispatchEvent(new Event("voice-controls:open"))
      }
      this.el.addEventListener("click", this.handleClick)
      this.unsubscribe = controller.subscribe(state => this.renderState(state))
    },

    destroyed() {
      this.el.removeEventListener("click", this.handleClick)
      this.unsubscribe()
    },

    renderState(state) {
      const active =
        ["requesting", "capturing", "muted"].includes(state.status) &&
          state.workspaceId === this.el.dataset.workspaceId

      this.el.hidden = !active
      if (!active) this.el.setAttribute("aria-expanded", "false")
    },
  }
}

export default createVoiceWorkspaceBadge(voiceController)
