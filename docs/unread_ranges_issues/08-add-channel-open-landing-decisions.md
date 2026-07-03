# Add Channel Open Landing Decisions

**Type:** AFK

**Blocked by:** 7. Expose Read-State Summaries And Private PubSub

**User stories covered:** 1, 4-5, 25-27, 38, 45-46

## What to build

Add a Chat-owned Channel open workflow that validates access, records
`last_opened_at`, preserves unread spans, and returns enough read-state summary
for the LiveView to choose a landing target. Opening a Channel should navigate
the User intelligently without marking anything read.

This slice establishes the product decision that unread state wins over resume
anchors, and that opening alone never clears unread.

## Acceptance criteria

- [ ] Chat exposes an authenticated `open_channel` workflow.
- [ ] Opening a Channel validates Workspace membership.
- [ ] Opening a Channel updates `last_opened_at`.
- [ ] Opening a Channel does not delete unread spans.
- [ ] Opening a Channel does not decrement unread counts.
- [ ] Opening a Channel does not call or update the old `channel_reads`
      cursor-read behavior.
- [ ] When unread count is at or below the small unread landing limit, the
      landing target uses `first_unread_seq`.
- [ ] When unread count is above the small unread landing limit, the landing
      target is near recent unread Messages, about 20 before `last_unread_seq`
      when possible.
- [ ] When there is no unread state, the landing target uses
      `last_viewed_anchor_seq` when present.
- [ ] When there is no unread state or anchor, the landing target is latest.
- [ ] Unread landing wins over `last_viewed_anchor_seq`.
- [ ] Message page size and small-unread landing limit are separate constants,
      even if both start at 50.
- [ ] Focused Chat tests cover access, `last_opened_at`, unread preservation,
      small unread landing, large unread landing, anchor landing, and latest
      landing.

## Blocked by

- 7. Expose Read-State Summaries And Private PubSub
