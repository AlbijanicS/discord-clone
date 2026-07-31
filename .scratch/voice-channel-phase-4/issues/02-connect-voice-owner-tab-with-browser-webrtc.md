# 02 — Connect the Voice Owner Tab through real browser WebRTC

**What to build:** A Workspace Member can use Join voice as one deliberate,
human-readable action: the Voice Owner Tab obtains microphone access first,
then negotiates its browser PeerConnection with the authorized server peer and
reaches Connected through two-way trickle ICE.

**Blocked by:** 01 — Create the real server-side Voice PeerConnection contract.

**Status:** ready-for-agent

- [ ] Pending, denied, unavailable, or cancelled microphone capture opens no
  signaling topic and starts no server PeerConnection.
- [ ] After capture succeeds, the browser uses the supplied audio track, joins
  the authenticated Voice Channel topic, sends one real offer and matching
  Negotiation ID, applies the correlated answer, and exchanges bounded
  per-candidate ICE in both directions.
- [ ] Server ICE that arrives before the answer is applied is temporarily
  buffered for only the current attempt, then applied in order or cleared on
  failure/Leave.
- [ ] Browser tests prove capture-first sequencing, signaling/PeerConnection
  behavior, candidate buffering, and the visible **Allow microphone access**,
  **Joining voice…**, **Connected**, and retryable-error stages.
