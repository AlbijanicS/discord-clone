# Phase 4 voice join UX research

Status: research note  
Checked: 2026-07-30  
Scope: the browser-to-server, localhost proof only. This does not introduce a
roster, remote-audio UX, reconnection, or a future Voice Session runtime.

## Question

For the Phase 4 Join action, should the browser obtain the microphone before
joining `/voice` and constructing/negotiating a `RTCPeerConnection`, or should
it connect to signaling first?

## Recommendation

Use **capture first, then signaling and peer negotiation**. The user has not
joined the voice connection until capture succeeds *and* the browser/server
PeerConnections report `connected`.

This is a good UX for this narrow one-peer slice because it does not create a
server PeerConnection for a user who declines permission, has no usable
microphone, or leaves the browser permission prompt unanswered. `getUserMedia`
can reject for denial or no matching device, and it is allowed to remain pending
when the user ignores the prompt.[^gum] The W3C WebRTC examples likewise obtain
the local stream, attach its audio track to the peer connection, and negotiate
afterward.[^webrtc-spec]

This is a sequencing decision, not a claim that an acquired microphone equals
a connected voice call. Capture, signaling, and transport are separate states;
the UI must say so.

## Accepted project decision

Phase 4 uses this capture-first sequence as one deliberate **Join voice**
experience: **Requesting microphone…** → **Connecting…** → **Connected**.
The existing Voice Owner Tab controller remains the owner of microphone tracks;
the browser peer/signaling flow starts only after it supplies a track.

The visible copy is human-facing rather than protocol-facing: **Allow
microphone access**, **Joining voice…**, **Connected**, **Connection lost — try
again**, **Couldn’t connect — try again**, and **Not connected**. Detailed
capture, signaling, and WebRTC states remain internal diagnostics and test
seams; the UI must not display a roster or imply remote audio in this slice.

## Recommended user-visible sequence

1. The user explicitly activates **Join voice**. Immediately show **Requesting
   microphone…** and allow cancellation/Leave. This click is the clearest
   privacy affordance for a browser permission prompt. Browser documentation
   requires a secure context and user permission; `localhost` qualifies as a
   secure context for development.[^gum]
2. Ask the existing Voice Owner Tab controller for its audio track. While the
   permission promise is pending, do **not** open a `/voice` topic or create a
   server PeerConnection. If the user cancels or permission is denied, return
   to **Not connected** with an actionable microphone error and no signaling
   cleanup necessary.
3. Once an audio track exists, open/join the already authenticated and
   authorized `/voice` topic, create one browser `RTCPeerConnection`, add that
   track, and show **Connecting…**. `addTrack()` is the standard API for adding
   a local track to the set transmitted to the remote peer.[^peer-connection]
4. Create and set the local offer, send it through the existing correlated
   offer/reply contract, apply the answer, and exchange trickle ICE candidates.
   Candidate gathering begins from local-description setup and candidates are
   sent over application signaling as they arrive.[^icecandidate]
5. Show **Connected** only after the browser connection state's `connected`
   value (and log the equivalent server transition for the proof). The browser
   API distinguishes `new`, `connecting`, `connected`, `disconnected`,
   `failed`, and `closed`; it emits `connectionstatechange` when that state
   changes.[^connection-state]

For this slice, do not display a participant roster or imply that anyone else
can hear the user. A concise connected label such as **Connected to server
audio test** is honest; **In voice** is premature if it implies a room.

## Permission, gesture, and failure behavior

- `getUserMedia()` is permission-gated and may remain pending. Therefore
  **Requesting microphone…** needs a real cancel/Leave path and must not be
  represented as a stuck network connection.[^gum]
- The standards/docs used here require secure context and permission, but do
  not make a user-activation requirement the basis for this design. Retain the
  direct Join-click invocation because it is clear, privacy-preserving, and
  keeps the implementation compatible with browser-specific permission UX
  (including browsers that may impose stricter prompting behavior).
- Treat denied permission, absent device, and device/read failure as capture
  failures—not signaling failures—and keep the existing controller's distinct
  user-facing error mapping. The browser documents `NotAllowedError`,
  `NotFoundError`, and `NotReadableError` for these cases.[^gum]
- Once capture succeeded, a signaling timeout, rejected offer, or peer
  `failed`/`closed` state should close the browser PeerConnection and release
  the captured track for this first proof. This avoids leaving a microphone
  active after an unsuccessful call attempt. A later product may deliberately
  retain capture across a retry, but that is a separate policy.

## Cleanup

An explicit Leave, navigation teardown, a failed attempt after capture, or an
ended input device should close the browser PeerConnection and ask the existing
Voice Owner Tab controller to release its track. `RTCPeerConnection.close()`
closes the peer connection; `MediaStreamTrack.stop()` disassociates the track
from its source and marks it ended.[^peer-connection][^track-stop]

Browser cleanup is best effort. The authenticated Phoenix Channel termination
remains the authoritative boundary for stopping its server-side PeerConnection.

## Why not connect signaling first?

Joining signaling first is viable for a product with a room roster, server-side
admission/lobby state, or pre-warmed connection policy. Phase 4 intentionally
has none of those. In this slice it adds a server resource and extra cleanup
path while the browser may still be waiting indefinitely at the permission
prompt. Capture-first avoids treating a permission prompt as a partially joined
server voice session, while keeping future extraction straightforward: a future
Voice Session owner can be created at the same post-capture boundary or can
adopt an explicit lobby policy without changing browser capture ownership.

## Sources

[^gum]: [MDN: `MediaDevices.getUserMedia()`](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia) — secure-context requirement, permission prompt, pending promise, failure types, and `localhost` treatment.

[^webrtc-spec]: [W3C WebRTC specification](https://www.w3.org/TR/webrtc/) — its examples obtain a local stream, attach its audio track, then negotiate; SDP state transitions and `addTrack()` transceiver behavior.

[^peer-connection]: [MDN: `RTCPeerConnection`](https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection) — `addTrack()` transmits a local track and `close()` ends the peer connection.

[^icecandidate]: [MDN: `icecandidate` event](https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection/icecandidate_event) — local-description-triggered candidate gathering and application signaling of candidates.

[^connection-state]: [MDN: `RTCPeerConnection.connectionState`](https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection/connectionState) — connection state values and change event.

[^track-stop]: [MDN: `MediaStreamTrack.stop()`](https://developer.mozilla.org/en-US/docs/Web/API/MediaStreamTrack/stop) — stopping/releasing an acquired track.
