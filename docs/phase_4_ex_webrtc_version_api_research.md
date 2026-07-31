# Phase 4 `ex_webrtc` version and API research

Status: research-note  
Checked: 2026-07-30  
Scope: dependency authority and the single browser-to-server PeerConnection
slice only. This note does not design a Voice Room, Voice Session runtime, or
media forwarding.

## Question

Which exact `ex_webrtc` release should Phase 4 use, and what is the
version-matched API boundary for a browser-offer/server-answer connection with
trickle ICE and reliable cleanup?

## Decision-ready finding

Use `ex_webrtc` **0.17.0** for Phase 4. On 2026-07-30 it is the newest
non-retired release on its official Hex package page, published/updated on
2026-06-22.[^hex-package] The implementation change should use an exact
dependency requirement:

```elixir
{:ex_webrtc, "0.17.0"}
```

This is stricter than the upstream README's compatible-series example,
`{:ex_webrtc, "~> 0.17.0"}`.[^upstream-readme] An exact requirement keeps the
Phase 4 protocol contract attached to the API documented here; `mix.lock` then
records the resolved transitive packages. Do not add the optional `ex_sctp`
package: upstream identifies it as DataChannel support requiring Rust, which is
outside this audio receive/connection proof.[^upstream-manifest]

The version-matched API authority is the **v0.17.0** ExWebRTC HexDocs:

- [PeerConnection API](https://ex-webrtc.hexdocs.pm/ExWebRTC.PeerConnection.html)
- [Negotiating the connection guide](https://ex-webrtc.hexdocs.pm/negotiation.html)

## Compatibility boundary

`ex_webrtc` v0.17.0 declares `elixir: "~> 1.15"` in its official release-tagged
manifest.[^upstream-manifest] This project declares the same Elixir requirement
in `mix.exs`, so the declared Elixir versions are compatible. The manifest does
not declare a Phoenix version requirement: ExWebRTC is a WebRTC/OTP library and
the Phoenix Channel is this application's signaling transport, rather than an
ExWebRTC framework integration. No separate OTP version floor was found in the
package manifest; validate the complete resolver result and supported runtime
when adding the dependency.

## Phase 4 API contract

The PeerConnection is a GenServer process. `start_link/2` starts it and sends
its messages to the calling process by default; `controlling_process:` selects
a different recipient.[^peer-connection][^negotiation] For this first slice,
the owner must receive and serialize those messages; the eventual Voice Session
process remains intentionally out of scope.

| Concern | v0.17.0 API fact | Phase 4 implication |
| --- | --- | --- |
| Server creation | `PeerConnection.start_link/2` accepts configuration such as `ice_servers`; `start_link/2` links the PeerConnection to its caller. | Start one owned PC for the single admitted browser and provide matching ICE server configuration on browser and server. |
| Browser offer | The official flow deserializes browser JSON with `SessionDescription.from_json/1`, then calls `set_remote_description/2`. | Validate the channel message, decode an SDP description, then set it as remote. Do not invent an SDP map format. |
| Server answer | `create_answer/1` returns `{:ok, description} | {:error, term()}`; `set_local_description/2` returns `:ok | {:error, term()}`; `SessionDescription.to_json/1` serializes the answer. | Return the serialized answer only after successfully setting it locally. |
| Browser completion | The browser sets the received answer through `setRemoteDescription`. | Keep the existing correlated offer-reply direction. |
| Browser-to-server ICE | `ICECandidate.from_json/1` parses the candidate; `add_ice_candidate/2` returns `:ok | {:error, term()}`. | Accept one validated candidate at a time and report errors without ending the whole channel prematurely. |
| Server-to-browser ICE | The controlling process receives `{:ex_webrtc, pc, {:ice_candidate, candidate}}`; `ICECandidate.to_json/1` serializes it. | Push each server candidate as its own channel event. ICE gathering is asynchronous, so it does not belong in the offer reply. |
| Connected proof | `{:ex_webrtc, pc, {:connection_state_change, :connected}}` is the documented connected signal. | Log/observe this transition as the Phase 4 success condition. |
| Leave cleanup | `close/1` closes transport but does **not** kill the process; `stop/1` closes **and stops** it. | The owner must invoke `stop/1` (or supervise and terminate the child) on leave. Calling `close/1` alone fails the no-obvious-process-leak proof. |

The official tutorial signals browser ICE completion with
`event.candidate === null`, but this note intentionally does not assert a
server-side end-of-candidates representation. Confirm it in the v0.17.0 API or
source while implementing the candidate validator rather than inferring it from
browser behavior.[^negotiation]

## Canonical Phase 4 sequence

```text
browser: getUserMedia(audio) -> addTrack -> createOffer -> setLocalDescription
browser -> Phoenix Channel: offer (SessionDescription JSON)
owner: SessionDescription.from_json -> set_remote_description
owner: create_answer -> set_local_description -> SessionDescription.to_json
owner -> browser: correlated answer reply

browser <-> Phoenix Channel: individual trickle ICE candidate messages
owner receives {:ex_webrtc, pc, {:ice_candidate, candidate}}
owner -> browser: individual serialized ICE-candidate event

owner receives {:ex_webrtc, pc, {:connection_state_change, :connected}}
browser leaves -> owner stops the PeerConnection process
```

The negotiation guide specifies this order for browser offer/server answer,
states that the application is responsible for signaling offer/answer and
candidates, and explains why candidates are normally sent separately: gathering
can take seconds.[^negotiation]

## Sources

[^hex-package]: [Official Hex package: `ex_webrtc`](https://hex.pm/packages/ex_webrtc) — current release list, release status, ownership, and update date.

[^upstream-readme]: [Official ExWebRTC README at v0.17.0](https://github.com/elixir-webrtc/ex_webrtc/tree/v0.17.0) — upstream installation example.

[^upstream-manifest]: [Official `mix.exs` at v0.17.0](https://github.com/elixir-webrtc/ex_webrtc/blob/v0.17.0/mix.exs) — declared Elixir requirement, runtime dependencies, and optional `ex_sctp` dependency.

[^peer-connection]: [ExWebRTC.PeerConnection v0.17.0 API](https://ex-webrtc.hexdocs.pm/ExWebRTC.PeerConnection.html) — creation, controlling-process messages, description, ICE, connection-state, close, and stop APIs.

[^negotiation]: [ExWebRTC v0.17.0 negotiation guide](https://ex-webrtc.hexdocs.pm/negotiation.html) — browser-offer/server-answer and trickle-ICE flow.
