# 11 — Move packet diagnostics off Voice media owners

Status: ready-for-agent
Type: AFK
Priority: Optional — explicitly select before dispatch
User stories covered: 39–42; 43 is future motivation only

## Parent and scope

Read [the parent PRD](../PRD.md), [the dispatch guide](../PORTFOLIO_PLAN.md), the repository AGENTS.md, CONTEXT.md, and relevant accepted ADRs. This is one bounded slice of the portfolio plan. The parent PRD supplies semantics, not permission to implement its entire program.

## Blocked by

02; finish before final 07 run

## What to build

Keep counters in their existing owning Voice Session and Forwarder processes. Periodically hand off counter deltas to a supervised diagnostics reporter, which performs aggregate Telemetry outside RTP owners. Coalesce positive speaking activity before RoomServer while preserving the existing decay behavior. Measure a representative capped-room baseline first and record before/after evidence.

## Acceptance criteria

- [ ] Burst tests preserve expected packet delivery and drops while diagnostic event counts depend on reporting intervals rather than packet volume.
- [ ] A deliberately blocking diagnostics handler cannot block RTP forwarding. Orderly final snapshots hand off without waiting.
- [ ] Low-volume connection/ICE/track lifecycle diagnostics remain immediate; measurements are numeric and metadata categories bounded.
- [ ] Speaking activates promptly, refreshes at a bounded rate, decays after activity stops, and clears on leave without changing audio authorization.
- [ ] Do not claim a measured performance gain without evidence; preserve room/session supervision and stale-session rejection.

## Out of scope

No topology change, shared concurrent counters, media mixing, room expansion, benchmark infrastructure, or unrelated instrumentation.

## Verification and handoff

Follow the dispatch guide's shared contract. Record focused checks, full required checks where code changes, the resulting revision when available, unresolved findings, and an exact next-agent handoff. Do not silently declare externally blocked acceptance passed.
