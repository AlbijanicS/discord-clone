Status: ready-for-agent

# 02 — Component attr types + defensive coordinate parsing

## Parent

[Code-Health Refactor PRD](../code_health_refactor_prd.md)

## What to build

Correct the component metadata and input handling left inconsistent by today's
`id -> UUID` refactor. The member-actions menu and the workspace shell declare
several identifier `attr`s as `:integer`, but those identifiers are now UUID
strings; update them to the correct string/any type. Make the channel view's
context-menu coordinate handling parse defensively instead of calling
`String.to_integer/1` on event-supplied values, so a malformed or forged
context-menu event cannot raise and crash the channel view. Also drop the
redundant `else {:error, reason} -> {:error, reason}` passthrough in the
Workspaces `fetch_channel` function.

## Acceptance criteria

- [ ] No component `attr` declares `:integer` for a value that is a UUID identifier.
- [ ] A context-menu event carrying non-numeric coordinates is handled without raising.
- [ ] The redundant `else` clause in `fetch_channel` is removed with no behavior change.
- [ ] Existing LiveView/menu behavior is unchanged for well-formed events.
- [ ] `mix precommit` is green.

## Blocked by

None - can start immediately.
