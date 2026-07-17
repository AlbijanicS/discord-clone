# 08 — Add the global Direct Messages destination and Conversation list

**What to build:** Make Direct Messages a first-class global destination above Workspace icons. Its shell brings together Friends, pending requests, and every created Direct Conversation while keeping private attention visible and ordering Conversations by recent Message activity.

**Blocked by:** 06 — Create and reopen Direct Conversations lazily; 07 — Send durable Direct Messages end to end.

**Status:** ready-for-agent

- [ ] The persistent global destination rail appears on authenticated Workspace and Direct Messages surfaces without duplicating layout ownership.
- [ ] The Direct Messages destination sits above Workspace icons, has a stable accessible identity and tooltip, and shows the aggregate Direct Message unread badge.
- [ ] The Direct Messages sidebar exposes Friends navigation, request counts, and every created Direct Conversation, including empty and former-Friend read-only entries.
- [ ] Direct Conversations sort by latest Message time, fall back to Conversation creation time when empty, and use a durable identifier as the final tie-breaker.
- [ ] New Messages and unread changes update and reposition streamed Conversation entries without a page refresh.
- [ ] Request and aggregate unread badges synchronize across authenticated sessions.
- [ ] The interface uses the established application layout, icon component, Tailwind styling, stable DOM IDs, responsive behavior, clear loading states, accessible focus treatment, and subtle transitions.
- [ ] LiveView tests cover navigation, auth boundaries, tooltips, badges, ordering, empty entries, read-only labels, stream updates, and stable selectors.
- [ ] Existing Workspace navigation and authenticated Activity shell behavior remains unchanged.
- [ ] The full required precommit check passes.
