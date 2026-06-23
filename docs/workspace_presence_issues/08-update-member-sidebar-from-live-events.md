# Update Member Sidebar From Live Presence Events

**Type:** AFK

**Blocked by:** 7. Join Presence From Workspace Surfaces

**User stories covered:** 2, 5, 7-8, 12, 30-31, 39

## What to build

Apply live Workspace presence events to the member sidebar. Subscribed
LiveViews should handle joined and left events idempotently by updating the
online user ID set and re-rendering durable members with online or offline
status.

The UI should continue deriving names and display data from the durable member
list. Events only say which durable user ID changed online state.

## Acceptance criteria

- [ ] LiveViews handle Workspace user-joined events.
- [ ] Joined events add the event user ID to the online user ID set.
- [ ] LiveViews handle Workspace user-left events.
- [ ] Left events remove the event user ID from the online user ID set.
- [ ] Event handlers are idempotent when the same user is joined or left more
      than once.
- [ ] The LiveView that caused an event can receive it without duplicate or
      broken UI state.
- [ ] Member display data still comes from durable member data, not event
      payloads.
- [ ] Online and offline member states are visually distinct in the right
      sidebar.
- [ ] Focused LiveView tests prove another Workspace Member opening the same
      Workspace appears online without refresh.
- [ ] Focused LiveView tests prove a member leaving their last active
      connection appears offline without refresh when practical with the test
      helpers.

## Blocked by

- 7. Join Presence From Workspace Surfaces
