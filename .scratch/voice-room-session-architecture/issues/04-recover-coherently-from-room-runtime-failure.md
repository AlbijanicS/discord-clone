# 04 — Recover coherently from room-runtime failure

**What to build:** A failure of one Voice Channel's room-correctness runtime
restarts that room coherently and clears affected cross-room admission state.
Individual temporary Session failures remain local, and an unrelated Voice
Channel continues operating.

**Blocked by:** 03 — Coordinate one Voice Session per User across rooms.

**Status:** complete

- [x] A RoomServer or Forwarder failure cannot leave stale canonical membership
  or a stale global User entry after the room runtime restarts.
- [x] The affected User must explicitly join again; no departed Session is
  silently recreated into an unknown signaling or WebRTC state.
- [x] An individual Voice Session failure removes only that membership and does
  not restart healthy sessions or unrelated rooms.
- [x] OTP crash tests use monitors and externally visible cleanup outcomes, and
  prove a different Voice Channel remains available.

## Implementation notes

Completed 2026-08-03.

- `AdmissionServer` now monitors each RoomServer and Forwarder generation and
  identity-guards invalidation by the old RoomServer PID. A room-core failure
  clears only that room's global User entries; the existing `:one_for_all`
  room tree replaces its local membership and Session processes.
- RoomServer waits for its restarted SessionSupervisor readiness before serving
  admissions, so callers do not observe the transient named-supervisor race.
- AdmissionServer restart policy is fail-closed: it returns `:recovering`,
  shuts down every pre-existing ephemeral room, and accepts fresh admissions
  only after all old RoomServers have stopped. No old Voice Session is
  resurrected.
- Added public-API OTP coverage for RoomServer failure, Forwarder failure,
  unrelated-room continuity, late old-session cleanup, existing individual
  Session failure cleanup, and coordinator restart. Tests use monitors and no
  sleeps or private-state assertions.

Files changed:

- `lib/discord_clone/voice.ex`
- `lib/discord_clone/voice/admission_server.ex`
- `lib/discord_clone/voice/forwarder.ex`
- `lib/discord_clone/voice/room_server.ex`
- `lib/discord_clone/voice/room_supervisor.ex`
- `lib/discord_clone/voice/session_supervisor.ex`
- `test/discord_clone/voice_test.exs`

Verification:

- Focused Voice tests: 22 passing across ExUnit seeds 1–10.
- Final `mix precommit` is run after this ticket is complete.

Interface pressure for later tickets:

- Ticket 05 can keep Phoenix Channel delegation on `DiscordClone.Voice`; room
  generation monitors and the fail-closed coordinator policy remain internal.
- Ticket 06 should revoke durable access through the same idempotent Voice
  leave/invalidation paths; it should not rebuild room membership from the
  coordinator index.
