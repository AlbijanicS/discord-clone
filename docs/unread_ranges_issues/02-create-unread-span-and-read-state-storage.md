# Create Unread Span And Read-State Storage

**Type:** AFK

**Blocked by:** 1. Add Channel-Local Message Sequencing

**User stories covered:** 2-3, 24, 36-38, 42-43, 46

## What to build

Add the durable Postgres storage for range-based unread truth and fast read
summaries. Unread spans should represent the exact unread ranges for one User
and Channel, while read states should expose the sidebar and landing fields
without scanning Messages on every render.

This slice creates the data model and schemas only. Later slices will backfill,
mutate, and render the state.

## Acceptance criteria

- [ ] A migration creates `channel_unread_spans` with User, Channel,
      `from_seq`, `to_seq`, and timestamps.
- [ ] A migration creates `channel_read_states` with User, Channel,
      `unread_count`, `first_unread_seq`, `last_unread_seq`,
      `last_viewed_anchor_seq`, `last_opened_at`, and timestamps.
- [ ] Migrations are generated with `mix ecto.gen.migration`.
- [ ] A unique index prevents duplicate read-state rows for one User and
      Channel.
- [ ] Indexes support User-scoped read-state lookup and cleanup.
- [ ] Foreign keys clean up unread state when Users or Channels are deleted.
- [ ] Span constraints reject non-positive bounds and invalid ranges where
      `from_seq` is greater than `to_seq`.
- [ ] A database-level invariant prevents overlapping unread spans for the same
      User and Channel with a Postgres exclusion constraint over `user_id`,
      `channel_id`, and `int8range(from_seq, to_seq, '[]')`; enable
      `btree_gist` if needed for equality on integer IDs.
- [ ] Read-state constraints reject negative unread counts.
- [ ] Read-state constraints keep zero unread summaries consistent with nil
      first and last unread sequence fields.
- [ ] Read-state constraints keep nonzero unread summaries consistent with
      non-nil first and last unread sequence fields where first is not after
      last.
- [ ] Anchor constraints reject non-positive `last_viewed_anchor_seq` values
      when an anchor is present.
- [ ] Chat-owned schemas exist for unread spans and read states.
- [ ] Channel and User associations exist where useful for queries and tests.
- [ ] Documentation or schema comments make clear that unread spans are truth
      and read states are summary/cache state.
- [ ] Focused schema and migration tests cover uniqueness, constraints, and
      cleanup behavior, including attempted overlapping spans.

## Blocked by

- 1. Add Channel-Local Message Sequencing
