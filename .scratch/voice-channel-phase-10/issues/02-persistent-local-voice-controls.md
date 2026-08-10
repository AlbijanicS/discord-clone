# 02 — Persistent Local Voice Controls

**What to build:** A Voice Owner Tab has a persistent Voice Connection Panel across navigation with Local Mute, Local Deafen, and Leave. Its effective muted/deafened state is reflected in the Voice Channel Roster without exposing a moderation reason.

**Blocked by:** 01 — Live Voice Channel Roster.

**Status:** ready-for-agent

- [ ] The persistent panel is the primary active-Voice control surface and exposes the active Voice Channel, Local Mute, Local Deafen, and Leave.
- [ ] Local Mute stops local microphone transmission without ending the Voice Session and updates the public effective-muted roster state.
- [ ] Local Deafen silences remote playback, enables Local Mute, updates public effective-deafened state, and undeafening leaves Local Mute enabled.
- [ ] Leave and every terminal Session cleanup clear shared mute/deafen state from the roster immediately; browser controller and LiveView behavior are covered by focused tests.
