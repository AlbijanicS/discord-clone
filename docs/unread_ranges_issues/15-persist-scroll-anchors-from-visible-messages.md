# Persist Scroll Anchors From Visible Messages

**Type:** AFK

**Blocked by:** 9. Add Sequence-Based Message Windows, 10. Replace Channel Mount With Landing Windows

**User stories covered:** 25-27, 31, 38, 46

## What to build

Persist the User's last meaningful position in a Channel by sending debounced
scroll-anchor updates from the browser. The anchor should use the center-most
visible Message and update `last_viewed_anchor_seq` without marking anything
read.

This slice lets no-unread Channels reopen where the User left off.

## Acceptance criteria

- [ ] A client hook identifies the center-most visible Message in the Channel
      message container.
- [ ] Scroll-anchor updates are debounced around 1.5 seconds.
- [ ] The server validates authenticated Workspace membership before updating
      the anchor.
- [ ] Anchor updates validate sequence bounds for the Channel.
- [ ] Anchor updates are accepted only for Message sequences currently present in
      the rendered window.
- [ ] Anchor writes update `last_viewed_anchor_seq`.
- [ ] Anchor writes do not modify unread spans.
- [ ] Anchor writes do not modify unread counts.
- [ ] No-unread Channel openings use `last_viewed_anchor_seq` when present.
- [ ] Unread Channel openings still prefer unread landing over the anchor.
- [ ] Focused Chat and LiveView tests cover anchor writes, access validation,
      no-read side effects, and reopen behavior.

## Blocked by

- 9. Add Sequence-Based Message Windows
- 10. Replace Channel Mount With Landing Windows
