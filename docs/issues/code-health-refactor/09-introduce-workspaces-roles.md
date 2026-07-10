Status: ready-for-agent

# 09 — Introduce Workspaces.Roles + migrate callers (expand–contract)

## Parent

[Code-Health Refactor PRD](../code_health_refactor_prd.md)

## What to build

Give Workspace Role names a single source of truth. Today the role strings
(owner/admin/member) are spelled as bare literals or module attributes in at least
three places: the Workspaces context, the membership schema, and the Chat context.

This is a shared-symbol change with a small blast radius, so do it expand→contract
within the one issue: first add a `Workspaces.Roles` module exposing the role values,
the full set, and the role-capability predicates; then migrate every caller (Workspaces
context, membership schema helper, Chat context) to use it; then remove the now-dead
literal definitions. The suite stays green throughout because the new module is added
before any literal is removed.

## Acceptance criteria

- [ ] A `Workspaces.Roles` module is the only definition of the Role vocabulary and the
      role-capability rules.
- [ ] The Workspaces context, membership schema, and Chat context reference it instead of
      bare role strings/attributes.
- [ ] No behavior change to any capability decision or Role validation.
- [ ] `mix precommit` is green.

## Blocked by

None - can start immediately.
