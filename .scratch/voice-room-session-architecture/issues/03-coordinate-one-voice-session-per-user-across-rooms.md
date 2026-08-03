# 03 — Coordinate one Voice Session per User across rooms

**What to build:** A User may have exactly one active Voice Session across all
Voice Channels. The Voice admission boundary serializes concurrent requests,
moves an admitted User safely to an available target room, and preserves their
current session when the target is full.

**Blocked by:** 02 — Admit and clean up room-local Voice Sessions.

**Status:** complete

- [x] Concurrent joins for one User cannot produce two active Voice Sessions.
- [x] Joining another available Voice Channel ends the old session before the
  new session is admitted and updates the global User index.
- [x] A move to a full Voice Channel returns room-full aggregate capacity and
  leaves the User's prior session and every target-room session unchanged.
- [x] Join, move, and leave use one narrow Voice API without web-layer access
  to runtime naming or supervision details.
- [x] OTP tests cover same-channel idempotency, simultaneous requests, ordered
  moves, and failed moves without sleeping or asserting implementation state.

## Implementation notes

- Added the application-scoped `Voice.AdmissionServer`, which serializes public
  `Voice.admit/4` and `Voice.leave/2` requests with a minimal User-to-current
  session index. RoomServer remains the canonical room-local membership and
  capacity owner.
- RoomServer reports every canonical removal to the coordinator; a stale old
  session notification is ignored when a newer Voice Session already exists.
- Added public-API OTP coverage for concurrent admission, moves, full-target
  preservation, explicit leave, Session failure cleanup, and stale cleanup.
  `mix precommit` passes (909 tests).
