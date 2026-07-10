Status: ready-for-agent

# 05 — Latent-bug regression tests

## Parent

[Code-Health Refactor PRD](../code_health_refactor_prd.md)

## What to build

Pin down two behaviors the review flagged as latent risks, at the Workspaces context
seam, BEFORE the moderation and role refactors touch them.

1. Workspace Role change: prove that every supported Role transition produces an audit
   `event_type` that the audit-event schema's allow-list accepts, so a transition can
   never fail the whole role-change transaction on an out-of-list event type. If the
   test reveals a real gap (a reachable transition whose generated event type is not in
   the allow-list), record it — the fix is proposed separately, not smuggled in here.
2. Moderation uniqueness: prove the real behavior of muting a Workspace Member a second
   time after a previous mute has ended — either it is allowed (a new active moderation)
   or it is explicitly rejected. Assert whichever is the intended behavior so the
   uniqueness constraint's semantics are locked down.

## Acceptance criteria

- [ ] A test asserts supported Role transitions only yield allowed audit event types.
- [ ] A test asserts the second-mute-after-ended-mute outcome (allowed or rejected).
- [ ] Both tests run through the Workspaces public API, not private helpers.
- [ ] If either test surfaces a real defect, it is documented as a separate follow-up
      rather than fixed inside this issue.
- [ ] `mix precommit` is green.

## Blocked by

None - can start immediately.
