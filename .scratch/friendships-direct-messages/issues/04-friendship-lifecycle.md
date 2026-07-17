# 04 — Manage the complete Friendship lifecycle

**What to build:** Let Users resolve pending requests and manage mutual Friendships from every relevant entry point. Accepting, declining, cancelling, removing, restoring, and crossed-request acceptance must produce one coherent relationship state and update every open session privately.

**Blocked by:** 03 — Send and review exact-username Friend Requests.

**Status:** ready-for-agent

- [ ] Recipients can accept or decline incoming Friend Requests, and requesters can cancel outgoing requests.
- [ ] Acceptance creates a mutual Friendship; crossed requests automatically accept the existing relationship rather than creating another row.
- [ ] Either Friend can remove the Friendship, and a later accepted request restores the relationship without introducing a second active row.
- [ ] Friend and request lists update across the affected User's open sessions through private per-User events broadcast after commit.
- [ ] A Workspace Member action can send a Friend Request through the same Friendships workflow without retyping the known username.
- [ ] Every mutation re-authorizes the acting User and returns consistent unauthenticated, unauthorized, not-found, and stale-state outcomes.
- [ ] Concurrency tests prove pair uniqueness and crossed-request behavior without sleeps.
- [ ] LiveView tests cover accept, decline, cancel, remove, restore, crossed-request refresh, and stable streamed item identities.
- [ ] The full required precommit check passes.
