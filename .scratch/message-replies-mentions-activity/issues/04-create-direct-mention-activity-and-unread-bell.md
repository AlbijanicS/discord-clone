# 04 — Create Direct-Mention Activity and Show the Unread Bell

**What to build:** Recognize valid `@username` references when a Channel Message is sent, resolve current Workspace Members, create one durable Activity Item per recipient in the same transaction, and show the current User's unread Activity count on a global bell across authenticated Workspace and Channel surfaces. Keep the Activity model generic enough for future non-Workspace producers while exposing mention behavior only in this slice.

**Blocked by:** 01 — Reserve `everyone` as a Username.

**Status:** ready-for-agent

- [ ] Mention recognition supports start/end boundaries, punctuation, and case-insensitive matching without changing original Message content.
- [ ] Email-like text, unknown usernames, non-members, and the Message author's own username do not create Activity Items.
- [ ] Repeated references to the same recipient create one Activity Item for the source Message.
- [ ] Recipient identity is fixed at send time and is not retargeted by later username or membership changes.
- [ ] Each Activity Item records its recipient, optional actor, source Message, source Channel, optional Workspace, kind, read timestamp, and insertion time.
- [ ] Uniqueness prevents duplicate Activity Items for one recipient and source Message.
- [ ] Message insertion, sequencing, reply validation, direct-mention resolution, Activity insertion, and unread fan-out succeed or fail atomically.
- [ ] Runtime cache updates and broadcasts occur only after the transaction commits.
- [ ] A global authenticated bell displays the scoped User's unread Activity count even when no Workspace is selected.
- [ ] Parser, Chat transaction, authorization, and authenticated shell tests cover the behavior without asserting private query internals.
- [ ] `mix precommit` passes.
