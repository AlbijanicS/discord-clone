# Stabilize The Channel Message Row Layout

**Type:** AFK

**Blocked by:** None - can start immediately

**User stories covered:** 1-2, 7, 9, 11-12, 33

## What to build

Reshape the Channel timeline so each message feels anchored in a stable
conversation layout. A Workspace Member should see a clear avatar column,
author/timestamp header, and message body column while preserving the existing
live message stream, empty state, line breaks, and safe wrapping behavior.

This slice should improve the visible message row without adding grouping,
emoji parsing, reactions, or new message actions. It gives later slices a
clean surface to build on.

## Acceptance criteria

- [ ] The Channel timeline uses a stable avatar column and message-content
      column.
- [ ] Full message rows show the author's avatar/initial, username, timestamp,
      and body in a visually anchored layout.
- [ ] Existing live message insertion continues to work.
- [ ] The empty Channel state still renders clearly.
- [ ] Message text preserves line breaks.
- [ ] Long words and emoji-heavy text wrap without breaking the layout.
- [ ] The implementation keeps grouping out of the Chat context.
- [ ] The LiveView continues to use public Chat APIs only.
- [ ] Focused LiveView tests verify stable message row selectors without raw
      HTML assertions.

## Blocked by

None - can start immediately.
