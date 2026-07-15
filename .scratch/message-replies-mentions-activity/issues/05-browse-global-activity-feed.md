# 05 — Browse the Global Activity Feed

**What to build:** Give every authenticated User a private global Activity Feed that aggregates mention Activity Items across all accessible Workspaces. The initial feed presents enough current source context to triage each request without changing its read state merely because the feed was opened.

**Blocked by:** 04 — Create Direct-Mention Activity and Show the Unread Bell.

**Status:** ready-for-agent

- [ ] The Activity Feed route is inside the existing authenticated browser scope and existing `live_session :require_authenticated_user` because it exposes private per-User data and requires `current_scope`.
- [ ] The Activity LiveView begins with the application layout and receives `current_scope` through the authenticated session.
- [ ] The feed spans all Workspaces currently accessible to the scoped User and never exposes another User's Activity Items.
- [ ] Activity Items are ordered newest first with stable insertion-time and identifier ordering.
- [ ] Each item shows current Workspace and Channel names, current actor username or “Former member,” its Activity kind, and source Message preview.
- [ ] Opening the feed does not mark any Activity Item read.
- [ ] An empty state, bell link, feed container, and Activity rows have stable unique IDs.
- [ ] Queries preload or batch-load displayed associations and avoid per-item source queries.
- [ ] Public Chat and authenticated Activity LiveView tests cover authorization, ordering, labels, preview data, and unchanged read state.
- [ ] `mix precommit` passes.
