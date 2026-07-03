# Sync Read State Across User Sessions

**Type:** AFK

**Blocked by:** 7. Expose Read-State Summaries And Private PubSub, 11. Add Explicit Channel Read Actions, 14. Add Visible-Read Observation Hook

**User stories covered:** 16, 22-24, 43, 46

## What to build

Wire private read-state PubSub into LiveViews so read changes from one tab or
device update the same User's other sessions. Clearing or observing Messages in
one session should update sidebar badges and unread affordances elsewhere
without exposing private read state to other Workspace Members.

This slice focuses on cross-session consistency after the core actions and
visible-read hook exist.

## Acceptance criteria

- [ ] Channel and Workspace LiveViews subscribe to the current User's private
      read-state topic when connected.
- [ ] A read-state event for one User updates that User's other open sessions.
- [ ] Read-state events from another User do not update or leak into the
      current User's session.
- [ ] Read-state event payloads include Workspace ID so LiveViews can ignore
      events for other open Workspaces.
- [ ] Sidebar badges update from private read-state events.
- [ ] The selected Channel's unread divider and sticky bar update when its
      unread state changes elsewhere.
- [ ] Clearing unread elsewhere removes stale unread UI in the selected
      Channel.
- [ ] Visible-read no-op events do not trigger unnecessary UI churn.
- [ ] Shared message PubSub payloads remain free of private read summaries.
- [ ] Focused LiveView and PubSub tests cover same-User sync, different-User
      isolation, selected Channel UI refresh, and no-op behavior.

## Blocked by

- 7. Expose Read-State Summaries And Private PubSub
- 11. Add Explicit Channel Read Actions
- 14. Add Visible-Read Observation Hook
