# Track Workspace Presence Connections

**Type:** AFK

**Blocked by:** 3. Add Workspace Presence Runtime Foundation

**User stories covered:** 2-3, 6, 9, 24-25, 32, 34, 40-41

## What to build

Teach the private Workspace runtime to track connected LiveView processes per
user. Joining presence should associate a user ID with a LiveView PID, monitor
that PID, treat duplicate joins for the same PID as idempotent, and expose a
read of currently online user IDs from runtime memory.

The runtime state should model both directions needed for cleanup: user IDs to
connection PIDs, and monitor references back to the user/PID pair that went
down. This slice should prove correct state transitions, but it should not
broadcast joined or left events yet.

## Acceptance criteria

- [ ] Joining presence for a user and PID records that user as online.
- [ ] Joining presence for the same user and same PID is idempotent.
- [ ] Joining presence for the same user from multiple PIDs keeps one online
      user ID with multiple tracked connections.
- [ ] Joining presence for different users tracks each user independently.
- [ ] The runtime monitors each tracked LiveView PID.
- [ ] When one of several PIDs for a user exits, the user remains online.
- [ ] When the last PID for a user exits, the user is removed from online
      state.
- [ ] Listing online user IDs reads runtime state without changing it.
- [ ] The runtime does not store full user structs.
- [ ] The slice does not add PubSub broadcasts or LiveView integration.
- [ ] Focused runtime tests cover first join, duplicate join, multiple PIDs,
      non-last disconnect, and last disconnect.
- [ ] Tests avoid `Process.sleep/1`; use monitors, `assert_receive`, and
      `_ = :sys.get_state/1` style synchronization where needed.

## Blocked by

- 3. Add Workspace Presence Runtime Foundation
