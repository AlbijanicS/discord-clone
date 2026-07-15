# 11 — Synchronize Activity Privately Across Sessions

**What to build:** Synchronize Activity bells and open Activity Feeds across a User's tabs through private per-User Chat events. Broadcast compact post-commit facts for creation, individual reads, mark-all operations, and removals; every LiveView refreshes authorized state through public Chat workflows instead of trusting records from the event payload.

**Blocked by:** 06 — Open an Activity Item at Its Exact Source Message; 09 — Paginate and Manage Activity Read State; 10 — Remove Activity When Its Source Becomes Inaccessible.

**Status:** ready-for-agent

- [ ] Private Activity topic construction, subscription, and broadcast contracts are owned by the Chat context.
- [ ] Activity creation, individual read, mark-all, and removal broadcasts happen only after their database transactions commit.
- [ ] Event payloads contain compact identifiers or change facts and never full Message, User, or Activity Item structs.
- [ ] Only the intended recipient's private topic receives Activity metadata.
- [ ] Authenticated Workspace and Channel LiveViews subscribe for `current_scope.user` and refresh the unread bell count through authorized Chat APIs.
- [ ] The Activity LiveView subscribes to the same private topic and refreshes or streams affected feed state without corrupting cursor ordering.
- [ ] Multiple sessions synchronize bell counts after creation, reads, mark-all operations, Message deletion, and membership cleanup.
- [ ] PubSub contract and multi-session LiveView tests prove privacy, compact payloads, post-commit timing, and cross-tab synchronization.
- [ ] `mix precommit` passes.
