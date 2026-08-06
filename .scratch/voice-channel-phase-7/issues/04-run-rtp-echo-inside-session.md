# 04 — Run the one-peer RTP echo inside Voice.Session

**What to build:** Preserve the working one-browser/one-server Opus echo while moving ExWebRTC media handling, track identity, RTP routing, and media counters into the Session that owns the server PeerConnection.

**Blocked by:** 03 — Route ICE and server signaling events through the owning Channel.

**Status:** ready-for-agent

- [ ] ExWebRTC media messages are received and handled by `Voice.Session`, not by the Phoenix Channel.
- [ ] The Session identifies and admits the expected inbound Opus audio track and provisions the existing outbound echo track.
- [ ] Expected RTP is echoed through the Session-owned PeerConnection with the existing payload and track behavior.
- [ ] Unexpected tracks, RTP, RTCP, data, and other unsupported media are dropped with the existing safe outcomes.
- [ ] Inbound, echoed, dropped-packet, and dropped-media counters are maintained by the Session and emitted as metadata-only diagnostics.
- [ ] No RTP packet, raw ExWebRTC message, or media state crosses the Phoenix Channel boundary.
- [ ] Existing deterministic wrapper tests and the authenticated Channel echo integration test prove the real ExWebRTC behavior.
- [ ] The localhost microphone and remote-playback echo proof remains valid without introducing Phase 8 forwarding.
