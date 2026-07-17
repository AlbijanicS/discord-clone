# 12 — Show global Friend Presence

**What to build:** Show whether each current Friend is online anywhere in the authenticated application, independently of Workspace presence. Presence is private, ephemeral, edge-triggered, and owned by one supervised process per connected User across all their open LiveViews.

**Blocked by:** 04 — Manage the complete Friendship lifecycle; 06 — Create and reopen Direct Conversations lazily.

**Status:** ready-for-agent

- [ ] A dedicated Presence boundary owns one dynamically supervised, Registry-identified User presence process that monitors authenticated LiveView connections.
- [ ] A User is online while at least one monitored authenticated connection remains and becomes offline only after the final connection exits.
- [ ] Presence broadcasts only zero-to-nonzero and nonzero-to-zero transitions and stops the per-User process after the final disconnect.
- [ ] Only current Friends can query or subscribe to Friend Presence; arbitrary Users and former Friends cannot monitor it.
- [ ] Presence subscriptions and rendered status are removed or ignored immediately after the Friendship ends.
- [ ] Presence is not persisted and does not add idle, invisible, custom status, or last-seen behavior.
- [ ] Friends and Direct Conversation surfaces render accessible online/offline states and synchronize them live.
- [ ] Public API, LiveView, and targeted process tests cover authentication, authorization, initial state, multiple connections, final disconnect, edge-triggered private events, unfriend access removal, and cleanup using supervised processes and monitors.
- [ ] Existing Workspace presence behavior remains unchanged.
- [ ] The full required precommit check passes.
