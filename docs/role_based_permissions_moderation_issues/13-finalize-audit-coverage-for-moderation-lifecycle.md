# Finalize Audit Coverage For Moderation Lifecycle

**Type:** AFK

**Blocked by:** 2. Add Owner-Only Role Changes With Audit Log Foundation, 4. Add Workspace-Wide Mute And Unmute Workflow, 5. Add Timeout Workflow With Runtime Expiry Scheduling, 6. Add Soft Message Delete And Reaction Cleanup, 7. Add Kick Workflow With Access-State Cleanup, 8. Add Ban Workflow And Invite Blocking, 9. Add Ban Message Cleanup Windows, 10. Add Owner-Only Unban And Rejoin Semantics

**User stories covered:** 25, 61-63, 67

## What to build

Audit the full moderation lifecycle and fill any gaps left by earlier slices.
The owner-only audit log should show meaningful rows for role changes,
mute/unmute, timeout/create, manual timeout removal, natural timeout expiry,
kick, ban, unban, moderator message delete, and ban cleanup deletes.

Moderation actions should not create channel system messages. Admins should get
immediate success or error feedback for their own actions, but they should not
be able to view audit history.

## Acceptance criteria

- [ ] Role changes appear in the audit log.
- [ ] Mute and unmute events appear in the audit log.
- [ ] Timeout creation, manual timeout removal, and natural timeout expiry
      appear in the audit log.
- [ ] Kick, ban, and unban events appear in the audit log.
- [ ] Moderator message deletes appear in the audit log.
- [ ] Own-message deletes do not appear as moderation audit events.
- [ ] Ban cleanup deletes preserve cleanup-window metadata in audit history.
- [ ] Audit rows show event type, actor, target, reason when present,
      timestamp, and relevant message/channel context.
- [ ] Moderation actions do not create channel system messages.
- [ ] Admins receive success or error feedback after moderation actions.
- [ ] Admins and members cannot view audit history.
- [ ] Focused context and LiveView tests cover audit completeness and access.

## Blocked by

- 2. Add Owner-Only Role Changes With Audit Log Foundation
- 4. Add Workspace-Wide Mute And Unmute Workflow
- 5. Add Timeout Workflow With Runtime Expiry Scheduling
- 6. Add Soft Message Delete And Reaction Cleanup
- 7. Add Kick Workflow With Access-State Cleanup
- 8. Add Ban Workflow And Invite Blocking
- 9. Add Ban Message Cleanup Windows
- 10. Add Owner-Only Unban And Rejoin Semantics
