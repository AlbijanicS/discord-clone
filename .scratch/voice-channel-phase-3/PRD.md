# Phase 3: Authenticated Phoenix Signaling Skeleton PRD

Status: ready-for-agent

This PRD specifies Phase 3 of the accepted Voice Channel roadmap. It follows
ADR 0016 and the settled Phase 3 design: a Voice Channel is a durable
Workspaces resource, while the new Phoenix Channel is an authenticated,
ephemeral signaling adapter. This phase intentionally does not create a Voice
Session runtime, a RoomServer, a PeerConnection, or media transport.

## Problem Statement

A Workspace Member can currently select a durable Voice Channel and the Voice
Owner Tab can own browser-local microphone capture, but the application has no
authenticated signaling transport between a browser and the server. Later
browser-to-server WebRTC work needs a narrow, authorized control plane whose
connection lifecycle is independent of LiveView navigation and whose messages
cannot be spoofed, leaked across Voice Channels, or accidentally become a
second source of durable or runtime Voice ownership.

The application needs to prove that two browser tabs can independently use an
authenticated Phoenix signaling connection for the same Voice Channel, using
small fake messages that preserve the intended browser-to-server WebRTC shape.
It must do so without changing the existing microphone controller into a
signaling transport or prematurely introducing real media state.

## Solution

Add a dedicated authenticated `/voice` Phoenix socket and an authenticated
Voice Channel topic for each durable Voice Channel. The socket derives the
existing `Accounts.Scope` from the browser's signed application session; the
Channel authorizes topic joins through Workspaces.

Joining `voice:<voice_channel_id>` is the complete Phase 3 admission action.
On success, the server issues an opaque Signaling Session ID for that one
socket/topic connection. All application signaling messages must present that
ID. The Channel accepts and returns only bounded fake signaling messages in
the same direction as the future browser-to-server PeerConnection flow:
offer requests receive a correlated answer reply, and server-originated ICE
messages are pushed only to their originating browser connection.

## User Stories

1. As a logged-in Workspace Member, I want a dedicated Voice signaling connection, so that Voice transport can evolve independently of LiveView navigation.
2. As a logged-in Workspace Member, I want the Voice socket to recognize my existing application session, so that I do not authenticate separately for signaling.
3. As a security-conscious Workspace Member, I do not want the browser to choose the User identity used for Voice signaling, so that a modified client cannot impersonate another User.
4. As a Workspace Member, I want to join signaling only for Voice Channels in my Workspace, so that Workspace Membership continues to protect Voice Channel access.
5. As a non-member, I want inaccessible, missing, and deleted Voice Channels to be indistinguishable at topic join, so that signaling cannot be used to enumerate another Workspace's Voice Channels.
6. As a Workspace Member, I want a successful Voice topic join to provide one server-issued Signaling Session ID, so that later messages are tied to the admitted connection.
7. As a Workspace Member, I want a new Signaling Session ID after reconnecting or rejoining, so that stale messages from an old connection cannot be reused.
8. As a Workspace Member, I want fake offer/answer and ICE traffic to remain on my own browser-to-server signaling connection, so that another tab on the same Voice Channel cannot receive or affect it.
9. As a Workspace Member, I want a fake offer to receive an answer through the same request/reply interaction used by the future server PeerConnection, so that the browser contract can later gain real WebRTC behavior without redesign.
10. As a Workspace Member, I want server-originated fake ICE to arrive as a direct asynchronous event, so that the application proves the future trickle-ICE direction without peer-to-peer broadcasting.
11. As a Workspace Member, I want a lightweight heartbeat acknowledgement, so that the signaling contract has a testable liveness interaction without claiming ownership or recovery authority.
12. As a developer, I want malformed fake messages to identify missing or invalid fields, so that full-stack debugging is practical.
13. As a security-conscious Workspace Member, I want identity and authorization failures to remain general, so that error responses do not reveal valid session IDs, Users, or Voice Channels.
14. As a Workspace Member, I want leaving to use the built-in Phoenix topic leave lifecycle, so that the signaling connection closes cleanly without a duplicate application-level leave protocol.
15. As a developer, I want bounded fake payloads and metadata-only logs, so that this learning slice is safe without imposing accidental limits on real SDP or ICE later.
16. As a future Voice implementer, I want Phase 3 to avoid a RoomServer, Voice Session, and PeerConnection, so that later runtime and media failures remain independently understandable.
17. As a future maintainer, I want authenticated socket and Channel tests to prove the public signaling behavior, so that a real browser/media stack is not required to trust this control-plane slice.

## Implementation Decisions

- Add a dedicated `/voice` Phoenix socket alongside, not inside, the existing `/live` LiveView socket. No router route, browser pipeline, or LiveView session changes are required: this is an endpoint socket transport, while the existing authenticated routes keep their current `:require_authenticated_user` LiveView session and browser pipeline.
- The browser opens the Voice socket on the same origin and sends no user ID, Workspace ID, or authentication credential in socket parameters. The socket reads the existing signed session made available by the endpoint, verifies its session token through Accounts, derives `Accounts.Scope`, assigns that trusted scope to the socket, and rejects absent, invalid, expired, or revoked sessions.
- Keep Workspaces as the authorization boundary. Add only the scoped Voice Channel lookup/authorization seam needed for signaling topic joins; do not query membership or role strings directly from the web Channel.
- Use the canonical topic grammar `voice:<voice_channel_id>`. Reject malformed identifiers safely. Treat an inaccessible, missing, or deleted Voice Channel as the same generic topic-join denial; do not disclose which condition occurred.
- A successful topic join is the only admission action. Phoenix creates one `DiscordCloneWeb.VoiceChannel` process for each socket/topic join. There is no custom `voice_join` event and no manual process start.
- On successful join, generate a cryptographically random, URL-safe Signaling Session ID on the server and retain it only in that Channel process. Return it in the join reply. It is an opaque wire-level binding, not a User ID, socket ID, process ID, database record, reusable credential, or Voice Session.
- Require the exact Signaling Session ID on every Phase 3 application message after join. A missing, malformed, stale, cross-topic, or mismatched ID is rejected. Topic termination, socket disconnection, and rejoin invalidate the prior ID and issue a new one when applicable.
- Preserve the glossary distinction: a Signaling Session ID binds one admitted signaling connection; a Voice Session remains the later active browser audio connection and runtime concept.
- Model one browser-to-server negotiation flow per admitted signaling connection. Do not add a negotiation ID, concurrent renegotiation policy, offer-collision handling, peer selection, or browser-to-browser signaling in this phase.
- Keep the fake contract small and isolated behind a Phase-3-only validator. The browser may submit a fake offer, a fake ICE candidate, and a heartbeat, each bound to its Signaling Session ID. The fake values use explicit placeholder fields such as labels and sequence values; they do not masquerade as real SDP or ICE strings.
- A fake offer receives one correlated Phoenix reply containing a fake answer. The implementation must preserve this request/reply browser contract even if a future Voice Session generates the real answer asynchronously.
- A fake client ICE candidate receives a safe acknowledgement. A fake server ICE candidate is delivered as a direct asynchronous push to the same admitted browser connection. Never broadcast offers, answers, candidates, heartbeats, or errors to other topic subscribers.
- Heartbeat is a validated request/reply probe only. Phoenix owns transport liveness and Channel termination. Do not add timeout authority, reconnection state, durable presence, roster membership, or ownership rules.
- Leaving uses Phoenix's built-in client topic leave operation. Do not add a custom `leave` event. A normal leave and an unexpected socket close both end the Channel process and invalidate its Signaling Session ID.
- For malformed payloads, return stable field-level validation feedback without echoing received values. For authentication, authorization, and Signaling Session ID failures, return only generic safe errors. Unsupported events receive a stable safe error code.
- Apply a Phase-3-only maximum decoded fake payload size of 4 KiB and a maximum fake text-field length of 256 characters. Do not alter endpoint WebSocket transport limits. Real SDP and ICE validation in a later phase must be a separate, explicitly chosen boundary rather than inheriting these temporary limits.
- Add a browser-side Voice signaling adapter that owns the `/voice` socket and its topic connections. Keep the Phase 2 Voice Owner Tab controller as the browser-local microphone/media boundary; it must not become the signaling transport. The adapter may coordinate with existing authenticated Voice UI but must not change microphone capture, ownership, or permission behavior in this phase.
- Log only reviewed structured metadata: lifecycle/operation, outcome, stable error code, and decoded byte count. Do not log fake signaling content, Signaling Session IDs, session tokens/cookies, User or Voice Channel identifiers, socket/channel structs, or raw parameters. Ensure any Channel telemetry handling also projects this safe subset; use the same no-content rule in development and production.
- Add no schema, migration, durable Voice ownership field, Voice RoomServer, Voice Session, Voice Forwarder, registry, supervisor, PeerConnection, `ex_webrtc` dependency, RTP, remote audio, or real browser WebRTC API work.

## Testing Decisions

- Good tests prove externally visible socket and Channel behavior, not private assigns, helper arrangement, raw payload logging, or a particular Channel-process implementation.
- The primary seam is real authenticated Phoenix socket and Channel integration. Tests should create signed authenticated session context, connect the custom Voice socket, join topics, push messages, receive replies/events, and leave topics through Phoenix's public test APIs.
- Socket-authentication tests should prove that absent, invalid, expired, and revoked session credentials cannot establish an authenticated Voice socket, and that browser-supplied identity parameters never control the derived scope.
- Channel-join tests should prove valid Workspace Members can join their durable Voice Channels and receive a fresh opaque Signaling Session ID; malformed identifiers and inaccessible/missing/deleted Voice Channels receive safe denials.
- Message tests should prove every supported application message requires the exact current Signaling Session ID; wrong, missing, stale-after-rejoin, and cross-topic IDs fail safely.
- Contract tests should prove a fake offer produces its correlated fake answer reply, client ICE receives acknowledgement, server fake ICE is delivered only to the originating connection, and heartbeat returns its acknowledgement.
- Isolation tests should connect two admitted tabs to the same Voice Channel topic and prove that neither receives, answers, or changes the other's offer, answer, ICE, heartbeat, or error traffic.
- Validation tests should prove helpful missing/type/size feedback for malformed fake payloads, generic responses for identity/authorization failures, unknown-event handling, and the temporary 4 KiB/256-character fake limits.
- Lifecycle tests should prove built-in topic leave and unexpected close invalidate the Channel-bound Signaling Session ID. They must not assert a future Voice Session, RoomServer, roster, or media cleanup effect.
- Add small isolated JavaScript tests for the browser signaling adapter's join, correlated offer reply, direct ICE push, heartbeat, safe error handling, and built-in leave behavior. Do not require a real microphone permission prompt, browser PeerConnection, or remote audio test in this phase.
- Reuse the existing Accounts session fixtures, Workspaces fixtures, and JavaScript hook-test convention as prior art. Run focused tests during implementation and `mix precommit` after all changes.

## Out of Scope

- Browser `RTCPeerConnection`, `getUserMedia` changes, microphone ownership changes, SDP parsing, ICE parsing, ExWebRTC, RTP, remote audio playback, media forwarding, STUN/TURN, or production WebRTC deployment.
- A Voice RoomServer, Voice Session, Voice Forwarder, dynamic supervision, registry, active roster, capacity enforcement, server-authoritative multi-tab ownership, reconnection/recovery policy, or idle-room lifecycle.
- Browser-to-browser signaling, a mesh topology, user-to-user offer/answer routing, peer selection, moderation, mute/deafen synchronization, speaking indicators, device selection, or a Voice Channel route/detail view.
- Any durable persistence of Signaling Session IDs, signaling state, Voice membership, Voice ownership, heartbeat state, fake payloads, or diagnostic data.
- Changing LiveView routes, their existing browser pipeline, or their `:require_authenticated_user` session. The new endpoint socket reuses session authentication but is not a LiveView route.
- Changing Bandit's general WebSocket limits or treating temporary fake-payload bounds as real SDP/ICE constraints.
- Marking Phase 2's manual microphone-verification gate complete or changing its roadmap status.

## Further Notes

- Phase 3 is complete when the dedicated authenticated Voice socket, Workspaces-authorized topic join, server-issued Signaling Session ID, bounded fake message contract, direct same-connection routing, lifecycle behavior, and metadata-only observability are covered by the agreed automated tests and `mix precommit` passes.
- The Phase 4 handoff is deliberately narrow: replace the fake validator and fake answer/ICE behavior with a pinned real browser-to-ExWebRTC PeerConnection implementation while preserving socket authentication, topic authorization, Signaling Session ID binding, offer-reply correlation, and direct server-ICE push direction.
- Research supporting the leave lifecycle, Phoenix/ExWebRTC request/reply and push pattern, fake payload bounds, and safe signaling observability is recorded in the four Phase 3 research notes under `docs/`.
