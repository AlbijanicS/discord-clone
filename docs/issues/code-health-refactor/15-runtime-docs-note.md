Status: ready-for-agent

# 15 — Runtime docs note (lazy timeout expiry)

## Parent

[Code-Health Refactor PRD](../code_health_refactor_prd.md)

## What to build

Documentation only; no code behavior change. Add a short note to the project docs
describing the timeout-expiry runtime's lazy behavior: an active future timeout is
scheduled in the workspace presence process, timers are re-scheduled when presence
starts (someone joins), and if no one is online when a timeout elapses it is expired
lazily on the next relevant action rather than exactly at its deadline — with the
database remaining the source of truth. While here, confirm and record whether the
short disconnect-grace window in the workspace presence server is intentional.

## Acceptance criteria

- [ ] The docs describe channel/timeout runtime lazy expiry and what state survives vs
      resets, consistent with the existing style-guide expectations.
- [ ] The disconnect-grace window's intent is confirmed and noted.
- [ ] No runtime/process code behavior changes.
- [ ] `mix precommit` is green.

## Blocked by

None - can start immediately.
