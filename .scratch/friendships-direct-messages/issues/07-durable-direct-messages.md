# 07 — Send durable Direct Messages end to end

**What to build:** Allow current Friends to exchange durable Direct Messages through their Direct Conversation with live delivery, Conversation-local ordering, recipient unread state, and private Activity. Persistence and all recipient effects must commit atomically before clients are notified.

**Blocked by:** 02 — Generalize the Channel runtime into a Conversation runtime; 05 — Surface Friend relationship Activity; 06 — Create and reopen Direct Conversations lazily.

**Status:** ready-for-agent

- [ ] Current Friends can send durable Direct Messages and both participants receive committed Messages live in Conversation order.
- [ ] The sender never receives unread state or a Direct Message Activity Item for their own Message; the other participant receives exactly one of each.
- [ ] Message insertion, Conversation sequence allocation, recipient Read State and Unread Span updates, and Direct Message Activity insertion occur in one transaction.
- [ ] Direct Conversations do not recognize `@everyone`, create mention Activity, apply Workspace moderation, or publish through Workspace topics.
- [ ] Every read, subscription, and mutation re-authorizes through public contexts; non-participants receive not-found behavior.
- [ ] Sending locks the accepted Friend relationship before the Conversation and recipient Read State, making send-versus-unfriend outcomes deterministic and deadlock-safe.
- [ ] Successful broadcasts occur only after commit and carry compact identifiers or change facts that clients reload through authorized workflows.
- [ ] Context tests cover durable send, sequence ordering, live delivery, unread fanout, Activity privacy and uniqueness, forged mutations, Workspace-membership insufficiency, and send-versus-unfriend concurrency.
- [ ] Existing Workspace Channel messaging and Activity behavior remains green.
- [ ] The full required precommit check passes.
