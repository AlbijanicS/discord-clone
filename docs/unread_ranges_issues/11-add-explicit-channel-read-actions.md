# Add Explicit Channel Read Actions

**Type:** AFK

**Blocked by:** 4. Implement Span Merge And Subtract Workflows, 9. Add Sequence-Based Message Windows, 10. Replace Channel Mount With Landing Windows

**User stories covered:** 6-9, 17-21, 26, 46

## What to build

Add the explicit Channel read actions that let a Workspace Member intentionally
navigate or dismiss unread state. `Jump to oldest unread` should navigate only,
`Mark as read` should clear unread without moving the User, and `Jump to
latest` should clear unread and move to the newest Messages.

This slice separates user intent clearly so navigation does not accidentally
become read confirmation.

## Acceptance criteria

- [ ] Chat exposes a `jump_to_oldest_unread` workflow or equivalent read-state
      lookup for the LiveView.
- [ ] `Jump to oldest unread` loads a targeted Message window around
      `first_unread_seq`.
- [ ] `Jump to oldest unread` does not clear unread spans or decrement unread
      counts.
- [ ] Chat exposes `mark_channel_read` for clearing all unread spans in the
      Channel.
- [ ] `Mark as read` clears unread spans without changing the current Message
      window or scroll target.
- [ ] Chat exposes `jump_to_latest` as a public action separate from
      `mark_channel_read`.
- [ ] `Jump to latest` clears all unread spans and loads the latest Message
      window.
- [ ] The visible UI copy or accessible label makes the clearing behavior
      explicit, for example by using `Skip to latest` or saying that unread will
      be marked read.
- [ ] After `Jump to latest`, `last_viewed_anchor_seq` updates to the Channel's
      latest sequence.
- [ ] After any clear action, unread UI is removed immediately for that User.
- [ ] All actions require authenticated Workspace membership.
- [ ] Focused Chat and LiveView tests cover navigation-only jump, mark-read
      without navigation, jump-latest clear and navigation, and access errors.

## Blocked by

- 4. Implement Span Merge And Subtract Workflows
- 9. Add Sequence-Based Message Windows
- 10. Replace Channel Mount With Landing Windows
