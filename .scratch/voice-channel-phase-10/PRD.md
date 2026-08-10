# Phase 10: Voice Controls and UI Polish

Status: ready-for-agent

## Problem Statement

Voice Channels now provide working server-routed audio for up to five active
Voice Sessions, but the interface still exposes mostly technical connection
controls. A Workspace Member cannot reliably see who is in a Voice Channel,
who is currently speaking, or whether another User is unavailable because they
are muted or deafened. Owners and admins also lack Voice-specific moderation
from the live Voice Channel surface.

The feature needs to feel like a small Discord-like voice experience without
changing the established durable Workspace moderation model or the bounded
server-routed media architecture.

## Solution

Add a live Voice Channel Roster beneath every Voice Channel in a Workspace
sidebar. Each roster displays active Voice Sessions in admission order with the
existing username-initial avatar treatment, username, effective muted/deafened
badges, and a subtle Speaking Indicator. The roster updates from tiny,
full-per-channel snapshots whenever membership or shared Voice state changes,
without a page refresh.

Replace the hidden active-voice popover as the primary control surface with a
persistent Voice Connection Panel visible while a User has an active Voice
Session. It provides Local Mute, Local Deafen, and Leave across navigation.

Extend existing Workspace moderation into Voice: a Workspace Mute blocks a
User's outgoing audio at the server but allows them to remain as an Audio
Destination; a Workspace Timeout ends their Voice Session and blocks admission
until expiry. Owners and admins reuse their existing permitted roster action
menu and gain Voice Disconnect, which silently ends only the target's current
Voice Session.

## User Stories

1. As a Workspace Member, I want to see who is in every Voice Channel, so that I can choose where to join.
2. As a Workspace Member, I want roster members ordered by when they joined, so that the list remains stable and understandable.
3. As a Workspace Member, I want each roster row to show the familiar initial avatar and username, so that I recognize people consistently across the app.
4. As a Workspace Member, I want a roster member to appear immediately when they join, so that I do not need to refresh.
5. As a Workspace Member, I want a roster member to disappear immediately when they leave or lose their Voice Session, so that I do not talk to someone who has gone.
6. As a Workspace Member, I want to see a muted badge when another User is not transmitting, so that I understand why they cannot respond by voice.
7. As a Workspace Member, I want to see a deafened badge when another User is not hearing the Voice Channel, so that I do not keep talking into the void.
8. As a Workspace Member, I want the public muted badge to look the same for Local Mute and Workspace Mute, so that private moderation reasons are not exposed.
9. As a Workspace Member, I want a subtle speaking ring around an active speaker, so that I can follow a small group conversation visually.
10. As a Workspace Member, I want speaking state to fade shortly after speech stops, so that the roster does not flicker.
11. As a Voice Owner Tab User, I want a persistent Voice Connection Panel across navigation, so that my controls remain easy to find.
12. As a Voice Owner Tab User, I want Local Mute to stop my outgoing microphone audio without leaving the Voice Channel.
13. As a Voice Owner Tab User, I want Local Deafen to silence remote playback and enable Local Mute, so that I can opt out of listening and transmitting quickly.
14. As a Voice Owner Tab User, I want undeafening to leave Local Mute enabled, so that resuming playback never resumes transmission unexpectedly.
15. As a Voice Owner Tab User, I want my Local Mute and Local Deafen states reflected in the roster, so that other people can interpret my availability.
16. As a Workspace Member, I want a short join/leave cue whenever a User enters or exits my Voice Channel, so that room changes are noticeable without visual attention.
17. As a Workspace Member, I want join/leave cues enabled by default without an in-app toggle, so that the initial experience stays simple.
18. As a muted User, I want to remain able to hear other Audio Sources, so that Workspace Mute is a participation restriction rather than removal.
19. As a muted User, I want modified browser metadata to be unable to restore my outgoing audio, so that Workspace Mute is server-enforced.
20. As a timed-out User, I want my current Voice Session to end and Voice joins to remain unavailable until expiry, so that timeout consistently blocks participation.
21. As a User whose timeout expires, I want ordinary Voice admission to become available again, so that temporary moderation ends automatically.
22. As an owner or admin, I want to use my existing permitted Workspace Member actions from a roster row, so that moderation policy stays consistent.
23. As an owner or admin, I want to Voice Disconnect a permitted target, so that I can remove disruption from the current Voice Channel without changing Workspace membership.
24. As a User who is Voice Disconnected, I want browser and server media resources to be released cleanly, so that I do not retain a ghost Voice Session.
25. As a User who is Voice Disconnected, I accept no special reason, popup, notification, or retry prompt in this phase, so that explanatory Voice signals remain a later feature.
26. As an eligible User after Voice Disconnect cleanup, I want the ordinary Join control to remain available, so that Voice Disconnect is not a timeout or kick.
27. As a Workspace Member, I want an interrupted non-terminal connection to show an honest interrupted state, so that I do not confuse it with leaving.
28. As a Workspace Member, I want a terminal failed connection to return to the normal Join state, so that recovery policy is not implied before Phase 11.
29. As a regular Workspace Member, I want roster rows to be non-clickable, so that the roster stays focused on Voice awareness rather than unbuilt profile features.
30. As an operator, I want live roster payloads to exclude PIDs, PeerConnection handles, SDP, ICE data, and raw RTP, so that UI synchronization does not expose runtime internals.

## Implementation Decisions

- Preserve ownership boundaries. `DiscordClone.Voice` owns live Voice Session,
  effective voice-state, and roster-snapshot publication; `Workspaces` owns
  durable User identity, authorization, and Workspace Mute/Timeout policy;
  the web layer renders authorized projections; the Voice Owner Tab owns local
  capture, playback, Local Mute/Deafen, and join/leave sounds.
- Add no durable schema. Voice Channel Rosters, speaking state, Local
  Mute/Deafen, and Voice Disconnect are runtime state.
- Publish a complete, safe roster snapshot for the affected Voice Channel on
  every membership or shared-state transition. A snapshot contains only the
  Voice Session/User identity needed by an authorized Workspace view plus
  effective muted, deafened, and speaking state. With a five-Session cap,
  snapshots are intentionally preferred over deltas to avoid stale UI.
- Workspace views subscribe while connected and resolve roster User display
  identity through their existing authorized Workspace data. Voice does not
  query or own profiles, and runtime process identities never cross the
  projection boundary.
- Render every Voice Channel's roster directly below that Voice Channel in the
  Workspace sidebar. Keep the row order equal to Voice Session admission order
  until the Session ends. Reuse the existing initial-avatar visual language;
  do not add profile images or profile popovers.
- The public roster shows only effective muted/deafened/speaking availability.
  It must not disclose whether muted is voluntary or moderated, moderation
  reasons, timeout details, or moderator identity. The affected User sees their
  own moderation explanation; authorized moderators retain existing action
  affordances.
- Local Mute and Local Deafen are browser-originated shared Voice state that is
  correlated to the active Voice Session. Local Deafen silences all remote
  playback and enables Local Mute; undeafening does not unmute. All shared
  states disappear immediately when the Voice Session ends.
- Negotiate and read the standard RTP audio-level extension for Speaking
  Indicators. The runtime derives speaking from audio activity above a
  conservative threshold and keeps it active for a 600 ms decay window.
  If the extension is unavailable, accepted RTP activity is a non-blocking,
  less precise fallback. This signal is presentational only and never grants
  permission to forward audio.
- Workspace Mute is authoritative at the server. It suppresses outbound audio
  regardless of local state or modified client signaling while leaving the
  target Voice Session connected as an Audio Destination. Unmuting restores
  normal eligibility without renegotiation when the Session remains active.
- Workspace Timeout is authoritative at the server. Applying it ends any
  matching Voice Session and prevents new Voice admission until the durable
  timeout is inactive; expiry restores ordinary eligibility.
- Reuse the existing Workspace Member action authorization and menu behavior
  on roster rows. Add Voice Disconnect only for permitted owner/admin targets;
  self and owner targets remain unavailable under existing moderation rules.
- Voice Disconnect ends exactly the target's current Voice Session and follows
  normal route, signaling, capture, and playback cleanup. It changes neither
  Workspace membership nor durable moderation state, is silent to the target,
  and does not add a special rejoin prompt. The ordinary Join affordance remains
  available once cleanup finishes.
- Replace the global popover as the primary active-Voice UI with a persistent
  Voice Connection Panel containing the current Voice Channel, Local Mute,
  Local Deafen, and Leave. It remains available across app navigation.
- Surface connecting, connected, interrupted, and terminal failure honestly.
  Interrupted remains non-terminal with ordinary controls and no Phase 10
  recovery promise. Terminal failure cleans up and returns to normal Join;
  reconnect/ICE restart policy remains Phase 11 work.
- Play a short browser-local cue to all current Voice Owner Tabs in the affected
  Voice Channel when a roster member joins or leaves. Do not add an in-app
  preference, generated voice announcement, system-message timeline entry, or
  notification center item.

## Testing Decisions

- Test observable behavior at the highest existing seams: the authenticated
  Workspace LiveView for roster and action visibility, the public
  `DiscordClone.Voice` facade for Voice Session/moderation lifecycle behavior,
  and the browser Voice Owner Tab controller for local controls, playback, and
  sounds. Do not test private GenServer maps, PIDs, helper calls, or message
  ordering.
- Extend existing Voice runtime and authenticated signaling tests to prove full
  roster snapshots after admission, leave, terminal cleanup, Local
  Mute/Deafen changes, effective Workspace Mute changes, timeout application,
  timeout expiry, and Voice Disconnect. Assert no runtime/media-sensitive data
  appears in the browser-facing projection.
- Extend existing Workspace LiveView and member-action tests to prove every
  Voice Channel shows its own admission-ordered roster; authorized members see
  immediate joins/leaves; regular members do not get action menus; owner/admin
  menus preserve existing authorization and add only permitted Voice Disconnect.
- Extend the existing browser controller/control/peer-attempt tests to prove
  Local Mute, Local Deafen, undeafen-stays-muted, public state publication,
  persistent panel behavior across navigation, interrupted/failed presentation,
  resource cleanup, and join/leave cue playback for affected Voice Owner Tabs.
- Test Workspace Mute at the public Voice boundary by proving outgoing audio is
  rejected even when a client claims an unmuted state, while inbound playback
  remains available. Test Timeout by proving active Session termination and
  blocked admission until the durable moderation state expires.
- Test Speaking Indicator behavior with known audio-level inputs, threshold
  crossing, 600 ms decay, fallback accepted-RTP activity, immediate clearing on
  Session termination, and no authorization effect.
- Tests remain behavior-focused and deterministic. Use existing supervision,
  monitors, and synchronization helpers rather than sleeps or process-liveness
  polling. Prior art includes the Phase 9 Voice/Forwarder/Session tests,
  authenticated Voice Channel tests, Workspace moderation tests, and browser
  Voice controller/controls tests.
- Run focused Voice, Workspaces, LiveView, and browser tests during work, then
  finish with `mix precommit`. A manual two-browser pass verifies roster
  appearance/disappearance, public badges, speaking rings, persistent controls,
  moderation consequences, and join/leave cues.

## Out of Scope

- Voice reconnect, ICE restart, automatic rejoin, heartbeat/recovery policy,
  and broader disconnect handling (Phase 11).
- STUN/TURN configuration and real-network deployment (Phase 12).
- Profile images, profile popovers, user cards, text/system messages, push
  notifications, generated spoken announcements, or an in-app voice-sound
  preference.
- Detailed reason/moderator attribution for Voice Disconnect or public
  disclosure of moderation reasons and timeout details.
- Audio mixing, decoding, transcription, recording, video, screen sharing,
  dynamic renegotiation, and changes to the five-Voice-Session cap.
- Production observability and performance-limit expansion beyond existing safe
  diagnostics (Phase 14).

## Further Notes

- Vocabulary follows `CONTEXT.md`: Voice Channel Roster, Local Mute, Local
  Deafen, Workspace Mute, Workspace Timeout, Voice Disconnect, and Speaking
  Indicator. Do not call the roster a voice room or participant list.
- The existing moderation model permits owners and admins to moderate admins
  and members, never themselves or an owner. Phase 10 inherits that policy.
- No ADR is required: this phase extends established Voice, Workspace
  moderation, and browser ownership boundaries rather than choosing a new
  durable architecture.
