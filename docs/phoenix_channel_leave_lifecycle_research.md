# Phoenix Channel Leave Lifecycle Research

Status: research-note

## Question

For Phase 3 Voice signaling, should the browser send a custom `leave` event,
wait for an application-level `left` reply, and then call `channel.leave()`?

## Finding

No. Phase 3 should call Phoenix's built-in `channel.leave()` directly. It is
already the explicit, acknowledged Channel-leave protocol:

- The JavaScript client unsubscribes from server events, instructs the server
  Channel to terminate, triggers its `onClose` callbacks, and returns a `Push`
  that can receive an `"ok"` acknowledgement.[^js-leave]
- On the server, that protocol terminates the Channel with
  `{:shutdown, :left}`. If the transport closes instead, the reason is
  `{:shutdown, :closed}`.[^channel-terminate]

Therefore Phase 3 does not need `handle_in("leave", ...)` or an application
`left` event. Adding both would duplicate a lifecycle Phoenix already provides
and introduces an unnecessary two-step race: the custom event might succeed
while the subsequent transport-level leave fails or is never sent.

The browser may use the built-in acknowledgement when it wants to update UI
after a graceful leave, but it must also handle `onClose` and timeout/error
paths. Its local ephemeral state should be cleared whenever the Channel closes;
an acknowledgement is not a durability guarantee.

## Implications for the Voice Roadmap

Phase 3 has no `Voice.RoomServer` or other external resource to clean up. The
Signaling Session ID is assigned to the Channel process, so either built-in
leave or transport close naturally invalidates it when that process ends.

In later phases, a `Voice.RoomServer` should monitor each associated Phoenix
Channel process and perform authoritative cleanup when it goes down. Phoenix
explicitly warns that `terminate/2` is not invoked for errors or exits and
recommends process monitoring when cleanup must be guaranteed.[^channel-terminate]
`terminate/2` may still be useful for best-effort, local teardown and for
distinguishing graceful leave from transport close; it must not be the only
correctness mechanism for a future Voice runtime.

## Recommended Phase 3 Contract

```text
User leaves Voice UI
  -> browser calls channel.leave()
  -> optional built-in "ok" acknowledgement
  -> Phoenix terminates that topic's Channel process
  -> browser clears its local signaling state on onClose

Unexpected WebSocket close
  -> Phoenix terminates the Channel process
  -> browser clears its local signaling state on onClose/reconnect handling
```

No custom `leave` signaling event is required.

## Sources

[^js-leave]: [Phoenix JavaScript `Channel.leave()` API](https://phoenix.hexdocs.pm/js/classes/Channel.html#leave): describes it as unsubscribing from server events, instructing the server Channel to terminate, invoking `onClose`, and returning a `Push` that can receive an acknowledgement.

[^channel-terminate]: [Phoenix.Channel — Terminate](https://phoenix.hexdocs.pm/Phoenix.Channel.html#module-terminate): documents `{:shutdown, :left}` and `{:shutdown, :closed}` reasons, the limits of `terminate/2`, and the recommendation to monitor the Channel process for cleanup.
