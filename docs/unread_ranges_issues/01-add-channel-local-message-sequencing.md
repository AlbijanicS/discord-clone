# Add Channel-Local Message Sequencing

**Type:** AFK

**Blocked by:** None - can start immediately

**User stories covered:** 24, 29, 36, 38, 44-46

## What to build

Give every Message a stable Channel-local sequence number and keep each
Channel's latest sequence in durable storage. A Workspace Member should be able
to send Messages normally while the Chat workflow assigns strictly increasing
sequence numbers within that Channel.

This slice establishes the ordering model that later unread spans, targeted
windows, dividers, and pagination will share. It should not introduce unread
span behavior yet.

## Acceptance criteria

- [ ] A migration adds `seq` to Messages as a Channel-local positive `bigint`.
- [ ] A migration adds `last_message_seq` to Channels as a non-null `bigint`
      that defaults to zero for empty Channels.
- [ ] Migrations are generated with `mix ecto.gen.migration`.
- [ ] The migration is staged so existing rows can be backfilled before `seq`
      becomes non-null and before constraints are enforced.
- [ ] Existing Messages are backfilled per Channel in chronological order with
      durable Message ID as the tie-breaker.
- [ ] Existing Channels have `last_message_seq` set to the highest sequence in
      that Channel, or zero for empty Channels.
- [ ] Database constraints reject non-positive Message sequences and negative
      Channel `last_message_seq` values.
- [ ] A unique database constraint prevents duplicate sequence numbers within a
      Channel.
- [ ] An index supports Message window queries by `channel_id` and `seq`.
- [ ] New Messages receive sequence numbers by locking the Channel row inside
      the Message transaction.
- [ ] Sequence assignment remains scoped to the Message's Channel and does not
      leak across Channels.
- [ ] Message reads that render authors still preload User data as needed.
- [ ] Focused tests cover backfill order, empty Channels, uniqueness, and
      concurrent sends in the same Channel.

## Blocked by

None - can start immediately.
