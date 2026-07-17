# 09 — Support Direct Message replies, reactions, and deletion

**What to build:** Bring established Message interactions to Direct Conversations while enforcing Direct Conversation-specific capabilities. Replies remain flat, reactions synchronize live, and author deletion produces one shared placeholder timeline for both participants.

**Blocked by:** 07 — Send durable Direct Messages end to end.

**Status:** ready-for-agent

- [ ] Current Friends can reply to an earlier, non-deleted Message in the same Direct Conversation, and replies remain flat in the normal timeline.
- [ ] Cross-Conversation, future, self, deleted, stale, and forged reply targets are rejected without disclosing private content.
- [ ] Current Friends can add and remove reactions and both open sessions receive committed reaction changes live.
- [ ] Only a Direct Message author can soft-delete that Message, and both participants see the same deleted placeholder.
- [ ] Replies to deleted Messages retain structure but show a deleted-message preview without exposing removed content.
- [ ] Former Friends may remove their own existing reactions and delete their own Direct Messages, but may not add reactions, reply, or create other content.
- [ ] No per-User Message hiding or divergent timeline state is introduced.
- [ ] Context and LiveView tests cover authorization, placeholders, live synchronization, stale controls, and regression parity for Workspace Channel interactions.
- [ ] The full required precommit check passes.
