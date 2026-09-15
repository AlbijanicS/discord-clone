# 05 — Handle stale authentication and malformed settings events

Status: complete (local implementation)
Type: AFK
Priority: Core
User stories covered: 29–31

## Parent and scope

Read [the parent PRD](../PRD.md), [the dispatch guide](../PORTFOLIO_PLAN.md), the repository AGENTS.md, CONTEXT.md, and relevant accepted ADRs. This is one bounded slice of the portfolio plan. The parent PRD supplies semantics, not permission to implement its entire program.

## Blocked by

01

## What to build

Replace assertion-driven failures in settings and password updates with safe current authorization checks and normalized outcomes. Cover expired sudo mode between opening a page and submitting, including the password-update controller.

## Acceptance criteria

- [x] Expired sudo mode safely requires reauthentication or returns the existing appropriate error; no password/email change or delivery occurs.
- [x] Missing nested form maps, wrong types, and malformed events do not crash settings or the controller.
- [x] Freshly authenticated valid updates retain existing behavior, including session handling.
- [x] Tests exercise user-visible outcomes through authenticated LiveViews/controller requests; privacy and existing router authentication boundaries remain intact.

## Out of scope

No new routes, authentication policy, registration, or email-provider implementation. Coordinate settings edits with 06 by landing this first.

## Verification and handoff

Follow the dispatch guide's shared contract. Record focused checks, full required checks where code changes, the resulting revision when available, unresolved findings, and an exact next-agent handoff. Do not silently declare externally blocked acceptance passed.

## Completion — 2026-09-09

Implemented and reviewed in the 05–06 batch. Final precommit passed with
99 JavaScript tests and 1,100 Elixir tests; coverage passed at 86.89% against
85%. See [the handoff](../../../docs/code-health-hardening-05-06.md) for
regressions, review resolution, revision, verification logs, and external
requirements. Real provider provisioning and hosted acceptance remain in 07.
