# Phase 5: RTP Echo Experiment

Status: ready-for-agent

## Problem Statement

The Voice Channel implementation has proven its authenticated signaling path and
one browser-to-server WebRTC connection. It has not yet proven the media path:
that microphone audio reaches Elixir as RTP and can be sent back to a browser
as a remote WebRTC audio track.

Without that proof, later work on `Voice.RoomServer`, `Voice.Session`, and
multi-user RTP forwarding would mix two unknowns: whether the application can
handle media packets at all, and whether the room architecture routes them
correctly. A small, single-connection echo diagnostic makes the media boundary
observable before the system introduces room membership, forwarding graphs, or
moderation policy.

## Solution

Extend the existing one-browser, one-server-PeerConnection Voice Channel path
with a temporary RTP echo diagnostic. The browser continues to capture a single
microphone track after an explicit Join Voice gesture and offers it to the
server. During that same initial offer/answer negotiation, the server attaches
one outbound audio track to the negotiated audio transceiver. Once connected,
the server forwards each expected inbound Opus RTP packet directly to that
outbound track. The browser receives it as a remote audio track and plays it
through one browser-controller-owned audio element.

The diagnostic is intentionally narrow. It neither decodes, mixes,
transcodes, buffers, reorders, records, nor persists audio. It introduces no
room runtime, Voice Session process, roster, remote-user UI, device picker, or
renegotiation protocol. It provides development-only, privacy-safe aggregate
diagnostics so an implementer can tell whether a failure is in inbound RTP,
server forwarding, or browser playback.

## User Stories

1. As a Workspace Member who has joined a Voice Channel, I want my microphone audio to be sent to the server over the existing authenticated WebRTC connection, so that the application can prove it receives real media rather than only signaling.
2. As a Workspace Member running the echo diagnostic with headphones, I want to hear my microphone audio returned as remote WebRTC audio, so that I can verify the complete browser-to-server-to-browser media path.
3. As a Workspace Member, I want one Join Voice action to remain sufficient for normal echo playback, so that the diagnostic does not add an unnecessary second-step workflow.
4. As a Workspace Member whose browser blocks delayed audible playback, I want an Enable audio fallback control, so that I can explicitly start the already-connected remote audio without restarting Voice.
5. As a Workspace Member, I want the browser to acquire microphone input with the existing simple audio capture request, so that the experiment does not introduce device-selection or browser audio-processing preferences prematurely.
6. As a Workspace Member, I want the local Mute control to stop my audible echo without leaving the Voice Channel, so that I can confirm local mute controls the real media path without a second negotiation.
7. As a Workspace Member, I want Unmute to resume audible echo on the same connection, so that the diagnostic proves track enablement rather than reconnection behavior.
8. As a Workspace Member who is silent, I want my connected Voice Channel not to fail merely because no RTP packets arrive for a period, so that silence is treated as normal use rather than a transport error.
9. As a Workspace Member whose microphone device stops unexpectedly, I want the echo attempt to end cleanly and offer the existing retry path, so that I do not remain in a misleading connected state.
10. As a Workspace Member who leaves Voice, I want microphone capture, remote audio playback, the browser PeerConnection, the signaling topic, and the server PeerConnection to be released, so that a later join starts cleanly and browser capture indicators do not persist.
11. As a Workspace Member whose Voice transport fails or closes, I want the echo attempt to clean up consistently, so that I can retry without stale browser or server media state.
12. As an implementer diagnosing the echo experiment, I want development-only aggregate signals for remote-track attachment and inbound, echoed, and dropped RTP packets, so that I can localize failures without inspecting sensitive media or signaling contents.
13. As an implementer, I want unexpected media to be safely ignored and counted, so that a browser cannot expand the one-microphone echo scope by offering extra audio, video, data channels, or unknown RTP tracks.
14. As an implementer, I want the server to accept only the single compatible Opus audio path required by the diagnostic, so that it never silently falls back to decoding, transcoding, or an unproven codec path.
15. As an implementer, I want RTP to be forwarded in arrival order with no application jitter buffer or queueing policy, so that Phase 5 measures the smallest possible media path and browser playback remains responsible for jitter handling.
16. As an implementer, I want the existing authenticated Voice Channel protocol to remain the highest automated seam, so that the media diagnostic is tested through the same authorization and signaling boundary users actually use.
17. As an implementer, I want focused server and browser tests below that seam, so that media lifecycle and browser remote-track behavior are deterministic without relying on a physical microphone in CI.
18. As an engineer preparing the later Voice Session and Forwarder phases, I want a repeatable one-peer echo proof, so that later RTP routing work begins from a known-good receive-and-send path.

## Implementation Decisions

- This is Phase 5 of the ExWebRTC Voice Channels roadmap and respects the accepted server-routed architecture: Phoenix Channels carry signaling and control traffic; WebRTC carries RTP/SRTP media.
- A Voice Channel remains a durable Workspaces resource. The echo diagnostic creates no durable Voice Session record, room membership, or database state.
- The current authenticated Voice Channel and its PeerConnection wrapper temporarily own the single server-side ExWebRTC PeerConnection for this spike. `Voice.Session`, `Voice.RoomServer`, `Voice.Forwarder`, Registry, DynamicSupervisor, canonical room membership, and capacity enforcement begin in later phases.
- The browser remains the offerer. The server applies the validated offer, provisions one outbound server audio track on the negotiated audio transceiver, then creates and returns the answer. The echo track is therefore available from initial negotiation; Phase 5 must not add renegotiation, perfect negotiation, or a second SDP lifecycle.
- The accepted media contract is exactly one expected inbound audio source and one server-to-browser echo sink, negotiated as Opus. If the offer does not produce the compatible single Opus audio path, the offer is rejected safely and the attempt is cleaned up. The user-facing failure remains generic; diagnostics must not include SDP.
- The server consumes ExWebRTC inbound track and RTP notifications, identifies the expected inbound audio track, and forwards each valid packet immediately to the known outbound echo track. ExWebRTC owns the outbound transport fields it must rewrite for the negotiated sender; the application does not decode or alter the encoded audio payload.
- Packet forwarding is direct arrival-order passthrough. Phase 5 adds no server-side jitter buffer, packet reordering, timing policy, mixing, recording, transcoding, or custom audio processing.
- RTP for an unknown track, extra audio tracks, video, data channels, and any other media outside the one-source contract are dropped and increment an aggregate diagnostic counter. They are never echoed and do not by themselves terminate the entire connection.
- The existing local mute behavior remains browser-side: it toggles the microphone `MediaStreamTrack.enabled` flag. It is a user convenience control, not server-enforced moderation. Muting must suppress audible echo, and unmuting must resume it without renegotiation. Server-enforced mute is deferred.
- The browser creates and owns one remote `<audio>` element outside LiveView rendering. It has autoplay enabled, receives the remote WebRTC track/stream, and is released on leave, failure, takeover, navigation teardown, and terminal cleanup.
- The normal path needs no separate playback permission prompt or dedicated Enable Echo protocol event. The Join interaction primes the playback element; when a remote track arrives, the browser attempts playback. If browser autoplay policy rejects audible playback, the UI exposes an Enable audio fallback that retries playback without reconnecting.
- No headphone warning, forced muted output, or artificial volume reduction is part of the diagnostic. Manual echo validation is performed with headphones.
- Microphone capture remains the existing `getUserMedia({audio: true})` behavior. This phase does not select a device or force echo cancellation, noise suppression, auto gain control, or other audio constraints.
- A connected but silent microphone is valid. There is no post-connection RTP inactivity timeout. Existing negotiation deadlines and terminal transport failure behavior remain in effect.
- An expected microphone track ending is terminal for this spike. The browser and server clean up the PeerConnection and remote playback, and the user may start a fresh retry/join. Device switching, `replaceTrack`, and in-place recovery are deferred.
- Existing authenticated topic authorization, server-issued signaling session IDs, negotiation correlation, bounded ICE handling, and privacy-safe signaling diagnostics remain unchanged. No raw SDP, ICE, RTP packets, credentials, session identifiers, User data, or Voice Channel data may be emitted to diagnostics.
- Development/test diagnostics may report only aggregate, non-identifying state: connection lifecycle category, remote-track attachment/playback outcome, and inbound/echoed/dropped RTP counts. They are not normal Voice Channel product UI and are temporary evidence for this diagnostic phase; Phase 14 owns durable observability design.

## Testing Decisions

- The primary automated seam is the authenticated Voice Channel protocol. Tests should drive a browser-shaped, valid offer through that boundary and assert externally observable outcomes: accepted or safely rejected negotiation, corresponding remote media contract, safe diagnostics, and cleanup. They should not assert private process-state representation.
- Focused ExWebRTC wrapper tests should prove that a compatible offer provisions an outbound audio track during the initial negotiation, exposes the inbound-track/RTP signals needed by the echo path, sends an RTP packet through the outbound track, and rejects incompatible media safely. Use supervised processes in tests so PeerConnection cleanup is guaranteed.
- Focused browser peer-attempt/controller tests should use a fake `RTCPeerConnection` and fake media element/remote track. They should prove remote-track attachment, autoplay attempt, Enable audio fallback after a rejected play, and complete detachment/closure on leave and terminal failure. They should test visible state and browser resource behavior, not implementation-local callbacks.
- Tests should verify that an expected inbound RTP packet increments inbound and echoed counters and is sent once to the echo track; unexpected tracks/media increment dropped counters and are not forwarded. Tests must never assert or print raw RTP payloads, SDP, ICE candidates, credentials, or identifiers.
- Tests should verify local mute and unmute through the browser media seam: a disabled microphone track produces no audible echo path, enabling it resumes the same established connection, and no new offer/answer is sent for either transition.
- Tests should verify cleanup idempotence for explicit leave, signaling-topic close, terminal connection state, and ended microphone track. A cleanup attempt must release browser remote playback, the browser PeerConnection, signaling membership, and the server PeerConnection without duplicate failure effects.
- Tests must prove that no RTP inactivity timeout is introduced after connected state. Silence is represented by zero packet counts while the connection remains healthy.
- Existing Phase 4 tests provide prior art: authenticated channel tests already validate authorization, correlated signaling and bounded ICE; focused PeerConnection tests use a supervised ExWebRTC PeerConnection; browser peer-attempt tests use deterministic fake peer connections and state assertions. Extend these seams rather than introducing a separate test harness.
- Completion also requires one documented localhost manual test with headphones. It must show: browser/server connected state, remote-track attachment and playback, audible microphone echo, local mute suppressing echo, unmute resuming it without renegotiation, explicit leave releasing capture/playback/PeerConnections, and a clean rejoin. The manual proof supplements but does not replace automated tests.

## Out of Scope

- OTP Voice Channel runtime architecture: `Voice.RoomServer`, `Voice.Session`, `Voice.Forwarder`, Registry/DynamicSupervisor ownership, canonical active membership, room capacity, and idle shutdown.
- Two-user or multi-user audio, fan-out routing, roster broadcasts, source-to-destination matrices, and the five-Voice-Session cap.
- Server-enforced mute/deafen, moderator disconnect/move actions, speaking indicators, deafen behavior, and any moderation policy.
- Audio mixing, transcoding, decoding, recording, transcription, video, screen sharing, data channels, and RTP processing beyond direct Opus passthrough.
- Renegotiation, track replacement, device switching, device picker UI, push-to-talk, or explicit browser audio-processing constraints.
- Jitter buffering, packet reordering, congestion tuning, packet-loss recovery policy, bitrate adaptation, and performance-limit measurements.
- Heartbeat/reconnect recovery, disconnected-state expiry, full cleanup failure matrix, and crash-injection work beyond the existing terminal cleanup behavior.
- STUN/TURN deployment, production networking, HTTPS/WSS deployment hardening, cross-network testing, and TURN credentials.
- Permanent production observability, dashboards, metrics, logging schema, or user-facing packet diagnostics.

## Further Notes

- This PRD implements the roadmap's Phase 5 RTP Echo Experiment and is intentionally a learning diagnostic, not a user-facing voice feature milestone.
- The browser’s microphone permission and speaker playback are different concerns. Microphone capture uses the existing explicit user gesture. Audible remote playback has no comparable permission dialog, but browsers may block autoplay; the fallback control handles that policy outcome without changing the signaling protocol.
- The phase preserves the roadmap sequence: prove one-peer media first, establish supervised runtime ownership in Phase 6, move the echo through `Voice.Session` in Phase 7, then build two-user forwarding in Phase 8.
- No ADR or glossary change is required. The decisions here are reversible, phase-scoped diagnostic choices and do not change the accepted durable Voice Channel model or the long-term server-routed architecture.
