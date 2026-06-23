# Broadcast User-Level Workspace Presence Events

**Type:** AFK

**Blocked by:** 4. Track Workspace Presence Connections

**User stories covered:** 7-8, 12, 26-29, 35, 37-39

## What to build

Have the private Workspace runtime broadcast granular Workspace presence events
when user-level online status changes. The first connection for a user should
broadcast a joined event. Additional connections for that already-online user
should not broadcast. Disconnecting a non-last connection should not broadcast.
Disconnecting the last connection should broadcast a left event.

Events should carry only the durable Workspace ID and user ID. Durable member
display data remains owned by Workspaces and the UI's existing member list.

## Acceptance criteria

- [ ] The first tracked connection for a user broadcasts a user-joined event.
- [ ] Additional tracked connections for an already-online user do not
      broadcast another joined event.
- [ ] Disconnecting one of several tracked connections for a user does not
      broadcast a left event.
- [ ] Disconnecting the last tracked connection for a user broadcasts a
      user-left event.
- [ ] Presence event payloads include Workspace ID and user ID.
- [ ] Presence event payloads do not include full user structs or member list
      snapshots.
- [ ] The private runtime owns broadcasting immediately after state changes.
- [ ] Topic construction and event naming stay centralized in the Chat runtime
      area.
- [ ] Focused runtime or Chat-adjacent tests prove event shape and no extra
      broadcasts for duplicate joins or non-last disconnects.
- [ ] Tests do not rely on sleeps to observe disconnect behavior.

## Blocked by

- 4. Track Workspace Presence Connections
