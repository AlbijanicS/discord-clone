# 10 — Stage complete releases and document tested rollback

Status: ready-for-agent
Type: AFK
Priority: Optional — explicitly select before dispatch
User stories covered: 71–74

## Parent and scope

Read [the parent PRD](../PRD.md), [the dispatch guide](../PORTFOLIO_PLAN.md), the repository AGENTS.md, CONTEXT.md, and relevant accepted ADRs. This is one bounded slice of the portfolio plan. The parent PRD supplies semantics, not permission to implement its entire program.

## Blocked by

01, 06; finish before final 07 run

## What to build

Replace instructions that copy into the running directory with immutable versioned release staging and atomic selection on the same filesystem. Adapt the service path and operator commands to preserve a known-good release. Run compatible migrations before switching; check HTTPS health/readiness after restart and restore the prior application release on failure.

## Acceptance criteria

- [ ] Locally verifiable operator tooling proves incomplete staging or migration failure cannot select the new release.
- [ ] Selection uses an atomic rename of a prepared symlink; service paths resolve consistently to the selected release.
- [ ] Failed health/readiness restores the prior selection and restarts it, with a clear failure report if recovery itself fails.
- [ ] Document initial conversion from the existing directory layout, retain a prior release, and state that application rollback does not undo migrations.
- [ ] Provide an operator dry run/checklist; do not execute against production without explicit authorization. Hosted evidence is recorded in 07.

## Out of scope

No CI/CD platform, infrastructure migration, automatic database rollback, or architecture refactor.

## Verification and handoff

Follow the dispatch guide's shared contract. Record focused checks, full required checks where code changes, the resulting revision when available, unresolved findings, and an exact next-agent handoff. Do not silently declare externally blocked acceptance passed.
