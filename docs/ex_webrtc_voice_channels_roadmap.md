# ExWebRTC Voice Channels Roadmap

Status: ready-for-agent
Owner: Stefan
Scope: audio-only workspace Voice Channels, server-routed through ExWebRTC, capped at 5 active Voice Sessions per Voice Channel
Related docs: `CLAUDE.md`, `AGENTS.md`, `CONTEXT.md`, `docs/webrtc_voice_channel_research.md`, `docs/adr/0009-model-conversation-kinds-with-shared-primary-key-subtypes.md`, `docs/adr/0016-use-exwebrtc-server-routed-voice-channels.md`, `docs/adr/0017-use-a-browser-wide-controller-for-phase-2-microphone-ownership.md`

## Decision

This project will build voice channels as an educational, Elixir-owned WebRTC
feature. The goal is not to outgrow dedicated media servers. The goal is to
learn Phoenix Channels, OTP supervision, runtime state ownership, WebRTC
signaling, ICE, RTP forwarding, cleanup, and observability inside a small,
bounded system.

Every browser session connects to one server-side `ExWebRTC.PeerConnection`.
Phoenix Channels carry signaling and control messages. Continuous audio flows
through WebRTC RTP/SRTP, not through LiveView, Phoenix Channels, or PubSub.

The first complete version is intentionally limited:

- audio only
- one workspace Voice Channel
- at most 5 active Voice Sessions per Voice Channel
- one browser session per voice session
- no recording
- no screen sharing
- no video
- no production-scale SFU promises

## Agent Operating Instructions

At the beginning of each phase, read this file, `CLAUDE.md`, `AGENTS.md`, and
only the linked docs needed for the phase. Do not reread every historical voice
note unless the phase explicitly asks for it.

When a phase is completed, update only that phase's `Implementation Notes` with:

- date completed
- files changed
- final architecture or API decisions
- behavior proven
- tests run
- known follow-up work

Keep notes concise. Prefer links to new ADRs, PRDs, tests, or issue files over
pasting long explanations here.

Each phase should leave the app compiling and the relevant tests green. When a
phase changes application behavior, finish with `mix precommit` unless the user
explicitly asks for a smaller verification pass.

## Architecture Boundaries

| Boundary | Owns | Does not own |
| --- | --- | --- |
| `DiscordClone.Workspaces` | durable Workspace resources, Voice Channel definitions, membership authorization, role/moderation policy | WebRTC protocol state, RTP routing, browser devices |
| `DiscordClone.Voice` | runtime Voice Channel rooms, Voice Sessions, signaling protocol shape, ExWebRTC lifecycle, forwarding state | durable workspace membership source of truth |
| `DiscordCloneWeb` | LiveView UI, Phoenix socket/channel adapters, JS hooks/modules | durable authorization rules, long-lived media state |
| Browser JS | microphone permission, `MediaStreamTrack` lifecycle, browser `RTCPeerConnection`, remote audio playback | workspace authorization, server-enforced moderation |
| Postgres/Ecto | durable Voice Channel identity, workspace association, ordering, permissions/config | active Voice Sessions, PIDs, ICE state, RTP routes, speaking state |

## Naming

Use `Voice Channel` for the durable workspace resource. Avoid overloading the
existing text-channel schema name, `DiscordClone.Workspaces.Channel`.

Suggested names:

- durable schema: `DiscordClone.Workspaces.VoiceChannel`
- runtime context: `DiscordClone.Voice`
- runtime room: `DiscordClone.Voice.RoomServer`
- runtime session: `DiscordClone.Voice.Session`
- RTP router: `DiscordClone.Voice.Forwarder`
- Phoenix transport: `DiscordCloneWeb.VoiceChannel`
- JS module/hook: `assets/js/hooks/voice_channel.js`

Before implementing durable data, decide whether Voice Channels are a new
`Conversation` subtype or a separate workspace resource. Text channels and DMs
use the shared `conversations` table because they share messages, sequencing,
read state, unread spans, and activity behavior. Voice Channels may not need
those mechanics.

## Signaling Contract

Client to server:

```text
voice_join
offer
ice_candidate
leave
mute_changed
deafen_changed
heartbeat
```

Server to client:

```text
joined
answer
ice_candidate
voice_session_joined
voice_session_left
mute_changed
deafen_changed
connection_state
error
```

Payloads must include a server-issued or server-validated `session_id`. SDP and
ICE payloads are routed, validated for shape, and logged carefully. Do not log
full SDP credentials or TURN credentials.

## Phase Progress

| Phase | Status | Completion date | Notes |
| --- | --- | --- | --- |
| 0. Architecture ADR | Complete | 2026-07-27 | `docs/adr/0016-use-exwebrtc-server-routed-voice-channels.md` |
| 1. Durable Voice Channel model | Complete | 2026-07-27 | Durable schema, scoped Workspaces API, and sidebar management UI. |
| 2. Browser microphone ownership spike | Complete | 2026-07-28 | Browser microphone ownership, lifecycle cleanup, Voice Owner Tab arbitration, and accessible controls are proven by focused JavaScript tests. |
| 3. Authenticated Phoenix signaling skeleton | Not started |  |  |
| 4. First browser-to-ExWebRTC PeerConnection | Manual localhost pass in progress | 2026-07-31 | Real signaling and terminal ICE coverage are green. After the voice socket began sending the page CSRF token, Chrome completed microphone permission, signaling, and browser-to-server connection; it also remained connected through app navigation and could be left globally. The required repeated-cycle proof remains. |
| 5. RTP echo experiment | Not started |  |  |
| 6. OTP Voice Channel Room and Session architecture | Complete | 2026-08-04 | Supervised room/session ownership, cross-room admission coordination, failure recovery, Phoenix delegation, and durable-access cleanup are complete; media remains intentionally scoped to Phases 7/8. |
| 7. Move echo into supervised `Voice.Session` | In progress | 2026-08-05 | Tickets 01–04 are complete; Tickets 05–06 remain before Phase 7 can close. |
| 8. Two-user server-routed audio | Not started |  |  |
| 9. Capped 3-5 user room | Not started |  |  |
| 10. Voice controls and UI polish | Not started |  |  |
| 11. Disconnects, cleanup, and recovery | Not started |  |  |
| 12. STUN/TURN and real-network deployment | Not started |  |  |
| 13. Automated testing layers | Not started |  |  |
| 14. Observability and performance limits | Not started |  |  |
| 15. Final docs and demonstration | Not started |  |  |

## Phase 0: Architecture ADR

Goal: document the ExWebRTC/server-routed decision and lock the learning scope
before implementation.

Build:

- ADR under `docs/adr/`
- control-plane diagram
- media-plane diagram
- process ownership table
- voice session state machine
- explicit deferral list
- hard 5-Voice Session cap
- initial dependency decision for `ex_webrtc`

Prove:

- Alice-to-Bob audio can be explained step by step
- browser-offer/server-answer signaling can be explained step by step
- every important state field has one owner

Implementation Notes:

```text
Completed 2026-07-27.
Files changed:
- CONTEXT.md
- docs/adr/0016-use-exwebrtc-server-routed-voice-channels.md
- docs/ex_webrtc_voice_channels_roadmap.md

Final decisions:
- Voice Channel is a separate durable Workspaces resource, not a Conversation subtype.
- Voice Session is runtime-only and represents one browser audio connection.
- One Voice Owner Tab owns a User's active Voice Session; other tabs may still use the app.
- Browser initiates SDP offer; ExWebRTC server PeerConnection answers.
- Phoenix Channel is the signaling adapter; Voice runtime owns long-lived state.
- RoomServer owns active Voice Sessions for one Voice Channel and enforces the hard 5-session cap.
- Session owns one server-side ExWebRTC PeerConnection.
- Forwarder performs selective RTP forwarding only: no mixing, transcoding, or recording.
- Mute/deafen are application/runtime state and do not trigger renegotiation.
- `ex_webrtc` is the chosen server-side WebRTC dependency, to be added and pinned in Phase 4.

Behavior proven:
- Alice-to-Bob audio can be explained step by step in ADR 0016.
- Browser-offer/server-answer signaling can be explained step by step in ADR 0016.
- Important durable, runtime, transport, browser, and Postgres state has one owner in ADR 0016.

Tests run:
- Not run; Phase 0 changed documentation and glossary only.

Known follow-up work:
- Phase 1 durable Voice Channel model.
- Phase 4 adds and pins the actual `ex_webrtc` dependency.
```

## Phase 1: Durable Voice Channel Model

Goal: users can create and view durable Voice Channels inside Workspaces without
any WebRTC runtime.

Build:

- migration generated with `mix ecto.gen.migration`
- durable `VoiceChannel` schema or documented `Conversation` subtype decision
- independent UUID primary key; no shared Conversation identity
- workspace association
- name, listed in creation order; persisted position and reordering are deferred
- reuse the existing Channel naming rules: normalized lowercase slug, 1–80 characters
- Voice Channel names are unique within a Workspace's Voice Channels but may match text Channel names
- context functions in `Workspaces`
- authorization through existing `current_scope` and Workspace Membership
- Workspace Owners and Admins may create Voice Channels; all Workspace Members may list them
- new Workspaces do not receive a default Voice Channel
- Workspace Owners may delete Voice Channels; deletion is included in Phase 1
- Workspace Owners and Admins may rename Voice Channels
- sidebar rendering in workspace/channel shells
- distinct Voice Channels sidebar section with owner/admin creation and owner-only deletion controls; no join control, roster, or WebRTC state
- Voice Channel rows are non-interactive in Phase 1; no Voice Channel route or placeholder destination
- schema/context/authorization tests

Prove:

- authorized Workspace Members can see Voice Channels
- authorized owners/admins can create Voice Channels if that matches current channel policy
- non-members and cross-workspace access are rejected
- no runtime process is required

Implementation Notes:

```text
Completed 2026-07-27.
Files changed:
- lib/discord_clone/workspaces.ex
- lib/discord_clone/workspaces/voice_channel.ex
- lib/discord_clone/workspaces/workspace.ex
- priv/repo/migrations/20260727130159_create_voice_channels.exs
- lib/discord_clone_web/live/workspace_live/shell.ex
- lib/discord_clone_web/live/channel_live/show.ex
- lib/discord_clone_web/live/workspace_live/audit_log.ex
- lib/discord_clone_web/live/workspace_live/invite_new.ex
- test/discord_clone/workspaces_test.exs
- test/discord_clone_web/live/workspace_live/home_management_test.exs

Final decisions:
- Voice Channel is a separate durable Workspaces resource with its own UUID,
  not a Conversation subtype.
- Workspace Owners and Admins can create and rename Voice Channels; Workspace
  Owners can delete them; Workspace Members can list them.
- Voice Channel rows remain non-interactive: there is no Voice Channel route,
  join control, roster, or runtime process in Phase 1.

Behavior proven:
- Scoped Workspace Members see only their workspace's Voice Channels.
- Voice Channel creation, validation, renaming, and owner-only deletion work
  from the authenticated workspace shell.

Tests run:
- Workspaces and workspace-shell LiveView coverage was added in the Phase 1
  implementation; the original commit does not record an exact test command.

Known follow-up work:
- Phase 2 browser microphone ownership spike.
```

## Phase 2: Browser Microphone Ownership Spike

Goal: prove browser-side microphone capture, mute, unmute, and release without
networking.

Build:

- external JS hook/module, not inline scripts
- `getUserMedia({audio: true})` on explicit user gesture
- permission pending, denied, no-device, and insecure-context states
- local mute using `MediaStreamTrack.enabled`
- full release using `MediaStreamTrack.stop()`
- hook cleanup on destroy/navigation
- visible UI states in LiveView

Prove:

- microphone capture works on localhost
- mute/unmute toggles capture behavior
- leaving releases the browser capture indicator
- permission failures are understandable

Implementation Notes:

```text
Completed 2026-07-28.

Files changed:
- `assets/js/app.js`
- `assets/js/hooks/voice_controller.js` and `voice_controller_test.mjs`
- `assets/js/hooks/voice_channels.js` and `voice_channels_test.mjs`
- `assets/js/hooks/voice_lifecycle.js` and `voice_lifecycle_test.mjs`
- `assets/js/hooks/voice_channel_indicator.js` and `voice_channel_indicator_test.mjs`
- `assets/js/hooks/voice_controls.js` and `voice_controls_test.mjs`
- `assets/js/hooks/voice_workspace_badge.js` and `voice_workspace_badge_test.mjs`
- `lib/discord_clone_web/components/global_destination_rail.ex`
- `lib/discord_clone_web/live/direct_messages_live/shell.ex`
- `lib/discord_clone_web/live/workspace_live/shell.ex`
- `test/discord_clone_web/live/direct_messages_destination_test.exs`
- `test/discord_clone_web/live/workspace_live/home_management_test.exs`
- `mix.exs`

Final architecture/API decisions:
- Browser capture is owned by a shared external `createVoiceController` and starts only from an explicit Voice Channel gesture.
- Local mute/unmute uses `MediaStreamTrack.enabled`; leave, teardown, logout, navigation, and stale or failed captures release tracks with `MediaStreamTrack.stop()`.
- Browser-wide Voice Owner Tab arbitration uses best-effort `BroadcastChannel` claims and is not a server authorization or media-ownership source.
- External hooks/modules own the browser integration and expose visible permission, error, capture, mute, and ownership states.

Behavior proven:
- Capture, mute/unmute, leave, page teardown, logout cleanup, and release of the browser microphone indicator.
- Understandable handling for pending permission, denied permission, no device, insecure context, unsupported browser, and externally ended microphone states.
- A newer browser tab can take ownership and release the previous tab's capture; same-tab coordination failure remains safe.

Tests run:
- `mix precommit` passed: 62 JavaScript tests and 929 ExUnit tests.
- Focused browser ownership coverage is in the `voice_controller`, `voice_channels`, `voice_lifecycle`, `voice_controls`, `voice_channel_indicator`, and `voice_workspace_badge` Node test suites.

Known follow-up work:
- Phase 3/4 integrate the browser controller with authenticated Phoenix signaling and server-side ExWebRTC.
```

## Phase 3: Authenticated Phoenix Signaling Skeleton

Goal: establish the control plane with fake SDP/ICE-shaped payloads.

Build:

- authenticated custom Phoenix socket, likely separate from `/live`
- `DiscordCloneWeb.VoiceChannel`
- topic format such as `voice:<voice_channel_id>`
- socket authentication that reconstructs or safely derives user scope
- topic authorization through `Workspaces`
- generated `session_id`
- validated message payloads
- fake `offer`, `answer`, `ice_candidate`, `leave`, and heartbeat routing
- Channel tests

Prove:

- unauthorized joins are rejected
- invalid payloads fail safely
- two tabs can exchange signaling-shaped messages
- every message is tied to a `session_id`

Implementation Notes:

```text
Completed 2026-08-04.

Files changed:
- `lib/discord_clone/application.ex`
- `lib/discord_clone/voice.ex`
- `lib/discord_clone/voice/forwarder.ex`
- `lib/discord_clone/voice/room_server.ex`
- `lib/discord_clone/voice/room_supervisor.ex`
- `lib/discord_clone/voice/session.ex`
- `lib/discord_clone/voice/session_coordinator.ex`
- `lib/discord_clone/voice/session_supervisor.ex`
- `lib/discord_clone/workspaces.ex`
- `lib/discord_clone_web/voice_channel.ex`
- `test/discord_clone/voice_test.exs`
- `test/discord_clone/workspaces_voice_lifecycle_test.exs`
- `test/discord_clone_web/voice_channel_test.exs`
- `test/discord_clone_web/voice_signaling/peer_connection_test.exs`

Final architecture/API decisions:
- `DiscordClone.Voice` is the stateless runtime facade. Dynamically started room trees are isolated per durable Voice Channel and supervise `RoomServer`, `SessionSupervisor`, and the `Forwarder` lifecycle boundary with `:one_for_all` room recovery.
- `RoomServer` owns canonical room membership, opaque Voice Session IDs, the five-session cap, and idempotent cleanup. Temporary Sessions monitor their signaling channels; empty rooms retire after the 30-second grace period.
- `SessionCoordinator` serializes one active Voice Session per User across rooms, preserves the current session when a target room is full, and fails closed during coordinator or room recovery.
- The authenticated Phoenix Voice Channel authorizes durable access and delegates runtime admission/leave to `Voice`. Workspaces sends lifecycle invalidations for revoked access and deleted Voice Channels; Voice does not query Workspaces.
- `Forwarder` is a supervised lifecycle boundary only. The proven one-peer media path remains unchanged until Phase 7, with multi-user RTP forwarding deferred to Phase 8.

Behavior proven:
- Dynamic room start/reuse, atomic admission and capacity enforcement, same-connection idempotency, cross-room moves, explicit and duplicate leave, signaling-channel death, Session failure, and idle shutdown.
- Room-core failure clears affected global membership coherently without resurrecting Sessions; unrelated rooms continue operating and the coordinator remains fail-closed when its index cannot be trusted.
- Authenticated Phoenix admission rejects unauthorized access, exposes only safe opaque outcomes, and delegates cleanup. Durable membership revocation and Voice Channel deletion terminate only the matching sessions and remove stale room/global state.

Tests run:
- `mix precommit` passed: 62 JavaScript tests and 929 ExUnit tests.
- Focused Voice OTP, Phoenix Voice Channel, and Workspaces lifecycle coverage passed, including room recovery, cross-room admission, channel termination, durable-access revocation, deletion cascades, and idle retirement.

Known follow-up work:
- Phase 7 moves the existing one-peer echo into supervised `Voice.Session`; Phase 8 adds multi-user RTP forwarding. Later phases cover the capped room UI, broader recovery policy, deployment, observability, and final documentation.
```

## Phase 4: First Browser-To-ExWebRTC PeerConnection

Goal: one browser and one server-side `ExWebRTC.PeerConnection` reach connected
on localhost.

Build:

- pinned `ex_webrtc` dependency
- ICE server config shape on browser and server
- browser `RTCPeerConnection`
- microphone track added to browser PeerConnection
- offer from browser to server
- ExWebRTC remote description, answer creation, local description
- trickle ICE in both directions
- connection-state logging
- clean close on leave

Prove:

- browser and server reach connected
- repeated join/leave does not leak obvious PeerConnection processes
- message shapes are documented for the pinned ExWebRTC version

Implementation Notes:

```text
Implemented through commit e9c2548 on 2026-07-31. A 2026-07-31 Chrome
localhost pass subsequently exposed and fixed the admission blocker: Phoenix
requires the page CSRF token before it will make a cookie session available to
the separate `/voice` WebSocket. The client now supplies that token when it
creates the voice socket.

Files changed in Ticket 04:
- assets/js/voice_peer_attempt.js
- assets/js/voice_peer_attempt_test.mjs
- lib/discord_clone_web/voice_channel.ex
- lib/discord_clone_web/voice_signaling/peer_connection.ex
- test/discord_clone_web/voice_channel_test.exs
- test/discord_clone_web/voice_signaling/peer_connection_test.exs

Final decisions:
- ExWebRTC v0.17.0 signals completed local ICE gathering with
  {:ice_gathering_state_change, :complete}; the Channel projects that to the
  existing correlated {end_of_candidates: true} wire envelope.
- ExWebRTC accepts the remote terminal marker as an ICECandidate whose
  candidate field is the empty string. The browser converts the correlated
  envelope back to {candidate: ""}, both before and after it applies the
  answer.
- No SDP, ICE payload, credential, Signaling Session ID, Negotiation ID, raw
  params, socket, User, or Voice Channel data is emitted as diagnostics.

Behavior proven automatically:
- The focused ExWebRTC test observes an actual server gathering-complete event
  from a supervised PeerConnection and verifies the empty remote candidate.
- Server ICE is session- and negotiation-correlated, topic-subscriber-isolated,
  and has 16 pending / 64 accepted candidate limits.
- Browser ICE queues are bounded, preserve arrival order, and are discarded on
  Leave or terminal cleanup. Failed and closed remain terminal; disconnected
  remains non-terminal.

Tests run:
- mix precommit (54 Node tests, 887 ExUnit tests; passed). The suite emitted
  known parallel Postgrex sandbox-disconnect log noise without test failures.
- Focused post-fix tests: `node --test assets/js/voice_signaling_test.mjs`
  (3 passing) and `mix test test/discord_clone_web/voice_channel_test.exs`
  (10 passing).

Manual observations:
- Chrome prompted for microphone permission, proceeded rapidly through joining,
  and reached `connected` with the server.
- The connection remained active while navigating the app and could be left
  from any app location.

Known follow-up work:
- Complete the localhost proof: verify both endpoints reach `connected` in
  each of three Join/Leave cycles and inspect for retained PeerConnection
  processes after every leave.
- Exercise and record manual permission-denial, navigation-persistence, and
  failure-path observations in that same browser.
```

## Phase 5: RTP Echo Experiment

Goal: prove the complete media path before room forwarding.

Build:

- observe incoming audio track in ExWebRTC
- count incoming RTP packets
- create outgoing server audio track
- forward incoming RTP back to the same browser as an echo diagnostic
- browser remote track handling and audio playback
- autoplay handling via Join Voice user gesture

Prove:

- Elixir receives microphone RTP
- browser receives a remote audio track
- echo works with headphones
- cleanup is repeatable

Implementation Notes:

```text
Ticket 01 implemented on 2026-07-31: the authenticated Voice Channel now
validates one negotiated Opus microphone source, attaches its server echo track
before creating the initial answer, directly routes only admitted inbound RTP,
and emits non-identifying aggregate media diagnostics. Ticket 02 made the
Voice Owner Tab own remote audio attachment and playback fallback. Ticket 03
keeps local mute/unmute on that established connection, treats silence and
`disconnected` as non-terminal, and terminates server peer failures cleanly.

Automated evidence:
- Browser controller tests prove mute/unmute changes the existing microphone
  track without another capture request or Voice connection attempt; existing
  attempt tests cover remote playback, signaling closure, terminal peer states,
  and idempotent remote-audio release.
- Authenticated Voice Channel tests prove a `disconnected` server peer remains
  available while `failed` releases the Channel-owned PeerConnection. Existing
  media diagnostics tests assert aggregate counters and reject identifying
  signaling/media metadata.

Localhost headphone checklist:
1. With headphones connected, join a Voice Channel and confirm browser and
   server connection state reach `connected`.
2. Confirm the browser attaches and plays the remote echo track, then speak and
   confirm audible echo.
3. Mute: confirm echo stops; unmute: confirm echo resumes without a new
   permission prompt, Join action, or connection transition.
4. Leave: confirm microphone capture and remote playback stop; rejoin and
   repeat the connected/echo checks to confirm a clean new attempt.

Manual result — 2026-07-31, browser not recorded: PASS. The localhost
headphone run reached connected state, attached and played the remote echo,
produced audible echo, muted and unmuted on the same connection, released
capture/playback on leave, and rejoined cleanly.
```

## Phase 6: OTP Voice Channel Room And Session Architecture

Goal: create supervised runtime ownership independent of the echo spike.

Build:

- `Voice.RoomRegistry`
- `Voice.RoomSupervisor` or room dynamic supervisor structure
- `Voice.RoomServer`
- `Voice.Session`
- `Voice.Forwarder`
- get-or-start room API
- canonical active membership in `RoomServer`
- session PID/user/session maps
- idempotent join/leave
- monitor relationships and restart policy
- idle shutdown
- OTP tests

Prove:

- rooms start dynamically
- sessions start dynamically
- last leave triggers idle policy
- duplicate cleanup is safe
- crashes do not leave canonical membership wrong

Implementation Notes:

```text
In progress as of 2026-08-05.

Completed Tickets 01–04:
- `923b473` moved PeerConnection ownership, negotiation, and media state into
  `Voice.Session`.
- `d3b3980` and `238a320` certified Session-routed offers and ICE.
- `8ff825b` certified the Session-owned one-peer RTP echo: the negotiated
  outbound track carries the accepted RTP packet, unsupported media is safely
  dropped, media counters remain Session-owned, and diagnostics are
  metadata-only.

Behavior proven:
- The authenticated browser signaling path remains a thin transport adapter;
  raw RTP, ExWebRTC media messages, track identity, and media counters do not
  cross into `DiscordCloneWeb.VoiceChannel`.
- Wrapper and authenticated Channel tests prove accepted Opus RTP routing,
  expected safe drops, counter accumulation, foreign-peer isolation, and
  telemetry allow-listing.

Tests run:
- Focused media/runtime suite: 70 tests, 0 failures with `--max-cases 1`.
- `mix precommit`: 62 JavaScript and 949 Elixir tests passed.

Known follow-up work:
- Complete Tickets 05 and 06 in `.scratch/voice-channel-phase-7/issues/`.
- Mark Phase 7 Complete only after those tickets pass their final certification.
```

## Phase 7: Move Echo Into Supervised `Voice.Session`

Goal: make the working one-peer echo run through supervised runtime ownership.

Build:

- `Voice.Session` owns one ExWebRTC PeerConnection
- Phoenix Channel routes offers/ICE to `Voice.Session`
- ExWebRTC events route back to the correct Channel
- Channel process is monitored
- PeerConnection failure triggers cleanup
- echo diagnostic mode remains available

Prove:

- echo still works
- Phoenix Channel is a thin transport adapter
- `Voice.Session` owns the WebRTC lifecycle
- Channel death cleans up the session

Implementation Notes:

```text
Not started.
```

## Phase 8: Two-User Server-Routed Audio

Goal: Alice and Bob hear each other through the Elixir forwarding layer.

Build:

- one server PeerConnection per Voice Session
- incoming source track identification
- destination outgoing track mapping
- `Voice.Forwarder` routing graph
- RTP fan-out with no self-forwarding
- route removal on leave
- both join orders
- reconnect and late RTP handling

Prove:

- Alice hears Bob
- Bob hears Alice
- neither hears their own forwarded audio
- one Voice Session failure does not corrupt the other

Implementation Notes:

```text
Not started.
```

## Phase 9: Capped 3-5 User Room

Goal: generalize two-user forwarding to the hard room cap.

Build:

- complete source-to-destination routing matrix
- hard capacity enforcement
- dynamic track or preallocated transceiver decision
- route/slot cleanup
- simultaneous join handling
- leave during negotiation
- forwarding invariant tests

Prove:

- up to 5 Voice Sessions can join in any order
- everyone hears allowed active speakers
- nobody hears themselves
- leaving does not break remaining users
- performance limits are documented from measurement

Implementation Notes:

```text
Not started.
```

## Phase 10: Voice Controls And UI Polish

Goal: make the technical room feel like a normal Discord-like voice feature.

Build:

- join/leave controls
- connecting/connected/disconnected/failed states
- Voice Session list
- local mute
- local deafen
- server-enforced mute
- moderator disconnect
- speaking indicators
- accessible labels and keyboard-friendly controls

Prove:

- controls are obvious
- local mute/deafen work
- server mute cannot be bypassed by modified client metadata
- Voice Session state stays synchronized

Implementation Notes:

```text
Not started.
```

## Phase 11: Disconnects, Cleanup, And Recovery

Goal: eliminate ghost Voice Sessions, stale routes, orphan PeerConnections, and
permanently empty rooms.

Build:

- cleanup invariants
- explicit leave
- Channel death handling
- LiveView disconnect/reconnect policy
- tab close/page refresh policy
- PeerConnection failed/disconnected handling
- duplicate join/leave policy
- heartbeat expiry
- late SDP/ICE/RTP handling
- crash-injection tests

Prove:

- cleanup is idempotent
- every failure case has a documented response
- no stale membership, route, slot, PeerConnection, or browser track remains
- remaining users continue where appropriate

Implementation Notes:

```text
Not started.
```

## Phase 12: STUN/TURN And Real-Network Deployment

Goal: make the feature work beyond localhost and same-machine tabs.

Build:

- environment-based ICE configuration
- STUN config
- TURN config and credential handling
- HTTPS/WSS requirements
- safe candidate-pair logging
- TURN-only diagnostic mode
- deployment port/firewall notes
- same LAN, different network, home/mobile, and restrictive network tests

Prove:

- direct connectivity works when available
- TURN-relayed connectivity works when needed
- secure browser requirements are met
- operational requirements are documented

Implementation Notes:

```text
Not started.
```

## Phase 13: Automated Testing Layers

Goal: test state and lifecycle without depending only on manual browser calls.

Build:

- pure routing matrix tests
- capacity tests
- slot-allocation tests if needed
- OTP room/session lifecycle tests
- Channel auth/payload tests
- ExWebRTC integration tests where stable enough
- manual browser test checklist

Prove:

- room state can be tested without microphones
- routing can be tested deterministically
- cleanup failure cases are covered
- flaky timing is controlled with monitors or state synchronization

Implementation Notes:

```text
Not started.
```

## Phase 14: Observability And Performance Limits

Goal: make failures explainable and limits explicit.

Build:

- structured log metadata
- active room/session metrics
- PeerConnection/ICE state counts
- join-to-connected duration
- RTP received/forwarded/dropped counts
- TURN usage signal where available
- `Voice.Forwarder` mailbox length checks
- CPU/bandwidth measurements for 2-user and 5-user rooms

Prove:

- failures can be localized by layer
- mailbox pressure is visible
- supported Voice Session and Voice Channel limits are documented
- sensitive SDP/TURN credentials are not logged

Implementation Notes:

```text
Not started.
```

## Phase 15: Final Docs And Demonstration

Goal: make the complete feature understandable to another engineer.

Build:

- final architecture diagram
- signaling sequence
- media-flow diagram
- supervision tree
- state ownership table
- session state machine
- join/leave/cleanup sequence
- failure matrix
- testing guide
- deployment guide
- troubleshooting guide
- known limitations
- demo script

Prove:

- another engineer can follow the system without reading every implementation file
- the feature can be demonstrated reliably
- known limits are explicit

Implementation Notes:

```text
Not started.
```
