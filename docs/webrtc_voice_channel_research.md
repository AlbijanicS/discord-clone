# WebRTC Voice Channel Research Note

Status: research-note

This note summarizes implementation constraints for adding Discord-like voice
channels to the Phoenix LiveView roadmap. It uses primary or high-trust sources:
W3C WebRTC specs, MDN Web API docs, IETF RFCs, official WebRTC docs, Phoenix
HexDocs, and official mediasoup docs for SFU behavior.

## Executive Summary

WebRTC does not remove the need for server-side coordination. Browsers own media
capture, ICE gathering, SDP offer/answer, encryption, congestion handling, and
peer transport state, but the application must still provide authenticated
signaling: who is in a voice channel, who should negotiate with whom, how offers,
answers, ICE candidates, mute/deafen state, and leave events are routed, and how
stale sessions are cleaned up. MDN describes signaling as the discovery and
media-negotiation process that lets peers locate each other and exchange
negotiation messages through a mutually agreed server; the signaling server's
message format is application-defined.[^mdn-signaling]

For a Phoenix LiveView app, LiveView can render the voice UI and supervise
client hooks, while Phoenix Channels or LiveView push events can carry signaling
messages. PubSub can fan out channel membership and signaling events inside the
cluster, but it is not the media plane. RTP audio should flow through WebRTC
peer connections or a media server, never through LiveView diffs or PubSub.
Phoenix PubSub supports topic subscribe/broadcast across a cluster,[^phoenix-pubsub]
and Phoenix Channels support topic broadcasts with serializable payloads,[^phoenix-channel]
which fits signaling messages, not realtime audio packets.

## Signaling Responsibilities

The application should treat signaling as a first-class room protocol:

- Authorize voice-channel join with `current_scope` and workspace membership.
- Maintain a server-side participant roster keyed by workspace/channel/user and
  browser voice-session ID.
- Route SDP offers and answers only to the intended participant or media server.
- Route ICE candidates after the remote description is ready, preserving ordering
  enough that candidates are not applied before the relevant answer/offer.
- Broadcast participant lifecycle events: join, leave, mute, speaking, reconnect,
  timeout, and connection health.
- Decide glare handling rules when two peers initiate negotiation at the same
  time. For mesh, a deterministic initiator rule such as lowest session ID calls
  the higher session ID keeps the MVP simpler.
- Avoid parsing or modifying SDP unless a later SFU integration explicitly
  requires it. MDN's guidance is that normal app code should route candidates to
  the other peer and hand received candidates to `addIceCandidate()`.[^mdn-signaling]

W3C defines `RTCPeerConnection` as the central browser API for sending and
receiving media/data, including connection, signaling, ICE gathering, and ICE
connection states. Its configuration includes `iceServers`, which supply the
STUN/TURN servers used by ICE.[^w3c-webrtc]
The official WebRTC peer-connection guide describes the normal flow: create a
peer connection with ICE configuration, create/set a local offer, transfer it
over a signaling service, listen for local ICE candidates, and transfer each
candidate over signaling.[^webrtc-peer]

## ICE, STUN, And TURN

ICE is mandatory as the browser-side connectivity strategy. RFC 8445 describes
ICE as a NAT traversal protocol that gathers candidates, checks candidate pairs,
nominates a working pair, and supports ICE restarts.[^rfc8445] The same RFC says
an ICE agent should gather server-reflexive and relayed candidates, while noting
some deployments may disable STUN/TURN for controlled networks and should keep
that functionality configurable.[^rfc8445]

For an internet-facing voice MVP, configure both:

- STUN: lets peers discover server-reflexive candidates when direct NAT traversal
  is possible.
- TURN: provides relayed candidates when direct peer-to-peer connectivity is
  impossible. RFC 8656 defines TURN as a relay protocol for cases where a host
  behind NAT cannot communicate directly with peers and needs an intermediate
  relay.[^rfc8656]

Without TURN, some users will simply fail to connect from corporate networks,
symmetric NATs, restrictive Wi-Fi, VPNs, or mobile environments. TURN adds cost
because it relays media bandwidth, but it is the reliability floor for a product
that should work outside happy-path home networks.

## Mesh Versus SFU For Group Voice

Mesh is the smallest implementation because every participant negotiates direct
peer connections with every other participant. It avoids operating a media
server, but it grows poorly: each participant sends audio to every other
participant and receives audio from every other participant. RFC 7667 documents
point-to-multipoint mesh as one of the RTP topologies and contrasts it with
centralized middlebox topologies.[^rfc7667]

An SFU moves media routing to a server. RFC 7667 calls this a Selective
Forwarding Middlebox: endpoints send media to the middlebox, and the middlebox
selectively forwards streams to receivers.[^rfc7667] Official mediasoup docs
summarize the practical model: an SFU receives audio/video streams from
endpoints and relays selected streams to everyone else; endpoints send one stream
and receive many, while the SFU avoids transcoding/mixing in the common case.[^mediasoup-overview]

Recommended roadmap stance:

- MVP: mesh only for small voice channels, with a hard participant cap, because
  it proves permission, UI, audio capture, signaling, mute/deafen, and lifecycle
  without choosing permanent media infrastructure.
- Later: add an SFU before treating group voice as production-scale. The
  mediasoup scalability docs model a Router as a multiparty room and note that
  workers/routers must be distributed across CPU cores and hosts for higher
  capacity.[^mediasoup-scalability]

## Browser API Behaviors

`getUserMedia()` is the microphone gate. It works only in secure contexts, asks
the user for permission, and returns a `Promise` that resolves to a
`MediaStream`; denial or missing devices reject with errors such as
`NotAllowedError` or `NotFoundError`. The promise can also remain pending if the
user ignores the prompt.[^mdn-gum] For local development, `localhost` counts as a
secure context; deployed voice requires HTTPS.[^mdn-gum]

`RTCPeerConnection` owns negotiation and transport state. App code should:

- Add the local microphone track to each peer connection.
- Send local SDP offers/answers over signaling.
- Send each local `icecandidate` event over signaling.
- Call `setRemoteDescription()` before applying related remote ICE candidates.
- Call `addIceCandidate()` for each received remote candidate; `null` or an
  empty candidate marks end-of-candidates.[^mdn-add-ice]
- Listen to `track` events for remote audio and attach tracks to stable audio
  elements. MDN marks older `addstream`/`removestream` events obsolete in favor
  of track-level events.[^mdn-pc]
- Track `iceConnectionState` and `connectionState` for UI health and reconnect
  behavior. `disconnected` may be transient; `failed` means ICE checked
  candidate pairs and could not find compatible matches for the connection's
  components.[^mdn-ice-state]
- Use `restartIce()` when ICE reaches `failed` or when a known network change
  requires renegotiation. MDN notes that `restartIce()` fires
  `negotiationneeded` and causes the next offer to trigger ICE restart.[^mdn-restart-ice]

Audio-only channels do not need camera APIs. They do need explicit microphone
track lifecycle: stop local tracks on leave, close peer connections, detach
remote audio, and clear signaling subscriptions for that voice session.

## Audio Device Permissions

The UI should make permission state visible without assuming it can force the
browser prompt. `getUserMedia()` always requires user permission for microphone
access and browsers must show indicators when capture is active, with permission
and notification behavior controlled by the browser.[^mdn-gum]

MVP implications:

- Entering a voice channel should be a user gesture that calls
  `navigator.mediaDevices.getUserMedia({audio: true})`.
- Handle pending permission as its own UI state.
- Handle denial, no input device, and insecure-context errors distinctly.
- Do not persist raw device IDs unless later product requirements need explicit
  device selection and privacy review.
- Default mute should disable the local audio track rather than renegotiating.
  Leaving should stop tracks so the browser capture indicator turns off.

Later phases can add device pickers with `enumerateDevices()`, input/output
level meters, automatic gain/noise controls where browser constraints support
them, and persisted user preferences.

## LiveView Lifecycle And Reconnection

LiveView begins as a regular HTTP response and then connects to the server as a
stateful view; on crash or client connection drop, the client reconnects and
`mount/3`/`handle_params/3` run again.[^lv-lifecycle] LiveView hooks have
`mounted`, `destroyed`, `disconnected`, and `reconnected` callbacks, which are
the right place to coordinate browser-only WebRTC resources with server
connection lifecycle.[^lv-hooks]

MVP lifecycle rules:

- Treat voice session IDs as ephemeral browser sessions, not durable channel
  membership.
- On hook `mounted`, initialize the client voice controller, but request mic
  permission only after a join action.
- On LiveView `disconnected`, show reconnecting state and pause nonessential
  signaling; keep existing peer connections alive briefly because media may
  continue even if the LiveView socket is reconnecting.
- On `reconnected`, reannounce presence and reconcile roster state.
- On hook `destroyed` or explicit leave, close every `RTCPeerConnection`, stop
  local tracks, remove audio elements, and notify the server.
- Server-side, expire voice participants that do not heartbeat/reannounce within
  a short window so stale browser tabs leave the roster.

## MVP Scope

The smallest useful MVP should include:

- Voice-channel join/leave inside existing authenticated workspace/channel
  authorization boundaries.
- LiveView UI with join, leave, mute, deafen, reconnecting, and permission-error
  states.
- External JavaScript hook or imported module for browser WebRTC logic; no
  inline template scripts.
- Audio-only `getUserMedia()`.
- Mesh `RTCPeerConnection` between participants with a low participant cap, such
  as 2-4 active speakers/listeners.
- STUN and TURN configuration supplied to the browser.
- Signaling over Phoenix Channel or LiveView push events with PubSub topic
  fanout where useful.
- Deterministic offer ownership to avoid glare.
- Connection health reporting from browser state changes.
- Cleanup on leave, navigation, tab close where possible, and server timeout for
  missed cleanup.

This MVP should explicitly label voice as experimental/small-room because mesh
bandwidth and negotiation complexity grow quickly with each participant.

## Later Phases

After the MVP proves the user workflow, add:

- SFU integration, likely as a dedicated media service rather than BEAM-owned
  media processing.
- SFU room allocation, credentials, and lifecycle tied to workspace/channel
  authorization.
- Regional TURN/SFU deployment and observability for packet loss, jitter,
  bitrate, reconnects, and relay usage.
- Device picker and persisted user audio preferences.
- Speaking indicators based on local audio analysis or RTP/audio-level stats.
- Push-to-talk, noise suppression controls, automatic gain controls, and input
  sensitivity.
- Moderation controls: disconnect member, server mute/deafen, move user between
  voice channels.
- Recording/transcription only after a consent, retention, and privacy design.
- Mobile browser QA, background-tab behavior testing, and network-change test
  scripts.

## Sources

[^mdn-signaling]: MDN, [Signaling and video calling](https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API/Signaling_and_video_calling).
[^w3c-webrtc]: W3C, [WebRTC: Real-Time Communication in Browsers](https://www.w3.org/TR/webrtc/).
[^webrtc-peer]: WebRTC.org, [Peer connections](https://webrtc.org/getting-started/peer-connections-advanced).
[^rfc8445]: IETF RFC 8445, [Interactive Connectivity Establishment (ICE)](https://www.rfc-editor.org/info/rfc8445/).
[^rfc8656]: IETF RFC 8656, [Traversal Using Relays around NAT (TURN)](https://www.rfc-editor.org/rfc/rfc8656.html).
[^rfc7667]: IETF RFC 7667, [RTP Topologies](https://www.rfc-editor.org/info/rfc7667/).
[^mediasoup-overview]: mediasoup, [Overview](https://mediasoup.org/documentation/overview/).
[^mediasoup-scalability]: mediasoup, [Scalability](https://mediasoup.org/documentation/v3/scalability/).
[^mdn-gum]: MDN, [MediaDevices: getUserMedia()](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia).
[^mdn-add-ice]: MDN, [RTCPeerConnection: addIceCandidate()](https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection/addIceCandidate).
[^mdn-pc]: MDN, [RTCPeerConnection](https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection).
[^mdn-ice-state]: MDN, [RTCPeerConnection: iceConnectionState](https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection/iceConnectionState).
[^mdn-restart-ice]: MDN, [RTCPeerConnection: restartIce()](https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection/restartIce).
[^phoenix-pubsub]: Phoenix PubSub HexDocs, [Phoenix.PubSub](https://phoenix-pubsub.hexdocs.pm/Phoenix.PubSub.html).
[^phoenix-channel]: Phoenix HexDocs, [Phoenix.Channel](https://phoenix.hexdocs.pm/Phoenix.Channel.html).
[^lv-lifecycle]: Phoenix LiveView HexDocs, [Phoenix.LiveView lifecycle](https://phoenix-live-view.hexdocs.pm/Phoenix.LiveView.html).
[^lv-hooks]: Phoenix LiveView HexDocs, [JavaScript interoperability](https://phoenix-live-view.hexdocs.pm/js-interop.html).
