# 10 — Support bounded history, typing, and runtime recovery

**What to build:** Keep Direct Conversations responsive and live as their history grows or runtime processes restart. Participants can navigate bounded Message windows, current Friends can share ephemeral typing state, and durable recent Messages recover after runtime loss.

**Blocked by:** 07 — Send durable Direct Messages end to end.

**Status:** ready-for-agent

- [ ] Initial, older, newer, and around-target Message windows are bounded and preserve Conversation-local ordering and navigation anchors.
- [ ] A participant can navigate to an authorized Direct Message without exposing Messages or Conversation existence to non-participants.
- [ ] Current Friends see live typing indicators that expire automatically and are never persisted.
- [ ] Former Friends and forged or stale clients cannot start or continue typing broadcasts.
- [ ] Stopping or idling out a Conversation runtime loses no durable Messages; reopening reloads the expected recent window from PostgreSQL.
- [ ] Runtime state is isolated by Conversation identity across Workspace Channels and Direct Conversations.
- [ ] Client and LiveView behavior handles loading, empty, boundary, recovery, and typing-expiry states with stable selectors.
- [ ] Context, LiveView, and targeted OTP tests prove bounded history, typing authorization and expiry, recovery, and idle shutdown without sleeps.
- [ ] Existing Workspace Channel pagination, scrolling, typing, and recovery behavior remains green.
- [ ] The full required precommit check passes.
