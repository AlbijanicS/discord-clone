# 09 — Paginate and Manage Activity Read State

**What to build:** Make a large Activity Feed efficient and manageable with stable cursor pagination, read styling, and a cutoff-safe “Mark all as read” workflow. Activity read state remains an attention inbox independent from Channel Read State and Unread Spans.

**Blocked by:** 06 — Open an Activity Item at Its Exact Source Message.

**Status:** ready-for-agent

- [ ] The initial Activity Feed contains at most 50 newest items and does not require a total count.
- [ ] Older items load incrementally through a stable insertion-time and identifier cursor without duplicates or gaps during concurrent inserts.
- [ ] The Activity LiveView uses a stream for the paginated collection and provides stable loading controls and read styling.
- [ ] “Mark all as read” captures a server-side cutoff and updates only unread Activity Items committed at or before that cutoff.
- [ ] Activity Items committed after the cutoff remain unread and visible in the bell count.
- [ ] Individual and mark-all Activity operations do not mutate Channel Read State or Unread Spans.
- [ ] Marking a Channel read does not mark Activity Items read.
- [ ] Public Chat and authenticated Activity LiveView tests cover the 50-item boundary, stable pagination, concurrent cutoff behavior, read styling, and state independence.
- [ ] `mix precommit` passes.
