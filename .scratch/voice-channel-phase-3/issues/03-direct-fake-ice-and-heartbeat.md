# 03 — Add direct fake ICE and heartbeat signaling

**What to build:** An admitted browser can send bounded fake ICE and heartbeat messages, receive their acknowledgements, and receive fake server ICE only on the same browser-to-server signaling connection. Rejoining or losing the topic makes the old Signaling Session ID unusable.

**Blocked by:** 01 — Establish authenticated Voice topic admission.

**Status:** ready-for-agent

- [ ] Fake client ICE and heartbeat messages require the exact current Signaling Session ID, use the Phase 3 fake-value limits, and return safe acknowledgements or field-level malformed-input feedback.
- [ ] Fake server ICE is delivered as a direct asynchronous event to the originating connection, never as a topic broadcast.
- [ ] Heartbeat remains a request/reply probe only; it creates no Voice Session, roster, timeout authority, or recovery state.
- [ ] Authenticated Channel and browser-adapter tests prove direct delivery, stale-ID rejection after rejoin/termination, and built-in topic-close behavior.
