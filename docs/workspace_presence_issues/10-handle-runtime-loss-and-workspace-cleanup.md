# Handle Presence Runtime Loss And Workspace Cleanup

**Type:** AFK

**Blocked by:** 6. Expose Workspace Presence Through Chat, 8. Update Member Sidebar From Live Presence Events

**User stories covered:** 13-17, 33, 42-43

## What to build

Round out the Workspace presence phase by making temporary runtime loss and
Workspace lifecycle cleanup explicit. If the Workspace presence runtime is
absent or crashes, durable member lists should still render with all members
offline, and persisted chat should continue working. Once runtime processes
exist, deleting or leaving Workspace flows should not leave obvious stale
presence state behind for deleted Workspaces.

This slice should stay bounded to Workspace presence lifecycle behavior. It
should not introduce distributed presence, Phoenix Presence, ChannelServer
processes, typing indicators, or persisted online status.

## Acceptance criteria

- [ ] Listing online user IDs through Chat returns an empty list when the
      Workspace runtime is absent.
- [ ] A Workspace presence runtime crash does not interrupt persisted message
      sending, message history loading, or channel PubSub delivery.
- [ ] After runtime loss, the member sidebar can still render durable members
      as offline.
- [ ] Connected LiveViews can naturally rebuild presence by rejoining through
      the established connected mount or recovery path.
- [ ] Runtime cleanup for deleted Workspaces is handled deliberately now that
      Workspace runtime processes exist.
- [ ] Cleanup behavior does not require nesting future channel process
      supervision under Workspace presence supervision.
- [ ] Online/offline state is not persisted in Postgres.
- [ ] Focused Chat/runtime tests cover absent-runtime reads and runtime crash
      tolerance.
- [ ] Focused LiveView or context tests cover deleted Workspace cleanup where
      practical.
- [ ] The project precommit alias passes after the full Workspace presence
      implementation phase.

## Blocked by

- 6. Expose Workspace Presence Through Chat
- 8. Update Member Sidebar From Live Presence Events
