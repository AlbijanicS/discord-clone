const MessageComposer = {
  mounted() {
    this.handleEvent("clear_message_composer", ({input_id}) => {
      const input = document.getElementById(input_id)

      if (!input) {
        return
      }

      input.value = ""
      input.dispatchEvent(new Event("input", {bubbles: true}))
    })
  },
}

export default MessageComposer
