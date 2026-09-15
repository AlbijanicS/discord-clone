# 08 — Make the project understandable and easy to evaluate

Status: ready-for-human
Type: HITL
Priority: Core
User stories covered: Portfolio extension; outside the hardening PRD

## Parent and scope

Read [the parent PRD](../PRD.md), [the dispatch guide](../PORTFOLIO_PLAN.md), the repository AGENTS.md, CONTEXT.md, and relevant accepted ADRs. This is one bounded slice of the portfolio plan. The parent PRD supplies semantics, not permission to implement its entire program.

## Blocked by

None for draft; 07 for verified final claims

## What to build

Replace the README opening with a concise product explanation, representative screenshots, demo/access instructions, and a link to a short demonstration recording. Reuse the existing Voice article and architecture diagram. Move detailed operator material to an appropriate linked document without losing it. Draft a two-to-three-minute demo script and an interview explanation sheet; the human reviews personal claims and supplies or records the final demonstration.

## Acceptance criteria

- [ ] A repository visitor can identify what the app does, its main features, how to see it, its stack, and its intended five-session Voice limit from the opening material.
- [ ] Explain signaling versus media, OTP ownership, durable versus runtime state, and one concrete bug/test story without claiming Discord-scale maturity.
- [ ] Clearly state known limitations, including deferred concurrency hardening. Link deeper technical documentation and reproducible local setup.
- [ ] Use actual application screenshots and verified results. Never fabricate screenshots, deployed availability, CI badges/results, authorship claims, or media evidence.
- [ ] Include a tested controlled-access path or explicitly available recorded walkthrough; keep passwords, tokens, and private contact details out of committed artifacts.
- [ ] Provide concise practice questions around design choices, recovery, testing, and remaining limitations for the human to answer.

## Out of scope

No visual redesign, new product features, automated job applications, social posting, or public release claims before 07 verifies them.

## Verification and handoff

Follow the dispatch guide's shared contract. Record focused checks, full required checks where code changes, the resulting revision when available, unresolved findings, and an exact next-agent handoff. Do not silently declare externally blocked acceptance passed.
