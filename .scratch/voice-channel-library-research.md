# Voice Channel Library Research

Date: 2026-07-21

Question: which community/open-source GitHub libraries could help add Discord-like Workspace Voice Channels to this Phoenix LiveView app without building WebRTC media infrastructure from scratch?

## Recommendation

Use LiveKit first unless the goal is specifically to learn low-level WebRTC/SFU internals.

Phoenix should own:

- Workspace voice channel rows, membership authorization, bans/roles, and route access.
- A short-lived "join voice channel" endpoint that verifies the current user can join.
- Token generation for the media backend.
- Optional durable voice channel metadata.
- UI state that belongs to the app, such as selected channel and maybe local mute/deafen preferences.

The media backend should own:

- WebRTC negotiation.
- Audio track publishing/subscribing.
- SFU/media routing.
- Network fallback across UDP/TCP/TURN.
- Speaking detection when available.
- Reconnect behavior and media transport observability.

## Shortlist

### 1. LiveKit

Sources:

- https://github.com/livekit/livekit
- https://docs.livekit.io/reference/internals/livekit-sfu/
- https://docs.livekit.io/frontends/reference/tokens-grants/

Why it fits:

- LiveKit is an open-source WebRTC stack with a server, browser/mobile SDKs, server APIs, Docker/Kubernetes deployment paths, and optional cloud hosting.
- Its README describes it as scalable multi-user conferencing based on WebRTC, with a distributed SFU, client SDKs, JWT authentication, UDP/TCP/TURN connectivity, speaker detection, selective subscription, moderation APIs, and E2EE.
- The LiveKit docs describe the SFU as horizontally scalable and explain why group calls need an SFU instead of plain peer-to-peer WebRTC once the room grows beyond very small calls.
- Access tokens encode participant identity, room, capabilities, and permissions, and are signed by the API secret. That maps cleanly to a Phoenix endpoint that authorizes a Workspace Member and returns a room-scoped token.

Maturity signals seen:

- GitHub showed about 19.9k stars, 2.2k forks, 83 releases, latest release v1.13.4 on 2026-07-18, Apache-2.0 license.
- Official browser, mobile, and server SDK ecosystem exists. No official Elixir server SDK was visible, but token generation is JWT-based and server SDKs exist in several languages.

Architecture fit:

- `voice_channels` table stores durable Workspace voice channels.
- LiveKit room name can be deterministic, e.g. `workspace:<workspace_id>:voice:<voice_channel_id>`.
- Phoenix verifies membership and generates a LiveKit token with `roomJoin`, `canPublish`, `canSubscribe`, and microphone-only publish permissions.
- Frontend imports LiveKit JS client in `assets/js/app.js` and uses a LiveView hook for local microphone and room connection.

Risks:

- Adds an external service/process, even when self-hosted.
- No first-party Elixir SDK means Phoenix either signs JWTs directly or uses a minimal local wrapper.
- Browser media state must live in JavaScript/LiveView hooks; LiveView alone cannot own microphone tracks.

### 2. Fishjam

Sources:

- https://documentation.fishjam.io/docs/
- https://docs.fishjam.io/explanation/architecture
- https://github.com/fishjam-dev/membrane_rtc_engine

Why it fits:

- Fishjam is a multimedia streaming toolkit with React/React Native SDKs and a media server. Its architecture docs say the app backend authenticates users, creates rooms, generates peer tokens, and manages lifecycle/permissions, while Fishjam routes audio/video, handles WebRTC negotiation, room types, media processing, and token validation.
- This boundary is almost exactly what we want for Phoenix plus Workspace Voice Channels.

Maturity signals seen:

- Current Fishjam docs show version 0.28.0.
- The older `fishjam-dev/membrane_rtc_engine` repository is archived and points to newer Fishjam Cloud work. The archived repo had an Elixir SFU lineage, but its archival is a warning if the goal is fully open-source self-hosting from that package.

Architecture fit:

- Similar to LiveKit: Phoenix owns auth and voice-channel metadata; Fishjam owns media rooms and tokens.
- Attractive if you want Software Mansion's Elixir/WebRTC ecosystem nearby.

Risks:

- The open-source story appears to have shifted compared with the older Membrane RTC Engine/Fishjam repositories.
- The current product/docs may be more platform/cloud oriented than a simple self-hosted OSS dependency.

### 3. mediasoup

Sources:

- https://github.com/versatica/mediasoup
- https://mediasoup.org/github/

Why it fits:

- mediasoup is a mature SFU toolkit. Its README says its design goals include being an SFU, supporting WebRTC and plain RTP, providing server-side Node.js/Rust APIs and client-side TypeScript/C++ libraries, staying signaling-agnostic, and handling only the media layer.

Maturity signals seen:

- GitHub showed about 7.3k stars, 1.2k forks, 121 releases, latest release `rust-0.22.12` on 2026-07-16, ISC license.

Architecture fit:

- Phoenix could remain the app backend, but you would likely run a separate Node/Rust media service using mediasoup.
- Phoenix would need to define and maintain the signaling protocol or proxy signaling messages between the browser and the media service.

Risks:

- Very powerful but intentionally low-level.
- More "build your own voice platform using this media toolbox" than "drop in voice channels."
- Signaling-agnostic means more design responsibility lands on you.

### 4. Janus WebRTC Gateway

Sources:

- https://github.com/meetecho/janus-gateway

Why it fits:

- Janus is a long-running general-purpose WebRTC server/gateway with plugins, including conferencing-style plugins.
- Mozilla Hubs historically used Phoenix for app orchestration with separate voice servers, initially Janus and later mediasoup.

Maturity signals seen:

- GitHub showed about 9.1k stars, 2.6k forks, GPL-3.0 license.

Architecture fit:

- Phoenix can authorize Workspace Members and then create/control Janus rooms via Janus APIs.
- Janus can handle media, while Phoenix manages Workspace assignment and UI state.

Risks:

- C service with native dependencies and plugin configuration.
- GPL-3.0 may matter depending on distribution plans.
- More operational/configuration complexity than LiveKit for a Discord-clone learning app.

### 5. Elixir WebRTC / ex_webrtc

Sources:

- https://github.com/elixir-webrtc/ex_webrtc
- https://elixir-webrtc.org/
- https://hex.pm/orgs/elixirwebrtc

Why it fits:

- `ex_webrtc` is an Elixir implementation of the W3C WebRTC API. It has examples, docs, and companion packages such as STUN/ICE/RTP/RTCP/DTLS pieces.
- There is a Phoenix-oriented package, `live_ex_webrtc`, for Live Components around Elixir WebRTC.

Maturity signals seen:

- GitHub showed about 476 stars, 35 forks, Apache-2.0 license, latest release v0.17.0 on 2026-06-22.
- Hex organization showed active package updates for WebRTC primitives in 2026.

Architecture fit:

- Good for experiments, small rooms, learning WebRTC, or building server-side WebRTC features in Elixir.
- Could be used for a prototype where Phoenix handles signaling and peer connections directly.

Risks:

- It is an implementation of WebRTC APIs, not a complete Discord-style group voice product.
- For group voice, you still need SFU semantics, room fanout, congestion behavior, and production media operations.
- More likely to teach you WebRTC than to save you from WebRTC.

## Practical Build Path

For this app, start with LiveKit.

Suggested first vertical slice:

1. Add `voice_channels` under the Workspaces context.
2. Add one authenticated route/action to join a voice channel.
3. Phoenix verifies `current_scope.user` is a current Workspace Member and not banned.
4. Phoenix returns a short-lived LiveKit token scoped to one room and microphone publishing.
5. A LiveView hook uses LiveKit JS to connect, publish microphone audio, subscribe to remote audio, and emit join/leave/speaking state back to LiveView.
6. Keep app presence and voice UI in Phoenix/PubSub, but treat LiveKit as authoritative for media transport.

This avoids inventing:

- ICE negotiation handling.
- SFU routing.
- TURN/TCP fallback behavior.
- Browser reconnection/media edge cases.
- Track subscription logic.

## Bottom Line

- Best default: LiveKit.
- Best Elixir-native learning path: ex_webrtc, possibly with LiveExWebRTC.
- Best low-level SFU toolbox: mediasoup.
- Best older gateway option: Janus.
- Interesting but verify current OSS/self-hosting fit: Fishjam.
