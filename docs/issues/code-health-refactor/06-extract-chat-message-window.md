Status: ready-for-agent

# 06 — Extract Chat.MessageWindow

## Parent

[Code-Health Refactor PRD](../code_health_refactor_prd.md)

## What to build

Remove the message-window duplication: the window query, the window/meta builder, and
the `has_older?/has_newer?/at_latest?/at_or_near_latest?` family are currently defined
identically in both the Chat context and its Unread submodule. Extract them into one
Chat submodule that both call. Behavior-preserving; verified through the existing Chat
context seam.

## Acceptance criteria

- [ ] The message-window and pagination-meta helpers exist in exactly one module.
- [ ] Both the Chat context and the Unread submodule use the extracted module.
- [ ] Pagination/window behavior (message ordering, meta flags, landing windows) is
      unchanged as asserted by existing Chat tests.
- [ ] `mix precommit` is green.

## Blocked by

None - can start immediately.
