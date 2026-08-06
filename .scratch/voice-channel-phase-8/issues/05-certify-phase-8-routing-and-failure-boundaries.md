# 05 — Certify Phase 8 routing and failure boundaries

**What to build:** Provide the final behavioral proof that the two-user
server-routed audio path is correct, private, and bounded, including its
existing room-wide Forwarder-failure policy.

**Blocked by:** 03 — Enforce route readiness and the two-user boundary; 04 —
Withdraw routes through canonical Voice Session cleanup.

**Status:** ready-for-agent

- [ ] Real ExWebRTC observer tests prove two-way destination-track delivery,
  no self-forwarding, and both setup orders without inspecting raw RTP in
  diagnostics.
- [ ] Lifecycle coverage proves late-packet drops, track-end behavior, cleanup
  isolation, and replacement Voice Session protection.
- [ ] A Forwarder crash resets only its Voice Channel room tree; unrelated
  Voice Channels remain usable and no old route forwards after reset.
- [ ] Focused tests and `mix precommit` pass, and Phase 8 documentation records
  the final implementation evidence and remaining Phase 9 deferrals.
