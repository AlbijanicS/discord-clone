# Add Timeout Workflow With Runtime Expiry Scheduling

**Type:** AFK

**Blocked by:** 4. Add Workspace-Wide Mute And Unmute Workflow

**User stories covered:** 20-29, 54-55, 63, 65

## What to build

Add durable workspace-wide timeout state with fixed duration presets of 5
minutes, 1 hour, 24 hours, and 7 days. Timeouts apply immediately, block the
same participation actions as mute, and can coexist with mute. Timeout expiry
should be scheduled through the workspace runtime for responsive UI updates,
while database timestamps remain the source of truth.

Manual timeout removal should supersede scheduled expiry. Natural timeout
expiry should be audited exactly once and broadcast enough state for connected
UIs to refresh.

## Acceptance criteria

- [ ] Active moderation storage can represent timeouts with durable expiry
      timestamps.
- [ ] Only the fixed timeout duration presets are accepted.
- [ ] Owners can timeout admins or members.
- [ ] Admins can timeout admins or members, except owners.
- [ ] Timed-out users cannot send messages, react, or type through public APIs.
- [ ] Timed-out admins retain admin capability checks.
- [ ] Mute and timeout can coexist for one user.
- [ ] Timeout expiry leaves any active mute in place.
- [ ] Workspace runtime schedules newly created timeouts.
- [ ] Workspace runtime schedules existing future timeouts when it starts.
- [ ] Manual timeout removal cancels or supersedes scheduled expiry.
- [ ] Natural timeout expiry appends one audit event and broadcasts state
      changes.
- [ ] Focused context, runtime, and LiveView tests cover presets, enforcement,
      expiry, coexistence, and UI refresh.

## Blocked by

- 4. Add Workspace-Wide Mute And Unmute Workflow
