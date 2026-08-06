# 03 — Route ICE and server signaling events through the owning Channel

**What to build:** Move client ICE ordering and limits into `Voice.Session`, route candidates to the matching Session through the Voice runtime, and deliver server ICE and end-of-candidates events directly back to the exact Phoenix Channel without using room-wide PubSub.

**Blocked by:** 02 — Negotiate browser offers through the Voice runtime.

**Status:** ready-for-agent

- [ ] Client ICE commands travel through `Voice → RoomServer → Voice.Session` without exposing private runtime process details.
- [ ] The Session owns pending ICE, accepted-candidate counts, candidate byte limits, and the rule that candidates cannot be applied before the remote description.
- [ ] Early ICE candidates remain bounded, preserve arrival order, and are applied after the matching offer is accepted.
- [ ] Stale, mismatched, malformed, oversized, and over-limit ICE candidates retain safe existing error outcomes.
- [ ] Server ICE candidates and end-of-candidates are transformed into typed internal Session events and sent only to the owning Channel process.
- [ ] The Channel converts internal events into the existing Phoenix push payloads, including the correct Signaling Session ID and Negotiation ID.
- [ ] Two simultaneous Voice Sessions in one Voice Channel cannot receive one another's ICE or end-of-candidates events.
- [ ] Phoenix PubSub and anonymous callbacks are not introduced for private per-connection signaling.
- [ ] Existing JavaScript signaling behavior and Phoenix Channel integration tests remain green.
