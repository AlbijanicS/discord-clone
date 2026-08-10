# 02 — Make Audio Routes Slot-Aware

**What to build:** Extend the existing two-Voice-Session path so each Audio
Route targets a specific destination Audio Output Slot. Two Users must hear
one another through separate destination tracks, while the Forwarder remains
the only owner of routing policy and never creates a self-route.

**Blocked by:** 01 — Negotiate Four Audio Output Slots and Aggregate Browser Playback

**Status:** ready-for-agent

- [ ] The Forwarder can create and withdraw a route whose destination includes
      a Voice Session and one of its fixed Audio Output Slots.
- [ ] Accepted RTP from the first Voice Session reaches only the other
      Voice Session's assigned outbound track.
- [ ] Accepted RTP from the second Voice Session reaches only the first
      Voice Session's assigned outbound track.
- [ ] Neither Voice Session receives its own forwarded RTP.
- [ ] The destination Session validates the exact Voice Session and slot before
      sending through its owned PeerConnection.
- [ ] Missing routes, stale identities, unavailable destinations, and late RTP
      are dropped asynchronously and update only aggregate diagnostics.
- [ ] The existing two-Voice-Session ExWebRTC proof still passes through the
      slot-aware route boundary.
