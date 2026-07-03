# Add Visible-Read Observation Hook

**Type:** AFK

**Blocked by:** 4. Implement Span Merge And Subtract Workflows, 10. Replace Channel Mount With Landing Windows

**User stories covered:** 2-3, 12-16, 42-43, 46

## What to build

Add browser visibility observation so Messages become read only after they were
actually visible. A Message should count as observed when at least 60 percent
of its row is visible for 1 second while the document is visible and the window
is focused.

This slice connects client observation to compact server range subtraction
without adding client event IDs.

## Acceptance criteria

- [ ] Message rows expose stable DOM IDs and sequence metadata for observation.
- [ ] A LiveView hook observes rendered Message rows.
- [ ] The hook uses IntersectionObserver or an equivalent viewport observation
      mechanism.
- [ ] The observer root is the Channel message container, not the browser
      viewport.
- [ ] A normal-height Message is submitted as read only after at least 60 percent
      row visibility for 1 second.
- [ ] A Message taller than the message container is submitted as read only after
      the visible pixels reach the smaller of 60 percent of the row height or 60
      percent of the message-container height for 1 second.
- [ ] Timers pause or cancel when the document is hidden.
- [ ] Timers pause or cancel when the window is unfocused.
- [ ] Timers cancel when observed rows are patched, trimmed, or removed.
- [ ] The hook unobserves removed rows and observes newly inserted rows after
      LiveView updates.
- [ ] Typing in the message input still counts as active focused use.
- [ ] The hook submits compact ordered sequence ranges.
- [ ] The hook splits larger observed sets so no submitted range exceeds 50
      Messages.
- [ ] The server rejects oversized, unordered, out-of-bounds, non-member, and
      unauthenticated visible-read events.
- [ ] The LiveView rejects visible-read ranges for sequences that are not
      currently present in the rendered window and observed by the hook.
- [ ] Visible-read subtraction updates unread spans and read-state summaries.
- [ ] Duplicate observed ranges are idempotent and do not churn broadcasts.
- [ ] Focused LiveView event-contract tests and practical JS checks cover the
      hook behavior, including tall rows, focus/visibility pauses, LiveView
      patch cleanup, and rendered-window validation.

## Blocked by

- 4. Implement Span Merge And Subtract Workflows
- 10. Replace Channel Mount With Landing Windows
