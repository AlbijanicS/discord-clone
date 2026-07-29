# Phase 3 signaling payload limits — research note

## Scope

This note covers the temporary, fake signaling protocol in Phase 3. It does
not set production limits for real SDP or ICE in a later WebRTC phase.

## What the primary sources establish

- This application uses `Bandit.PhoenixAdapter` and Bandit 1.12.0. Bandit's
  default maximum is **8,000,000 bytes** for one WebSocket frame and also for
  a message split across continuation frames. Those are transport guardrails,
  not an application-level signaling contract. [Bandit WebSocket options](https://bandit.hexdocs.pm/Bandit.html#t:websocket_options/0)
- Phoenix documents `:max_frame_size` as a per-socket WebSocket option. Its
  documented default is infinity, so an application must not assume that a
  Phoenix setting is the active bound when using Bandit. [Phoenix Endpoint socket options](https://hexdocs.pm/phoenix/Phoenix.Endpoint.html#socket/3)
- WebRTC deliberately leaves signaling transport to the application (for
  example, WebSocket). `RTCSessionDescriptionInit.sdp` and
  `RTCIceCandidateInit.candidate` are `DOMString` values; the WebRTC API
  specification sets no portable maximum length for either. Therefore neither
  a 256-character field limit nor a 4 KB message limit can be treated as a
  future SDP/ICE limit. [WebRTC signaling model](https://w3c.github.io/webrtc-pc/#peer-to-peer-connections), [session-description dictionary](https://w3c.github.io/webrtc-pc/#dom-rtcsessiondescriptioninit), [ICE-candidate dictionary](https://w3c.github.io/webrtc-pc/#dom-rtcicecandidateinit)

## Recommendation

Use the proposed **4 KiB total decoded fake-payload limit** and **256-character
limit per fake text field** in Phase 3, but apply them only inside the
Phase-3-only fake-message validator. The fake contract should use fields such
as `label` and `sequence`, not an `sdp` or `candidate` field with an
artificially small shared limit.

This gives the learning slice a small, bounded input surface while preserving
an easy replacement seam: Phase 4 adds a distinct real-SDP/ICE validator and
chooses its own explicit limits from the supported server peer-connection
implementation, codecs, and operational memory budget. It must not inherit
the Phase 3 constants.

Do not lower the endpoint's general Bandit WebSocket limit merely to enforce
the fake protocol. That limit applies before the application can distinguish
fake Phase 3 messages from future real signaling, and changing it would turn a
temporary exercise bound into an accidental platform constraint.

## Proposed decision

Adopt the 4 KiB / 256-character limits as deliberately temporary Phase 3 fake
protocol limits, isolated from the socket transport and any future real WebRTC
validation.
