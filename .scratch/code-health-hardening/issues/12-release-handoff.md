# 12 — Verify the integrated portfolio release and freeze scope

Status: ready-for-human
Type: HITL
Priority: Core
User stories covered: 75; portfolio extension

## Parent and scope

Read [the parent PRD](../PRD.md), [the dispatch guide](../PORTFOLIO_PLAN.md), the repository AGENTS.md, CONTEXT.md, and relevant accepted ADRs. This is one bounded slice of the portfolio plan. The parent PRD supplies semantics, not permission to implement its entire program.

## Blocked by

01–08; any explicitly selected optional issue

## What to build

Verify the final integrated revision, not a collection of separate agent branches. Check that the hosted acceptance evidence matches it and that documentation describes its actual behavior. Produce a concise release handoff with completed work, commands/results, known limitations, demo access procedure, and remaining human actions.

## Acceptance criteria

- [ ] Run the complete precommit alias and coverage gate on the integrated code; record exact revision and results, including any environmental blockers.
- [ ] Repeat affected acceptance checks after the last code change. The final hosted record corresponds to the release actually demonstrated.
- [ ] README links and supplied artifacts work; no credentials are included; CI status is truthfully reported.
- [ ] List deferred work separately from defects that prevent a reliable demo. Unfinished work is not marked complete.
- [ ] Freeze feature/refactor scope and provide the final demo script plus explanation notes. Publishing/deploying remains an explicit operator action when not already authorized.

## Out of scope

No new features or speculative cleanup. A discovered blocker gets a bounded fix and relevant re-verification, not an expansion to the full PRD.

## Verification and handoff

Follow the dispatch guide's shared contract. Record focused checks, full required checks where code changes, the resulting revision when available, unresolved findings, and an exact next-agent handoff. Do not silently declare externally blocked acceptance passed.
