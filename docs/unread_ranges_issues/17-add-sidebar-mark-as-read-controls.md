# Add Sidebar Mark-As-Read Controls

**Type:** AFK

**Blocked by:** 7. Expose Read-State Summaries And Private PubSub, 11. Add Explicit Channel Read Actions

**User stories covered:** 8, 20-24, 46

## What to build

Add a Channel context-menu `Mark as read` action in the sidebar for Channels
with unread Messages. The action should work for selected and non-selected
Channels so a Workspace Member can clean up unread badges without navigating.

This slice connects existing sidebar affordances to the range-based clear
workflow and private read-state summary updates.

## Acceptance criteria

- [ ] Channels with unread Messages expose a context-menu `Mark as read`
      action.
- [ ] Channels without unread Messages do not show a misleading mark-read
      action.
- [ ] Marking the selected Channel read clears its unread state without moving
      the current Message window.
- [ ] Marking a non-selected Channel read clears its unread state without
      navigating.
- [ ] Sidebar badges update immediately after the action succeeds.
- [ ] The action requires authenticated Workspace membership.
- [ ] Access failures follow existing sidebar or LiveView recovery behavior.
- [ ] The implementation uses public Chat APIs rather than direct Repo queries
      from the web layer.
- [ ] Stable DOM IDs or selectors are available for LiveView tests.
- [ ] Focused LiveView tests cover selected Channel, non-selected Channel,
      zero-unread visibility, and badge update behavior.

## Blocked by

- 7. Expose Read-State Summaries And Private PubSub
- 11. Add Explicit Channel Read Actions
