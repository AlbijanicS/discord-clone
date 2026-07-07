# Add Workspace-Wide Mute And Unmute Workflow

**Type:** AFK

**Blocked by:** 2. Add Owner-Only Role Changes With Audit Log Foundation, 3. Render Role-Aware Member Sidebar And Member Action Menus

**User stories covered:** 14-19, 27, 29, 53-55, 63, 65

## What to build

Add durable workspace-wide mute state and public workflows to mute and unmute
allowed targets. Mute applies immediately, reasons are optional, and muted
users retain read access while participation actions are blocked. Muted admins
keep admin authority.

The user who is muted should see their own composer and participation actions
disabled with clear feedback. Other regular members should not see that user's
mute state. Owners and admins should see active moderation state where they need
it to remove the mute or choose another action.

## Acceptance criteria

- [ ] Durable active moderation storage can represent a workspace-wide mute.
- [ ] Owners can mute and unmute admins or members.
- [ ] Admins can mute and unmute admins or members, except owners.
- [ ] Mute reasons are optional.
- [ ] Muted users retain workspace and channel read access.
- [ ] Muted users cannot send messages, react, or type through public APIs.
- [ ] Muted admins retain admin capability checks.
- [ ] Muting and unmuting append audit events.
- [ ] The affected user sees disabled participation controls.
- [ ] Regular members cannot see another user's mute state.
- [ ] Connected workspace surfaces refresh after mute and unmute changes.
- [ ] Focused context and LiveView tests cover authorization, enforcement,
      visibility, and feedback.

## Blocked by

- 2. Add Owner-Only Role Changes With Audit Log Foundation
- 3. Render Role-Aware Member Sidebar And Member Action Menus
