Status: ready-for-agent

# 17 — Add Credo (strict) + fix/annotate

## Parent

[Code-Health Refactor PRD](../code_health_refactor_prd.md)

## What to build

Add Credo (strict) to the dev/test toolchain so the duplication and complexity removed
by this refactor cannot silently regrow. Add the dependency (dev/test only), a project
Credo config, and wire a strict check into the workflow (alongside format/compile/test).
Resolve the findings by fixing them or annotating deliberate exceptions. Do this last so
it runs against the already-simplified code rather than churning against in-flight
refactors.

## Acceptance criteria

- [ ] Credo is added as a dev/test dependency with a project config.
- [ ] `mix credo --strict` runs clean (findings fixed or explicitly, justifiably annotated).
- [ ] A strict Credo check is part of the standard local check flow.
- [ ] No new dependency is added beyond Credo without separate approval.
- [ ] `mix precommit` is green.

## Blocked by

- Issues 06–14 (the structural refactor cluster) — added last to avoid churn.
