# 03 — Server-Derived Speaking Indicators

**What to build:** Workspace Members see a subtle Speaking Indicator on roster rows when a Voice Session has current audio activity, without granting that Session any media permission.

**Blocked by:** 01 — Live Voice Channel Roster.

**Status:** ready-for-agent

- [ ] The Voice runtime derives speaking from negotiated RTP audio-level metadata using a conservative threshold and 600 ms decay.
- [ ] A browser that does not provide the audio-level extension remains join-compatible and uses accepted-RTP activity as a less-precise fallback.
- [ ] Speaking state is included in safe roster snapshots, clears immediately when the Session ends, and displays as a subtle ring without layout movement.
- [ ] Tests cover threshold crossing, decay, fallback, termination clearing, and prove speaking never authorizes RTP forwarding.
