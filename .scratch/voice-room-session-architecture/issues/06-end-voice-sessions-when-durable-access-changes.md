# 06 — End Voice Sessions when durable access changes

**What to build:** A Voice Session ends when its User loses access to the
Voice Channel or the durable Voice Channel is deleted. The corresponding room
and global admission state are cleaned without exposing runtime details or
affecting unrelated Voice Channels.

**Blocked by:** 05 — Delegate authenticated Voice admission from the Phoenix Channel.

**Status:** complete

- [x] Removing a connected User's durable access terminates only that User's
  matching Voice Session and clears its room and global membership state.
- [x] Deleting a Voice Channel terminates all of its active Voice Sessions and
  allows its empty runtime to retire under the defined policy.
- [x] Existing durable authorization behavior remains the source of truth; the
  Voice runtime receives lifecycle notification rather than reimplementing
  membership queries.
- [x] Integration and OTP tests prove no orphan session, stale User index, or
  unrelated-room disruption remains after either durable change.

## Implementation notes

- Added `Voice.end_user_session/2` and `Voice.end_channel_sessions/1` as
  validated, idempotent lifecycle operations. `SessionCoordinator` routes both
  operations through `RoomServer` cleanup and identity-checks the private User
  index so late notifications cannot remove a moved replacement session.
- `Workspaces` now notifies Voice after successful kick, ban, member leave,
  direct Voice Channel deletion, and Workspace deletion cascades. Channel IDs
  are resolved from durable Workspaces data; Voice does not query Workspaces.
- Added OTP and Workspaces integration coverage for targeted cleanup,
  channel-wide cleanup, late notifications, idle retirement, cascade cleanup,
  and failed/unauthorized durable mutations. Existing Phoenix Voice Channel
  termination remains the idempotent cleanup path.
- No additional interface pressure was found for the next Phase 6 ticket.
