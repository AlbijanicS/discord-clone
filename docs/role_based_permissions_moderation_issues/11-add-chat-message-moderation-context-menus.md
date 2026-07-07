# Add Chat Message Moderation Context Menus

**Type:** AFK

**Blocked by:** 4. Add Workspace-Wide Mute And Unmute Workflow, 5. Add Timeout Workflow With Runtime Expiry Scheduling, 6. Add Soft Message Delete And Reaction Cleanup, 7. Add Kick Workflow With Access-State Cleanup, 8. Add Ban Workflow And Invite Blocking, 9. Add Ban Message Cleanup Windows

**User stories covered:** 49, 58-60, 63

## What to build

Add chat message context menus that combine message actions and user moderation
actions. Moderators should be able to act from the message where harmful
content appears instead of switching to the member sidebar. The available
actions must match the same actor/target authorization used by member rows.

Message deletion applies immediately. Mute applies immediately. Timeout applies
after choosing a preset. Kick and ban open confirmation flows with required
reasons, and ban from a message includes cleanup choices.

## Acceptance criteria

- [ ] Message context menus expose own-message delete for authors.
- [ ] Message context menus expose moderator message delete when allowed.
- [ ] Message context menus expose mute, timeout, kick, and ban actions when
      allowed for the message author.
- [ ] Message context menus hide actions disallowed by owner immunity and
      admin/admin restrictions.
- [ ] Mute applies immediately from a message context menu.
- [ ] Timeout applies after selecting a fixed preset from a message context
      menu.
- [ ] Kick from a message context menu requires confirmation and a reason.
- [ ] Ban from a message context menu requires confirmation, a reason, and
      cleanup choice.
- [ ] Moderation action success and error feedback is visible to admins even
      though they cannot view the audit log.
- [ ] Context menu controls use stable DOM IDs for tests.
- [ ] Focused LiveView tests cover action availability and each action path.

## Blocked by

- 4. Add Workspace-Wide Mute And Unmute Workflow
- 5. Add Timeout Workflow With Runtime Expiry Scheduling
- 6. Add Soft Message Delete And Reaction Cleanup
- 7. Add Kick Workflow With Access-State Cleanup
- 8. Add Ban Workflow And Invite Blocking
- 9. Add Ban Message Cleanup Windows
