# Final Permissions And Moderation Acceptance Pass

**Type:** AFK

**Blocked by:** 1-13

**User stories covered:** 1-67

## What to build

Run a final acceptance pass across the role, permission, moderation, ban,
audit, message delete, invite, unread, and presence boundaries. This slice is
for hardening after the vertical slices land, not for introducing new product
scope.

The goal is to prove the feature is internally coherent: public context APIs own
authorization and workflows, LiveViews render capability-aware controls, runtime
state is responsive but not the source of truth, and durable state survives
reloads and process restarts.

## Acceptance criteria

- [ ] Owner/admin/member capabilities match the PRD across context APIs.
- [ ] LiveView controls match context-level authorization for all actor/target
      pairs.
- [ ] Forged events and direct route visits are rejected safely.
- [ ] Mute and timeout enforcement is consistent across send, reaction, typing,
      and future participation hooks noted by the PRD.
- [ ] Kick and ban cleanup does not leave stale read/unread or active
      moderation state.
- [ ] Invite preview and acceptance correctly handle banned, kicked, existing,
      and unbanned users.
- [ ] Deleted messages remain placeholders and cannot receive reactions.
- [ ] Audit history is owner-only and complete for moderation events.
- [ ] Connected LiveViews remain consistent after moderation broadcasts.
- [ ] Tests cover public context boundaries before LiveView behavior.
- [ ] Relevant documentation reflects any final implementation decisions.
- [ ] Focused tests pass.
- [ ] `mix precommit` passes.

## Blocked by

- 1. Add Role Capability Boundaries For Existing Workspace Actions
- 2. Add Owner-Only Role Changes With Audit Log Foundation
- 3. Render Role-Aware Member Sidebar And Member Action Menus
- 4. Add Workspace-Wide Mute And Unmute Workflow
- 5. Add Timeout Workflow With Runtime Expiry Scheduling
- 6. Add Soft Message Delete And Reaction Cleanup
- 7. Add Kick Workflow With Access-State Cleanup
- 8. Add Ban Workflow And Invite Blocking
- 9. Add Ban Message Cleanup Windows
- 10. Add Owner-Only Unban And Rejoin Semantics
- 11. Add Chat Message Moderation Context Menus
- 12. Harden Live Refresh And Access-Loss Redirects
- 13. Finalize Audit Coverage For Moderation Lifecycle
