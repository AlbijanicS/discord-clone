# Phase 8: Two-User Server-Routed Audio PRD

Status: ready-for-agent

This specification synthesizes the Phase 8 `grill-with-docs` decisions for the
server-routed audio milestone. It uses the canonical Voice Channel and Voice
Session vocabulary in `CONTEXT.md` and follows ADRs 0018 and 0019. Primary
source findings are retained in the local Phase 8 ExWebRTC routing and
Forwarder-recovery research notes.

## Problem Statement

The application has one supervised server-side PeerConnection per Voice
Session and a proven one-browser echo diagnostic. It does not yet let two
Workspace Members in the same Voice Channel hear each other. The echo path
sends a person's RTP back to their own browser, which is useful for diagnosis
but is the wrong behavior for a shared Voice Channel.

Phase 8 must establish a safe, explicit two-person audio path without moving
PeerConnection ownership into Phoenix Channels or room-global mutable state.
It must handle either join and negotiation order, leave and failure cleanup,
late RTP, and reconnection while preserving the existing authenticated
signaling contract, five-Session capacity, and one-Voice-Session-per-User
rules.

## Solution

Replace self-echo with room-local forwarding between exactly two ready Voice
Sessions. Each Session continues to own its linked PeerConnection. It reports
when it can receive, when its accepted inbound audio track can send, and sends
accepted inbound RTP asynchronously to the room-local Forwarder. The
Forwarder owns the directed Audio Route graph and asks the destination Session
to send the packet through its own outbound track.

An Audio Route uses `{source_voice_session_id, inbound_track_id}` as its
source identity and `destination_voice_session_id` as its destination identity.
PIDs and outbound-track IDs remain private delivery details. RTP is forwarded
only when exactly two Voice Sessions are active, both are ready, and both
negotiated compatible Opus. Missing, stale, queued-after-removal, or otherwise
ineligible packets are dropped without waiting, retrying, or buffering.

## User Stories

1. As a Workspace Member, I want my Voice Session's microphone audio to reach the other ready Voice Session, so that a two-person Voice Channel works as a conversation rather than an echo test.
2. As a Workspace Member, I want to hear the other person's audio through my server-provided remote track, so that I do not hear my own RTP through the new forwarding path.
3. As a Workspace Member, I want the first person in a Voice Channel to hear nothing while alone, so that the old self-echo diagnostic cannot masquerade as shared audio.
4. As a Workspace Member, I want audio to begin once both people have completed the required setup, so that either join and offer order works.
5. As a Workspace Member, I want my Voice Session to be able to receive once its offer is accepted and outbound audio track exists, so that the server has a valid destination before routing audio to me.
6. As a Workspace Member, I want my Voice Session to become an audio source only after the server accepts my inbound track, so that unexpected tracks cannot enter the room's audio path.
7. As a Workspace Member, I want audio packets sent before both people are ready to be dropped, so that no stale audio is delayed into a later connection state.
8. As a Workspace Member, I want a third active Voice Session to disable Phase 8 forwarding rather than select a preferred pair, so that the two-user boundary remains honest.
9. As a Workspace Member, I want the remaining two ready Sessions to resume their pairwise routes when a three-person room returns to exactly two Sessions, so that no manual route repair is needed.
10. As a Workspace Member, I want leave to stop all audio to and from my Voice Session immediately, so that I cannot receive queued audio after I leave.
11. As a Workspace Member, I want a browser Channel death, terminal peer state, command timeout, access removal, or Voice Channel deletion to remove my routes through the same cleanup authority, so that no ghost audio route survives lifecycle cleanup.
12. As a Workspace Member, I want a failed Voice Session to remove only its own audio routes, so that the healthy person's Session and PeerConnection remain usable.
13. As a Workspace Member, I want a temporary disconnected state not to end my Voice Session, so that existing non-terminal reconnection behavior is preserved.
14. As a Workspace Member, I accept that packets during a disconnected interval can be dropped, so that Phase 8 does not invent a buffering or retry protocol.
15. As a Workspace Member, I want an ended microphone track to stop only that Session's outgoing audio, so that old-track RTP cannot resume unexpectedly.
16. As a Workspace Member, I want a temporarily muted track not to destroy the route, so that temporary silence is not treated as a terminal media change.
17. As a Workspace Member, I want incompatible audio setup to fail safely without conversion, so that the server never claims to support unproven transcoding or mixing.
18. As a security-conscious Workspace Member, I want Voice Session IDs rather than PIDs or PeerConnection handles to identify routes, so that runtime implementation details remain private.
19. As a security-conscious Workspace Member, I want SDP, ICE, raw RTP, credentials, PIDs, Users, and Voice Channels excluded from diagnostics, so that forwarding does not weaken existing privacy rules.
20. As an implementer, I want the Forwarder to be the only owner of routing policy, so that Sessions do not maintain competing destination maps.
21. As an implementer, I want the destination Session to make the final identity and readiness check before calling its PeerConnection, so that stale forwarding work cannot target a replacement or stopped Session.
22. As an implementer, I want RTP delivery to be asynchronous, so that high-frequency media does not consume the five-second browser-command budget or block Session command handling.
23. As an implementer, I want a Forwarder crash to reset only that Voice Channel's room tree, so that route state and canonical runtime membership are discarded together while unrelated Voice Channels continue.
24. As an implementer, I want real ExWebRTC evidence of the destination sender and track, so that the phase is proven against the actual media API rather than a fake peer implementation.
25. As an implementer, I want test coverage for both directions and both setup orders, so that the routing graph is not accidentally asymmetric.
26. As an implementer, I want late packets, self-forwarding attempts, and post-cleanup packets to be observable as drops, so that safety is proved at the behavior boundary.

## Implementation Decisions

- Retire the Phase 7 self-echo behavior. An accepted inbound packet is a source-side media event; it is never sent directly back through that Session's own outbound track.
- Keep `Voice.Session` as the sole owner of one linked ExWebRTC PeerConnection. The Forwarder never calls a PeerConnection directly, and Phoenix Channels remain authenticated signaling adapters only.
- Make the room-local Forwarder the sole owner of the active Audio Route graph. The media path is source Session, Forwarder, destination Session, then destination PeerConnection.
- Identify sources using `{voice_session_id, inbound_track_id}`. Target a route by destination Voice Session ID. PIDs and outbound-track IDs are private, replaceable delivery metadata and must not be exposed as route identity or browser data.
- Each Session sends direct typed readiness messages to the Forwarder: receive-ready after successful offer acceptance and outbound-track provisioning; send-ready after its expected inbound track event. It sends only accepted inbound RTP to the Forwarder.
- Create a route only when exactly two canonical Voice Sessions are active, both have complementary send and receive readiness, and both negotiated compatible Opus. Build and withdraw routes incrementally and idempotently from readiness and cleanup events.
- Keep one server outbound audio track per destination Session. This is sufficient for the exactly-two-Session topology; destination-per-source tracks and general fan-out topology are deferred.
- Require compatible negotiated Opus for routing. ExWebRTC owns destination payload type, SSRC, and RTP header extensions when sending. The application passes the received packet through without decoding, mixing, transcoding, or manually rewriting sequence numbers or timestamps; it does not promise byte-identical RTP.
- Deliver RTP asynchronously from source to Forwarder and Forwarder to destination. Missing routes, unavailable processes, destination readiness loss, stale identities, or packets received during the crash/cleanup gap are dropped with metadata-only diagnostics. Do not buffer, retry, or wait for RTP delivery.
- The destination Session validates its exact Voice Session ID and current outbound-track readiness immediately before using its owned PeerConnection to send. An old source, stale route entry, or replacement Session must not receive delivery.
- RoomServer remains canonical cleanup authority. On ordinary removal it withdraws all routes involving the Voice Session before stopping that Session. On an unexpected Session crash it withdraws those routes when its monitor reports the crash. Cleanup remains idempotent and exact-Voice-Session scoped.
- Keep `:disconnected` non-terminal and retain routes through it; packets that cannot be delivered are dropped. Remove routes on leave, canonical membership removal, `:failed`, `:closed`, and accepted inbound-track ended. Track-muted retains the route. Track replacement and renegotiation are not Phase 8 behavior.
- Preserve the existing five-Voice-Session admission limit. Phase 8 forwards only with exactly two active Sessions. With three through five Sessions, withdraw all routes and drop RTP; once the room again has exactly two ready Sessions, establish their two directional routes without pair preference.
- Retain the room's `:one_for_all` supervision policy. A Forwarder crash resets that Voice Channel's RoomServer, SessionSupervisor, Sessions, and PeerConnections; clients must rejoin and negotiate. Do not implement Forwarder-only recovery without a separately designed snapshot, readiness, epoch, and coordinator protocol.
- Preserve the browser signaling transport, Signaling Session ID and Negotiation ID behavior, finite five-second runtime command budget, readiness barrier, capacity semantics, cross-room one-Session-per-User coordination, direct private ICE/state events, and metadata-only diagnostics.
- Make no durable schema changes and expose no new browser media, route, PID, or PeerConnection API.

## Testing Decisions

- Good tests prove observed routing, isolation, and cleanup outcomes rather than private map shape, Registry keys, or helper-call order.
- Keep real ExWebRTC integration as the primary media seam. Reuse the existing test-only RTP observer on the real PeerConnection: inject a distinct packet into a source Session and assert the actual destination PeerConnection and outbound track sent it, while the source PeerConnection did not.
- Reuse authenticated Phoenix Channel tests for unchanged signaling authorization and correlation. Phase 8 does not add a browser transport or terminal wire contract.
- Reuse public Voice/RoomServer lifecycle tests for admission, exact Voice Session cleanup, Session crash isolation, capacity, replacement-session protection, and Forwarder room reset. Use `start_supervised!/1`, monitors, and `:sys.get_state/1`; do not use sleeps.
- Reuse synthetic `{:ex_webrtc, ...}` messages for deterministic track-ready, track-muted, track-ended, RTP, disconnected, failed, closed, and late-event transitions.
- Prove both join/offer completion orders create exactly the same two directional routes once both Sessions are ready.
- Prove A-to-B and B-to-A forwarding uses the intended destination outbound track, and that neither A-to-A nor B-to-B forwarding occurs.
- Prove no forwarding occurs while alone, before readiness, with incompatible Opus, with three or more active Sessions, or after source-track end.
- Prove normal leave withdraws routes before Session termination; peer failure, Channel death, timeout, access removal, Voice Channel deletion, and Session crash leave no route that can deliver a later packet.
- Prove failure of one Session does not corrupt the healthy Session, while a Forwarder crash resets only the affected Voice Channel and prevents old-route forwarding after the reset.
- Run focused Voice and PeerConnection tests during implementation, then run `mix precommit` after all phase changes.

## Out of Scope

- Three-to-five-user fan-out, pair selection, speaker matrices, destination-per-source tracks, or any Phase 9 topology.
- Audio mixing, decoding, transcoding, recording, transcription, video, screen sharing, data channels, or custom RTP processing.
- Track replacement, renegotiation, ICE restart, perfect negotiation, automatic browser reconnect, disconnected-state expiry, or a Forwarder-only recovery protocol.
- Voice Channel roster and UI work, speaking indicators, mute/deafen synchronization, moderation controls, or new browser-facing media/route events.
- New signaling transports, PubSub-based private signaling or media, changes to the existing finite browser command budget, durable Voice Session persistence, schema changes, or authorization-policy changes.
- Raw media/signaling diagnostics, debug endpoints exposing runtime topology, or browser exposure of PIDs, PeerConnection handles, route graphs, SDP, ICE, credentials, or raw RTP.

## Further Notes

- This is intentionally the exactly-two-user proof. The existing room capacity remains five, but the application deliberately provides no partial three-user behavior; it drops RTP until exactly two Sessions are active again.
- The ExWebRTC send API rewrites destination transport-specific RTP fields. The functional promise is encoded Opus delivery through the destination sender, not a byte-for-byte packet relay.
- ADR 0018 remains the room-lifecycle authority; ADR 0019 captures the forwarding ownership, route identity, topology, readiness, cleanup, and failure decisions specific to this phase.
- The current narrow RTP observer is the approved media test seam. It is test-only and observes real sending behavior, so no production-configurable fake PeerConnection is required.

### Suggested implementation sequence

1. Replace the PeerConnection wrapper's self-echo outcome with typed accepted-track and accepted-RTP results, retain destination outbound-track ownership, and prove real ExWebRTC destination sending without self-echo.
2. Build the room-local Forwarder route graph and its idempotent readiness, RTP, withdrawal, exactly-two-Session, and late-packet drop behavior using Voice Session IDs as its public identities.
3. Connect Session media events to the Forwarder and destination-delivery boundary; prove both directions, both setup orders, destination checks, and track-ended behavior through real PeerConnection observers.
4. Connect RoomServer's canonical removal paths to route withdrawal; prove leave, Channel death, terminal peer state, timeout, Session crash, access removal, Voice Channel deletion, and replacement-session isolation.
5. Certify phase boundaries: three-or-more Sessions drop media, `:disconnected` remains non-terminal, Forwarder failure resets only its room, diagnostics remain metadata-only, and the focused suite plus `mix precommit` pass.
