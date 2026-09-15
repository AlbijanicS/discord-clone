# 01 — Automate the existing quality gates

Status: ready-for-agent
Type: AFK
Priority: Core
User stories covered: 66–67, 75

## Parent and scope

Read [the parent PRD](../PRD.md), [the dispatch guide](../PORTFOLIO_PLAN.md), the repository AGENTS.md, CONTEXT.md, and relevant accepted ADRs. This is one bounded slice of the portfolio plan. The parent PRD supplies semantics, not permission to implement its entire program.

## Blocked by

None

## What to build

Create a fast CI workflow for pull requests and the primary branch, using a clean PostgreSQL service and explicitly pinned supported Elixir, OTP, and Node versions. Reuse the existing precommit checks and expose the configured coverage gate separately. Verify the actual development toolchain before choosing pins.

## Acceptance criteria

- [ ] CI compiles with warnings as errors, runs strict Credo, all existing JavaScript tests, Elixir tests, and the existing coverage threshold.
- [ ] Check formatting without allowing the formatting step in precommit to conceal an initially unformatted checkout; fail on unintended tracked changes from the alias.
- [ ] A clean checkout can reproduce the documented commands; dependency caching does not replace dependency installation or database setup.
- [ ] Record local results separately from a remotely observed CI run. Do not claim remote CI passed until observed.

## Out of scope

No coverage inflation, dependency upgrades unrelated to CI, browser tooling, deployment automation, or changes to application behavior.

## Verification and handoff

Follow the dispatch guide's shared contract. Record focused checks, full required checks where code changes, the resulting revision when available, unresolved findings, and an exact next-agent handoff. Do not silently declare externally blocked acceptance passed.
