# Slice 5 — Integrate & verify

## Parent

`docs/uuid_identifier_refactor_prd.md`

> **Integration note:** This is the integrate-and-verify issue for the wide refactor. Green (`mix precommit`) is promised **here**, once Slices 2, 3, and 4 have merged onto the integration branch atop Slice 1.

## What to build

Bring the integration branch to a fully green, documented, UUID-native state and verify ordering behavior end-to-end.

- Document that the refactor is destructive: reset development/test databases before use; no integer-ID compatibility or migration path is provided (update the relevant docs / reset instructions).
- Verify creation-order stability under `:utc_datetime_usec`: member lists, audit log, bans, channel lists, recent-message ordering, and channel unread summaries (the last orders by `channel.id` alone) render in stable creation order rather than reshuffling.
- Run a fresh `mix ecto.reset` and the full `mix precommit` on the integrated branch.

## Acceptance criteria

- [ ] Docs state the refactor is destructive and require a database reset; no integer-ID upgrade path is implied.
- [ ] `mix ecto.reset` produces all tables with UUID PKs and FKs.
- [ ] Ordering-sensitive views/queries remain in stable creation order with random UUIDs (no flakiness from same-second rows).
- [ ] Full `mix precommit` passes (compile `--warnings-as-errors`, `deps.unlock --unused`, `format`, `test`).

## Blocked by

- Slice 2 — Context / runtime / PubSub identifier boundary conversion
- Slice 3 — Web-layer de-integering + malformed-ID handling
- Slice 4 — DB baseline test + raw-SQL/fixtures update
