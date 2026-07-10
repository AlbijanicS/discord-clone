Status: ready-for-agent

# 12 — Normalize public context error tuples

## Parent

[Code-Health Refactor PRD](../code_health_refactor_prd.md)

## What to build

Give the public context APIs a consistent, small set of error shapes. Some functions
(workspace creation, leave-workspace, channel creation) return five-element error
tuples that leak `Ecto.Multi` failure internals (`failed_operation`, `failed_value`,
`changes_so_far`) to the web layer, while most return `{:error, reason}` or
`{:error, tag, changeset}`. Normalize every public Workspaces and Chat function to
`{:error, reason}` or `{:error, tag, changeset}`, log the transaction internals inside
the context rather than returning them, and update the member-actions web helper and
every affected caller `case` accordingly.

## Acceptance criteria

- [ ] No public context function returns a tuple that exposes `Ecto.Multi` internals.
- [ ] Every public Workspaces/Chat error is `{:error, reason}` or `{:error, tag, changeset}`.
- [ ] The member-actions web helper and all callers handle the normalized shapes; no
      caller `case` can fall through on an unmatched arity.
- [ ] Web-layer flash/redirect behavior for failures is unchanged.
- [ ] `mix precommit` is green.

## Blocked by

None - can start immediately.
