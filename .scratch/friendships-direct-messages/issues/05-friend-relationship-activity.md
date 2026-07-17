# 05 — Surface Friend relationship Activity

**What to build:** Add Friend relationship events to each User's private Activity Feed so incoming requests and accepted requests are discoverable alongside Message activity, with lifecycle cleanup and navigation that do not change the underlying Friend Request merely by viewing it.

**Blocked by:** 04 — Manage the complete Friendship lifecycle.

**Status:** ready-for-agent

- [ ] Receiving a Friend Request creates one Activity Item for the recipient, and acceptance creates one for the original requester.
- [ ] Friend relationship Activity supports its own source integrity and uniqueness without weakening existing Message-backed Activity constraints.
- [ ] Declining a request remains silent, while cancelling it removes the recipient's obsolete pending-request Activity Item.
- [ ] Viewing a Friend relationship Activity Item marks only the item read and navigates to the relevant Friends or requests view without accepting or declining anything.
- [ ] Friend relationship Activity is delivered only through private recipient topics and synchronizes unread bell counts across sessions after commit.
- [ ] Existing mention Activity semantics, cleanup rules, history, and Channel Read State independence remain unchanged.
- [ ] Public context tests cover recipients, actors, sources, privacy, uniqueness, read state, and lifecycle cleanup.
- [ ] Activity LiveView tests cover rendering, navigation, primary unread behavior, history, and multi-session synchronization using stable selectors.
- [ ] The full required precommit check passes.
