# Harden Live Refresh And Access-Loss Redirects

**Type:** AFK

**Blocked by:** 4. Add Workspace-Wide Mute And Unmute Workflow, 5. Add Timeout Workflow With Runtime Expiry Scheduling, 6. Add Soft Message Delete And Reaction Cleanup, 7. Add Kick Workflow With Access-State Cleanup, 8. Add Ban Workflow And Invite Blocking, 9. Add Ban Message Cleanup Windows, 10. Add Owner-Only Unban And Rejoin Semantics, 11. Add Chat Message Moderation Context Menus

**User stories covered:** 23-24, 64-65

## What to build

Harden the live-update behavior after moderation. Connected affected users
should see participation controls change promptly after mute, timeout, unmute,
manual timeout removal, and timeout expiry. Kicked and banned users with open
workspace sessions should be redirected away promptly where possible. Other
workspace viewers should see member lists and deleted message placeholders
refresh without manual reloads.

Context authorization remains the security boundary. Live refresh is for user
experience and consistency.

## Acceptance criteria

- [ ] Mute and unmute refresh affected user participation controls.
- [ ] Timeout creation, manual removal, and natural expiry refresh affected user
      participation controls.
- [ ] Timeout expiry re-enables participation only when no mute remains active.
- [ ] Kicked users with open workspace LiveViews are redirected away promptly.
- [ ] Banned users with open workspace LiveViews are redirected away promptly.
- [ ] Other connected workspace viewers see member list updates after role,
      mute, timeout, kick, ban, unban, and presence-relevant changes.
- [ ] Connected channel viewers see deleted-message placeholder updates.
- [ ] Broadcast payloads do not expose private unread summaries or moderation
      details to regular members.
- [ ] Focused LiveView and runtime tests cover refresh and redirect behavior.

## Blocked by

- 4. Add Workspace-Wide Mute And Unmute Workflow
- 5. Add Timeout Workflow With Runtime Expiry Scheduling
- 6. Add Soft Message Delete And Reaction Cleanup
- 7. Add Kick Workflow With Access-State Cleanup
- 8. Add Ban Workflow And Invite Blocking
- 9. Add Ban Message Cleanup Windows
- 10. Add Owner-Only Unban And Rejoin Semantics
- 11. Add Chat Message Moderation Context Menus
