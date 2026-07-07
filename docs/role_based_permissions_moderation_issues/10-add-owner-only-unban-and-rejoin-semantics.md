# Add Owner-Only Unban And Rejoin Semantics

**Type:** AFK

**Blocked by:** 8. Add Ban Workflow And Invite Blocking

**User stories covered:** 42-45

## What to build

Add an owner-only unban workflow. Unban removes the durable ban and restores
eligibility to rejoin, but it does not recreate membership or restore the
target's previous role. If an unbanned user rejoins by invite, they join as a
regular member.

Admins should not be able to view or perform ban reversal in this slice.

## Acceptance criteria

- [ ] Owners can list or otherwise reach banned users for unban.
- [ ] Owners can unban a banned user.
- [ ] Admins cannot unban users.
- [ ] Members cannot unban users.
- [ ] Unban removes the ban record or marks it inactive according to the chosen
      durable model.
- [ ] Unban appends an audit event.
- [ ] Unban does not restore workspace membership.
- [ ] Unban does not restore previous admin status.
- [ ] An unbanned user can accept a valid invite and rejoin as a member.
- [ ] Focused context, controller, and LiveView tests cover owner-only unban,
      audit, invite eligibility, and regular-member rejoin.

## Blocked by

- 8. Add Ban Workflow And Invite Blocking
