# Phoenix Channel signaling delivery research

Status: research-note

## Question

For the future browser-to-server WebRTC flow, should a browser `offer` receive
the server `answer` in the immediate Phoenix Channel reply, or as a separate
Channel event? How should server ICE candidates be delivered?

## Finding

Use two delivery modes with distinct jobs:

1. Reply to the browser's `offer` with the one correlated SDP `answer` (or a
   validation/authorization error).
2. Deliver every server-generated ICE candidate as a direct
   Channel event, one candidate at a time.

This is the closest fit to the ExWebRTC project's own browser-to-Elixir
negotiation example: it receives an offer, calls `set_remote_description/2`,
creates and sets an answer, sends that answer back, and the browser sets it as
its remote description. The same guide says that renegotiation repeats the
offer/answer process when tracks change.[^exwebrtc-negotiation]

Phoenix supports this directly: a `handle_in/3` reply is correlated to exactly
the client push that caused it, while `push/3` sends a standalone event only to
the connected client. Phoenix also documents `socket_ref/1` plus `reply/2` for
the case where a separate `Voice.Session` process must produce the correlated
answer after `handle_in/3` returns. This preserves the browser contract if
answer creation later becomes asynchronous.[^phoenix-channel]

ExWebRTC separately supports the server answer operations and sends
`{:ex_webrtc, peer_connection, {:ice_candidate, candidate}}` messages to the
PeerConnection's controlling process. That asynchronous candidate notification
is a direct reason to use a pushed event for server ICE rather than trying to
fit ICE into the original offer reply. Its official guide specifically says
candidates are generally sent separately because gathering can take several
seconds.[^exwebrtc-api][^exwebrtc-negotiation]

## Recommended future-shaped contract

The exact SDP and ICE schemas remain Phase 4 work. Phase 3 can nevertheless
keep its fake messages in the same directional shape:

```text
browser -> server: offer {signaling_session_id, negotiation_id, description}
server -> browser reply: ok {signaling_session_id, negotiation_id, description}

browser -> server: ice_candidate {signaling_session_id, negotiation_id, candidate}
server -> browser reply: ok {negotiation_id}
server -> browser event: ice_candidate {signaling_session_id, negotiation_id, candidate}
```

`negotiation_id` is an opaque per-offer correlation value. The browser creates
one for each offer (including a future renegotiation); the server copies it
into the related answer and candidate events. It is a correlation value, not
authentication or authorization. The server-issued Signaling Session ID remains
the proof that the current socket/topic connection was admitted.

Phase 3's fake implementation should return its fake `answer` in the `offer`
reply. When Phase 4 introduces a separate `Voice.Session`, the Channel can take
`socket_ref/1`, return `{:noreply, socket}`, and let the Session's result call
`Phoenix.Channel.reply/2` with that reference. The browser still receives the
same correlated offer reply; no wire-contract change is needed.

## Caveats

- `push/3` has no client request reference. Phoenix explicitly says that a
  client/server acknowledgement for a pushed event needs application-provided
  correlation state; `negotiation_id` supplies the needed correlation for a
  candidate sequence.[^phoenix-channel]
- A Phoenix Channel topic is not a broadcast route for this protocol. Use
  `push/3` on the current socket/channel process for browser-to-its-own-server
  PeerConnection signaling. Do not use `broadcast/3` or
  `broadcast_from/3`, which deliver to topic subscribers.[^phoenix-channel]
- Answers and candidates must still be validated and scoped to the accepted
  Signaling Session ID. Neither a request acknowledgement nor a
  `negotiation_id` is an identity credential.

## Sources

[^phoenix-channel]: [Phoenix.Channel official API](https://phoenix.hexdocs.pm/Phoenix.Channel.html) — replies are correlated to the current client event; `push/3` sends a standalone event to the connected client; `reply/2` supports asynchronous correlated replies; broadcasts go to topic subscribers.

[^exwebrtc-api]: [ExWebRTC.PeerConnection official API](https://ex-webrtc.hexdocs.pm/ExWebRTC.PeerConnection.html) — `create_answer/1`, `set_remote_description/2`, `set_local_description/2`, and the controlling-process `:ice_candidate` message.

[^exwebrtc-negotiation]: [ExWebRTC official negotiation guide](https://ex-webrtc.hexdocs.pm/negotiation.html) — browser offer/server answer exchange, repeated negotiation, and separate asynchronous ICE candidate exchange.
