# 03 — Make the Voice PeerConnection safe to keep and safe to end

**What to build:** A connected Voice Owner Tab remains connected through normal
authenticated navigation, gives people clear non-technical failure feedback,
and reliably ends its browser and server resources when the attempt is over
without exposing signaling values in diagnostics.

**Blocked by:** 02 — Connect the Voice Owner Tab through real browser WebRTC.

**Status:** ready-for-agent

- [ ] Ordinary authenticated navigation reattaches the global Voice UI to the
  active connection without taking over microphone ownership or disconnecting
  the Voice Owner Tab.
- [ ] Explicit Leave, logout, tab/socket closure, terminal connection failure,
  and an ended microphone device close the browser peer, release browser-owned
  capture, leave the topic, and authoritatively stop the server peer.
- [ ] The UI presents **Connection lost — try again** or **Couldn’t connect —
  try again** rather than browser/WebRTC state names, and requires a fresh Join
  with no automatic recovery policy.
- [ ] Diagnostics and telemetry contain only reviewed metadata and exclude SDP,
  ICE candidates and credentials, session identifiers, raw params, and raw
  socket/User/Voice Channel structures.
