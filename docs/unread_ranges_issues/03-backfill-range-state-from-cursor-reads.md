# Backfill Range State From Cursor Reads

**Type:** AFK

**Blocked by:** 1. Add Channel-Local Message Sequencing, 2. Create Unread Span And Read-State Storage

**User stories covered:** 1-3, 10-11, 24, 36, 46

## What to build

Populate the new range-based unread model from the existing cursor read rows.
For existing Workspace Members, Messages after the old cursor become unread
spans, excluding the User's own Messages. The resulting read-state summary
should match those spans.

This slice preserves the current unread-count meaning while preparing the app
to stop using cursor reads as active state.

## Acceptance criteria

- [ ] Existing Workspace Members receive one read-state row per Channel they
      can access.
- [ ] Existing cursor reads are used as migration input only.
- [ ] Messages after the cursor become unread for that User and Channel.
- [ ] Messages authored by the User are excluded from their unread spans.
- [ ] Messages whose author has been deleted and now have `user_id: nil` count
      as not-own Messages when they are otherwise eligible.
- [ ] Channels with no unread Messages receive zero-unread read states.
- [ ] Empty Channels receive zero-unread read states.
- [ ] Backfilled spans are merged into the fewest adjacent ranges possible.
- [ ] Read-state `unread_count`, `first_unread_seq`, and `last_unread_seq`
      match the backfilled spans.
- [ ] Missing or nil old cursor rows use the existing membership-time fallback
      semantics from the cursor model.
- [ ] The membership-time fallback does not count pre-join history as unread.
- [ ] Backfill behavior is idempotent for already migrated data.
- [ ] Focused tests cover cursor after latest, cursor before unread history,
      missing cursor rows, nil cursor rows, own Messages, nil-author Messages,
      and empty Channels.

## Blocked by

- 1. Add Channel-Local Message Sequencing
- 2. Create Unread Span And Read-State Storage
