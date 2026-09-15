# 04 — Handle malformed Workspace and Channel actions safely

Status: implemented-locally (2026-09-08; uncommitted)
Type: AFK
Priority: Core
User stories covered: 28–29, 31

## Parent and scope

Read [the parent PRD](../PRD.md), [the dispatch guide](../PORTFOLIO_PLAN.md), the repository AGENTS.md, CONTEXT.md, and relevant accepted ADRs. This is one bounded slice of the portfolio plan. The parent PRD supplies semantics, not permission to implement its entire program.

## Blocked by

03

## What to build

Make the existing Channel/Workspace management and member-action event paths total over malformed browser payloads. Start with missing timeout_duration, invalid timeout presets, unknown actions, malformed identifiers, and partial integer parsing where these paths use integers. Context workflows remain authoritative for policy.

## Acceptance criteria

- [x] Missing fields, wrong value types, malformed UUIDs, unknown action names, invalid presets, and forged private IDs produce a safe error or no-op without crashing the view.
- [x] Valid authorized actions still work; malformed or unauthorized actions persist no changes.
- [x] Preserve privacy-oriented not-found/unauthorized normalization and existing role permissions.
- [x] Use authenticated LiveView tests and stable DOM IDs for the actual affected handlers. Reuse existing UUID helpers and accept integers only when completely parsed.

## Out of scope

No repository-wide event rewrite, new moderation rules, timeout reconciler, or participation-locking changes. Settings belong to 05.

## Verification and handoff

Follow the dispatch guide's shared contract. Record focused checks, full required checks where code changes, the resulting revision when available, unresolved findings, and an exact next-agent handoff. Do not silently declare externally blocked acceptance passed.

## Implementation handoff

See [slices 03–04 handoff](../../../docs/code-health-hardening-03-04.md) for
changes, regression evidence, verification commands/results, and scope boundaries.
Final gates: `mix precommit` passed (99 JavaScript tests; 1,089 Elixir tests),
`mix test --cover` passed (86.70%; unchanged 85% minimum), and
`git diff --check` passed. No remote CI or deployment was performed.
