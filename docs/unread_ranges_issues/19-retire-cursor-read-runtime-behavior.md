# Retire Cursor-Read Runtime Behavior

**Type:** AFK

**Blocked by:** 3. Backfill Range State From Cursor Reads, 5. Create Message Send Unread Fanout, 7. Expose Read-State Summaries And Private PubSub, 10. Replace Channel Mount With Landing Windows, 11. Add Explicit Channel Read Actions, 14. Add Visible-Read Observation Hook, 18. Sync Read State Across User Sessions

**User stories covered:** 1-3, 10-11, 24, 36-38, 46

## What to build

Audit and finish removal of the old `channel_reads` cursor model from active
unread behavior. The read-on-open behavior is removed earlier when Channel mount
switches to landing windows; this slice verifies no remaining runtime unread
counts, read actions, Channel opening, selected-Channel message handling,
cross-session sync, or send fanout path still depends on cursor reads.

Cursor rows may remain as historical migration input until a later cleanup, but
they should no longer be part of active unread behavior.

## Acceptance criteria

- [ ] Opening a Channel no longer calls cursor-based mark-read behavior.
- [ ] The old Channel LiveView `mark_selected_channel_read` behavior has been
      removed or is no longer reachable on mount or selected-Channel message
      refresh.
- [ ] Sidebar unread badges are sourced from `channel_read_states`.
- [ ] Message send unread behavior uses span fanout rather than advancing
      cursor reads.
- [ ] Explicit read actions clear spans and maintain read states.
- [ ] Visible-read observation clears spans and maintains read states.
- [ ] Private read-state PubSub, not workspace message refreshes alone, keeps
      same-User sessions synchronized.
- [ ] LiveViews do not assemble cursor-read queries directly.
- [ ] Chat APIs that still expose cursor semantics are removed, deprecated, or
      limited to migration compatibility.
- [ ] Tests that asserted read-on-open behavior are updated to the new
      preserve-unread behavior.
- [ ] No runtime unread path depends on ChannelServer state as the source of
      truth.
- [ ] Focused regression tests prove opening preserves unread, sending does
      not clear sender backlog, selected-Channel incoming Messages are not
      auto-marked read, and badges remain exact.

## Blocked by

- 3. Backfill Range State From Cursor Reads
- 5. Create Message Send Unread Fanout
- 7. Expose Read-State Summaries And Private PubSub
- 10. Replace Channel Mount With Landing Windows
- 11. Add Explicit Channel Read Actions
- 14. Add Visible-Read Observation Hook
- 18. Sync Read State Across User Sessions
