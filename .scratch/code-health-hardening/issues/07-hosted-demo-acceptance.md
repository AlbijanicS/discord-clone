# 07 — Verify the hosted two-user demonstration

Status: ready-for-human
Type: HITL
Priority: Core
User stories covered: Hosted portion of 68–70; portfolio extension

## Parent and scope

Read [the parent PRD](../PRD.md), [the dispatch guide](../PORTFOLIO_PLAN.md), the repository AGENTS.md, CONTEXT.md, and relevant accepted ADRs. This is one bounded slice of the portfolio plan. The parent PRD supplies semantics, not permission to implement its entire program.

## Blocked by

02, 03, 04, 05 (06 removed at user request)

## What to build

Prepare and execute an operator-assisted acceptance session on the integrated revision. Use existing private-alpha authentication and provisioning rather than building public registration. The human supplies authorized host access, test accounts, a second participant/network, and physical audio verification. Prepare all scripts/checklists and local checks possible before requesting those inputs.

## Acceptance criteria

- [ ] Record revision, date, browsers, ICE mode, network setup category, and observed pass/fail/blocked results without secrets or personal data.
- [ ] Verify HTTPS health/readiness, password login, Workspace entry, two-user Messages/replies/reactions/unread behavior, and representative permitted/denied moderation.
- [ ] Verify Voice join, actual two-way audio, mute/deafen, navigation while connected, brief interruption/recovery, leave/rejoin, tab takeover, and cleanup.
- [ ] Verify separate-network standard ICE and TURN-only audio, then restore standard mode and prove a fresh call works. Obtain authorization before changing a running deployment.
- [ ] Verify console-provisioned accounts can log in; self-service email changes and mail-provider setup were removed at user request on 2026-09-11.
- [ ] Document how an evaluator obtains controlled demo access and a repeatable demo dataset. Record failures as bounded follow-ups; only fix small direct blockers here.

## Out of scope

No open public signup, new demo-account platform, broad refactors, performance program, or unattended production changes. A local fake-media test cannot substitute for these observations.

## Verification and handoff

Follow the dispatch guide's shared contract. Record focused checks, full required checks where code changes, the resulting revision when available, unresolved findings, and an exact next-agent handoff. Do not silently declare externally blocked acceptance passed.
