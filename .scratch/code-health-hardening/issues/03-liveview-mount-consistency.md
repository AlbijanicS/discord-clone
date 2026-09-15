# 03 — Prevent missed updates during Channel and Workspace initialization

Status: implemented-locally (2026-09-08; uncommitted)
Type: AFK
Priority: Core
User stories covered: 23–27

## Parent and scope

Read [the parent PRD](../PRD.md), [the dispatch guide](../PORTFOLIO_PLAN.md), the repository AGENTS.md, CONTEXT.md, and relevant accepted ADRs. This is one bounded slice of the portfolio plan. The parent PRD supplies semantics, not permission to implement its entire program.

## Blocked by

01

## What to build

Fix subscription/snapshot ordering in Channel and Workspace entry/home views and shared shell initialization they invoke. Authorize the destination, subscribe to discoverable parent topics, discover and subscribe to child topics, then load mutable projections. Include Messages, reactions, channel lists, membership/moderation, unread summaries, and Voice Channel Rosters in those surfaces. Preserve the existing Direct Conversation subscribe-before-message-load behavior.

## Acceptance criteria

- [x] Subscriptions happen only for connected sockets and at most once per topic per LiveView process.
- [x] Deterministic mount-race tests deliver an update after subscription but before snapshot completion; the final UI includes the authoritative result exactly once.
- [x] Exercise Message creation/deletion or reaction overlap, unread-summary overlap, and a Workspace membership or channel-list change. Include roster projection coverage.
- [x] Counts reload authoritative summaries or consume idempotent facts; duplicate delivery does not increment twice.
- [x] Navigation, unauthorized destinations, and Direct Conversation initialization remain correct. Do not solve ordering by adding sleeps or background polling.

## Out of scope

No shared timeline extraction, context reorganization, database locking redesign, or unrelated LiveView rewrite. Report newly found surfaces outside these entry paths as follow-ups.

## Verification and handoff

Follow the dispatch guide's shared contract. Record focused checks, full required checks where code changes, the resulting revision when available, unresolved findings, and an exact next-agent handoff. Do not silently declare externally blocked acceptance passed.

## Implementation handoff

See [slices 03–04 handoff](../../../docs/code-health-hardening-03-04.md) for
changes, regression evidence, verification commands/results, and scope boundaries.
Final gates: `mix precommit` passed (99 JavaScript tests; 1,089 Elixir tests),
`mix test --cover` passed (86.70%; unchanged 85% minimum), and
`git diff --check` passed. No remote CI or deployment was performed.
