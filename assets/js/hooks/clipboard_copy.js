const copiedLabel = "Invite link copied"
const resetDelay = 1800

const ClipboardCopy = {
  mounted() {
    this.originalLabel = this.el.getAttribute("aria-label")
    this.handleClick = () => copyFromTarget(this)
    this.el.addEventListener("click", this.handleClick)
  },

  destroyed() {
    this.el.removeEventListener("click", this.handleClick)
    clearTimeout(this.resetTimer)
  },
}

async function copyFromTarget(hook) {
  const target = document.getElementById(hook.el.dataset.copyTarget)

  if (!target) {
    return
  }

  const value = target.value || target.textContent || ""

  if (!value) {
    return
  }

  try {
    await copyText(value, target)
    showCopiedFeedback(hook)
  } catch (_error) {
    target.focus()
    target.select?.()
  }
}

async function copyText(value, target) {
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(value)
    return
  }

  target.focus()
  target.select?.()

  if (!document.execCommand("copy")) {
    throw new Error("copy command failed")
  }
}

function showCopiedFeedback(hook) {
  hook.el.setAttribute("aria-label", copiedLabel)
  hook.el.dataset.copied = "true"

  clearTimeout(hook.resetTimer)

  hook.resetTimer = setTimeout(() => {
    hook.el.setAttribute("aria-label", hook.originalLabel)
    delete hook.el.dataset.copied
  }, resetDelay)
}

export default ClipboardCopy
