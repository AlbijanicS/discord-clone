# 06 — Create and reopen Direct Conversations lazily

**What to build:** Let a User choose Message from an accepted Friendship to atomically find or create the pair's one Direct Conversation. Empty and historical Direct Conversations remain accessible to both participants independently of the current Friend relationship row.

**Blocked by:** 01 — Introduce the shared Conversation persistence foundation; 04 — Manage the complete Friendship lifecycle.

**Status:** ready-for-agent

- [ ] A Direct Conversation is a shared-primary-key Conversation subtype containing one canonical pair of two distinct Users and no Workspace identity.
- [ ] Only an accepted Friendship permits first creation, and accepting a Friend Request alone does not create a Direct Conversation.
- [ ] Simultaneous first-open attempts converge on one Direct Conversation through the canonical pair uniqueness boundary and conflict recovery.
- [ ] Participants can find and open their Direct Conversation; non-participants receive not-found behavior that does not disclose private existence.
- [ ] Removing a Friendship preserves the Direct Conversation, and restoring the Friendship reuses the same Conversation rather than creating a parallel history.
- [ ] Direct Conversation participant foreign keys restrict hard User deletion and do not depend on the deletable Friend relationship row.
- [ ] Authenticated Direct Conversation routes live in the existing authenticated pipeline and existing authenticated LiveSession and receive `current_scope`.
- [ ] Public Chat and LiveView tests cover lazy creation, empty Conversations, participant authorization, concurrent creation, preservation, restoration reuse, and unauthenticated routing.
- [ ] The full required precommit check passes.
