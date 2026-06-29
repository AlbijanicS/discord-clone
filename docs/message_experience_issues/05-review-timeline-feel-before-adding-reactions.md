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

- [ ] The polished Channel timeline is available to review in a running app.
- [ ] Full rows, compact grouped rows, hover states, older-message loading, live
      inserts, empty state, and composer spacing are reviewed together.
- [ ] The reviewer confirms the timeline is ready for reaction UI, or records a
      small follow-up list before reactions proceed.
- [ ] No reaction UI is added in this checkpoint.
- [ ] Any requested adjustments are documented before dependent reaction-render
      issues begin.

## Blocked by

- 1. Stabilize The Channel Message Row Layout
- 2. Add Simple Same-Author Message Grouping
- 3. Preserve Grouping Across Live Inserts And Older History
- 4. Polish Message Hover And Composer Spacing
