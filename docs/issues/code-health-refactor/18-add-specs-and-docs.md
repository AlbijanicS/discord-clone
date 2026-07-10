Status: ready-for-agent

# 18 — Add @spec/@doc to touched public APIs

## Parent

[Code-Health Refactor PRD](../code_health_refactor_prd.md)

## What to build

Add `@doc` and `@spec` to the Workspaces and Chat public functions touched by this
refactor, describing their normalized return contracts. This both documents the context
boundary and prepares the ground for adding Dialyzer later without noise. Do this after
the error tuples are normalized so the specs describe the final, consistent shapes.

## Acceptance criteria

- [ ] Public Workspaces/Chat functions touched by the refactor carry `@spec`s reflecting
      the normalized `{:ok, _}` / `{:error, reason}` / `{:error, tag, changeset}` contracts.
- [ ] Context-API functions that form the public boundary carry a useful `@doc`.
- [ ] Specs compile cleanly (no contradictions); Dialyzer is NOT added in this issue.
- [ ] `mix precommit` is green.

## Blocked by

- [12 — Normalize public context error tuples](12-normalize-context-error-tuples.md)
