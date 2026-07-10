# Slice 1 — UUID baseline schema + migration

## Parent

`docs/uuid_identifier_refactor_prd.md`

> **Integration note:** This is a wide, destructive refactor. Slices 1–4 land on a shared integration branch and the test suite is only promised green at Slice 5 (Integrate & verify). Do not expect `mix precommit` to pass on this slice in isolation — the context and web layers still assume the old key type until their slices land.

## What to build

Establish the UUID-native identity model at the schema and database layer for all 14 Ecto-backed tables, replacing the 17 integer-era migrations with a single fresh baseline.

- Add `@primary_key {:id, :binary_id, autogenerate: true}` and `@foreign_key_type :binary_id` to every schema (`users`, `users_tokens`, `workspaces`, `channels`, `workspace_memberships`, `workspace_invites`, `workspace_moderations`, `workspace_bans`, `workspace_audit_events`, `messages`, `message_reactions`, `channel_reads`, `channel_read_states`, `channel_unread_spans`).
- Change `timestamps` from `:utc_datetime` (second precision) to `:utc_datetime_usec` across schemas and the baseline, so `inserted_at` carries creation order and the random UUID tiebreak in `order_by: [inserted_at, id]` clauses goes inert.
- Write one baseline migration for the complete current schema:
  - Enable `citext` and `btree_gist`. **Do not enable `pgcrypto`** — PostgreSQL 14.20 has `gen_random_uuid()` in core.
  - Every table: explicit UUID primary key with a `gen_random_uuid()` default.
  - Every foreign key recreated as `:binary_id`, preserving nullability, `on_delete` behavior (`:delete_all` / `:nilify_all` / `:restrict`), uniqueness rules, indexes, check constraints, and the unread-span GiST exclusion constraint.
  - Preserve the workspace ↔ landing-channel creation cycle (nullable `default_channel_id`, assigned after the `general` channel exists).
- Keep relationships, changesets, domain validations, and all bigint sequence/count fields unchanged except for the key type.

## Acceptance criteria

- [ ] All 14 schemas declare `:binary_id` primary and foreign key types and use `:utc_datetime_usec` timestamps.
- [ ] A single baseline migration recreates the full schema; the 17 integer-era migrations are removed.
- [ ] `citext` and `btree_gist` are enabled; `pgcrypto` is **not** enabled.
- [ ] `mix ecto.reset` produces all tables with UUID primary keys defaulting to `gen_random_uuid()` and UUID foreign keys.
- [ ] All FK delete behaviors, unique indexes, check constraints, and the unread-span exclusion constraint are preserved.
- [ ] The workspace ↔ landing-channel creation cycle still works (workspace inserts, general channel created, landing channel assigned).
- [ ] Numeric `seq`/count fields are unchanged.

## Blocked by

None - can start immediately.
