# Slice 2 — Context / runtime / PubSub identifier boundary conversion

## Parent

`docs/uuid_identifier_refactor_prd.md`

> **Integration note:** Part of the shared integration branch. Green is promised at Slice 5, not here.

## What to build

Convert every identifier boundary below the web layer to treat entity IDs as canonical UUID strings, and make malformed identifiers degrade gracefully.

- Accounts, Workspaces, Chat, and Unread: entity IDs flow as UUID strings through Ecto queries, `Repo.get`/`Repo.get_by`, comparisons, and audit `metadata` maps (which now carry UUID strings for `invite_id`/`message_id`/`channel_id`).
- Runtime and PubSub: UUID strings used as `WorkspaceRegistry`/`ChannelRegistry` keys, GenServer state map keys (presence/typing), moderation timeout timer keys, PubSub event payloads (`%{workspace_id: ...}`, `%{channel_id: ...}`, `%{user_id: ...}`), and interpolated topic names (`chat:workspace_presence:<workspace_id>`, `chat:channel:<channel_id>`).
- Malformed-UUID handling: any externally supplied identifier that is not a valid UUID must follow the existing not-found/unauthorized flow **without crashing** (no unhandled `Ecto.Query.CastError`).
- Preserve public context facade APIs and authorization behavior. Keep sequence guards (`anchor_seq`, `target_seq`, `before_seq`, `after_seq`) and count/duration values numeric — they are not entity IDs. Message ordering stays driven by numeric `seq`, not message UUIDs. Bulk/`insert_all` unread paths rely on the DB UUID default when omitting primary keys.

## Acceptance criteria

- [ ] Accounts/Workspaces/Chat/Unread context functions operate correctly with UUID identifiers; public APIs and authorization behavior are unchanged.
- [ ] Registry keys, GenServer state keys, timeout timers, PubSub payloads, and topic names carry UUID strings and route correctly.
- [ ] Malformed UUID input to any context/runtime boundary returns the standard not-found/unauthorized result without raising or crashing a process.
- [ ] Sequence guards and count/duration values remain numeric.
- [ ] Existing context/unread/reaction/moderation/runtime/presence tests pass with UUID identifiers (once fixtures are updated in Slice 4).

## Blocked by

- Slice 1 — UUID baseline schema + migration
