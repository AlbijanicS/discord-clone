# UUID-Native Identifier Refactor — PRD

## Problem Statement

Every entity in the Discord clone is currently identified by a sequential integer primary key. Sequential integers leak information (row counts, creation order, relative volume) through URLs, API responses, and DOM attributes, and they make identifiers guessable and enumerable. As the project matures toward Discord-like semantics — where every workspace, channel, message, and user is addressed by an opaque snowflake-style identifier — integer keys are the wrong foundation. We want opaque, non-enumerable, globally unique identifiers for every persisted entity, established as the schema's native identity model rather than bolted on later.

## Solution

Replace integer primary and foreign keys with UUIDs across **every** Ecto-backed table, and rebuild the database as a single fresh UUID-native baseline. Because this is a learning project with disposable data, there is no in-place migration, dual-ID period, or backfill: existing development and test databases are reset. After the refactor, identifiers are opaque UUID strings everywhere they surface — URLs, LiveView event payloads, DOM IDs, PubSub topics, registry keys, and audit metadata — while genuinely numeric domain values (message/unread sequences, counts, durations, scroll positions) stay numeric.

Two correctness concerns discovered during review are folded into this refactor:

1. **Creation-order ordering must survive the switch.** Timestamps are currently second-precision (`:utc_datetime`), so same-second rows are today disambiguated by the monotonic integer `id`. Random UUIDs (UUIDv4, Ecto's default for `:binary_id`) break that tiebreak. We move timestamps to `:utc_datetime_usec` so `inserted_at` alone carries creation order and the random `id` tiebreak effectively never fires.
2. **Malformed identifiers must degrade to not-found, not crash.** Integer parsing (`String.to_integer/1`) raises on bad input today; under UUIDs a bad path/event value flows into `Repo.get` and can raise `Ecto.Query.CastError`. Graceful malformed-ID handling becomes a first-class, tested behavior.

## User Stories

1. As a workspace member, I want the workspace ID in my browser URL to be an opaque UUID, so that it does not reveal how many workspaces exist or the order they were created.
2. As a workspace member, I want channel URLs to carry opaque UUIDs, so that channel identifiers are not guessable or enumerable.
3. As a workspace member, I want message identifiers to be UUIDs, so that individual messages cannot be enumerated by incrementing an integer.
4. As a user, I want my own user identifier to be a UUID wherever it appears, so that my account cannot be probed by sequential-ID guessing.
5. As a workspace owner, I want member lists to still appear in stable creation order, so that the roster does not visibly reshuffle after the identifier change.
6. As a workspace owner, I want the audit log to remain in correct chronological order, so that I can still read moderation history top-to-bottom by time.
7. As a workspace owner, I want the channel list to keep its creation order, so that navigation stays predictable.
8. As a workspace member, I want recent messages to render in the same order as before, so that conversations read correctly regardless of the identifier type.
9. As a workspace member, I want unread channel summaries to remain in a stable order, so that the unread UI does not jump around.
10. As a moderator, I want to promote, demote, mute, timeout, kick, ban, and unban members using UUID user identifiers, so that all moderation actions work unchanged after the refactor.
11. As a user following an invite link, I want to be redirected to a UUID-based workspace/channel URL that resolves correctly, so that joining still works end-to-end.
12. As a user, I want message reactions to add and remove correctly using UUID message and user identifiers, so that reactions are unaffected by the identifier change.
13. As a user, I want presence (who's online) to update correctly with UUID user identifiers as registry and state keys, so that online indicators keep working.
14. As a user, I want typing indicators to appear and clear correctly with UUID channel/user identifiers, so that live typing feedback is unaffected.
15. As a user, I want unread counts and unread spans to compute correctly with UUID channel/user identifiers, so that unread tracking still works while sequence math stays numeric.
16. As a user who mistypes or tampers with a workspace/channel URL, I want a clean not-found/unauthorized response, so that the app does not show a server error.
17. As a user who sends a malformed identifier in a LiveView event, I want the action to be safely ignored or rejected, so that a crafted payload cannot crash my session.
18. As a developer, I want a single UUID-native baseline migration, so that the schema history is clean and easy to reason about.
19. As a developer, I want every schema to declare UUID primary and foreign key types, so that the identity model is explicit and consistent across all 14 tables.
20. As a developer, I want both PostgreSQL defaults and Ecto autogeneration to produce UUIDs, so that raw/bulk inserts and normal changeset inserts both get valid identifiers.
21. As a developer, I want the web layer free of integer-ID assumptions, so that no `String.to_integer/1` call silently breaks on a UUID.
22. As a developer, I want fixtures and test helpers to obtain UUIDs naturally from Ecto, so that tests need no hard-coded integer IDs.
23. As a developer, I want a database-level test that asserts UUID primary keys, defaults, foreign-key delete behavior, unique indexes, check constraints, and the unread-span exclusion constraint, so that the fresh baseline is verified in one place.
24. As a developer, I want documentation stating the refactor is destructive and requires a database reset, so that no one expects an integer-ID upgrade path.
25. As a developer, I want message ordering and local `seq` behavior to remain independent of message UUIDs, so that history windows and unread ranges keep working.
26. As a developer running the suite after the change, I want ordering-sensitive tests to remain deterministic, so that the switch to random UUIDs does not introduce flakiness.

## Implementation Decisions

**Scope of conversion**
- UUIDs apply to **every** Ecto-backed table — all 14: `users`, `users_tokens`, `workspaces`, `channels`, `workspace_memberships`, `workspace_invites`, `workspace_moderations`, `workspace_bans`, `workspace_audit_events`, `messages`, `message_reactions`, `channel_reads` (legacy read-position table, explicitly included), `channel_read_states`, `channel_unread_spans`.
- The 14-table relationship graph and every foreign key — including nullability and `on_delete` behavior (`:delete_all`, `:nilify_all`, `:restrict`) — are preserved exactly; only the key **type** changes to `:binary_id`.

**Baseline migration**
- Collapse the 17 integer-era migrations into a **single UUID-native baseline migration**; the incremental migrations are removed.
- Enable `citext` (case-insensitive `users.email`) and `btree_gist` (unread-span exclusion constraint).
- **Do not enable `pgcrypto`.** The local server is PostgreSQL 14.20, and `gen_random_uuid()` is built into core from PostgreSQL 13 onward, so no extension is required for the UUID default.
- Every table gets an explicit UUID primary key with a PostgreSQL `gen_random_uuid()` default.
- Every foreign key is recreated as `:binary_id`, preserving delete behavior, uniqueness rules, indexes, check constraints, and the GiST exclusion constraint on unread spans.
- Preserve the intentional workspace ↔ landing-channel creation cycle: insert the workspace with a nullable `default_channel_id`, create its `general` channel, then assign the landing channel.

**Schema layer**
- Add `@primary_key {:id, :binary_id, autogenerate: true}` and `@foreign_key_type :binary_id` to all 14 schemas.
- Keep relationships, changesets, domain validations, and bigint sequence fields unchanged except for the key type.

**Timestamps / ordering (review finding #1)**
- Change `timestamps` from `:utc_datetime` (second precision) to `:utc_datetime_usec` (microsecond precision) across the schemas/baseline.
- Rationale: current `order_by: [inserted_at, id]` clauses rely on the monotonic integer `id` to break same-second ties into creation order. UUIDv4 is random, so without microsecond timestamps, same-second rows would sort randomly — affecting member lists, audit log, bans, channel lists, recent-message ordering, and channel unread summaries (the last of which orders by `channel.id` alone). Microsecond precision makes `inserted_at` the effective sort key and renders the random `id` tiebreak inert.
- UUIDs remain valid deterministic tiebreakers but must not be interpreted as chronological. Message ordering continues to be driven by the numeric `seq`, not by message UUIDs.

**Identifier boundaries (contexts, runtime, PubSub)**
- Treat entity IDs as canonical UUID strings in Ecto queries, maps, `WorkspaceRegistry`/`ChannelRegistry` keys, GenServer state, moderation timeout timers, PubSub event payloads (`%{workspace_id: ...}`, `%{channel_id: ...}`, `%{user_id: ...}`), and interpolated topic names (`chat:workspace_presence:<workspace_id>`, `chat:channel:<channel_id>`).
- Preserve the public context facade APIs and authorization behavior. The web layer continues to call context facades, not schemas directly.
- Keep sequence guards (`anchor_seq`, `target_seq`, `before_seq`, `after_seq`) and count/duration parsing numeric — these are not entity IDs.
- `Repo.insert_all` / bulk paths (unread storage) rely on the PostgreSQL UUID default when they omit primary keys.

**Malformed-ID handling (review finding #2)**
- Malformed UUID input must follow the existing not-found/unauthorized flow **without crashing**. Routes have no ID format constraints, and today integer parsing raises `ArgumentError` while `Repo.get` on a non-castable value can raise `Ecto.Query.CastError`.
- Each boundary that accepts an externally supplied identifier (path params, LiveView event payloads) must degrade to the standard not-found/unauthorized outcome for malformed UUIDs rather than surfacing a 500 or crashing the LiveView.

**Web layer**
- Remove every `String.to_integer/1`, integer-only ID helper, and integer-equality assumption used for workspace, channel, user, message, and moderation IDs (notably in `member_actions`, `entry`, `invite_new`, `audit_log`, and `channel_live/show`, including their local `to_integer/1` helpers).
- Keep numeric parsing only for genuinely numeric values (message sequences, scroll positions, invite-use counts, timeout durations) — including `ChannelLive.Show`'s `parse_integer/1`/`parse_number/1`, which are sequence/scroll helpers, not ID parsers.
- Route generation (`~p`), event payloads, DOM IDs/data attributes, stream keys, action-menu assigns, and the invite controller redirect carry UUID strings unchanged. DOM interpolations are already string-safe.

**Fixtures, SQL, docs**
- Normal fixtures obtain UUIDs from Ecto inserts; any explicit-ID setup uses valid UUID literals.
- Raw SQL test inserts rely on the database UUID default or supply UUIDs intentionally.
- Document that the refactor is destructive: reset development/test databases before use; no integer-ID compatibility or migration path is provided.

**Tiny commit sequence** (unchanged from the source plan, with the two findings folded in)
1. Add UUID conventions + `:utc_datetime_usec` to one isolated schema plus focused schema/fixture tests.
2. Extend to all Accounts and Workspace schemas; update associations and tests.
3. Extend to all Chat/read/unread schemas; update schema and context tests.
4. Replace migration history with the UUID baseline (citext + btree_gist, no pgcrypto); preserve constraints/indexes/exclusion constraint.
5. Update raw SQL and add the DB baseline-schema test; remove obsolete incremental migration tests.
6. Convert Accounts/Workspaces/Chat/Unread/runtime identifier + PubSub/registry handling, including malformed-ID degradation.
7. Convert LiveViews/controllers/routes/event handlers; remove integer ID parsers.
8. Update fixtures + reset instructions; run `mix precommit`.

## Testing Decisions

**What makes a good test here:** assert externally observable behavior — that routes resolve, events act, ordering is stable, malformed IDs degrade cleanly, and constraints hold — not that a specific key happens to be a UUID string internally. Prefer the highest existing seam; add exactly one new seam for the database baseline.

**Seam 1 — Context facades (existing, primary).** Accounts, Workspaces, and Chat public functions. The existing context/unread/reaction/moderation/runtime/presence test suites already exercise this seam; they pass through unchanged with UUIDs once fixtures stop assuming integers. Add/adjust assertions for: creation-order stability under microsecond timestamps (member lists, audit log, bans, channels, unread summaries), and malformed-UUID input following the not-found/unauthorized path.

**Seam 2 — LiveView / controller (existing).** `workspace_live/*`, `channel_live/*`, `user_live/*`, and the invite controller. Prior art: existing tests under `test/discord_clone_web/live/workspace_live` and `user_live`. Cover: UUID route navigation, UUID-bearing events and action menus, message reactions, presence/typing, invite redirect, and **malformed-ID handling** (bad path segment / crafted event payload → clean not-found/ignored, no 500 or crash).

**Seam 3 — Database baseline (new, replaces removed migration tests).** A single test that boots the fresh schema and asserts: UUID primary keys with working `gen_random_uuid()` defaults, foreign-key delete actions (`:delete_all` / `:nilify_all` / `:restrict`), unique indexes, unread read-state summary check constraints, and the unread-span GiST exclusion constraint. Prior art: `test/discord_clone/repo/migrations/create_unread_span_and_read_state_storage_test.exs` and `add_channel_local_message_sequences_test.exs` — these incremental rollback/reapply tests are removed and replaced by this baseline test; note the traded-away coverage explicitly.

**Suite-level:** a fresh `mix ecto.reset` produces all tables with UUID PKs and FKs; `mix precommit` passes after the reset and full test update. Genuinely numeric assertions (unread counts, `seq` values) stay numeric.

## Out of Scope

- Any in-place migration, dual-ID period, backfill, or zero-downtime compatibility phase — existing data is intentionally discarded.
- Preserving the chronological migration history — it is collapsed into one baseline.
- Switching to time-ordered UUIDs (UUIDv7) or a custom Ecto autogenerate type — Ecto's default random `:binary_id` (UUIDv4) is used, with microsecond timestamps handling ordering instead. (Recorded as a considered-and-rejected alternative, not a deliverable.)
- Changing any genuinely numeric field: message/channel `seq`, unread counts/spans, invite `max_uses`/`uses_count`, scroll positions, timeout durations.
- Router-level UUID format constraints as the *primary* malformed-ID defense — handling is at the identifier boundaries, not enforced by route regex (though such a constraint is not prohibited if convenient).
- Any change to authentication semantics, the `Scope` boundary, or domain vocabulary.

## Further Notes

- **Environment confirmed:** PostgreSQL 14.20 (Homebrew). This is why `pgcrypto` is unnecessary — `gen_random_uuid()` is in core. If the target database is ever downgraded below PostgreSQL 13, the baseline migration would need to enable `pgcrypto`.
- **Why microsecond timestamps rather than UUIDv7:** UUIDv7 would keep `id` monotonic but requires a custom Ecto type or a PostgreSQL 18 `uuidv7()` default, adding complexity this refactor deliberately avoids. `:utc_datetime_usec` solves the ordering problem with a one-line-per-schema change and no new identifier machinery.
- **Lost coverage acknowledged:** removing the two incremental-migration rollback/reapply tests drops genuine migration-mechanics coverage; the new baseline test is the deliberate replacement.
- Sources: `docs/uuid_identifier_refactor_prd.md` supersedes the draft at `~/Downloads/PLAN.md`; grounded in the session handoff (`handoff-discord-clone-uuid-identifier-study-20260710.md`) and direct codebase verification of timestamp precision, `order_by` clauses, web-layer integer parsing, route definitions, and PostgreSQL version.
