# Slice 3 — Web-layer de-integering + malformed-ID handling

## Parent

`docs/uuid_identifier_refactor_prd.md`

> **Integration note:** Part of the shared integration branch. Green is promised at Slice 5, not here.

## What to build

Remove every integer assumption about entity identifiers from the web layer so that workspace, channel, user, message, and moderation IDs flow as UUID strings end-to-end.

- Remove every `String.to_integer/1` call, local `to_integer/1` helper, and integer-equality assumption used for entity IDs (notably in the member-actions menu, workspace entry, invite-new, audit-log, and channel show LiveViews).
- Route generation (`~p`), LiveView event payloads, DOM IDs/data attributes, stream keys, action-menu assigns, and the invite controller redirect carry UUID strings unchanged (DOM interpolations are already string-safe).
- Keep numeric parsing only for genuinely numeric values — message sequences, scroll positions, invite-use counts, timeout durations — including `ChannelLive.Show`'s `parse_integer/1`/`parse_number/1`, which are sequence/scroll helpers, not ID parsers.
- Malformed-ID handling at the web boundary: a bad path segment (routes have no ID format constraint) or a crafted event payload degrades to the standard not-found/unauthorized outcome or is safely ignored — never a 500 or a crashed LiveView.

## Acceptance criteria

- [ ] No `String.to_integer` / integer-only ID helper / integer-equality remains for workspace/channel/user/message/moderation IDs.
- [ ] Numeric parsing is retained only for sequences, scroll positions, use counts, and durations.
- [ ] UUID route navigation works; events, action menus, message reactions, presence/typing, and the invite redirect operate with UUID strings.
- [ ] A malformed workspace/channel path segment returns a clean not-found/unauthorized response (no server error).
- [ ] A malformed identifier in a LiveView event is safely rejected/ignored without crashing the session.

## Blocked by

- Slice 1 — UUID baseline schema + migration
