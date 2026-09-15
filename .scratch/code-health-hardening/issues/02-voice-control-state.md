# 02 — Preserve Voice controls across connection transitions

Status: ready-for-agent
Type: AFK
Priority: Core
User stories covered: 32–38

## Parent and scope

Read [the parent PRD](../PRD.md), [the dispatch guide](../PORTFOLIO_PLAN.md), the repository AGENTS.md, CONTEXT.md, and relevant accepted ADRs. This is one bounded slice of the portfolio plan. The parent PRD supplies semantics, not permission to implement its entire program.

## Blocked by

01

## What to build

Separate connection lifecycle, independently selected Local Mute, and Local Deafen in the browser controller. Derive effective mute as Local Mute OR Local Deafen, and preserve the established presentation where practical. Connection callbacks must update current state instead of rebuilding it from a captured Channel descriptor. Keep request-generation and connection-identity guards.

## Acceptance criteria

- [ ] Add a regression through the controller interface: connect, deafen, interrupt, recover; control intent, display, microphone track, playback, and published roster controls remain consistent.
- [ ] Undeafening restores the independently selected mute preference. Test both initially muted and initially unmuted cases.
- [ ] Republish current effective controls after admission and signaling recovery. Replacement peers and newly attached audio apply current controls.
- [ ] Cover joining, interruption/recovery, explicit retry, stale callbacks, takeover, ended tracks, and leave; retired attempts cannot overwrite a new attempt or leak capture.
- [ ] Define retry versus explicit leave behavior in tests: retry for the same intended channel preserves controls; explicit leave resets the session. Preserve existing ownership/admission policy.

## Out of scope

No media topology, server diagnostics, room capacity, routing, or broad UI redesign changes.

## Verification and handoff

Follow the dispatch guide's shared contract. Record focused checks, full required checks where code changes, the resulting revision when available, unresolved findings, and an exact next-agent handoff. Do not silently declare externally blocked acceptance passed.
