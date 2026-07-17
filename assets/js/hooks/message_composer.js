const MessageComposer = {
  mounted() {
    this.lastTypingPushAt = 0
    this.typingThrottleMs = 3000
    this.input = this.el.querySelector("input, textarea")

    this.pushMentionQuery = () => {
      if (!this.input) {
        return
      }

      const cursor = this.input.selectionStart ?? this.input.value.length

      this.pushEvent("mention_query", {
        before_cursor: this.input.value.slice(0, cursor),
        after_cursor: this.input.value.slice(cursor),
      })
    }

    this.handleInput = () => {
      this.pushMentionQuery()

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

    this.handleKeydown = event => {
      const autocomplete = this.el.querySelector("#message-mention-autocomplete")

      if (!autocomplete || !["ArrowDown", "ArrowUp", "Enter", "Escape"].includes(event.key)) {
        return
      }

      event.preventDefault()
      this.pushEvent("mention_keydown", {key: event.key})
    }

    this.handleBlur = () => {
      this.pushEvent("message_typing", {message: {content: ""}})
    }

    if (this.input) {
      this.input.addEventListener("input", this.handleInput)
      this.input.addEventListener("keydown", this.handleKeydown)
      this.input.addEventListener("blur", this.handleBlur)
    }

    this.handleEvent("clear_message_composer", ({input_id}) => {
      const input = document.getElementById(input_id)

      if (!input) {
        return
      }

      input.value = ""
      input.dispatchEvent(new Event("input", {bubbles: true}))
    })

    this.handleEvent("mention_selected", ({input_id, before_cursor, content}) => {
      window.requestAnimationFrame(() => {
        const input = document.getElementById(input_id)

        if (!input) {
          return
        }

        input.value = content
        input.focus()
        input.setSelectionRange(before_cursor.length, before_cursor.length)
      })
    })
  },

  destroyed() {
    if (this.input) {
      this.input.removeEventListener("input", this.handleInput)
      this.input.removeEventListener("keydown", this.handleKeydown)
      this.input.removeEventListener("blur", this.handleBlur)
    }
  },
}

export default MessageComposer
