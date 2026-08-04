# 01 — Start and retire isolated Voice Channel room runtimes

**What to build:** A Workspace Member's authorized Voice Channel can obtain one
isolated, supervised runtime room through the public Voice API. The room has a
single runtime identity per durable Voice Channel and, when empty, remains
available for 30 seconds before stopping; a new admission during that grace
period keeps the room available.

**Blocked by:** None — can start immediately.

**Status:** complete

- [x] Starting the same Voice Channel concurrently returns one live room runtime
  without exposing runtime process details to callers.
- [x] A newly started room contains its RoomServer, SessionSupervisor, and
  Forwarder lifecycle boundary with the approved room-wide supervision policy.
- [x] An empty room stops after its 30-second idle grace, while a new admission
  before expiry cancels the pending shutdown.
- [x] OTP tests prove dynamic start, same-room reuse, and idle shutdown without
  timing sleeps or private-state assertions.

## Implementation notes

- Added the stateless `DiscordClone.Voice` lifecycle facade, app-wide room
  Registry/DynamicSupervisor, and an isolated `:one_for_all` room tree with
  RoomServer, SessionSupervisor, and Forwarder.
- RoomServer begins a 30-second empty-room grace on startup; the internal
  ticket-02 lifecycle seam marks rooms in use or empty and safely ignores stale
  timer messages.
- Added focused lifecycle coverage in `test/discord_clone/voice_test.exs` and
  ran `mix precommit` (898 tests passing).
- Ticket 02 can drive `mark_room_in_use/1` and `mark_room_empty/2` from its
  canonical admission/membership transitions; no User, Session, or media state
  was introduced here.
