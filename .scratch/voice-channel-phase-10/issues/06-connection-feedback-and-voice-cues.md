# 06 — Connection Feedback and Voice Cues

**What to build:** The persistent Voice Connection Panel communicates connection state honestly, and active Voice Owner Tabs hear a short cue when someone joins or leaves their Voice Channel.

**Blocked by:** 01 — Live Voice Channel Roster; 02 — Persistent Local Voice Controls.

**Status:** ready-for-agent

- [ ] The panel clearly distinguishes connecting, connected, interrupted non-terminal, and terminal failed states without adding reconnect policy.
- [ ] Terminal failure cleans up and returns to ordinary Join; interrupted remains non-terminal with ordinary controls.
- [ ] All current Voice Owner Tabs in the affected Voice Channel receive short browser-local join/leave cues by default, with no in-app preference, spoken announcement, system message, or notification-center item.
- [ ] Browser behavior tests prove status presentation, cue targeting, and cleanup; the feature remains usable under browser playback restrictions.
