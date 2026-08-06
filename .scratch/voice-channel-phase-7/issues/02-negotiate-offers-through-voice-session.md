# 02 — Negotiate browser offers through the Voice runtime

**What to build:** Route a validated browser SDP offer through the public Voice runtime boundary to the matching `Voice.Session`, let the Session-owned ExWebRTC PeerConnection create the answer, and return that answer through the existing correlated Phoenix Channel reply.

**Blocked by:** 01 — Admit Voice Sessions only with a ready Session-owned PeerConnection.

**Status:** ready-for-agent

- [ ] `VoiceChannel` validates the browser payload and Signaling Session ID before invoking the runtime command.
- [ ] The Channel delegates through `DiscordClone.Voice`; it does not call a Session PID, Registry entry, or supervisor directly.
- [ ] `RoomServer` verifies the supplied Voice Channel and Voice Session relationship before routing the offer.
- [ ] `Voice.Session` serializes offer handling and owns the active Negotiation ID and negotiation state.
- [ ] A valid browser offer receives the existing answer shape, including the same Signaling Session ID, Negotiation ID, and serialized SDP answer.
- [ ] Duplicate offers, stale negotiations, incompatible Opus offers, and malformed or oversized SDP retain safe existing error behavior.
- [ ] Offer processing uses a bounded synchronous runtime command and does not synchronously call back into `Voice`, `RoomServer`, or `SessionCoordinator` from the Session.
- [ ] Diagnostics remain metadata-only and do not expose SDP, ICE credentials, PIDs, socket state, Users, or Voice Channel structures.
