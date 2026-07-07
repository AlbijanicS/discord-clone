# Add Role Capability Boundaries For Existing Workspace Actions

**Type:** AFK

**Blocked by:** None - can start immediately

**User stories covered:** 1, 5-12, 46-47, 66

## What to build

Replace broad membership-based management checks with fixed role capability
checks for the actions that already exist: workspace rename/delete, channel
create/rename/delete, and invite creation. The first slice should preserve the
current product surfaces while making owner, admin, and member capabilities
explicit through public context APIs.

Owners can manage workspace identity, create invites, and create, rename, and
delete channels. Admins can create invites and create or rename channels, but
cannot rename/delete the workspace or delete channels. Members can view and
participate in channels but cannot use management actions.

## Acceptance criteria

- [ ] `admin` is a valid workspace membership role.
- [ ] Existing owner memberships remain valid and existing member memberships
      remain valid.
- [ ] Workspace creation still creates an owner membership.
- [ ] Invite acceptance and rejoin paths create `member` memberships.
- [ ] Public capability helpers exist for the current workspace, channel, and
      invite actions.
- [ ] Workspace rename and delete are owner-only through the public context.
- [ ] Channel creation and rename are owner/admin only through the public
      context.
- [ ] Channel deletion is owner-only through the public context.
- [ ] Invite creation is owner/admin only through the public context.
- [ ] Management controls are hidden or disabled in LiveViews according to the
      same capabilities.
- [ ] Forged events and direct route visits are rejected by context-level
      authorization.
- [ ] Focused context and LiveView tests cover owner/admin/member boundaries.

## Blocked by

None - can start immediately
