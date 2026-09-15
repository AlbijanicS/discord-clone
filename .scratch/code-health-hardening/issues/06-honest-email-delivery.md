# 06 — Make email-change delivery truthful and production configurable

Status: superseded (removed at user request, 2026-09-11)
Type: AFK
Priority: Core
User stories covered: 61–65

## Parent and scope

Read [the parent PRD](../PRD.md), [the dispatch guide](../PORTFOLIO_PLAN.md), the repository AGENTS.md, CONTEXT.md, and relevant accepted ADRs. This is one bounded slice of the portfolio plan. The parent PRD supplies semantics, not permission to implement its entire program.

## Blocked by

05

## What to build

Implement the PRD-selected fixed Resend adapter using the existing Req-backed Swoosh client, configurable verified sender, and required production configuration. Insert the exact change token before delivery, deliver outside a transaction, and show success only when the adapter accepts. Delete that exact token on a reported delivery failure. This brief delivers code and operator instructions; actual provider provisioning is part of 07.

## Acceptance criteria

- [x] Successful adapter delivery retains a usable exact token; reported failure removes only that token and shows a generic retryable error.
- [x] Tests use the existing test adapter and a failing adapter seam; failures do not expose tokens, credentials, or unbounded provider response bodies.
- [x] Production configuration fails clearly when the required API key or sender is missing, and never silently retains Local or the placeholder sender.
- [x] Document the exact provider/sender setup required before deploying this change. Run configuration tests without requiring a real provider key.
- [x] The release handoff explicitly flags the new startup requirements so an operator does not deploy it without provisioning.

## Out of scope

No public registration, magic-link activation, arbitrary dynamic adapters, marketing delivery, or notification system. Never invent credentials or claim provider acceptance proves inbox delivery.

## Verification and handoff

Follow the dispatch guide's shared contract. Record focused checks, full required checks where code changes, the resulting revision when available, unresolved findings, and an exact next-agent handoff. Do not silently declare externally blocked acceptance passed.

## Completion — 2026-09-09

Implemented and reviewed in the 05–06 batch. Final precommit passed with
99 JavaScript tests and 1,100 Elixir tests; coverage passed at 86.89% against
85%. See [the handoff](../../../docs/code-health-hardening-05-06.md) for
regressions, review resolution, revision, verification logs, and external
requirements. Real provider provisioning and hosted acceptance remain in 07.

## Scope reversal — 2026-09-11

The user requested removal of email changes and Resend. The acceptance criteria
above are historical and are no longer release requirements. Accounts are
provisioned over SSH using the existing release command.
