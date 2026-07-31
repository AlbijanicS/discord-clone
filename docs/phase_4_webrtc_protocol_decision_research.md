# Phase 4 WebRTC protocol decision research

Status: research note  
Checked: 2026-07-30  
Scope: one authenticated browser-to-server `ex_webrtc` 0.17.0 connection. This does not add a RoomServer, Voice Session runtime, roster, forwarding, retry, or renegotiation implementation.

## Decision-ready protocol

Use the browser's standard session-description JSON (`{type, sdp}`) inside the application's signaling envelope. Decode it with `ExWebRTC.SessionDescription.from_json/1`; serialize the server answer with `to_json/1`; return the answer only after `set_local_description/2` succeeds. This is the exact browser-offer/server-answer flow in the official ExWebRTC 0.17.0 guide.[^ex-negotiation]

Keep the already proposed opaque, browser-generated `negotiation_id` on the offer, its answer reply, and every ICE message in that negotiation:

```text
offer         {signaling_session_id, negotiation_id, description}
offer reply   {signaling_session_id, negotiation_id, description}
ice_candidate {signaling_session_id, negotiation_id, candidate}
```

`negotiation_id` is **application-protocol correlation**, not a WebRTC-standard field and never an authorization credential. WebRTC deliberately leaves the signaling channel unspecified, while its SDP and ICE APIs have no such ID.[^w3c-signaling][^w3c-sdp] Phoenix's reply ref correlates the immediate answer, but a pushed server ICE event has no request ref; the application ID keeps every asynchronous candidate sequence tied to its offer. The server-issued Signaling Session ID continues to bind an admitted socket/topic; require both IDs to match the active connection. This also gives later renegotiation or ICE restart a stale-message rejection boundary without changing the wire shape. ExWebRTC's guide says negotiation repeats when tracks are added or removed.[^ex-negotiation]

## Accepted project decision

Phase 4 carries an opaque browser-generated **Negotiation ID** on the offer,
its correlated answer reply, and every related ICE message. It is correlation
only; the server-generated **Signaling Session ID** remains the authorization
binding for the admitted socket/topic connection.

The server returns the answer through the existing immediate Channel reply.
The browser gives that reply a 10-second deadline. A timeout, rejection, or
failure to apply the answer is terminal for the current attempt: close the
browser PeerConnection, release the microphone track, show a retryable
connection error, and require a fresh Join without automatic recovery.

Phase 4 uses bounded, per-negotiation trickle-ICE buffering: each candidate is
bound to the active Signaling Session ID and Negotiation ID; server candidates
wait until the browser applies the answer; stale candidates and all queues are
discarded on failure or Leave. The limits are 16 pending and 64 accepted
candidates per negotiation. The protocol reserves `end_of_candidates: true`,
but a focused ExWebRTC 0.17.0 test must establish the server-side terminal
marker before server terminal-candidate signaling is enabled.

Phase 4 keeps an active connection across ordinary authenticated LiveView
navigation. Explicit Leave, logout, tab/socket closure, a terminal connection
failure, or an ended microphone device end the attempt. Browser cleanup is
best effort: it closes its PeerConnection, releases its browser-owned track,
and uses Phoenix's built-in `channel.leave()`. Channel termination is the
authoritative server boundary and stops the linked ExWebRTC PeerConnection with
`stop/1`, not `close/1` alone.

Phase 4 has no automatic reconnect or ICE-restart policy. It offers a fresh,
explicit Join after a failure. A later Voice Session/room phase must make a
separate, deliberate product decision about bounded automatic retries; this
temporary slice does not establish that policy.

Browser and server use the same centrally owned ICE-server configuration
shape, empty for localhost. This phase does not configure public STUN/TURN
services or hard-code external credentials. Adding them later is a deliberate
configuration and security decision, not a browser-protocol rewrite.

Phase 4 replaces the Phase 3 fake validator and its temporary 4 KiB total /
256-character field bounds with the Phase-4-specific SDP and candidate bounds
in this note. The fake limits are not retained as an additional or hidden
constraint. Diagnostics remain metadata-only: operation, outcome, stable error
code, payload byte count, connection-state transition, and bounded
candidate/queue counts are permitted; SDP, candidates, credentials, both
session IDs, raw parameters, and raw socket/user/channel structures are not.

The proof plan includes focused automated coverage for authentication/session
binding, real-description validation, offer replies, ICE races and limits,
cleanup, and safe diagnostics; plus a localhost browser proof that both peers
reach `connected` and three join/leave cycles show no obvious PeerConnection
process leak.

## What the sources establish

### SDP and state

- A browser `RTCSessionDescriptionInit` has required `type` and string `sdp`; `offer` and `answer` are the applicable first-negotiation types.[^w3c-sdp]
- ExWebRTC 0.17.0 exposes the matching JSON conversion and requires the server to set the remote offer, create/set the local answer, then send it.[^ex-negotiation]
- Browser and server connection-state values are `new`, `connecting`, `connected`, `disconnected`, `failed`, and `closed`; the browser emits `connectionstatechange`, while ExWebRTC sends `{:ex_webrtc, pc, {:connection_state_change, state}}` to its controller.[^mdn-state][^ex-pc]

### Trickle ICE and races

- Candidate gathering is asynchronous and candidates are normally exchanged separately from SDP; ExWebRTC supplies candidates through `{:ice_candidate, candidate}` and JSON conversion APIs.[^ex-negotiation]
- Calling browser `addIceCandidate()` with no remote description rejects with `InvalidStateError`. Its candidate also has to match the remote SDP's m-line or MID and applicable ICE username fragment/generation.[^mdn-add-ice][^w3c-ice]
- An `icecandidate` event with an **empty candidate string** is the per-media/ICE-generation end-of-candidates indication and should be signaled and added like another candidate. An event whose `candidate` is **null** means all transports have completed gathering; it is legacy compatibility and need not be sent to the peer.[^w3c-ice]
- ExWebRTC's v0.17.0 guide's JavaScript sketch sends its null event, but its documented Elixir `ICECandidate` type is non-null and the guide does not document a server-side end-marker representation.[^ex-negotiation]

### Lifetime

- Browser `close()` terminates its ICE agent, active streams and ICE resources; remove application references before making a new connection.[^mdn-close]
- `ExWebRTC.PeerConnection.close/1` does not stop its OTP process; `stop/1` closes **and stops** it.[^ex-pc]

## Recommendations for Phase 4

1. Permit exactly one active offer/negotiation per Channel-owned PeerConnection. Validate `{type: "offer", sdp: binary}` before conversion; reject duplicate offers, answers/pranswers/rollbacks, a mismatched Signaling Session ID, or a new/mismatched Negotiation ID. This is a narrow first-negotiation state machine, not an implementation of perfect negotiation.
2. The browser must buffer server ICE events keyed by `negotiation_id` until `await pc.setRemoteDescription(answer)` resolves, then apply them in arrival order. The Channel must not call `add_ice_candidate/2` until its remote offer is set. Use small, bounded per-negotiation queues only as defensive race handling; reject a mismatched/stale ID and clear queues on failure/leave.
3. Define a wire-level `end_of_candidates: true` variant now, correlated by the same IDs. Do not send the browser's `event.candidate === null` as a normal candidate. Before enabling the server-to-browser terminal marker, add a focused v0.17.0 integration test establishing how ExWebRTC surfaces it; do not guess that `nil`, `%ICECandidate{candidate: ""}`, or absence are interchangeable.
4. Show **Connected** only from browser `connectionState === "connected"` and record the matching ExWebRTC server transition. Treat `failed` and `closed` as terminal for this proof. `disconnected` is observable but is not itself a portable terminal/failure signal, so Phase 4 should surface it as degraded rather than silently claiming success.
5. On explicit Leave, negotiation error, terminal browser state, or Channel termination: close the browser PC, release the browser-owned microphone track, and stop the server PC. Channel termination is authoritative; `terminate/2` is best-effort cleanup rather than the only proof of cleanup.

## Limits and safe observability

The WebRTC specification defines `sdp` and ICE `candidate` as strings; it does **not** provide portable maximum lengths. Bandit's 8,000,000-byte WebSocket guardrail and Phoenix's documented default `:max_frame_size` of infinity are transport protection, not a suitable signaling contract.[^phase3-limits]

Therefore Phase 4 needs its own explicitly tested, separately named limits; it must not inherit Phase 3's fake 4 KiB/256-character limits. Suggested starting policy for this one-audio-m-line proof is: 64 KiB decoded SDP, 8 KiB decoded candidate JSON, 64 accepted candidates and 16 pending candidates per negotiation. These numbers are **application policy**, not protocol facts; record rejections by stable code and revisit them before video, bundle changes, or multi-party sessions. Bound the decoded payload before parsing, and bound both queue count and accumulated bytes.

SDP and ICE can carry addresses, ports, ICE username fragments/passwords, and other sensitive topology/security material. Log only operation, outcome, stable error code, payload byte count, local state transition, and bounded candidate/queue counters—never raw SDP, raw candidate/object, ufrag/password, Signaling Session ID, Negotiation ID, socket, or error text that may echo an input. Project Phoenix Channel telemetry to this same safe subset.[^phase3-logging]

## Sources

[^ex-negotiation]: [ExWebRTC v0.17.0 negotiation guide](https://ex-webrtc.hexdocs.pm/negotiation.html) — official browser/server offer-answer flow, JSON conversion, separate trickle ICE, and repeated negotiation.
[^ex-pc]: [ExWebRTC.PeerConnection v0.17.0 API](https://ex-webrtc.hexdocs.pm/ExWebRTC.PeerConnection.html) — controller messages, connection states, ICE APIs, `close/1`, and `stop/1`.
[^w3c-signaling]: [W3C WebRTC, introduction](https://www.w3.org/TR/webrtc/#introduction) — signaling is provided by unspecified means.
[^w3c-sdp]: [W3C WebRTC, session-description model](https://www.w3.org/TR/webrtc/#rtcsessiondescriptioninit) — SDP description shape and types.
[^w3c-ice]: [W3C WebRTC, ICE candidate events and `addIceCandidate`](https://www.w3.org/TR/webrtc/#rtcpeerconnectioniceevent) — ICE generations and both end-of-candidates forms.
[^mdn-add-ice]: [MDN: `RTCPeerConnection.addIceCandidate()`](https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection/addIceCandidate) — remote-description prerequisite and validation failures.
[^mdn-state]: [MDN: `RTCPeerConnection.connectionState`](https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection/connectionState) — browser aggregate connection states and event.
[^mdn-close]: [MDN: `RTCPeerConnection.close()`](https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection/close) — browser resource/lifetime behavior.
[^phase3-limits]: [Phase 3 signaling payload limits research](phase_3_signaling_payload_limits_research.md) — project-confirmed Bandit/Phoenix transport facts and absence of portable string limits.
[^phase3-logging]: [Phase 3 voice-signaling logging research](phase_3_voice_signaling_logging_research.md) — project privacy boundary and Phoenix telemetry/logging implications.
