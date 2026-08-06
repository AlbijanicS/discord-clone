# 06 — Certify Phase 7 ownership and browser compatibility

**What to build:** Complete the full authenticated Phase 7 proof so the browser experiences the same join, offer, ICE, echo, and connection-loss behavior while the server-side WebRTC resource is now owned and cleaned up by `Voice.Session`.

**Blocked by:**

- 04 — Run the one-peer RTP echo inside Voice.Session.
- 05 — Converge terminal peer failure and command-timeout cleanup.

**Status:** ready-for-agent

- [ ] The complete authenticated flow passes: join, readiness, offer, answer, early ICE, server ICE, end-of-candidates, RTP echo, and leave.
- [ ] Two or more Voice Sessions in one Voice Channel receive only their own signaling events and retain independent media lifecycles.
- [ ] Capacity enforcement, one-active-Voice-Session-per-User coordination, cross-room moves, full-target rejection, failed-start semantics, and idle-room cleanup remain intact.
- [ ] Durable Workspace access cleanup and Voice Channel deletion still remove matching runtime Sessions idempotently.
- [ ] No server PeerConnection remains after leave, Channel termination, terminal peer failure, Session failure, timeout, or room shutdown.
- [ ] Browser JavaScript tests continue to pass without a new signaling transport, terminal wire event, reconnect protocol, or ICE restart.
- [ ] Real ExWebRTC, Phoenix ChannelTest, and public Voice runtime seams provide the implementation proof; no production fake PeerConnection setting is added.
- [ ] Metadata-only diagnostics continue to exclude SDP, ICE credentials, PIDs, sockets, Users, Voice Channels, and raw RTP.
- [ ] The repository's `mix precommit` verification passes after implementation.
