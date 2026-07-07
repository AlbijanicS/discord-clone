# Add Ban Workflow And Invite Blocking

**Type:** AFK

**Blocked by:** 2. Add Owner-Only Role Changes With Audit Log Foundation, 3. Render Role-Aware Member Sidebar And Member Action Menus

**User stories covered:** 13, 35-38, 46, 59-60, 64-65

## What to build

Add durable workspace bans for current members. Ban requires confirmation and a
required reason, removes the target's membership immediately, clears active
moderation and read/unread state, and blocks future invite preview and
acceptance. Banned users should see generic invite-unavailable copy with no
accept option.

Owners can ban admins or members. Admins can ban members only. Owners are
immune to moderation.

## Acceptance criteria

- [ ] Durable ban storage survives membership deletion.
- [ ] Ban targets current members only in this slice.
- [ ] Ban requires confirmation and a non-empty reason.
- [ ] Owners can ban admins or members.
- [ ] Admins can ban members only.
- [ ] Admins cannot ban owners or other admins.
- [ ] Banning deletes the target workspace membership.
- [ ] Banning clears active moderation state for the target in that workspace.
- [ ] Banning clears read/unread state for the target in that workspace.
- [ ] Banned users are blocked from invite preview and invite acceptance.
- [ ] Banned invite access uses generic unavailable copy and no accept option.
- [ ] Banning appends an audit event.
- [ ] Connected banned users are redirected away promptly where possible.
- [ ] Focused context, controller, and LiveView tests cover authorization,
      cleanup, invite blocking, audit, and redirects.

## Blocked by

- 2. Add Owner-Only Role Changes With Audit Log Foundation
- 3. Render Role-Aware Member Sidebar And Member Action Menus
