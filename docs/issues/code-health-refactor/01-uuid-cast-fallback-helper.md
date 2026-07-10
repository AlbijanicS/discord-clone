Status: ready-for-agent

# 01 — UUID cast-or-fallback helper

## Parent

[Code-Health Refactor PRD](../code_health_refactor_prd.md)

## What to build

Introduce one helper on the UUID identifier module that expresses the repeated
"cast this identifier; if it isn't a valid UUID, return a caller-chosen fallback,
otherwise run the query" pattern. Route the ~10 defensive getters that currently
inline `with {:ok, id} <- cast(id) do Repo... else :error -> nil/[]/false end`
through it — across the Workspaces context, the Chat context, the Unread submodule,
and the runtime lookups.

Pure cleanup: the observable results (a bad identifier still yields the same
not-found/empty/false outcome) are identical.

## Acceptance criteria

- [ ] A single reusable cast-or-fallback helper exists on the UUID identifier module.
- [ ] Every getter that previously inlined the cast-or-fallback wrapper now uses it.
- [ ] Invalid-identifier inputs return exactly the same fallback values as before
      (nil / empty list / false, per call site).
- [ ] No public function's return shape changes.
- [ ] `mix precommit` is green.

## Blocked by

None - can start immediately.
