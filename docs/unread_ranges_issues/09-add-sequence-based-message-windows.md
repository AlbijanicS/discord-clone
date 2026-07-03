# Add Sequence-Based Message Windows

**Type:** AFK

**Blocked by:** 1. Add Channel-Local Message Sequencing, 8. Add Channel Open Landing Decisions

**User stories covered:** 4-5, 7, 9, 25-29, 44-46

## What to build

Expose Chat APIs for loading latest, targeted, older, and newer Message windows
by Channel-local sequence number. These APIs should give Channel LiveViews one
ordering model for unread landing, jumps, dividers, and history pagination.

This slice creates the server-side windowing contract without replacing the UI
scroll behavior yet.

## Acceptance criteria

- [ ] Chat can load the latest Message page ending at the Channel's latest
      sequence.
- [ ] Chat can load a targeted window around a sequence.
- [ ] Targeted windows use a 15-before and 35-after split.
- [ ] Chat can load older Messages before the current oldest sequence.
- [ ] Chat can load newer Messages after the current newest sequence.
- [ ] Message window APIs require authenticated Workspace membership.
- [ ] Results are ordered oldest to newest for rendering.
- [ ] Results include enough metadata for the LiveView to know oldest sequence,
      newest sequence, latest sequence, and whether older or newer history
      exists.
- [ ] Results include enough metadata for the LiveView to know whether the
      current window is at or near latest.
- [ ] Targeted windows clamp cleanly near the beginning or end of Channel
      history without returning duplicate Messages.
- [ ] Latest loading works for empty Channels.
- [ ] Window loading does not rely on inserted timestamp cursors.
- [ ] Focused Chat tests cover latest, targeted, older, newer, empty Channels,
      access checks, clamped targets, metadata, and ordering.

## Blocked by

- 1. Add Channel-Local Message Sequencing
- 8. Add Channel Open Landing Decisions
