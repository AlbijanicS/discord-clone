# Render Unread Divider And Sticky Actions

**Type:** AFK

**Blocked by:** 10. Replace Channel Mount With Landing Windows, 11. Add Explicit Channel Read Actions, 14. Add Visible-Read Observation Hook

**User stories covered:** 6-8, 17-19, 46

## What to build

Render the in-pane unread affordances for the current Message window. The
inline unread divider should mark the loaded Message where unread began, while
a sticky unread action bar should appear when unread exists outside the useful
loaded window.

This slice should keep the divider visually stable while the User reads and
avoid directional unread counts inside the message pane.

## Acceptance criteria

- [ ] The inline unread divider renders only when its target Message is loaded.
- [ ] The divider target is calculated when opening, jumping, replacing the
      Message window, or clearing all unread.
- [ ] The divider does not chase the first remaining unread Message after every
      visible-read event.
- [ ] The divider disappears when unread state is cleared.
- [ ] A sticky unread action bar appears under the Channel header when unread
      exists outside the current loaded window and the inline divider is not
      useful.
- [ ] The sticky bar includes `Jump to oldest unread`.
- [ ] The sticky bar includes `Mark as read`.
- [ ] The sticky bar hides after `Jump to oldest unread` when the inline
      divider is visible.
- [ ] The message pane does not show directional unread counts.
- [ ] The message pane does not add `Jump to next unread`.
- [ ] The UI uses stable DOM IDs for the divider and sticky actions.
- [ ] Focused LiveView tests cover divider render, divider stability, sticky
      bar visibility, and action outcomes.

## Blocked by

- 10. Replace Channel Mount With Landing Windows
- 11. Add Explicit Channel Read Actions
- 14. Add Visible-Read Observation Hook
