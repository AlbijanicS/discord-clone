# 04 — Coordinate same-browser Voice Owner Tab takeover

**What to build:** When a Workspace Member requests a Voice Channel from another tab in the same browser, the new tab automatically becomes the best-effort Voice Owner Tab and the prior tab releases its microphone with an understandable takeover message.

**Blocked by:** 01 — Capture, mute, and release microphone from a Voice Channel.

**Status:** ready-for-agent

- [ ] Same-browser tab messaging shares only ephemeral ownership coordination; it does not persist microphone, device, or Voice Channel data.
- [ ] A newer Voice Channel click takes ownership automatically and causes the losing tab to stop its tracks and report takeover.
- [ ] Simultaneous requests resolve deterministically with newest-click-wins and a generated tab-identifier tie-breaker.
- [ ] The controller behaves safely if tab messaging is unavailable.
- [ ] Automated controller tests and a two-tab manual localhost check verify takeover and cleanup.
