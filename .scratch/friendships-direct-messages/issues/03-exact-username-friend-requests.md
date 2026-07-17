# 03 — Send and review exact-username Friend Requests

**What to build:** Give authenticated Users a Friends home where they can send a Friend Request using another User's exact global username and review clearly separated incoming and outgoing requests. This is exact discovery only: the feature must not expose a global directory or fuzzy search.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] A dedicated Friendships context owns Friend Request persistence, pair canonicalization, exact-username resolution, lists, authorization, and public return contracts.
- [ ] One canonical relationship record represents the pending request for an unordered pair of distinct Users, with database constraints preventing contradictory or duplicate rows.
- [ ] Exact username matching uses canonical normalized identity and reports unknown targets without exposing unrelated Users.
- [ ] Self-targeting is rejected and Workspace membership is neither required nor used as global discovery permission.
- [ ] Repeating the same pending request is idempotent, while concurrent crossed requests resolve to one accepted relationship.
- [ ] The Friends home shows stable, streamed incoming and outgoing request lists and clear validation outcomes.
- [ ] The Friends route is placed inside the existing authenticated pipeline and existing authenticated LiveSession, receives `current_scope`, and redirects unauthenticated visitors through the established auth flow.
- [ ] Context and LiveView tests cover exact lookup, privacy boundaries, idempotency, concurrency, lists, forms, stable DOM IDs, and unauthenticated behavior.
- [ ] The full required precommit check passes.
