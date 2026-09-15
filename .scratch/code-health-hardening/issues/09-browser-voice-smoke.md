# 09 — Add one deterministic two-user browser Voice smoke test

Status: ready-for-agent
Type: AFK
Priority: Optional — explicitly select before dispatch
User stories covered: Narrow subset of 68–70

## Parent and scope

Read [the parent PRD](../PRD.md), [the dispatch guide](../PORTFOLIO_PLAN.md), the repository AGENTS.md, CONTEXT.md, and relevant accepted ADRs. This is one bounded slice of the portfolio plan. The parent PRD supplies semantics, not permission to implement its entire program.

## Blocked by

01, 02

## What to build

Add isolated pinned Playwright/Chromium tooling in a separate slower CI job. Authenticate two distinct Users in separate browser contexts through existing mechanisms, provide deterministic fake audio and microphone permission, join the same Voice Channel, and verify actual two-way media movement.

## Acceptance criteria

- [ ] Outbound and inbound standardized RTP packet/byte statistics increase in both directions after admission; a connected badge alone is insufficient.
- [ ] Leave and cleanup are verified. Setup/teardown is repeatable and does not require cloud credentials or production accounts.
- [ ] The test uses bounded condition waits and useful failure artifacts, with no blind sleeps or production test backdoors.
- [ ] Document that physical playback, public NAT traversal, and TURN still require 07. Keep the fast CI job independent.

## Out of scope

No full browser transition matrix, multi-browser suite, or expanded product API. If infrastructure setup exceeds the optional budget, report remaining work rather than replacing packet assertions with weaker ones.

## Verification and handoff

Follow the dispatch guide's shared contract. Record focused checks, full required checks where code changes, the resulting revision when available, unresolved findings, and an exact next-agent handoff. Do not silently declare externally blocked acceptance passed.
