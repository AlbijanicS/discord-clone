# 02 — Generalize the Channel runtime into a Conversation runtime

**What to build:** Replace Channel-only runtime identity with a shared Conversation runtime while preserving everything Users currently experience in Workspace Channels. The runtime owns only recent-message caching and transient typing; public contexts continue to authorize every subscription and mutation before invoking it.

**Blocked by:** 01 — Introduce the shared Conversation persistence foundation.

**Status:** ready-for-agent

- [ ] One runtime process is keyed by Conversation identity and can serve either Conversation kind without knowing Friendship or Workspace policy.
- [ ] Recent-message caching, typing expiry, idle shutdown, and PostgreSQL recovery retain their existing Channel behavior.
- [ ] Conversation PubSub topics replace Channel-only runtime topics without leaking unauthorized events.
- [ ] All broadcasts happen only after the related database transaction commits.
- [ ] Public Chat workflows remain the authorization boundary; callers cannot use runtime APIs to bypass Conversation access rules.
- [ ] Runtime tests exercise observable behavior and lifecycle through public seams, using supervised processes, monitors, and synchronization barriers rather than sleeps or internal state assertions.
- [ ] Existing Workspace Channel live delivery, typing, recovery, and idle-shutdown tests remain green.
- [ ] The full required precommit check passes.
