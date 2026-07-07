# Render Role-Aware Member Sidebar And Member Action Menus

**Type:** AFK

**Blocked by:** 1. Add Role Capability Boundaries For Existing Workspace Actions, 2. Add Owner-Only Role Changes With Audit Log Foundation

**User stories covered:** 53, 55-58

## What to build

Make the member sidebar role-aware and prepare member-row moderation entry
points. Online users should be grouped into Owner, Admins, and Members
sections, while offline users remain in one combined Offline section. Regular
members should still see the member list, but not moderation state or
moderation controls.

Owners and admins should see only the actions they are allowed to perform for
each target. This slice can wire action availability and role management entry
points before the later moderation workflows fill in every action.

## Acceptance criteria

- [ ] Online owners, admins, and members render in separate sidebar sections.
- [ ] Offline users render in one combined Offline section.
- [ ] Regular members do not see other users' mute or timeout state.
- [ ] Owners and admins see role and moderation action entry points where they
      can act.
- [ ] Owner immunity is reflected in available member-row actions.
- [ ] Admins cannot see actions that would moderate owners.
- [ ] Admins cannot see kick or ban actions for other admins.
- [ ] Member-row controls use stable DOM IDs for LiveView tests.
- [ ] Action availability is derived from public capability helpers, not direct
      role comparisons in templates.
- [ ] Focused LiveView tests cover grouping and actor/target action
      availability.

## Blocked by

- 1. Add Role Capability Boundaries For Existing Workspace Actions
- 2. Add Owner-Only Role Changes With Audit Log Foundation
