# Implement Span Merge And Subtract Workflows

**Type:** AFK

**Blocked by:** 2. Create Unread Span And Read-State Storage

**User stories covered:** 2-3, 12, 16, 24, 42-43, 46

## What to build

Add Chat-owned operations for adding unread ranges, subtracting visible-read
ranges, clearing a Channel, and maintaining read-state summaries. These
operations should be idempotent and should broadcast only when unread state
actually changes.

This slice is the core range algebra behind sending, visible reads, explicit
read actions, and cross-tab sync.

## Acceptance criteria

- [ ] Chat can add unread ranges for a User and Channel.
- [ ] Every add, subtract, and clear workflow runs in one transaction.
- [ ] Every mutation serializes on the matching `channel_read_states` row with a
      row-level lock before reading or changing unread spans.
- [ ] Missing read-state rows for valid members are created before the row is
      locked and mutated.
- [ ] Added ranges merge adjacent and overlapping spans.
- [ ] The implementation preserves the database invariant that unread spans for
      one User and Channel never overlap.
- [ ] Chat can subtract a visible-read range from unread spans.
- [ ] Subtraction handles exact overlap, partial overlap, middle splits,
      non-overlap, and duplicate submissions.
- [ ] Chat can clear all unread spans for a User and Channel.
- [ ] Read-state summaries are updated transactionally with span changes.
- [ ] Read-state summaries are recalculated from the resulting spans or otherwise
      proven to match the resulting spans after every mutation.
- [ ] Clearing unread sets `unread_count` to zero and clears first and last
      unread sequence fields.
- [ ] Duplicate no-op visible-read operations do not publish read-state
      broadcasts.
- [ ] Range operations validate authenticated Workspace membership.
- [ ] Unauthenticated scopes return `{:error, :unauthenticated}` and logged-in
      non-members return `{:error, :not_found}` to match existing Chat unread
      privacy semantics.
- [ ] Visible-read validation rejects unordered, out-of-bounds, and oversized
      ranges.
- [ ] Each visible-read range is capped at 50 Messages.
- [ ] Focused Chat context tests prove merge, subtract, summary maintenance,
      access validation, row-lock serialization behavior, and no-op broadcast
      behavior.

## Blocked by

- 2. Create Unread Span And Read-State Storage
