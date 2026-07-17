# 13 — Make open Direct Conversations react live to Friendship changes

**What to build:** Keep an open Direct Conversation on screen while its Friendship changes and immediately recompute what the User may do. Unfriending enters a clear read-only mode without losing history or drafts; restoring the Friendship re-enables the same Conversation in place.

**Blocked by:** 08 — Add the global Direct Messages destination and Conversation list; 09 — Support Direct Message replies, reactions, and deletion; 10 — Support bounded history, typing, and runtime recovery; 12 — Show global Friend Presence.

**Status:** ready-for-agent

- [ ] Removing the Friendship leaves the open Direct Conversation visible, preserves its Message history and unsent draft, and changes the sidebar entry to read-only without redirecting.
- [ ] Read-only mode clearly explains why interaction is disabled and offers the appropriate Send Friend Request recovery action.
- [ ] New Messages, replies, reactions, and typing stop immediately; Friend Presence is hidden; ownership cleanup controls remain available where authorized.
- [ ] In-flight typing is stopped and stale or forged mutations are rejected by current server-side authorization rather than relying on disabled controls.
- [ ] Restoring the Friendship re-enables sending, replies, reactions, typing, and Friend Presence in the same Direct Conversation without creating another history.
- [ ] Friendship events remain private, Conversation subscription remains authorized for both participants, and all capability changes synchronize across open sessions.
- [ ] Multi-session LiveView tests cover unfriend, read-only rendering, draft preservation, typing shutdown, Presence hiding, stale mutations, restoration, and same-Conversation reuse.
- [ ] End-to-end regression coverage proves Workspace Channel membership, moderation, mentions, Everyone Mentions, audit events, unread behavior, Activity cleanup, default Channels, and routing remain unchanged.
- [ ] The full required precommit check passes.
