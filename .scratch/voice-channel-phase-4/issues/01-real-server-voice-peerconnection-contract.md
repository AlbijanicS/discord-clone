# 01 — Create the real server-side Voice PeerConnection contract

**What to build:** A Workspace Member admitted to a durable Voice Channel can
use the existing authenticated signaling connection to negotiate one real
server-side PeerConnection. The server accepts one safely bounded browser
offer, returns its real correlated answer, and sends its own ICE candidates
only to that admitted browser connection.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] The exact supported ExWebRTC dependency is added and one admitted Voice
  Channel process owns and stops one server PeerConnection without creating a
  RoomServer, Voice.Session runtime, registry, or roster.
- [ ] A real offer requires the current Signaling Session ID and a fresh
  Negotiation ID, returns a matching real answer reply, and rejects duplicate,
  stale, cross-topic, malformed, or mismatched attempts safely.
- [ ] Server ICE is delivered as direct, per-candidate signaling to only the
  originating connection; bounded real SDP/ICE validation replaces the Phase
  3 fake validators and their temporary fake limits.
- [ ] Public authenticated socket/Channel integration and peer-boundary tests
  prove real negotiation behavior, isolation, direct ICE delivery, and server
  PeerConnection cleanup without relying on a browser.
