# 01 — Establish authenticated Voice topic admission

**What to build:** A logged-in Workspace Member can open the dedicated Voice socket, join the durable Voice Channel topic they are authorized to access, receive a fresh server-issued Signaling Session ID, and leave through Phoenix's built-in topic lifecycle. The browser reuses its signed application session; it never supplies the User identity used for authorization.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] The Voice socket derives trusted `Accounts.Scope` from the existing signed session and rejects unauthenticated, invalid, expired, or revoked sessions without trusting browser-supplied identity.
- [ ] A Workspace Member can join `voice:<voice_channel_id>` and receive a fresh opaque Signaling Session ID; malformed, missing, deleted, and inaccessible Voice Channels are denied safely without enumeration details.
- [ ] The browser signaling adapter can join and leave the topic without changing Phase 2 microphone ownership or capture behavior.
- [ ] Authenticated socket and Channel integration tests prove session-derived scope, Workspaces authorization, fresh IDs, and built-in leave invalidation.
