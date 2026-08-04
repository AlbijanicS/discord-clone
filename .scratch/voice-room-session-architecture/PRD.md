# Phase 6: OTP Voice Channel Room and Session Architecture PRD

Status: ready-for-agent

This is the ready-for-agent product artifact in the repository's local Markdown
issue tracker. It synthesizes the Phase 6 design session and uses the canonical
Voice Channel vocabulary from `CONTEXT.md`.

## Problem Statement

The application has proven a single browser-to-server WebRTC connection and a
one-peer RTP echo diagnostic, but the Phoenix signaling adapter currently owns
the server PeerConnection directly. It has no supervised Voice Channel room,
canonical active membership, cross-room User coordination, or safe lifecycle
for runtime failures. Adding multi-user media on this foundation would make
capacity, cleanup, and ownership ambiguous.

Workspace Members need Voice Channels to have an explicit, supervised runtime
that can admit one Voice Session per User across the application, preserve a
working current session when a requested move cannot be admitted, and remove
failed sessions without leaving ghost membership or long-lived processes.

## Solution

Create `DiscordClone.Voice` as the stateless runtime API boundary. The
authenticated Phoenix signaling adapter authorizes durable Voice Channel access
through `Workspaces`, then delegates runtime admission to `Voice`.

Start one isolated, dynamically supervised room tree for each active durable
Voice Channel. A RoomServer owns that room's canonical Voice Session membership
and five-session capacity. A global AdmissionServer serializes cross-room
operations and keeps the minimal per-User active-session index. Each admitted
Voice Session has a separately generated opaque Voice Session ID and a
temporary Session process. The existing one-peer echo negotiation remains
unchanged until Phase 7.

## User Stories

1. As a Workspace Member, I want my Voice Channel access authorized before runtime admission, so that non-members cannot create Voice runtime state.
2. As a Workspace Member, I want one active Voice Session across the application, so that my audio connection has one unambiguous owner.
3. As a Workspace Member, I want joining a different Voice Channel to move me there, so that I can switch rooms without manually cleaning up the old connection.
4. As a Workspace Member, I want a failed move to a full Voice Channel to preserve my current connection, so that attempting to switch does not disconnect me unnecessarily.
5. As a Workspace Member, I want a clear room-full response, so that I understand why a requested join did not happen.
6. As a Workspace Member, I want aggregate room occupancy made available to the authorized control plane, so that a later interface can show information such as three of five available slots without exposing a roster.
7. As a Workspace Member, I want a repeated join from my same active signaling connection to be harmless, so that double-clicks and duplicate deliveries do not create duplicate Voice Sessions.
8. As a Workspace Member, I want a different tab or a different Voice Channel request to follow the move policy, so that duplicate and move behavior remain distinguishable.
9. As a Workspace Member, I want explicit leave to release my Voice Session immediately, so that microphone, PeerConnection, and membership resources are not retained.
10. As a Workspace Member, I want an empty Voice Channel runtime to remain briefly available after the last leave, so that quick rejoin or another near-immediate join does not needlessly churn room processes.
11. As a Workspace Member, I want an idle Voice Channel runtime to stop after its grace period, so that unused server resources do not accumulate.
12. As a Workspace Member, I want a browser/signaling connection failure to remove my Voice Session, so that I do not remain visibly or logically connected after it is gone.
13. As a Workspace Member, I want a Voice Session crash to remove only that session, so that one failed browser connection does not silently resurrect or corrupt other memberships.
14. As a Workspace Member, I want other healthy sessions in the room removed coherently if room ownership itself fails, so that a restarted room never retains stale membership or routing state.
15. As a Workspace Member, I want losing Workspace access to end my matching Voice Session, so that durable authorization changes are reflected in runtime access.
16. As a Workspace Member, I want deletion of a Voice Channel to end its active Voice Sessions, so that no runtime room outlives its durable resource.
17. As a Workspace Member, I want my Signaling Session ID and Voice Session ID to stay distinct, so that signaling correlation is not confused with active room membership.
18. As an implementer, I want an opaque Voice Session ID instead of a PID exposed across boundaries, so that runtime processes can change without becoming application identity.
19. As an implementer, I want a narrow Voice API rather than web-layer Registry and supervisor access, so that process topology remains encapsulated.
20. As an implementer, I want RoomServer to own room-local membership while AdmissionServer coordinates only cross-room User uniqueness, so that each process has one clear state responsibility.
21. As an implementer, I want capacity enforcement to happen atomically at RoomServer admission, so that concurrent joins cannot exceed five active Voice Sessions.
22. As an implementer, I want all leave/failure paths to converge on idempotent cleanup, so that duplicate notifications cannot leave indexes, routes, or membership inconsistent.
23. As an implementer, I want Forwarder introduced as a supervised boundary without media behavior, so that Phase 8 routing has a clear owner without advancing multi-user scope.
24. As an implementer, I want privacy-safe runtime outcomes, so that capacity and lifecycle reporting never reveals SDP, ICE, RTP, credentials, PIDs, raw identifiers, User data, or Voice Channel structures.
25. As an implementer, I want deterministic lifecycle tests, so that Phase 7 and Phase 8 build on a proven runtime rather than timing-dependent browser behavior.

## Implementation Decisions

- Add a stateless `DiscordClone.Voice` context/API as the only public runtime façade. It gets or starts rooms and delegates admission, leave, and lifecycle actions without exposing Registry keys, supervisor topology, or process IDs to the web layer.
- `DiscordCloneWeb.VoiceChannel` remains a thin authenticated signaling/control adapter. It authorizes a User's durable Voice Channel access through `Workspaces` at topic admission, then invokes the Voice API using minimal trusted runtime facts. It does not own room state, capacity, Voice Session lifecycle, or long-lived PeerConnections.
- Durable Workspace authorization and runtime admission remain separate. RoomServer validates runtime invariants rather than repeating database authorization on every signaling event.
- A `Voice.RoomRegistry`, uniquely keyed by durable Voice Channel ID, identifies the currently running room runtime. A global `Voice.RoomSupervisor` dynamically starts one isolated room tree on demand.
- Each room tree contains RoomServer, Forwarder, and SessionSupervisor. The room supervisor uses `:one_for_all`: failure of a room-correctness sibling restarts the room coherently. SessionSupervisor dynamically owns individual Sessions, so an individual Session failure stays local.
- RoomServer is the sole canonical owner of active Voice Session membership in its Voice Channel. It owns mappings among Voice Session ID, User ID, Session PID, and monitored signaling-channel PID; those PIDs are internal state only.
- RoomServer creates a new opaque Voice Session ID on admission. Voice Session ID identifies active runtime membership; it is distinct from durable Voice Channel ID, User ID, Signaling Session ID, and any PID.
- Phoenix Channel continues to create and validate the existing opaque Signaling Session ID. It correlates signaling messages to one browser connection and is associated with, but never conflated with, the admitted Voice Session.
- Add one global `Voice.AdmissionServer`. It serializes join, move, and leave operations and owns only the global `user_id` to active Voice Session and room reference index. It does not duplicate RoomServer's canonical room membership.
- AdmissionServer enforces the one-active-Voice-Session-per-User rule across all Voice Channels. Same connection/same Voice Channel admission is idempotent and returns the existing session result. A new connection or different target Voice Channel uses the move workflow.
- A move checks target room capacity before ending the old session. If the target room is full, return a normal `room_full` outcome and retain the User's existing session unchanged. If capacity exists, stop and fully remove the old session before admitting the new one.
- RoomServer enforces the hard five-active-Voice-Session cap atomically during admission. Capacity outcomes may expose only aggregate active count and capacity to the authorized control plane; roster and identifying information are not part of Phase 6.
- Sessions use `restart: :temporary`. A Session that stops or crashes is removed; it is never automatically restarted into an unknown signaling or WebRTC state.
- RoomServer monitors its Sessions. Each Session monitors its Phoenix Channel process. Session termination, signaling-channel death, explicit leave, and future PeerConnection failure follow one idempotent cleanup path: stop Session, remove RoomServer membership, clear AdmissionServer's User index, remove Forwarder routes, then begin idle handling if the room is empty.
- Forwarder exists as a supervised lifecycle boundary in Phase 6 but owns no RTP graph, echo routing, roster broadcast, or media processing. Phase 7 moves the proven one-peer echo through Session; Phase 8 introduces multi-user RTP forwarding.
- After the final Voice Session is removed, a room starts a fixed 30-second idle timer. A new admission during that interval cancels the timer. Expiry stops the empty room tree. No departed Session, PeerConnection, browser capture, or User index survives the grace period.
- An explicit Workspaces-to-Voice lifecycle notification ends matching runtime sessions when durable Voice Channel access is revoked or the Voice Channel is deleted.
- Existing Phase 5 browser-offer/server-answer negotiation, one-peer Opus echo, browser-owned remote audio element, and local `MediaStreamTrack.enabled` mute behavior remain unchanged. This phase does not move media behavior through the new processes.
- Runtime results are privacy-safe. They must not emit raw SDP, ICE, RTP, credentials, PIDs, opaque identifiers, User data, or Voice Channel structures in diagnostics or unauthenticated responses.

## Testing Decisions

- The primary seam is the public Voice runtime API. OTP tests should assert externally observable lifecycle outcomes rather than map layouts, Registry internals, PIDs, or private process messages.
- Test dynamically starting a room for a valid durable Voice Channel ID, returning an existing running room, and stopping an idle room after the 30-second timer; use process monitoring or state synchronization rather than sleeps.
- Test same-channel idempotent join, one active Voice Session per User, ordered cross-room moves, and simultaneous join requests without duplicate active sessions.
- Test atomic room capacity: the sixth admission is rejected as `room_full`, reports only aggregate capacity, does not displace any existing User, and preserves a mover's old session if the target is full.
- Test explicit leave, duplicate leave, Phoenix Channel death, Session crash, durable access revocation, Voice Channel deletion, and room-core failure. Each must leave RoomServer membership and AdmissionServer's User index correct and eventually stop an idle room.
- Test that individual temporary Session failures do not restart the failed session or corrupt healthy room membership, while a room-core restart produces no stale canonical membership.
- Add authenticated Phoenix Channel integration coverage for topic authorization and delegation to the Voice API. This is the highest transport seam and must confirm that unauthorized users cannot trigger runtime admission.
- Preserve the existing deterministic Voice Channel, PeerConnection-wrapper, and browser controller tests. Phase 6 does not alter their Phase 5 offer/answer, echo, remote-playback, or local-mute contracts; Phase 7 will extend those seams to prove Session ownership.
- Use the repository's existing dynamic-runtime tests as prior art for Registry lookup, DynamicSupervisor start races, named processes, Process monitors, and `start_supervised!/1` cleanup.

## Out of Scope

- Moving Phase 5's server PeerConnection, offer/answer processing, ICE handling, or one-peer echo into Voice.Session; that is Phase 7.
- Two-user or multi-user RTP forwarding, route matrices, self-audio exclusion, roster broadcasts, or media fan-out; that is Phase 8.
- Mixing, decoding, transcoding, recording, transcription, video, screen sharing, data channels, device selection, track replacement, renegotiation, or browser audio-processing constraints.
- User-facing room roster, speaking indicators, server mute/deafen, moderator actions, or final capacity UI. A later controls/UI phase may use the safe aggregate capacity result.
- Heartbeat/reconnection recovery policy, disconnected-state expiry, crash-injection matrices beyond the defined monitor cleanup, STUN/TURN deployment, production networking, and permanent observability design.
- Durable Voice Session records or database persistence of runtime membership, PIDs, signaling state, ICE state, RTP routes, or idle timers.

## Further Notes

- The approved room supervision structure and its rationale are recorded in ADR 0018. The targeted official OTP research note explains why rooms are dynamically started but own their own static supervision policy.
- The 30-second grace keeps only an empty room runtime alive; it must never keep a departed User's media/session resources alive or imply reconnect recovery.
- Phase 6 establishes ownership and safe lifecycle boundaries. It deliberately avoids changing the manually certified Phase 5 media proof narrative.
