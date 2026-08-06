# 05 — Converge terminal peer failure and command-timeout cleanup

**What to build:** Make server-side PeerConnection failure, Channel death, Session failure, and bounded runtime-command timeouts converge on one idempotent Voice Session cleanup path while preserving the existing browser connection-lost behavior.

**Blocked by:** 03 — Route ICE and server signaling events through the owning Channel.

**Status:** ready-for-agent

- [ ] `:disconnected` remains non-terminal and leaves the Voice Session and Channel alive.
- [ ] `:failed` and `:closed` produce one typed terminal event to the owning Channel, which closes through the existing normal Channel path.
- [ ] The browser's existing `onClose` behavior continues to report `connection_lost` without requiring a new terminal wire event.
- [ ] Terminal peer failure stops the Session-owned PeerConnection and removes exactly the matching Voice Session from canonical RoomServer membership.
- [ ] Channel termination remains an idempotent lifecycle signal and is not the sole cleanup authority or direct PeerConnection owner.
- [ ] Session failure, PeerConnection failure, Channel death, explicit leave, and cleanup races do not affect a replacement Voice Session.
- [ ] Offer and ICE commands use one finite timeout budget below the browser's existing offer deadline; timeout results are safe and do not leave an ambiguous active Voice Session.
- [ ] Failed Sessions and PeerConnections are not automatically restarted into unknown WebRTC negotiation state.
- [ ] Tests use process monitoring and synthetic ExWebRTC messages to prove terminal failure, timeout, late-event, and no-orphan invariants without sleeps or production fake-peer configuration.
