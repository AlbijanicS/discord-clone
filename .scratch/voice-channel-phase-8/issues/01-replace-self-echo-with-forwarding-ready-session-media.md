# 01 — Replace self-echo with forwarding-ready Session media

**What to build:** Replace the one-person echo diagnostic with Session-owned
media handling that safely identifies accepted inbound audio as a forwarding
source and lets a destination Voice Session send through its own outbound
track. A person alone in a Voice Channel must no longer hear their own audio.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] An accepted inbound audio track and its RTP become typed Session media
  outcomes rather than self-echo behavior.
- [ ] The destination Session alone performs its exact Voice Session and
  outbound-track readiness check before sending through its PeerConnection.
- [ ] A lone Voice Session receives no self-forwarded RTP, while unexpected
  media retains the existing safe drop behavior and metadata-only diagnostics.
- [ ] Real ExWebRTC tests prove outbound sending through the destination track
  without a fake PeerConnection.
