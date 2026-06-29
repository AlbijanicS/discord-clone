# Polish Message Hover And Composer Spacing

**Type:** AFK

**Blocked by:** 1. Stabilize The Channel Message Row Layout

**User stories covered:** 10, 13

## What to build

Refine the Channel message surface around the stabilized row layout. Message
hover treatment should make rows feel interactive without cluttering the
default view, and the composer should visually belong to the same conversation
surface instead of feeling detached from the timeline.

This slice should remain visual and structural only. It should not add reaction
buttons, message action menus, rich composer behavior, or new JavaScript.

## Acceptance criteria

- [ ] Message rows have a subtle hover treatment that improves scanability
      without visual noise.
- [ ] Hover treatment works for both full rows and compact continuation rows if
      grouping has already landed.
- [ ] Composer spacing, border, and alignment feel connected to the timeline.
- [ ] Composer behavior remains unchanged for sending and typing indicators.
- [ ] No external scripts, external stylesheets, daisyUI-specific dependencies,
      or inline script tags are introduced.
- [ ] Focused LiveView tests continue to locate the composer and message rows
      by stable selectors.

## Blocked by

- 1. Stabilize The Channel Message Row Layout
