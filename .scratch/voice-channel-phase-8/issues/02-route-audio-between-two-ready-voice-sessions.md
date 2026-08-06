# 02 — Route audio between two ready Voice Sessions

**What to build:** Make two ready Voice Sessions in one Voice Channel hear one
another through the room-local Forwarder. Each Session reports its own media
readiness, the Forwarder owns the directed Audio Routes, and each destination
Session sends through its owned PeerConnection.

**Blocked by:** 01 — Replace self-echo with forwarding-ready Session media.

**Status:** ready-for-agent

- [ ] Two ready Voice Sessions with compatible Opus create one directional
  Audio Route in each direction using Voice Session IDs and source track IDs.
- [ ] Distinct RTP from each source reaches only the other Session's outbound
  track; neither Session receives its own RTP through the new route.
- [ ] RTP delivery is asynchronous and missing routes, unavailable processes,
  or stale delivery work are dropped without waiting, buffering, or retrying.
- [ ] The Forwarder keeps PIDs and outbound-track IDs only as private delivery
  details and does not call a PeerConnection itself.
