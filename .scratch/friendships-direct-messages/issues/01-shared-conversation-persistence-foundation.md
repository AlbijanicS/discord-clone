# 01 — Introduce the shared Conversation persistence foundation

**What to build:** Reshape the existing Channel-only persistence model so every Workspace Channel is a Conversation subtype and shared messaging data belongs to Conversation identity. Existing Channel creation, messaging, replies, reactions, unread behavior, Activity, moderation, and routing must remain observably unchanged while the foundation becomes capable of supporting Direct Conversations.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] A Conversation base owns durable identity, kind, and the last allocated Message sequence.
- [ ] Workspace Channels use the accepted shared-primary-key subtype model and retain Workspace identity, naming uniqueness, and Landing Channel behavior.
- [ ] Messages, Read States, and Unread Spans belong to Conversations and preserve their existing constraints and public Channel workflows.
- [ ] Conversation creation cannot leave a bare base row without its matching subtype.
- [ ] Message sequences remain positive, unique within a Conversation, and allocated atomically with Message insertion.
- [ ] The obsolete cursor-based Channel read model is removed without a compatibility phase, as no application data must be preserved.
- [ ] Existing Workspace Channel context and LiveView behavior remains green, including moderation, mentions, Everyone Mentions, Activity, unread state, replies, reactions, deletion, and routing.
- [ ] Database invariants cover subtype integrity, Conversation-local sequence uniqueness, and cascading lifecycle behavior.
- [ ] The full required precommit check passes.
