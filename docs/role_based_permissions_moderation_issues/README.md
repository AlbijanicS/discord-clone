# Role-Based Permissions And Moderation Issues

This folder breaks `docs/role_based_permissions_moderation_prd.md` into small,
independently grabbable tracer-bullet issues. The project is using a docs-first
fallback for now, so these are not published to GitHub Issues.

The audit log route should be placed in the existing authenticated browser
scope and existing `live_session :require_authenticated_user`, because audit
access depends on `current_scope`, workspace membership, and owner
authorization. Existing workspace and channel LiveViews should stay in that
same authenticated LiveView session.

## Proposed Breakdown

1. **Add Role Capability Boundaries For Existing Workspace Actions**
   - **Type:** AFK
   - **Blocked by:** None - can start immediately
   - **User stories covered:** 1, 5-12, 46-47, 66
   - **Issue:** `01-add-role-capability-boundaries-for-existing-workspace-actions.md`
2. **Add Owner-Only Role Changes With Audit Log Foundation**
   - **Type:** AFK
   - **Blocked by:** 1. Add Role Capability Boundaries For Existing Workspace Actions
   - **User stories covered:** 2-4, 61-63, 66
   - **Issue:** `02-add-owner-only-role-changes-with-audit-log-foundation.md`
3. **Render Role-Aware Member Sidebar And Member Action Menus**
   - **Type:** AFK
   - **Blocked by:** 1. Add Role Capability Boundaries For Existing Workspace Actions, 2. Add Owner-Only Role Changes With Audit Log Foundation
   - **User stories covered:** 53, 55-58
   - **Issue:** `03-render-role-aware-member-sidebar-and-member-action-menus.md`
4. **Add Workspace-Wide Mute And Unmute Workflow**
   - **Type:** AFK
   - **Blocked by:** 2. Add Owner-Only Role Changes With Audit Log Foundation, 3. Render Role-Aware Member Sidebar And Member Action Menus
   - **User stories covered:** 14-19, 27, 29, 53-55, 63, 65
   - **Issue:** `04-add-workspace-wide-mute-and-unmute-workflow.md`
5. **Add Timeout Workflow With Runtime Expiry Scheduling**
   - **Type:** AFK
   - **Blocked by:** 4. Add Workspace-Wide Mute And Unmute Workflow
   - **User stories covered:** 20-29, 54-55, 63, 65
   - **Issue:** `05-add-timeout-workflow-with-runtime-expiry-scheduling.md`
6. **Add Soft Message Delete And Reaction Cleanup**
   - **Type:** AFK
   - **Blocked by:** 2. Add Owner-Only Role Changes With Audit Log Foundation
   - **User stories covered:** 47-52, 61, 65
   - **Issue:** `06-add-soft-message-delete-and-reaction-cleanup.md`
7. **Add Kick Workflow With Access-State Cleanup**
   - **Type:** AFK
   - **Blocked by:** 2. Add Owner-Only Role Changes With Audit Log Foundation, 3. Render Role-Aware Member Sidebar And Member Action Menus
   - **User stories covered:** 30-34, 46, 60, 64-65
   - **Issue:** `07-add-kick-workflow-with-access-state-cleanup.md`
8. **Add Ban Workflow And Invite Blocking**
   - **Type:** AFK
   - **Blocked by:** 2. Add Owner-Only Role Changes With Audit Log Foundation, 3. Render Role-Aware Member Sidebar And Member Action Menus
   - **User stories covered:** 13, 35-38, 46, 59-60, 64-65
   - **Issue:** `08-add-ban-workflow-and-invite-blocking.md`
9. **Add Ban Message Cleanup Windows**
   - **Type:** AFK
   - **Blocked by:** 6. Add Soft Message Delete And Reaction Cleanup, 8. Add Ban Workflow And Invite Blocking
   - **User stories covered:** 39-41, 50-52, 61, 65
   - **Issue:** `09-add-ban-message-cleanup-windows.md`
10. **Add Owner-Only Unban And Rejoin Semantics**
    - **Type:** AFK
    - **Blocked by:** 8. Add Ban Workflow And Invite Blocking
    - **User stories covered:** 42-45
    - **Issue:** `10-add-owner-only-unban-and-rejoin-semantics.md`
11. **Add Chat Message Moderation Context Menus**
    - **Type:** AFK
    - **Blocked by:** 4. Add Workspace-Wide Mute And Unmute Workflow, 5. Add Timeout Workflow With Runtime Expiry Scheduling, 6. Add Soft Message Delete And Reaction Cleanup, 7. Add Kick Workflow With Access-State Cleanup, 8. Add Ban Workflow And Invite Blocking, 9. Add Ban Message Cleanup Windows
    - **User stories covered:** 49, 58-60, 63
    - **Issue:** `11-add-chat-message-moderation-context-menus.md`
12. **Harden Live Refresh And Access-Loss Redirects**
    - **Type:** AFK
    - **Blocked by:** 4. Add Workspace-Wide Mute And Unmute Workflow, 5. Add Timeout Workflow With Runtime Expiry Scheduling, 6. Add Soft Message Delete And Reaction Cleanup, 7. Add Kick Workflow With Access-State Cleanup, 8. Add Ban Workflow And Invite Blocking, 9. Add Ban Message Cleanup Windows, 10. Add Owner-Only Unban And Rejoin Semantics, 11. Add Chat Message Moderation Context Menus
    - **User stories covered:** 23-24, 64-65
    - **Issue:** `12-harden-live-refresh-and-access-loss-redirects.md`
13. **Finalize Audit Coverage For Moderation Lifecycle**
    - **Type:** AFK
    - **Blocked by:** 2. Add Owner-Only Role Changes With Audit Log Foundation, 4. Add Workspace-Wide Mute And Unmute Workflow, 5. Add Timeout Workflow With Runtime Expiry Scheduling, 6. Add Soft Message Delete And Reaction Cleanup, 7. Add Kick Workflow With Access-State Cleanup, 8. Add Ban Workflow And Invite Blocking, 9. Add Ban Message Cleanup Windows, 10. Add Owner-Only Unban And Rejoin Semantics
    - **User stories covered:** 25, 61-63, 67
    - **Issue:** `13-finalize-audit-coverage-for-moderation-lifecycle.md`
14. **Final Permissions And Moderation Acceptance Pass**
    - **Type:** AFK
    - **Blocked by:** 1-13
    - **User stories covered:** 1-67
    - **Issue:** `14-final-permissions-and-moderation-acceptance-pass.md`

## Notes For Implementers

- Keep authorization behind public context APIs. LiveViews should ask
  capability questions and call public workflows; they should not compare roles
  directly or query moderation tables.
- Keep `member` as the lowest stored role name. Do not rename it to `user`.
- Mute and timeout block participation, not staff authority. Muted or timed-out
  admins still retain admin capabilities.
- Owners are immune from moderation in this slice.
- Active moderation state, bans, and audit events are durable Postgres state.
  Workspace runtime timers are only for responsive timeout expiry.
- Run focused context, runtime, and LiveView tests first, then `mix precommit`.
