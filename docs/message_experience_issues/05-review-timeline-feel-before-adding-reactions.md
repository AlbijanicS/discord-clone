# Review Timeline Feel Before Adding Reactions

**Type:** HITL

**Blocked by:** 1. Stabilize The Channel Message Row Layout, 2. Add Simple Same-Author Message Grouping, 3. Preserve Grouping Across Live Inserts And Older History, 4. Polish Message Hover And Composer Spacing

**User stories covered:** 1-4, 10, 13

## What to build

Pause after the timeline polish slices and review the actual Channel message
surface before reaction UI is layered onto it. The goal is a human confirmation
that the message list no longer feels like detached floating rows and that it
is ready to carry reaction pills and hover controls.

This is intentionally a human-in-the-loop checkpoint. It should produce either
approval to proceed or a short punch list of visual adjustments.

## Acceptance criteria

- [x] The polished Channel timeline is available to review in a running app.
- [x] Full rows, compact grouped rows, hover states, older-message loading, live
      inserts, empty state, and composer spacing are reviewed together.
- [x] The reviewer confirms the timeline is ready for reaction UI, or records a
      small follow-up list before reactions proceed.
- [x] No reaction UI is added in this checkpoint.
- [x] Any requested adjustments are documented before dependent reaction-render
      issues begin.

## Review outcome

Reviewed in the running Phoenix app on June 30, 2026.

Review scenes used:

- `/workspaces/13/channels/18` for full rows, compact grouped rows, composer spacing, and a local live send.
- `/workspaces/13/channels/19` for the empty Channel state.
- `/workspaces/13/channels/20` for older-message loading.

Confirmed:

- Full rows show avatar, author, timestamp, and the anchored body column.
- Compact rows align under the message body column and keep the same hover-surface contract as full rows.
- The composer panel and shell visually attach to the timeline while preserving the existing form, input, submit, and typing indicator selectors.
- Loading older history prepends older rows without breaking the row stream structure.
- A local send appends to the timeline and clears the composer.
- No reaction UI was added in this checkpoint.

Follow-up punch list before reaction UI:

- None. The timeline is ready for the next reaction-related slice.

## Blocked by

- 1. Stabilize The Channel Message Row Layout
- 2. Add Simple Same-Author Message Grouping
- 3. Preserve Grouping Across Live Inserts And Older History
- 4. Polish Message Hover And Composer Spacing
