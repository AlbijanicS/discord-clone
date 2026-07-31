# 04 — Harden and prove the Phase 4 WebRTC connection slice

**What to build:** The completed one-browser-to-one-server Voice connection is
safe under normal signaling races and has a repeatable localhost proof that it
connects and cleans up without obvious PeerConnection leaks.

**Blocked by:** 01 — Create the real server-side Voice PeerConnection contract; 02 — Connect the Voice Owner Tab through real browser WebRTC; 03 — Make the Voice PeerConnection safe to keep and safe to end.

**Status:** ready-for-agent

- [ ] A focused ExWebRTC 0.17.0 integration test establishes the exact
  end-of-candidates representation before a server terminal marker is enabled;
  no `nil`, empty, or absent-candidate form is assumed interchangeable.
- [ ] Tests prove SDP and ICE decoded-size limits, candidate and queue bounds,
  stale-queue cleanup, safe failures, topic-subscriber isolation, and
  metadata-only diagnostics.
- [ ] A localhost browser proof shows the browser and server peers reach
  connected, and three Join/Leave cycles complete without an obvious retained
  PeerConnection process.
- [ ] Focused test suites and the full project quality gate pass with Phase 4
  behavior, while deferred room, media, retry, and recovery work remains out
  of scope.
