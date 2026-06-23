# Prove Multi-Tab And Last Disconnect Behavior

**Type:** AFK

**Blocked by:** 8. Update Member Sidebar From Live Presence Events

**User stories covered:** 8-10, 24-29, 41

## What to build

Add focused acceptance coverage for the multi-tab semantics selected in the
PRD. A user with multiple connected LiveViews in the same Workspace should
remain online until their final connection exits. Channel navigation inside the
same Workspace should not make the user appear offline to other subscribers.

This slice is mostly verification and small hardening. It should avoid
expanding product scope into channel-scoped presence, typing indicators, or
Phoenix Presence.

## Acceptance criteria

- [x] A user with two connected Workspace surfaces appears online once in the
      member sidebar.
- [x] Closing one of two connected surfaces does not make that user appear
      offline.
- [x] Closing the final connected surface makes that user appear offline.
- [x] Switching channels inside the same Workspace does not produce an
      incorrect offline flicker in subscribed member sidebars.
- [x] Runtime tests prove duplicate joins and non-last disconnects do not emit
      extra user-level events.
- [x] LiveView tests prove the highest-value user-visible multi-tab behavior
      that the existing test helpers can cover reliably.
- [x] Tests avoid sleeps; use monitored processes, LiveView exits, and mailbox
      synchronization patterns where practical.
- [x] No channel-scoped presence or ChannelServer behavior is introduced.

## Blocked by

- 8. Update Member Sidebar From Live Presence Events
