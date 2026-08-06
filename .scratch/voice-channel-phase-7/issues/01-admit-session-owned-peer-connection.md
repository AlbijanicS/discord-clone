# 01 — Admit Voice Sessions only with a ready Session-owned PeerConnection

**What to build:** Make a successful Voice Channel join create a supervised `Voice.Session` that owns the server-side ExWebRTC PeerConnection. The browser should receive the same join result as before, but the Phoenix Channel must no longer create or own the server PeerConnection.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] An authorized Voice Channel join starts one temporary `Voice.Session` and one linked server-side ExWebRTC PeerConnection.
- [ ] Session startup completes the required ExWebRTC readiness handshake before `RoomServer` commits canonical Voice Session membership.
- [ ] A PeerConnection or Session startup failure returns a safe unavailable result, leaves no committed membership, and leaves no orphan PeerConnection process.
- [ ] The Phoenix Channel retains only its transport/session assignments and does not store or directly stop the PeerConnection wrapper.
- [ ] The Session-to-PeerConnection link makes the two processes share failure fate, while orderly cleanup uses the PeerConnection stop operation.
- [ ] Explicit leave, normal Channel termination, and repeated cleanup stop the Session-owned PeerConnection and remove exactly one Voice Session.
- [ ] Existing opaque Voice Session and Signaling Session identifiers, occupancy, capacity, one-active-Session-per-User, move, and idle-room behavior remain unchanged.
- [ ] Tests prove readiness-before-membership ordering and resource cleanup through existing Voice runtime and authenticated Channel seams without adding a production fake PeerConnection.
