const ChannelMessages = {
  mounted() {
    scrollToBottom(this.el)

    this.handleEvent("scroll_channel_messages_to_bottom", ({container_id}) => {
      const container = document.getElementById(container_id)

      if (!container) {
        return
      }

      requestAnimationFrame(() => scrollToBottom(container))
    })
  },
}

function scrollToBottom(container) {
  container.scrollTop = container.scrollHeight
}

export default ChannelMessages
