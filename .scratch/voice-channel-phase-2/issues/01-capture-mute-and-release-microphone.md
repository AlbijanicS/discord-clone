# 01 — Capture, mute, and release microphone from a Voice Channel

**What to build:** A Workspace Member can explicitly click a Voice Channel to request local microphone capture, see pending/capturing/muted state, mute or unmute without another browser prompt, and Leave Voice to stop capture. This establishes the browser-only Voice Owner Tab controller without signaling, Voice Sessions, or media networking.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] Clicking a Voice Channel directly initiates browser microphone capture; loading an authenticated destination never requests permission automatically.
- [ ] Pending permission, capturing, and muted state are visibly rendered from browser-owned state.
- [ ] Mute disables the local audio track and unmute restores it without stopping the track or requesting permission again.
- [ ] Leave Voice stops all owned tracks and returns the UI to idle, allowing the browser capture indicator to turn off.
- [ ] Focused controller and authenticated LiveView tests prove the happy-path lifecycle without signaling or a server Voice runtime.
