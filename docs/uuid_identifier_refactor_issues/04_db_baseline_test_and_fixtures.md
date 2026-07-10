# Slice 4 — DB baseline test + raw-SQL/fixtures update

## Parent

`docs/uuid_identifier_refactor_prd.md`

> **Integration note:** Part of the shared integration branch. Green is promised at Slice 5, not here.

## What to build

Replace the removed incremental-migration tests with a single database baseline test, and make fixtures and raw SQL UUID-native.

- Add one database baseline test (new seam) that boots the fresh schema and asserts: UUID primary keys with working `gen_random_uuid()` defaults; foreign-key delete actions (`:delete_all` / `:nilify_all` / `:restrict`); unique indexes; the unread read-state summary check constraints; and the unread-span GiST exclusion constraint.
- Remove the two incremental rollback/reapply migration tests (`create_unread_span_and_read_state_storage_test.exs`, `add_channel_local_message_sequences_test.exs`); this baseline test is their deliberate replacement (lost migration-mechanics coverage acknowledged).
- Update raw SQL test inserts to rely on the database UUID default or supply valid UUIDs intentionally.
- Update fixtures and test helpers so normal inserts obtain UUIDs from Ecto; any explicit-ID setup uses valid UUID literals instead of integers.

## Acceptance criteria

- [ ] A single DB baseline test asserts UUID PKs/defaults, FK delete behavior, unique indexes, unread summary checks, and the unread-span exclusion constraint.
- [ ] The two incremental-migration tests are removed.
- [ ] Raw SQL test inserts succeed under the UUID schema (via DB default or explicit UUIDs).
- [ ] Fixtures/helpers assume no integer entity IDs; explicit-ID setups use valid UUID values.
- [ ] Genuinely numeric assertions (unread counts, `seq` values) remain numeric.

## Blocked by

- Slice 1 — UUID baseline schema + migration
