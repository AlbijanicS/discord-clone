# Add Ban Message Cleanup Windows

**Type:** AFK

**Blocked by:** 6. Add Soft Message Delete And Reaction Cleanup, 8. Add Ban Workflow And Invite Blocking

**User stories covered:** 39-41, 50-52, 61, 65

## What to build

Extend the ban workflow with fixed message cleanup windows: none, last 1 hour,
last 24 hours, last 7 days, and all workspace messages. Cleanup uses the same
soft-delete behavior as message moderation, removes reactions, preserves
message placeholders, and records audit history.

The all-workspace-messages cleanup option is owner-only. Admins can use the
bounded cleanup windows when banning members.

## Acceptance criteria

- [ ] Ban confirmation includes fixed cleanup choices.
- [ ] Cleanup option `none` preserves the banned user's messages.
- [ ] Last 1 hour, 24 hours, and 7 days cleanup options soft-delete only
      matching workspace messages.
- [ ] All-workspace-messages cleanup soft-deletes all matching workspace
      messages.
- [ ] All-workspace-messages cleanup is owner-only.
- [ ] Admins cannot select or forge all-workspace-messages cleanup.
- [ ] Cleanup removes reactions from deleted messages.
- [ ] Cleanup leaves deleted message placeholders visible to viewers.
- [ ] Ban cleanup appends audit history with cleanup metadata.
- [ ] Connected channel viewers receive enough state to refresh affected
      messages.
- [ ] Focused context and LiveView tests cover cleanup windows, owner-only
      all-message cleanup, reaction cleanup, placeholders, audit, and live
      refresh.

## Blocked by

- 6. Add Soft Message Delete And Reaction Cleanup
- 8. Add Ban Workflow And Invite Blocking
