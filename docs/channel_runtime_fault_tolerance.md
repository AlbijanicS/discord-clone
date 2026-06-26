# Channel Runtime Fault Tolerance

Channel runtimes are supervised, temporary processes keyed by durable channel
IDs. They make active channels feel responsive, but they are not the source of
truth for durable chat history.

## Durable State

Postgres owns state that must survive process loss:

- users
- workspaces
- workspace memberships
- channels
- messages

When a channel runtime starts, `DiscordClone.Chat.ChannelSupervisor` rebuilds
the bounded recent-message cache by loading the latest persisted messages for
that channel ID. Older history is always loaded through Postgres-backed Chat
queries, so pagination does not depend on any ChannelServer memory surviving.

## Temporary State

`DiscordClone.Chat.ChannelServer` owns state that is useful only while the
runtime is alive:

- recent-message cache
- typing user IDs and deadlines
- idle shutdown timers

If the runtime exits, typing state is intentionally lost. The Channel LiveView
monitors the runtime returned by `DiscordClone.Chat.ensure_channel_runtime/2`
and clears visible typing indicators when that process goes down. A later Chat
workflow, such as reading recent messages, sending a message, or typing again,
starts a fresh runtime and continues from durable channel and message data.

Workspace online status is separate from channel runtime recovery. It remains
workspace-scoped through the workspace presence runtime and is not stored on the
ChannelServer.

## Existing PubSub Boundary

Message and typing events are delivered directly through Phoenix PubSub after
the Chat workflow succeeds. There is no durable event outbox in this project, so
PubSub delivery itself is best-effort live behavior. Persisted messages remain
recoverable from Postgres even if a subscriber misses a live event.
