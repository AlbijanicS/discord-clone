# 03 — Enforce route readiness and the two-user boundary

**What to build:** Make Phase 8 forwarding appear only for exactly two eligible
Voice Sessions, regardless of which person joins or finishes setup first. Keep
the existing five-Session admission capacity while honestly dropping media
outside the two-person case.

**Blocked by:** 02 — Route audio between two ready Voice Sessions.

**Status:** ready-for-agent

- [ ] Both join and offer-completion orders create the same two directional
  routes only after each Session is ready to send and receive compatible Opus.
- [ ] RTP before readiness, after an old source track ends, or from
  incompatible audio is dropped without a self-echo fallback.
- [ ] Temporary `:disconnected` and track-muted states retain routes; a
  terminal track-ended state removes only that source's outgoing route.
- [ ] Three through five active Voice Sessions have no Phase 8 Audio Routes and
  drop RTP; returning to exactly two ready Sessions restores that pair's routes.
