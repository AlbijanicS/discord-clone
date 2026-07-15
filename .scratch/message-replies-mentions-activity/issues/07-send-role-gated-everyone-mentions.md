# 07 — Send Role-Gated Everyone Mentions

**What to build:** Allow Workspace owners and admins to use `@everyone` to address the current Workspace audience while treating the same token from a regular member as ordinary Message content. Persist one Activity Item per eligible recipient at send time, using a bulk fan-out and direct-mention precedence when both mention kinds target the same User.

**Blocked by:** 04 — Create Direct-Mention Activity and Show the Unread Bell.

**Status:** ready-for-agent

- [ ] Owners and admins can create Everyone Mention Activity Items; regular members' `@everyone` text remains ordinary content without rejecting or rewriting the Message.
- [ ] The audience contains current Workspace Members at send time and excludes the Message author.
- [ ] Members who join later do not receive historical Everyone Mention Activity Items.
- [ ] Eligible recipients are inserted in bulk without application-level per-recipient insert loops or tasks.
- [ ] Repeated `@everyone` tokens create at most one Activity Item per recipient and source Message.
- [ ] A User addressed by both a direct User Mention and Everyone Mention receives one Activity Item with `user_mention` precedence.
- [ ] Message, Activity, sequencing, and unread effects remain atomic for Everyone Mentions.
- [ ] Public Chat tests cover owner, admin, regular-member, overlap, deduplication, author exclusion, fixed-audience, and rollback behavior.
- [ ] `mix precommit` passes.
