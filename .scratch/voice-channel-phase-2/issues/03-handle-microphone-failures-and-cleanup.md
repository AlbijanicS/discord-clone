# 03 — Handle microphone failures and cleanup

**What to build:** A Workspace Member receives clear, actionable microphone status when capture cannot start or ends unexpectedly, and local capture is safely released for leave, logout, switching Voice Channels, teardown, and late browser permission results.

**Blocked by:** 01 — Capture, mute, and release microphone from a Voice Channel.

**Status:** ready-for-agent

- [ ] Permission denied, no device, insecure context, unsupported browser, and unknown failures each produce understandable state and a retry path where applicable.
- [ ] Repeated activation of the current Voice Channel is safe, while selecting another Voice Channel releases the old capture before requesting the new one.
- [ ] Leaving while permission is pending discards and immediately stops any stream returned later.
- [ ] External track end, logout, and relevant browser/UI teardown clear local ownership and never leave UI claiming active capture.
- [ ] Controller tests cover each failure and cleanup transition; manual localhost checks cover real browser permission and release-indicator behavior.
