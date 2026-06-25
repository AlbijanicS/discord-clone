const MessageComposer = {
  mounted() {
    this.lastTypingPushAt = 0
    this.typingThrottleMs = 3000
    this.input = this.el.querySelector("input, textarea")

    this.handleInput = () => {
      if (!this.input || this.input.value.trim() === "") {
        return
      }

      const now = Date.now()

      if (now - this.lastTypingPushAt < this.typingThrottleMs) {
        return
      }

      this.lastTypingPushAt = now
      this.pushEvent("message_typing", {})
    }

    if (this.input) {
      this.input.addEventListener("input", this.handleInput)
    }

    this.handleEvent("clear_message_composer", ({input_id}) => {
      const input = document.getElementById(input_id)

      if (!input) {
        return
      }

      input.value = ""
      input.dispatchEvent(new Event("input", {bubbles: true}))
    })
  },

  destroyed() {
    if (this.input) {
      this.input.removeEventListener("input", this.handleInput)
    }
  },
}

export default MessageComposer
