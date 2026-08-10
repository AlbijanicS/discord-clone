# 06 — Measure and Certify the Five-Session Room

**What to build:** Finish Phase 9 with the strongest evidence for the maximum
room: real five-Session ExWebRTC delivery, exhaustive routing invariants,
metadata-only diagnostics, measured resource use, and a manual browser proof
using separately authenticated Users.

**Blocked by:** 05 — Harden Multi-Session Cleanup and Failure Handling

**Status:** ready-for-agent

- [ ] A real five-Session ExWebRTC test observes each source reaching all four
      intended destination tracks and observes no self-delivery.
- [ ] Pure Forwarder tests prove the complete directed matrix, fixed slot
      assignment, slot reuse, partial readiness, late-packet drops, and
      duplicate cleanup for room sizes one through five.
- [ ] Browser tests prove four receive lanes, separate remote track identity,
      one stable aggregate playback `MediaStream`, explicit compatibility retry,
      and complete cleanup.
- [ ] A manual browser validation is completed with five separately
      authenticated Users; its detailed setup/checklist remains a separate
      testing discussion.
- [ ] Five-Session measurements record route count, forwarded and dropped RTP,
      CPU, and bandwidth without adding a stricter Phase 9 cutoff.
- [ ] Diagnostics exclude SDP, ICE credentials, raw RTP, PIDs, User identity,
      Voice Channel identity, and browser correlation data.
- [ ] Focused Voice, ExWebRTC, Forwarder, authenticated Voice Channel, and
      browser JavaScript tests pass.
- [ ] `mix precommit` passes and the Phase 9 roadmap notes are updated with the
      proven behavior, measurements, and remaining follow-up work.
