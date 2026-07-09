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

- [x] Owner/admin/member capabilities match the PRD across context APIs.
- [x] LiveView controls match context-level authorization for all actor/target
      pairs.
- [x] Forged events and direct route visits are rejected safely.
- [x] Mute and timeout enforcement is consistent across send, reaction, typing,
      and future participation hooks noted by the PRD.
- [x] Kick and ban cleanup does not leave stale read/unread or active
      moderation state.
- [x] Invite preview and acceptance correctly handle banned, kicked, existing,
      and unbanned users.
- [x] Deleted messages remain placeholders and cannot receive reactions.
- [x] Audit history is owner-only and complete for moderation events.
- [x] Connected LiveViews remain consistent after moderation broadcasts.
- [x] Tests cover public context boundaries before LiveView behavior.
- [x] Relevant documentation reflects any final implementation decisions.
- [x] Focused tests pass.
- [x] `mix precommit` passes.

## Known findings to resolve

- **RESOLVED — role change UI is now wired.** The phantom promote/demote
  controls are connected to `Workspaces.change_member_role/4`. Fix:
  `member_action_click/1` in `member_actions_menu.ex` now returns
  `"member_action"` for `:promote_to_admin` / `:demote_to_member`, and the
  `handle_event("member_action", …)` clause in all three surfaces
  (`channel_live/show.ex`, `audit_log.ex`, `invite_new.ex`) now maps those
  actions to `change_member_role/4` with `"admin"` / `"member"` and the same
  member-list refresh the other moderation actions use. Owners can promote a
  member to admin and demote an admin to member from the sidebar and message
  menus; the change is audited (`member_role_promoted` / `member_role_demoted`)
  and the controls refresh live. Covered by promote/demote LiveView tests on all
  three surfaces in `home_test.exs`.

- **Role change is a phantom UI path (found during issue 12).** The context
  function `Workspaces.change_member_role/4` works and writes a
  `member_role_promoted` / `member_role_demoted` audit event, but the
  `promote_to_admin` / `demote_to_member` menu items are **not wired to any
  LiveView handler**: `member_action_click/1` in `member_actions_menu.ex`
  returns `nil` for those actions (buttons render with no `phx-click`), and every
  `handle_event("member_action", …)` clause only matches
  `["mute","unmute","timeout","remove_timeout"]` (`channel_live/show.ex`,
  `audit_log.ex`, `invite_new.ex`). So an owner sees promote/demote controls that
  do nothing. This is exactly the acceptance criterion "LiveView controls match
  context-level authorization for all actor/target pairs." Resolve by either
  wiring promote/demote to `change_member_role/4` (with the same broadcast +
  member-list refresh the other actions use) or removing the dead controls —
  decide with the user. Issue 13 only proves the role-change *audit row* at the
  context level; the UI wiring is deferred here.

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
