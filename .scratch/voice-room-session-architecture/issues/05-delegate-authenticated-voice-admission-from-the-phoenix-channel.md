# 05 — Delegate authenticated Voice admission from the Phoenix Channel

**What to build:** The authenticated Phoenix signaling adapter authorizes
durable Voice Channel access through Workspaces and delegates runtime join and
leave to Voice. A browser connection receives only safe, opaque admission
outcomes, and channel death removes the associated Voice Session without
altering the proven Phase 5 negotiation and echo behavior.

**Blocked by:** 03 — Coordinate one Voice Session per User across rooms.

**Status:** ready-for-agent

- [ ] An authorized browser connection can enter a Voice Channel through the
  Phoenix adapter and receive associated opaque signaling and Voice Session
  identities.
- [ ] Unauthorized or missing Voice Channel access cannot create a room or
  Voice Session.
- [ ] Explicit leave and Phoenix Channel termination both delegate idempotent
  runtime cleanup.
- [ ] Admission and error payloads reveal neither raw signaling/media data nor
  process, User, roster, or Voice Channel structures.
- [ ] Existing deterministic signaling, PeerConnection, browser playback, and
  local mute tests remain green; new integration tests assert adapter behavior.

