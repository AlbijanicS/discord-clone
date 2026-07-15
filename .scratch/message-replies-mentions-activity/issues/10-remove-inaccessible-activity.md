# 10 — Remove Activity When Its Source Becomes Inaccessible

**What to build:** Permanently remove Activity Items when their source Message is deleted or when their recipient loses access to the source Workspace. Cleanup must participate in existing deletion, moderation, leave, kick, and ban transactions so the Activity Feed cannot retain inaccessible content.

**Blocked by:** 07 — Send Role-Gated Everyone Mentions.

**Status:** ready-for-agent

- [ ] Soft-deleting one Message removes all of its Activity Items in the same transaction.
- [ ] Bulk message moderation removes Activity Items for every affected Message without exposing deleted content afterward.
- [ ] Leave, kick, and ban workflows permanently remove the affected User's Workspace-specific Activity Items in their existing transactions.
- [ ] Cleanup failure rolls back the surrounding mutation rather than leaving Message, membership, or Activity state inconsistent.
- [ ] Rejoining a Workspace does not restore previously removed Activity Items.
- [ ] Other recipients retain Activity Items they are still authorized to access.
- [ ] Public Chat and Workspaces tests cover direct deletion, bulk moderation, leave, kick, ban, rollback, and rejoin behavior.
- [ ] `mix precommit` passes.
