# Phase 9: Capped 3–5 User Room

Status: ready-for-agent

## Problem Statement

The project has a working two-User server-routed Voice Channel. Each admitted
Voice Session owns one server-side ExWebRTC PeerConnection, and the room-local
Forwarder can send one accepted Audio Source to the other ready Audio
Destination.

That implementation deliberately stops forwarding when a Voice Channel has
three or more active Voice Sessions. The hard five-Voice-Session admission cap
already exists, but the media plane does not yet provide the expected group
conversation: every User should hear every other active User, without hearing
their own audio.

The next phase must extend the existing ownership and cleanup boundaries rather
than introduce a second media architecture. It must also handle the browser
fact that a destination needs a separate receiving track for each possible
other source. A single mixed or shared track would hide source boundaries and
conflict with the project's decision to keep routing in Elixir without mixing.

## Solution

Give every Voice Session four fixed Audio Output Slots during its initial
WebRTC negotiation. Each slot represents one possible other Voice Session in
the five-Session room cap and is backed by its own negotiated outbound audio
track.

The media path remains:

Audio Source → room-local Forwarder → destination Audio Output Slot →
destination browser audio track

The Forwarder creates the complete directed matrix for the ready Voice
Sessions. A room with `N` eligible Voice Sessions has `N × (N - 1)` routes, up
to 20 routes at the five-Session cap. No route targets the source's own Voice
Session.

The browser preflights and creates the microphone connection plus four
receive-only audio lanes before requesting admission. The server validates the
same four-lane requirement from the offer and attaches the four outbound
tracks before returning the answer. Later joins and leaves change which source
feeds a slot; they do not require renegotiation.

The Voice Owner Tab keeps one stable aggregate `MediaStream` and one
controller-owned `<audio>` element. Each received remote `MediaStreamTrack`
remains separate and keeps its own browser identity and lifecycle. The browser
combines the tracks only for playback; the server's Audio Sources, Audio
Routes, and Audio Output Slot assignments remain separate.

If a browser cannot provide all four Audio Output Slots, the Voice join fails
with a clear, retryable compatibility error. The attempted Voice Session is
cleaned up completely, and the browser waits for an explicit User retry rather
than retrying in a loop.

## User Stories

1. As a Workspace Member, I want to join a Voice Channel with up to five
   active Voice Sessions, so that the room supports a small group conversation.
2. As a Workspace Member, I want the existing five-Voice-Session capacity to
   remain enforced, so that the room has a clear and bounded limit.
3. As a Workspace Member, I want the first Voice Session to hear no audio
   while alone, so that I never mistake a self-echo diagnostic for a group
   conversation.
4. As a Workspace Member, I want a three-person room to deliver each person's
   audio to the other two people, so that every participant can participate.
5. As a Workspace Member, I want a five-person room to deliver each person's
   audio to the other four people, so that the maximum room is fully connected.
6. As a Workspace Member, I want never to hear my own forwarded audio, so that
   the room does not create a self-route.
7. As a Workspace Member, I want each other person's audio to remain a
   separate audio source, so that one person's route cannot overwrite or
   impersonate another person's route.
8. As a Workspace Member, I want audio between two ready Voice Sessions to
   start even while a third Voice Session is still connecting, so that one
   slow negotiation does not interrupt people who are already connected.
9. As a Workspace Member, I want a newly ready Voice Session to begin sending
   to and receiving from the other ready Sessions without restarting the room,
   so that joining feels incremental.
10. As a Workspace Member, I want a Voice Session that is still negotiating to
    contribute no audio until it is ready, so that incomplete setup cannot
    create stale or invalid routes.
11. As a Workspace Member, I want four Audio Output Slots reserved during the
    initial negotiation, so that later Users can join without renegotiating my
    browser connection.
12. As a Workspace Member, I want each Audio Output Slot to have a fixed
    position for the life of my Voice Session, so that the browser can keep
    track identities stable.
13. As a Workspace Member, I want an unused Audio Output Slot to remain
    connected but silent, so that it can be used later without another browser
    negotiation.
14. As a Workspace Member, I want a departing source's slot to become
    available, so that a later source can use it.
15. As a Workspace Member, I want existing sources to stay in their current
    slots when another User joins or leaves, so that audio does not unexpectedly
    move between browser tracks.
16. As a Workspace Member, I want a new source to use the first available slot,
    so that slot assignment is predictable.
17. As a Workspace Member, I want one person's departure to stop their audio
    immediately for everyone else, so that no audio continues after leave.
18. As a Workspace Member, I want the remaining Voice Sessions to continue
    hearing one another after someone leaves, so that one departure does not
    break the room.
19. As a Workspace Member, I want a microphone track that becomes muted to
    retain its routes, so that temporary silence does not require reconnection.
20. As a Workspace Member, I want an ended microphone track to stop sending to
    every destination, so that an old track cannot resume unexpectedly.
21. As a Workspace Member, I want RTP that arrives after a source leaves to be
    discarded, so that late packets cannot reach a stopped or replacement
    Voice Session.
22. As a Workspace Member, I want leaving during negotiation to end my Voice
    Session immediately, so that the room does not wait for an unfinished
    connection.
23. As a Workspace Member, I want late offers, ICE candidates, and RTP from a
    departed Voice Session to be ignored, so that stale browser work cannot
    affect the room.
24. As a Workspace Member, I want a failed Voice Session to lose only its own
    routes, so that healthy Voice Sessions continue exchanging audio.
25. As a Workspace Member, I want a replacement Voice Session for the same
    User not to receive late audio intended for the old Session, so that a
    reconnect cannot inherit stale media.
26. As a Workspace Member, I want a full room to return a clear room-full
    result, so that I understand why I was not admitted.
27. As a Workspace Member, I want simultaneous joins to admit no more than
    five Voice Sessions, so that concurrency cannot bypass the room cap.
28. As a Workspace Member, I want the first five processed joins to remain in
    the room, so that the server never removes an existing User to make room
    for a later request.
29. As a Workspace Member, I want my browser to verify that it can create all
    four Audio Output Slots before asking the server to admit me, so that a
    local compatibility failure does not create a partial Voice Session.
30. As a Workspace Member, I want the server to validate the four-slot offer,
    so that a modified or incompatible client cannot claim a media capability
    it does not have.
31. As a Workspace Member, I want an unsupported four-slot join to fail with a
    clear retryable compatibility error, so that I know what must be corrected.
32. As a Workspace Member, I want a failed compatibility attempt to release
    microphone, browser PeerConnection, signaling, and server Session resources,
    so that I can safely try again.
33. As a Workspace Member, I want an explicit “Try again” action, so that the
    browser does not retry endlessly while I correct permissions, device, or
    browser problems.
34. As a Workspace Member, I want all four remote tracks added to one stable
    playback `MediaStream`, so that one controller-owned audio element can play
    the room.
35. As a Workspace Member, I want each remote `MediaStreamTrack` to remain
    separately identifiable in the browser, so that adding one source does not
    replace another source's track.
36. As a Workspace Member, I want releasing a slot to remove or silence only
    that slot's browser track, so that other sources keep playing.
37. As a Workspace Member, I want the browser to use only local slot and track
    identities in Phase 9, so that runtime User and Voice Session identifiers
    are not exposed through the playback API.
38. As a Workspace Member, I want the server to forward compatible Opus audio
    without mixing or transcoding, so that the implementation remains bounded
    and understandable.
39. As a Workspace Member, I want packets to be forwarded asynchronously, so
    that high-frequency media does not block browser-originated signaling
    commands.
40. As a Workspace Member, I accept that packets which arrive during a missing
    route or cleanup race are dropped, so that the system does not buffer stale
    audio for later playback.
41. As an implementer, I want the Forwarder to own the complete Audio Route
    matrix, so that Sessions do not maintain competing destination maps.
42. As an implementer, I want an Audio Route to identify its source by the
    Voice Session ID and accepted inbound track, so that identical track IDs in
    different PeerConnections cannot collide.
43. As an implementer, I want an Audio Route to target a destination Voice
    Session and Audio Output Slot, so that one destination can receive all
    other sources on separate tracks.
44. As an implementer, I want PIDs, PeerConnection handles, and outbound track
    IDs to remain private delivery details, so that runtime implementation
    details do not become domain or browser identities.
45. As an implementer, I want the Forwarder to keep a source in the same slot
    while it remains active, so that route updates do not disturb existing
    playback.
46. As an implementer, I want route assignment to be idempotent, so that
    duplicate readiness or cleanup messages do not create duplicate routes or
    corrupt slot state.
47. As an implementer, I want route creation to depend only on the source and
    destination being eligible, so that unrelated unready Sessions do not
    block the room.
48. As an implementer, I want every room size from one through five covered by
    route-invariant tests, so that the matrix does not work only at its maximum
    size by accident.
49. As an implementer, I want a real five-Session ExWebRTC proof, so that the
    test suite validates actual negotiated outbound tracks rather than only
    Forwarder state.
50. As an implementer, I want a manual browser pass with five separately
    authenticated Users, so that aggregate playback is proven in a real
    browser.
51. As an operator, I want aggregate forwarded and dropped packet counts, so
    that the maximum room's media behavior can be measured without logging raw
    media.
52. As an operator, I want CPU and bandwidth measurements for the five-Session
    room, so that the project's supported educational limit is documented from
    evidence.
53. As an operator, I want SDP, ICE credentials, raw RTP, PIDs, User identity,
    Voice Channel identity, and browser correlation data excluded from
    diagnostics, so that observability does not expose sensitive runtime data.

## Implementation Decisions

- Preserve the existing architecture: `DiscordClone.Voice` remains the
  runtime facade, `RoomServer` remains the canonical room membership and
  capacity owner, `Voice.Session` remains the owner of one server-side
  ExWebRTC PeerConnection, and `Voice.Forwarder` remains the sole owner of
  Audio Route policy.
- Keep the hard capacity at five active Voice Sessions per Voice Channel.
  RoomServer continues to serialize admission. The first five processed joins
  succeed, the next receives the normal room-full result, and no existing
  Voice Session is displaced.
- Give each Voice Session four fixed Audio Output Slots for its lifetime. The
  four slots represent the four possible other Voice Sessions in the capped
  room.
- During the initial browser negotiation, create the microphone media
  connection and four receive-only audio lanes. The browser must preflight all
  four lanes before requesting server admission.
- The server must validate that the received offer provides all four usable
  Audio Output Slots before committing the Voice Session to the room. The
  browser-side preflight is a usability check; server validation remains the
  authority against modified clients.
- Attach four server-owned outbound audio tracks before returning the initial
  answer. Later joins and leaves do not add or remove negotiated tracks and do
  not trigger renegotiation.
- Treat a browser or server inability to establish all four slots as a
  retryable compatibility failure. Clean up the attempted browser and server
  resources, expose no partial Voice Session, show an explicit retry action,
  and do not run an automatic retry loop.
- Keep one outbound track per Audio Output Slot and one source per slot at a
  time. Do not mix several sources into one track, even when the browser later
  combines the separately received tracks for playback.
- Keep slot positions fixed for the life of a Voice Session. Preserve a
  source's slot while it remains active; when it leaves, make only that slot
  silent and available, then assign the next source to the first free slot.
  Existing sources are not moved.
- Make the Forwarder build the complete directed matrix for eligible Sessions.
  A source is routed to every eligible destination except itself. The maximum
  is 20 directed Audio Routes.
- Extend each Audio Route's private destination metadata with its target Audio
  Output Slot. Keep route identity based on Voice Session IDs and accepted
  inbound track identity; keep PIDs and outbound track IDs as replaceable
  private delivery details.
- Start routes independently. A source/destination pair may route as soon as
  both Sessions are ready; an unrelated active Session that is still
  negotiating does not block it.
- Continue to deliver RTP asynchronously. Do not buffer, retry, or wait for
  RTP when a route, slot, Forwarder, destination Session, or destination track
  is unavailable. Drop the packet and update aggregate diagnostics.
- Preserve Phase 8 media rules: compatible Opus is required; mute retains the
  source's routes; an ended accepted inbound track withdraws that source's
  routes; `:disconnected` remains non-terminal; terminal peer states and
  canonical removal withdraw routes.
- Preserve canonical cleanup. RoomServer withdraws routes involving a Voice
  Session before ordinary termination and after an unexpected Session crash.
  Leave during negotiation removes the Session immediately, and late offer,
  ICE, or RTP work is ignored. A healthy remaining room continues to rebuild
  eligible routes.
- Preserve the existing room-wide `:one_for_all` recovery policy. A Forwarder
  failure resets that Voice Channel's runtime tree and requires browsers to
  rejoin and negotiate; Phase 9 does not add Forwarder-only state recovery.
- Make the Voice Owner Tab own one stable aggregate `MediaStream` and one
  controller-owned `<audio>` element. Add up to four separately identified
  received remote `MediaStreamTrack` values to that stream, and remove or
  silence only the track belonging to a released slot.
- Keep browser remote-track identity local to the slot and track. Do not expose
  User IDs, Voice Session IDs, route graphs, PIDs, PeerConnection handles, or
  source identity through a Phase 9 playback API. Voice roster identity is
  deferred to Phase 10.
- Add no durable schema or Postgres state. Active Voice Sessions, Audio Output
  Slots, Audio Routes, PeerConnections, and media readiness remain runtime
  state.
- Measure the maximum five-Session room: route count, forwarded and dropped
  packets, CPU, and bandwidth. Phase 9 documents the result but adds no new
  performance cutoff beyond the five-Session cap; stricter limits belong to
  Phase 14.
- Keep the implementation and API language aligned with the domain glossary:
  Voice Session, Audio Source, Audio Destination, Audio Output Slot, and Audio
  Route. Avoid using Participant, Receiver, Publisher, or Room as substitutes
  for those domain concepts.

## Testing Decisions

- Tests prove observable routing, playback, admission, failure, and cleanup
  outcomes. They do not assert private map shape, Registry keys, process IDs,
  outbound track IDs, helper-call order, or implementation-specific message
  sequencing unless the value is explicitly part of an external boundary.
- Use the existing `Voice.Forwarder` seam for exhaustive deterministic route
  policy tests. Cover room sizes one through five, every ordered source to
  destination pair, no self-forwarding, fixed slot positions, first-free-slot
  assignment, slot reuse, partial readiness, source track end, room changes,
  late RTP, duplicate readiness, duplicate cleanup, and stale replacement
  identities.
- Use the existing `DiscordClone.Voice` and RoomServer runtime seam for
  admission and lifecycle tests. Prove serialized simultaneous joins, the
  five-Session cap, leave during negotiation, healthy-room continuation after
  one Session failure, route withdrawal before termination, and replacement
  Voice Session protection.
- Use real ExWebRTC PeerConnections for the full five-Session media proof.
  Inject distinct accepted RTP into each source Session and observe the actual
  destination PeerConnection and outbound Audio Output Slot. Prove the full
  directed matrix and no source self-delivery.
- Keep smaller runtime tests focused and deterministic. Use
  `start_supervised!/1`, process monitors, and `:sys.get_state/1` for
  synchronization. Do not use sleeps, process-aliveness polling, or fake
  production PeerConnection configuration when the real ExWebRTC seam can
  prove the behavior.
- Extend the existing browser peer-attempt tests to cover four receive-only
  lanes, local compatibility preflight, stable slot-to-track mapping, adding
  and releasing tracks in one aggregate `MediaStream`, playback through one
  audio element, explicit retry after compatibility failure, and complete
  cleanup on leave or terminal failure.
- Keep the manual browser proof separate from the implementation spec's
  detailed checklist. It must use five separately authenticated Users because
  one User may have only one active Voice Session. The manual pass proves
  multi-track browser playback in the Voice Owner Tab.
- Keep diagnostics assertions metadata-only. Verify aggregate forwarded and
  dropped counts and reject SDP, ICE credentials, raw RTP, PIDs, User identity,
  Voice Channel identity, and browser correlation data.
- Run focused Voice, Forwarder, Session, PeerConnection, authenticated Voice
  Channel, and browser JavaScript tests during implementation, then finish
  with `mix precommit`.

## Out of Scope

- Audio mixing, decoding, transcoding, recording, transcription, or any other
  server-side transformation of source audio.
- Video, screen sharing, data channels, recording tracks, and non-Opus media.
- Dynamic track addition, track replacement, renegotiation after the initial
  answer, ICE restart, perfect negotiation, or automatic browser reconnect.
- Joining with fewer than four usable Audio Output Slots. Reduced-audio mode
  is deliberately not supported; incompatible joins fail and can be retried.
- Selective speaker choice, speaker priority, rotating sources, volume
  controls, or any policy that makes a destination hear only a preferred subset
  when all four slots are available.
- Voice Channel roster UI, User identity attached to remote tracks, speaking
  indicators, local deafen, synchronized mute controls, server-enforced mute,
  moderator disconnect, and other Voice controls scheduled for Phase 10.
- New durable Voice Session persistence or Voice Channel schema changes.
- A Forwarder-only recovery protocol. The existing isolated room-tree reset
  remains the recovery behavior for a Forwarder crash.
- STUN, TURN, HTTPS/WSS deployment, real-network testing, and restrictive
  network behavior scheduled for Phase 12.
- Strict CPU, bandwidth, latency, or mailbox cutoffs beyond the existing
  five-Voice-Session admission cap. Phase 9 records measurements; Phase 14
  turns evidence into operational limits.
- The detailed manual five-User browser setup and demonstration checklist; that
  will be discussed separately.

## Further Notes

- This PRD is the implementation spec produced from the completed Phase 9
  design interview. It carries forward the ownership and cleanup decisions in
  the existing Voice runtime ADRs and the Phase 8 Forwarder decision.
- The key topology is four destination slots per Voice Session, not one shared
  destination track. At five active Voice Sessions, each source fans out to
  four destinations and the room contains up to 20 directed Audio Routes.
- The browser's aggregate playback stream is only a rendering convenience. It
  does not change the server's source identity, route graph, slot assignment,
  or cleanup behavior.
- The current Phase 8 behavior for exactly two ready Voice Sessions remains a
  valid subset of the Phase 9 matrix. Phase 9 generalizes it to three, four,
  and five eligible Voice Sessions while preserving the no-self and late-drop
  invariants.
- The implementation should update the Phase 9 section of the roadmap only
  after the behavior, tests, measurements, and final architecture are proven.
