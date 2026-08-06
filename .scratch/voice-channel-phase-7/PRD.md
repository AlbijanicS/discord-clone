# Phase 7: Voice Session-Owned WebRTC Runtime PRD

Status: ready-for-agent

This specification synthesizes the Phase 7 `grill-with-docs` decisions and the
final research pass. It uses the canonical Voice Channel vocabulary from
`CONTEXT.md`. The supporting research is recorded in
`docs/phase_7_voice_session_ownership_research.md` and
`docs/phase_7_voice_session_remaining_research.md`.

## Problem Statement

The application has a working Phase 4/5 browser-to-server WebRTC proof and a
Phase 6 supervised Voice Channel runtime. However, the Phoenix signaling
adapter still directly owns the server-side ExWebRTC PeerConnection and all of
the mutable state around it: negotiation state, pending ICE candidates, media
routing state, and media counters.

That ownership is now at odds with the Phase 6 runtime. A Phoenix Channel is a
transport process that can leave, close, or crash, while `Voice.Session` is the
temporary OTP process that represents one admitted browser connection. The
server-side PeerConnection must follow the Voice Session's supervision and
cleanup lifecycle, without moving browser signaling away from Phoenix
Channels or changing the proven browser wire contract.

Without this refactor, later multi-user media work would have no trustworthy
place to determine which PeerConnection, negotiation, ICE queue, and media
counters belong to which Voice Session. Cleanup would also depend too heavily
on Channel termination callbacks, which Phoenix does not guarantee for every
exit path.

## Solution

Move the server-side ExWebRTC PeerConnection and all per-connection WebRTC
state into the supervised `DiscordClone.Voice.Session` process. Keep
`DiscordCloneWeb.VoiceChannel` as the authenticated Phoenix signaling adapter
between the browser and server.

The Channel validates and decodes browser payloads, checks the
`Signaling Session ID`, and serializes browser replies and pushes. It delegates
validated commands through the stateless `DiscordClone.Voice` facade to the
canonical `RoomServer`, which routes them to the matching `Voice.Session`.
The Session owns negotiation, pending ICE, media routing, counters, and the
server PeerConnection.

The Session sends typed internal events directly to the exact Channel process.
The Channel converts server ICE events into the existing Phoenix pushes. For a
terminal server peer failure, the Channel uses the existing normal close path
so the browser's existing `onClose` cleanup continues to report
`connection_lost`. No new required terminal wire event is introduced.

Admission must use a readiness barrier: the Session must not report successful
startup, and `RoomServer` must not commit canonical membership, until the
Session-owned PeerConnection has completed the relevant ExWebRTC startup path.

## User Stories

1. As a Workspace Member, I want my existing Voice Channel join flow to keep using Phoenix Channels for browser/server signaling, so that this runtime refactor does not change how my browser connects.
2. As a Workspace Member, I want my valid browser offer to receive the same correlated server answer, so that an established browser client continues to negotiate without a new protocol.
3. As a Workspace Member, I want server ICE candidates to arrive through the same Channel push and payload shape, so that my browser does not need a new ICE implementation.
4. As a Workspace Member, I want a terminal server peer failure to close my signaling Channel, so that the existing browser `onClose` failure handling cleans up my local connection.
5. As a Workspace Member, I want a temporary network disconnection to remain non-terminal, so that the current Phase 4/5 behavior is preserved until a future recovery policy is explicitly designed.
6. As a Workspace Member, I want malformed or oversized offers rejected at the browser boundary, so that invalid SDP cannot reach the runtime or destabilize my Voice Session.
7. As a Workspace Member, I want malformed or oversized ICE candidates rejected safely, so that unbounded signaling data cannot accumulate in my connection.
8. As a Workspace Member, I want a stale Signaling Session ID rejected, so that an old browser connection cannot control my current Channel.
9. As a Workspace Member, I want a stale Negotiation ID rejected, so that an ICE candidate from an earlier attempt cannot mutate my active negotiation.
10. As a Workspace Member, I want early ICE candidates to remain supported, so that normal browser candidate timing does not cause a valid connection to fail.
11. As a Workspace Member, I want early ICE buffering to remain bounded, so that a malicious or broken browser cannot consume unlimited runtime memory.
12. As a Workspace Member, I want duplicate offers rejected according to the existing contract, so that one Voice Session cannot accidentally create multiple server negotiations.
13. As a Workspace Member, I want server ICE and end-of-candidates events delivered only to my Channel, so that another subscriber to the same Voice Channel cannot receive my connection's signaling data.
14. As a Workspace Member, I want my Voice Session removed when the server peer fails, so that the room does not show me as connected after the server connection is gone.
15. As a Workspace Member, I want a normal Leave to stop the server PeerConnection immediately, so that my microphone and server resources are released promptly.
16. As a Workspace Member, I want a closed or crashed Phoenix Channel to remove my matching Voice Session, so that navigation, tab closure, or transport failure cannot leave ghost membership.
17. As a Workspace Member, I want a crashed Voice Session to remove only itself, so that another User's Voice Session remains healthy.
18. As a Workspace Member, I want a server PeerConnection process to share the Voice Session's lifetime, so that a failed or terminated owner cannot leave an orphaned WebRTC process.
19. As a Workspace Member, I want a failed Session startup to avoid committing membership, so that the room never counts a connection that cannot own a ready server peer.
20. As a Workspace Member, I want a failed move to a full Voice Channel to preserve my current Voice Session, so that capacity rejection does not disconnect me unnecessarily.
21. As a Workspace Member, I accept that a move to an available Voice Channel that fails during new Session/PeerConnection startup leaves me in neither Voice Channel, so that Phase 7 does not introduce an implicit rollback policy.
22. As a Workspace Member, I want server-side peer failure to produce the existing simple connection-lost behavior rather than new WebRTC jargon, so that the UI remains understandable.
23. As a Workspace Member, I want the browser's existing offer timeout to remain meaningful, so that a stalled server command eventually becomes a safe failed connection rather than an indefinitely pending operation.
24. As a security-conscious Workspace Member, I want SDP, ICE credentials, raw candidates, and raw RTP excluded from logs, so that network-sensitive data is not disclosed through diagnostics.
25. As a security-conscious Workspace Member, I want PIDs and internal supervisor data excluded from browser replies and pushes, so that process topology does not become part of the public protocol.
26. As an implementer, I want the Channel to own only browser wire concerns, so that Phoenix serialization and authorization are not mixed with WebRTC runtime state.
27. As an implementer, I want the Voice facade to be the only web-to-runtime command boundary, so that the Channel does not depend on Registry keys, supervisor topology, or Session PIDs.
28. As an implementer, I want `RoomServer` to verify Voice Session membership before forwarding a command, so that a stale or cross-room Voice Session ID cannot control a different runtime.
29. As an implementer, I want `Voice.Session` to serialize all SDP and ICE commands for one browser connection, so that negotiation and candidate ordering cannot race across processes.
30. As an implementer, I want media routing and counters owned by the Session that receives the ExWebRTC messages, so that RTP handling does not depend on Phoenix Channel assigns.
31. As an implementer, I want internal Session events sent directly to the owning Channel process, so that one-user ICE and terminal events do not require room-wide broadcast infrastructure.
32. As an implementer, I want the Session to send typed internal events rather than Phoenix wire maps, so that the runtime remains independent from the browser serialization format.
33. As an implementer, I want PubSub reserved for future room-wide events such as rosters, so that Phase 7 does not accidentally broadcast private signaling data.
34. As an implementer, I want offer acceptance to remain a synchronous command, so that the existing Channel reply directly correlates the browser offer with its answer.
35. As an implementer, I want asynchronous server ICE and state events to use direct messages and Channel pushes, so that events not tied to one incoming browser request retain the correct transport semantics.
36. As an implementer, I want the Session-to-PeerConnection relationship to use OTP linking, so that owner and resource cannot silently outlive one another.
37. As an implementer, I want `RoomServer` to remain the canonical membership cleanup authority, so that Channel, Session, and PeerConnection failure paths converge on one idempotent removal operation.
38. As an implementer, I want terminal peer failure to stop the Session without automatic restart, so that the system never resurrects an unknown WebRTC negotiation state.
39. As an implementer, I want a finite command timeout below the browser deadline, so that a hung runtime operation cannot block the Channel forever.
40. As an implementer, I want timeout outcomes to retire an ambiguous Voice Session, so that a late server answer cannot leave a connection admitted without a known browser state.
41. As an implementer, I want real ExWebRTC integration tests to remain the primary test seam, so that tests verify the actual server-side WebRTC behavior rather than a fake protocol.
42. As an implementer, I want synthetic ExWebRTC messages available in tests for state transitions, so that terminal failure and media routing can be tested deterministically without requiring a real network.
43. As an implementer, I want no public fake PeerConnection configuration added for this phase, so that test seams do not become production architecture.
44. As an implementer, I want the startup readiness barrier tested, so that the room never commits membership before its server peer is usable.
45. As an implementer, I want stale events from a departed Voice Session ignored, so that a late process message cannot affect a replacement Session for the same User.
46. As an implementer, I want existing capacity, one-active-Session-per-User, move, and room-idle behavior preserved, so that Phase 7 changes PeerConnection ownership without regressing Phase 6 runtime guarantees.
47. As an implementer, I want no new database schema or durable Voice Session record, so that this phase remains an in-memory runtime refactor.
48. As an implementer, I want no Phase 8 forwarding, roster, reconnection, or ICE-restart behavior added, so that the implementation remains an honest Phase 7 slice.

## Implementation Decisions

- Keep Phoenix Channels as the browser-to-server signaling transport. The
  Channel remains responsible for topic authorization, untrusted payload
  validation, decoded-size limits, Signaling Session ID validation, browser
  replies, browser pushes, and Channel termination.
- Make `DiscordClone.Voice.Session` the owner of one server-side
  `ExWebRTC.PeerConnection`. The Session starts the PeerConnection, remains its
  ExWebRTC controlling process, receives its WebRTC messages, applies SDP and
  ICE, routes RTP, records media counters, and stops the PeerConnection during
  orderly shutdown.
- Keep the Channel's adapter state limited to the Voice Channel ID, Voice
  Session ID, Signaling Session ID, and any transport-local data needed to
  serialize replies and pushes. Remove PeerConnection state, negotiation state,
  pending ICE, accepted-candidate counters, media counters, and track-routing
  state from Channel ownership.
- Keep `signaling_session_id` as Channel-level wire correlation. Keep
  `negotiation_id` as runtime negotiation state that the Session validates and
  returns in typed results/events. The Channel adds the Signaling Session ID
  to browser-facing payloads. Phoenix's own reply reference continues to
  correlate the immediate answer to the offer push.
- Preserve the current browser wire contract for offer replies, client ICE
  acknowledgements, server ICE pushes, end-of-candidates, and normal Channel
  close behavior. Do not require a new browser terminal event.
- Keep Channel payload parsing and size checks at the edge. The Channel rejects
  malformed input and mismatched Signaling Session IDs. The Session enforces
  negotiation ordering, pending-candidate bounds, accepted-candidate bounds,
  and PeerConnection applicability.
- Use the stateless `DiscordClone.Voice` facade as the command boundary from
  the Channel into the runtime. Commands carry the Voice Channel ID, Voice
  Session ID, Negotiation ID, and decoded SDP/ICE value. The facade locates
  the room and normalizes stale, unavailable, and timeout outcomes.
- Have `RoomServer` verify canonical membership and forward commands to the
  matching Session. The Channel must not call a Session PID or Registry
  directly, and the runtime must not expose PIDs in results.
- Keep offer acceptance synchronous: Channel `handle_in` calls the Voice
  facade, the RoomServer calls the Session, the Session calls the
  PeerConnection, and the Channel returns the answer in the existing Phoenix
  reply. Use direct asynchronous events for server ICE and terminal state.
- Use one finite command budget of 5 seconds for each browser-originated Voice
  runtime command, propagated as remaining time through the facade, RoomServer,
  and Session rather than stacking independent full timeouts. This remains
  below the browser's existing 10-second offer deadline. A timeout is a failed
  runtime command; when its outcome is ambiguous, retire the affected Voice
  Session and converge cleanup rather than leaving it admitted.
- Do not use `:infinity` for SDP or ICE commands originating at the Channel.
  Do not create a synchronous callback from Session into RoomServer, Voice, or
  SessionCoordinator while a runtime command is being handled. Lifecycle
  notifications use asynchronous messages, monitors, or normal process exit.
- Use a direct per-connection event sink: Session sends an allow-listed typed
  message to the Channel PID, and Channel `handle_info` translates it into a
  safe Phoenix push or terminal Channel stop. Include the exact Voice Session
  ID and Negotiation ID where relevant, and discard stale/mismatched events.
- Do not use Phoenix PubSub for one-browser ICE, SDP, media, or terminal
  events. PubSub remains available for future room-wide roster events and is
  not part of Phase 7. Do not use an anonymous callback as the Session event
  path; the existing Channel PID and monitor provide the required unicast
  sink.
- When Session receives a server peer `:failed` or `:closed` state, it sends a
  terminal internal event to the owning Channel and then terminates. Channel
  returns `{:stop, :normal, socket}` so the existing browser `onClose` path
  reports `connection_lost`. `:disconnected` remains non-terminal.
- Keep Session-to-PeerConnection ownership linked. `start_link` makes Session
  the controlling process and shares failure fate with the PeerConnection.
  Use `PeerConnection.stop/1` for orderly cleanup; do not rely on
  `terminate/2` as the only cleanup path and do not use `trap_exit` as the
  primary ownership mechanism.
- Keep RoomServer's existing Session monitor as the canonical membership
  cleanup authority. Channel termination may remain an idempotent lifecycle
  signal, but it must not directly stop the PeerConnection. Session/Channel
  races must converge on one exact Voice Session removal and must not affect a
  replacement Session.
- Start the PeerConnection during Session admission and enforce a readiness
  barrier. Session startup must not report success until the pinned ExWebRTC
  startup path has completed the required readiness step. RoomServer commits
  membership only after Session startup succeeds. A startup failure must not
  leave an admitted membership or orphaned PeerConnection.
- Keep `Voice.Session` temporary and do not automatically restart a failed
  Session or PeerConnection into unknown WebRTC state.
- Do not add production dependency injection or a configurable fake
  PeerConnection. Use the existing real ExWebRTC wrapper and Phoenix
  ChannelTest seams. If a startup-failure assertion cannot be made deterministic
  through existing seams, add only the smallest private test seam needed for
  that negative test; it must not become a public runtime setting.
- Keep Phase 6 room capacity, one-active-Voice-Session-per-User coordination,
  move semantics, idle-room behavior, and Workspaces lifecycle notifications
  unchanged.
- Keep Phase 7 limited to ownership and signaling/runtime boundaries. Do not
  add RTP forwarding, room roster, browser reconnection, ICE restart,
  multi-user audio, or move rollback.

## Testing Decisions

- Good tests assert externally visible outcomes and resource lifetime, not
  private Session maps, Registry layout, process topology, or implementation
  callback arrangement. Tests should remain valid if the internal helper
  modules are reorganized.
- Use the authenticated Phoenix Channel integration seam for the complete
  browser-facing contract: join authorization, offer reply, client ICE reply,
  server ICE pushes, end-of-candidates, stale correlation rejection, terminal
  Channel close, and isolation between two joined connections.
- Extend the existing real ExWebRTC wrapper tests to prove PeerConnection
  startup, answer creation, Opus track provisioning, ICE application, RTP
  routing, connection-state translation, and `stop/1` cleanup.
- Extend the public `Voice` runtime tests to prove command routing through the
  canonical Voice Channel and Voice Session IDs, no command to a stale or
  cross-room Session, timeout normalization, Session failure cleanup, and
  replacement-session isolation.
- Add a focused Session/runtime test seam only where direct internal events or
  the readiness barrier cannot be observed through the Channel integration
  seam. A test process may act as the event sink; production code still sends
  directly to the Channel PID and does not use PubSub.
- Preserve the current synthetic ExWebRTC message technique for deterministic
  `:disconnected`, `:failed`, `:closed`, track, and RTP tests. Do not require a
  real browser or network failure to exercise those transitions.
- Verify startup ordering: successful admission has a ready Session-owned
  PeerConnection before occupancy is visible; startup failure has no committed
  membership and no running orphan PeerConnection.
- Verify negotiation state is serialized in the Session: early ICE is bounded
  and applied after the offer, duplicate offers are rejected, stale negotiation
  IDs cannot mutate state, and accepted-candidate limits remain enforced.
- Verify the existing wire contract is unchanged: answer replies contain the
  same Signaling Session ID, Negotiation ID, and serialized answer shape;
  server ICE pushes contain the same IDs and candidate/end marker shape; a
  terminal server peer failure closes the Channel instead of requiring a new
  browser event.
- Verify direct event isolation: two Channel connections in one Voice Channel
  receive only their own Session's ICE, terminal, and lifecycle events. No
  PubSub broadcast assertion should be needed for Phase 7 signaling.
- Verify cleanup convergence through public occupancy and process monitoring:
  normal Leave, Channel death, Session crash, PeerConnection terminal failure,
  command timeout, and room shutdown all remove exactly one Voice Session and
  stop its server PeerConnection without affecting another Session.
- Verify diagnostics remain metadata-only and exclude SDP, ICE candidate
  values, credentials, Signaling Session IDs, Negotiation IDs, PIDs, sockets,
  Users, Voice Channels, and raw RTP.
- Reuse the repository's existing `start_supervised!/1`, process-monitoring,
  `:sys.get_state/1`, Phoenix ChannelTest, and real ExWebRTC test conventions.
  Do not use sleeps as synchronization.
- Run focused Elixir and JavaScript tests during implementation and run the
  repository's `mix precommit` alias after all implementation changes.

## Out of Scope

- Changing Phoenix Channels to another signaling transport, replacing Phoenix
  signaling with PubSub, or allowing Voice.Session to call Phoenix socket APIs.
- New browser wire events, a new browser terminal-state protocol, or changes
  to the existing `voice_signaling.js` request/reply and server-ICE behavior
  beyond what is required to preserve it.
- Video, screen sharing, data channels, recording, transcription, mixing,
  transcoding, production media-server integration, or multi-user RTP
  forwarding. Those belong to later phases.
- Voice Channel rosters, speaking indicators, mute/deafen synchronization,
  moderator controls, room-wide signaling broadcasts, or PubSub-based media
  events.
- Automatic browser reconnect, ICE restart, perfect negotiation,
  renegotiation, Session resurrection, or recovery into an unknown WebRTC
  state.
- Transactional move rollback. The Phase 6 move policy remains: a full target
  preserves the current Voice Session; an available target whose new startup
  fails may leave the User in neither Voice Channel.
- Durable Voice Session records, persisted SDP/ICE state, database migrations,
  or changes to durable Workspace authorization.
- A production-configurable fake PeerConnection or general dependency
  injection framework.
- New public diagnostics, debug endpoints, raw WebRTC logging, or exposure of
  PIDs, credentials, SDP, ICE, or RTP.

## Further Notes

- The key architectural clarification is that Phoenix Channels remain the
  signaling road. `Voice.Session` is the server-side driver and owner at the
  end of that road, not a replacement signaling plane.
- The readiness barrier is required because the pinned ExWebRTC version uses a
  deferred startup path. The implementation may choose the concrete internal
  handshake, but the observable admission ordering is fixed.
- The direct event sink is intentionally one connection at a time. PubSub is
  a future room-wide fanout tool, not a safer or more appropriate transport for
  private ICE and terminal events.
- Existing Phase 4/5 browser and Phoenix contracts are the compatibility
  boundary. A successful implementation should be demonstrably different in
  process ownership while remaining indistinguishable to the browser except
  for improved lifecycle correctness.
- The two supporting research notes contain the primary-source citations and
  repository evidence behind these decisions.
