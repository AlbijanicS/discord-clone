# Add Kick Workflow With Access-State Cleanup

**Type:** AFK

**Blocked by:** 2. Add Owner-Only Role Changes With Audit Log Foundation, 3. Render Role-Aware Member Sidebar And Member Action Menus

**User stories covered:** 30-34, 46, 60, 64-65

## What to build

Add a confirmed kick workflow with a required reason. Kicking removes the target
from the workspace immediately, clears active moderation state and read/unread
state, removes presence access when applicable, preserves historical messages,
and allows the kicked user to rejoin later with a valid invite.

Owners can kick admins or members. Admins can kick members only. Owners are
immune to moderation.

## Acceptance criteria

- [ ] Kick requires confirmation and a non-empty reason.
- [ ] Owners can kick admins or members.
- [ ] Admins can kick members only.
- [ ] Admins cannot kick owners or other admins.
- [ ] Kicking deletes the target workspace membership.
- [ ] Kicking clears active moderation state for the target in that workspace.
- [ ] Kicking clears read/unread state for the target in that workspace.
- [ ] Kicking preserves the target's historical messages.
- [ ] Kicked users can rejoin with a valid invite as regular members.
- [ ] Kicking appends an audit event.
- [ ] Connected kicked users are redirected away promptly where possible.
- [ ] Focused context and LiveView tests cover authorization, reason
      validation, cleanup, rejoin, audit, and redirect behavior.

## Blocked by

- 2. Add Owner-Only Role Changes With Audit Log Foundation
- 3. Render Role-Aware Member Sidebar And Member Action Menus
