# Add Owner-Only Role Changes With Audit Log Foundation

**Type:** AFK

**Blocked by:** 1. Add Role Capability Boundaries For Existing Workspace Actions

**User stories covered:** 2-4, 61-63, 66

## What to build

Add the first role management workflow and the durable audit event foundation.
Owners should be able to promote members to admins and demote admins to
members. Admins and members must not be able to change roles.

This slice should also add append-only audit event storage and a simple
owner-only audit log screen. The audit route belongs in the existing
authenticated browser scope and existing `live_session
:require_authenticated_user`, because access depends on `current_scope`,
workspace membership, and owner authorization.

## Acceptance criteria

- [ ] Durable audit event storage records workspace, actor, target user, event
      type, reason when present, timestamp, and metadata.
- [ ] Role promotion and demotion are owner-only public workflows.
- [ ] Owners can promote a member to admin.
- [ ] Owners can demote an admin to member.
- [ ] Owners cannot demote or otherwise remove owner authority in this slice.
- [ ] Admins cannot promote, demote, or otherwise change roles.
- [ ] Role changes append audit events.
- [ ] A simple audit log screen lists newest events first.
- [ ] The audit log is visible to owners only.
- [ ] Admins and members are rejected from the audit log route.
- [ ] The route is placed in the existing authenticated browser scope and
      existing `live_session :require_authenticated_user`.
- [ ] Focused context and LiveView tests cover role changes and audit access.

## Blocked by

- 1. Add Role Capability Boundaries For Existing Workspace Actions
