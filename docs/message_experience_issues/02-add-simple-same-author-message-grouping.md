# Add Simple Same-Author Message Grouping

**Type:** AFK

**Blocked by:** 1. Stabilize The Channel Message Row Layout

**User stories covered:** 3-6, 33

## What to build

Add the first Slack-like grouping rule for consecutive messages. When the
previous visible message is from the same author and falls within the v1 time
window, render the next message as a compact continuation aligned to the same
message body column. Speaker changes, missing previous messages, and messages
outside the time window should render as full message rows.

This slice should keep grouping as presentation behavior in the web layer
rather than adding grouping fields to durable messages or the Chat context.

## Acceptance criteria

- [ ] Consecutive messages from the same author within five minutes render as
      compact continuation rows.
- [ ] Messages from different authors render as full rows.
- [ ] Messages from the same author outside the grouping window render as full
      rows.
- [ ] The first visible message renders as a full row.
- [ ] Compact continuation rows align with the full row's message body column.
- [ ] Chat continues returning durable messages without presentation
      annotations.
- [ ] Grouping logic is isolated enough to test without relying on private
      LiveView internals where practical.
- [ ] Focused tests cover same-author grouping, speaker changes, and the time
      window.

## Blocked by

- 1. Stabilize The Channel Message Row Layout
