# 02 — Admit and clean up room-local Voice Sessions

**What to build:** A RoomServer can admit and remove Voice Sessions within one
Voice Channel. It issues opaque Voice Session IDs, maintains canonical
room-local membership, supports idempotent same-connection admission, enforces
the hard five-session cap, and removes a temporary Session when it leaves or
crashes.

**Blocked by:** 01 — Start and retire isolated Voice Channel room runtimes.

**Status:** complete

- [x] An admitted Workspace Member receives one opaque Voice Session ID that is
  distinct from User, Voice Channel, Signaling Session, and process identity.
- [x] Repeating the same connection's admission returns the existing Voice
  Session without consuming another slot.
- [x] The sixth room-local admission returns a safe room-full result with only
  aggregate occupancy and capacity.
- [x] Explicit leave, duplicate leave, and Session crash remove the same
  canonical membership safely and do not restart the departed Session.
- [x] OTP tests observe public admission and cleanup outcomes rather than
  internal maps, Registry values, or PIDs.

## Implementation notes

- Added the public `Voice.admit/4`, `Voice.leave/2`, and aggregate
  `Voice.room_occupancy/1` room-local API. Voice Session IDs are generated as
  opaque UUIDs; public results contain no runtime process or connection data.
- `RoomServer` now serializes idempotent admission and five-session capacity,
  while temporary `Voice.Session` children monitor trusted signaling-channel
  processes and converge explicit leave, connection death, and Session crashes
  on canonical membership cleanup and the existing empty-room grace lifecycle.
- Focused Voice tests and `mix precommit` pass. Ticket 03 can add its global
  User index and move coordinator without changing this room-local contract.
