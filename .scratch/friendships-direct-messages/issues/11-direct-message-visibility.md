# 11 — Synchronize Direct Message reads with genuine visibility

**What to build:** Mark received Direct Messages read only after genuine attention: one continuous second while the Message remains in the viewport, the document is visible, and the window is focused. The server must atomically synchronize Conversation unread state with Direct Message Activity.

**Blocked by:** 07 — Send durable Direct Messages end to end; 08 — Add the global Direct Messages destination and Conversation list.

**Status:** ready-for-agent

- [ ] A LiveView client hook observes visible received Messages and starts the one-second timer only while intersection, document visibility, and window focus all hold.
- [ ] Leaving the viewport, hiding the document, or losing focus cancels an incomplete timer without marking the Message read.
- [ ] The client groups eligible visible sequences into bounded range reports and safely tolerates reconnects and retries.
- [ ] The server re-authorizes the participant and atomically locks and updates Read State, Unread Spans, summaries, and matching Direct Message Activity Items.
- [ ] Repeated, overlapping, stale, and already-read visibility reports are idempotent.
- [ ] Read Direct Message Activity disappears from the primary unread view and badges promptly while remaining in Activity history.
- [ ] Existing mention Activity read state remains independent from Workspace Channel Read State.
- [ ] JavaScript tests cover the continuous threshold, viewport exit, background document, focus loss, and grouped reporting.
- [ ] Context and LiveView tests cover atomic synchronization, badge updates, history retention, and multi-session behavior.
- [ ] The full required precommit check passes.
