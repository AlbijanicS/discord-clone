# Phase 4: First Browser-to-ExWebRTC PeerConnection PRD

Status: ready-for-agent

This PRD specifies the first real WebRTC slice for the accepted Voice Channel
roadmap. It follows ADR 0016, ADR 0017, the completed Phase 3 signaling
contract, and the Phase 4 research notes. A Voice Channel remains a durable
Workspaces resource. This phase proves one Voice Owner Tab can form one
browser-to-server PeerConnection; it does not build a multi-user Voice Session
runtime or media feature.

## Problem Statement

A Workspace Member can select a Voice Channel, grant microphone access to the
Voice Owner Tab, and join the authenticated signaling topic. The signaling
messages are still fake, however, so the application has not proven that the
browser can negotiate a real encrypted WebRTC connection with an Elixir-owned
PeerConnection.

The next safe learning step is a small, honest connection proof. It must retain
the existing Workspace authorization and Signaling Session ID protections while
handling real SDP and ICE values without leaking them to logs. It must also
make Join feel like a normal, understandable user action rather than exposing
browser/WebRTC implementation state.

## Solution

Pin `ex_webrtc` 0.17.0 and replace the Phase 3 fake offer and ICE behavior with
one browser `RTCPeerConnection` and one Channel-owned
`ExWebRTC.PeerConnection`. A deliberate Join action first obtains the
browser-owned microphone track, then opens authenticated signaling and
negotiates a single browser-offer/server-answer connection using trickle ICE.

The user sees simple stages—microphone permission, joining, connected, and
clear retryable errors—while capture, signaling, and connection state remain
separate internally. A normal authenticated navigation preserves the active
Voice Owner Tab connection. Explicit Leave, logout, socket/tab closure, a
terminal connection failure, or an ended microphone device stop the connection
and release its resources.

## User Stories

1. As a Workspace Member, I want one deliberate Join voice action, so that I understand when the app is about to request microphone access.
2. As a Workspace Member, I want to see **Allow microphone access** while the browser permission prompt is unresolved, so that I do not mistake it for a broken network connection.
3. As a Workspace Member, I want a declined permission or missing microphone to leave me not connected, so that no server voice resource is created for an attempt that cannot continue.
4. As a Workspace Member, I want to see **Joining voice…** after microphone capture succeeds, so that I know the app is connecting without being shown protocol jargon.
5. As a Workspace Member, I want to see **Connected** only after my browser PeerConnection reaches connected, so that the UI does not claim success prematurely.
6. As a Workspace Member, I want understandable **Connection lost — try again** and **Couldn’t connect — try again** errors, so that I know how to retry without learning WebRTC state names.
7. As a Workspace Member, I want my active Voice Owner Tab connection to survive ordinary authenticated navigation, so that moving through the app does not unexpectedly disconnect me.
8. As a Workspace Member, I want Leave, logout, and a closed tab to end my connection, so that microphone and server resources are not left active.
9. As a Workspace Member, I want an ended microphone device to stop the connection, so that the app does not represent an unusable call as active.
10. As a Workspace Member, I want local mute to keep controlling my browser track, so that muting does not create a second capture owner or unnecessary renegotiation.
11. As a Workspace Member, I want signaling to continue using my authenticated Voice Channel topic, so that Workspace Membership still protects Voice Channel access.
12. As a security-conscious Workspace Member, I want every real signaling message tied to the server-issued Signaling Session ID, so that an old or cross-topic connection cannot send messages into my current attempt.
13. As a Workspace Member, I want one opaque Negotiation ID per connection attempt, so that delayed ICE messages from another attempt cannot be applied to mine.
14. As a Workspace Member, I want the browser offer to receive its server answer through the correlated request reply, so that the answer belongs to the attempt that created it.
15. As a Workspace Member, I want server ICE candidates delivered only to my own signaling connection, so that another subscriber to the same Voice Channel cannot receive or affect my connection.
16. As a Workspace Member, I want normal candidate timing races handled safely, so that a valid candidate arriving slightly early does not fail the connection.
17. As a security-conscious Workspace Member, I want malformed, stale, oversized, and mismatched signaling values rejected safely, so that real SDP and ICE do not expand the control-plane attack surface.
18. As a privacy-conscious Workspace Member, I do not want SDP, ICE routes, ICE credentials, or session identifiers written to logs, so that debugging does not disclose network or security-sensitive data.
19. As a developer, I want a localhost proof that browser and server reach connected, so that the first real browser-to-Elixir WebRTC boundary is demonstrably working.
20. As a developer, I want repeated Join and Leave cycles to clean up PeerConnections, so that this small proof does not hide obvious process leaks.
21. As a future Voice implementer, I want the Channel-owned PeerConnection logic kept behind a narrow transport-independent boundary, so that Phase 7 can move it into `Voice.Session` without changing the wire contract.
22. As a future product team, I want automatic retry, recovery, rosters, and remote audio deferred explicitly, so that this proof does not accidentally become a partial room implementation.

## Implementation Decisions

- Add the exact `ex_webrtc` 0.17.0 dependency. Its version-matched official HexDocs and the repository's Phase 4 ExWebRTC research note are the API authority. Do not add the optional DataChannel dependency.
- Keep the existing authenticated `/voice` socket, `voice:<voice_channel_id>` topic grammar, Workspaces authorization, server-issued Signaling Session ID, immediate offer-reply direction, and direct same-connection server-ICE push direction from Phase 3.
- The existing authenticated LiveView routes remain in the existing `:require_authenticated_user` live session and browser pipeline. Phase 4 adds no route, schema, migration, or durable Voice ownership record.
- For this narrow phase, the admitted Phoenix Channel directly owns one linked server-side `ExWebRTC.PeerConnection`. It starts and stops that PeerConnection while a small transport-independent peer-connection boundary holds the ExWebRTC state and message handling. Do not add a RoomServer, Voice.Session process, Registry, DynamicSupervisor, or roster.
- The browser Voice Owner Tab controller remains the sole owner of microphone tracks, permission, mute, release, and best-effort same-browser takeover. The browser peer/signaling flow is separate and receives a track only after capture succeeds.
- Join is capture first, then signaling and negotiation. While microphone permission is pending, denied, unavailable, or cancelled, do not open the Voice topic or start a server PeerConnection. After capture, join the authorized topic, construct the browser PeerConnection, add the audio track, create/set the browser offer, and negotiate.
- Use one browser-generated opaque Negotiation ID per Phase 4 connection attempt. It appears on the offer, correlated answer reply, and every client/server ICE message. It is correlation only; the Signaling Session ID remains the admission binding. Permit one initial offer only and reject duplicate, stale, or mismatched negotiation attempts; do not implement perfect negotiation, renegotiation, offer collisions, or ICE restart.
- Carry browser-standard session-description JSON with `type` and `sdp` inside the signaling envelope. Validate it as an offer before converting it with ExWebRTC, set it as the server remote description, create and set the server local answer, then return the serialized answer in the correlated reply only after those operations succeed.
- The browser gives the correlated answer reply a 10-second deadline. A timeout, rejected offer, invalid answer, or answer-application failure closes the browser PeerConnection, releases the microphone track, shows a retryable failure, and requires a deliberate fresh Join. Phase 4 has no automatic retry or recovery policy; a later Voice Session/room phase must choose any bounded retry behavior explicitly.
- Exchange trickle ICE candidates individually in both directions. The browser buffers server candidates for the active Negotiation ID until it applies the answer, then adds them in arrival order. Discard stale candidates and all candidate queues on failure or Leave. Bound queues at 16 pending candidates and 64 accepted candidates per negotiation.
- Reserve an explicit `end_of_candidates: true` wire variant. Before sending a server terminal marker, add a focused ExWebRTC 0.17.0 integration test that establishes its exact server-side representation; do not assume `nil`, an empty candidate, and an absent candidate are equivalent.
- Use one centrally owned ICE-server configuration shape for browser and server. It is empty on localhost, relying on local host candidates. Do not configure public STUN/TURN services or hard-code credentials in this phase. A future STUN/TURN addition is a deliberate configuration and security decision.
- Keep technical capture, signaling, and connection states internal. The visible UI uses **Allow microphone access**, **Joining voice…**, **Connected**, **Connection lost — try again**, **Couldn’t connect — try again**, and **Not connected**. Do not show a roster, remote audio, a room-presence claim, or developer-facing “server audio test” wording.
- Keep an active connection across ordinary authenticated LiveView navigation and reattach the global Voice UI to it. Explicit Leave, logout, tab/socket closure, terminal browser connection failure, and an ended microphone device end the attempt.
- Browser cleanup is best effort: close the browser PeerConnection, release browser-owned tracks, and call Phoenix's built-in topic leave. Channel termination is the authoritative server lifetime boundary. On graceful cleanup, invoke ExWebRTC `stop/1`; `close/1` alone is insufficient because it does not terminate the PeerConnection process.
- Replace—not supplement—the Phase 3 fake validator and its temporary 4 KiB total / 256-character fake-field limits. Use explicit Phase 4 application limits: 64 KiB decoded SDP, 8 KiB decoded ICE-candidate JSON, 64 accepted candidates, and 16 pending candidates. Enforce decoded-size limits before parsing and bound both count and accumulated queued bytes. Do not change Bandit's general WebSocket limits.
- Preserve metadata-only observability in development and production. Permit only operation, outcome, stable error code, decoded payload byte count, connection-state transition, and bounded candidate/queue counters. Never log SDP, candidate values or objects, ICE credentials, Signaling Session IDs, Negotiation IDs, raw parameters, or raw socket/User/Voice Channel structures. Any Phoenix Channel telemetry must be projected to the same safe subset.

## Testing Decisions

- Good tests prove externally visible behavior, resource lifetime, and safe observability—not private assigns, callback arrangement, raw WebRTC values, or a particular eventual `Voice.Session` extraction.
- The primary server seam is authenticated Phoenix socket and Channel integration. It should use the same signed-session and Workspace fixtures as Phase 3 to join the real Voice topic, submit bounded real-description-shaped requests, receive correlated replies and direct events, and observe leave/close behavior through public Phoenix test APIs.
- Add focused tests for the transport-independent peer-connection boundary at its public behavior: creation, browser offer application, server answer result, client/server ICE handling, connection-state transitions, error mapping, and `stop/1` cleanup. Do not make a real browser necessary for those tests.
- Socket/Channel integration tests must retain Phase 3 proof that absent, invalid, expired, and revoked sessions cannot connect; non-members cannot join; browser-supplied identity cannot select the User; and stale/cross-topic/missing Signaling Session IDs fail safely.
- Protocol tests must prove a valid offer receives a matching Negotiation ID and real answer reply; duplicate or mismatched Negotiation IDs and invalid description types are rejected; no offer/answer/ICE/error traffic is broadcast to another admitted topic subscriber; and the 10-second browser reply deadline maps to a retryable local failure.
- ICE tests must prove one-candidate-at-a-time behavior, browser buffering until the answer is applied, stale-queue cleanup, count and byte bounds, safe rejection, and the verified end-of-candidates representation. They must not assert a guessed ExWebRTC terminal marker.
- Browser adapter/controller-boundary tests should cover capture-first sequencing, no signaling during a pending/failed permission request, adding the supplied track, human-facing UI stage mapping, direct server-ICE buffering, explicit Leave, terminal failure, ended-device cleanup, and authenticated navigation persistence. Reuse the existing isolated JavaScript hook-test convention.
- Observability tests must inspect emitted safe metadata and prove it excludes SDP, ICE candidates, ICE credentials, both session IDs, raw params, and socket/User/Voice Channel structures. Never print raw signaling data as test diagnostics.
- The manual localhost proof must show one browser and one server PeerConnection reach `connected`, then complete three Join/Leave cycles without an obvious retained PeerConnection process. It must also manually exercise permission denial, explicit Leave, navigation persistence, and a failure path.
- Run focused Elixir and JavaScript tests while implementing and `mix precommit` after all changes.

## Out of Scope

- Multi-user Voice Channels, a Voice RoomServer, Voice.Session runtime,
  Registry, DynamicSupervisor, roster, capacity limits, one-session-per-User
  enforcement, or authoritative cross-tab ownership.
- RTP forwarding, remote audio playback, echo, mixing, transcoding, recording,
  moderation, mute/deafen synchronization, device selection, speaking
  indicators, video, or screen sharing.
- Browser-to-browser mesh signaling, peer selection, SDP renegotiation,
  perfect negotiation, ICE restart, automatic reconnection, or recovery
  policy.
- Public STUN/TURN deployment, production network traversal policy, or storage
  and rotation of TURN credentials.
- Persistence of Signaling Session IDs, Negotiation IDs, PeerConnections,
  candidate queues, Voice membership, or browser ownership.
- Marking Phase 2's outstanding manual microphone-verification gate complete.

## Further Notes

- Phase 4 succeeds when one browser and one Channel-owned ExWebRTC
  PeerConnection reach `connected` on localhost with real offer/answer and
  trickle-ICE signaling, then cleanly stop on Leave.
- This direct ownership is a deliberate Phase 4 scaffold. The narrow
  peer-connection boundary is the extraction seam for the future supervised
  `Voice.Session`; it is not a substitute for that later runtime design.
- The dependency/API, join UX, and protocol decisions are captured in the
  accompanying Phase 4 research notes under `docs/`.
