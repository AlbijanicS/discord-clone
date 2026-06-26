# Phase 10 Backlog

Status: draft-from-doc-sweep

This backlog comes from a sweep of the project Markdown docs after the core
loop reached:

```text
auth -> workspace -> channel -> message -> live update -> recovery
```

The earlier phases intentionally left product features and polish out of scope
so the first working version could prove the Phoenix, Postgres, PubSub, and OTP
boundaries. Phase 10 should add those features as vertical slices, one at a
time, without disturbing the core architecture.

## Already Covered Core

- Users can register, log in, and log out.
- Authenticated users can create Workspaces.
- Workspaces create owner memberships and a durable `general` Landing Channel.
- Workspace Members can create, rename, delete, join, and leave workspace
  structures through the shell.
- Workspace invites exist with policy, preview, accept, expiry, max-use, and
  already-member handling.
- Channel pages show durable recent messages and older-message pagination.
- Sending validates membership, persists first, preloads authors, updates the
  Channel runtime cache, clears typing, and broadcasts live messages.
- Channel runtimes are supervised, named by durable Channel ID, cache recent
  messages, shut down when idle, and recover from process loss.
- Workspace presence is workspace-scoped and renders durable members as online
  or offline.
- Typing indicators are Channel-scoped, temporary, expire automatically, and
  recover cleanly after runtime loss.

## Phase 10 Must-Haves

These are the features the project owner wants to add next.

### 1. Unread Counts With `channel_reads`

Why first:

- It is the most natural next Discord-like feature.
- It deepens the durable/in-memory distinction without requiring a new product
  area.
- It uses the existing Channel shell and message timeline.

Likely model:

- Add `channel_reads` with `channel_id`, `user_id`, `last_read_message_id`, and
  timestamps.
- Persist read positions, not unread counters.
- Compute unread counts from messages newer than the read position.
- Mark the selected Channel read when the member views or catches up to it.

Important tests:

- Opening a Channel marks it read for that member.
- Messages from other members increment unread counts for Channels not
  currently selected.
- The selected Channel does not show an unread count for messages the viewer has
  already seen.
- Counts are scoped by Workspace membership and Channel ID.
- Counts survive Channel runtime crashes because they are Postgres-backed.

### 2. Reactions

Likely model:

- Add `message_reactions` with `message_id`, `user_id`, and `emoji`.
- Enforce one row per user/message/emoji.
- Delete toggles off the same reaction.
- Broadcast reaction changes to Channel subscribers.

Important tests:

- Workspace Members can add and remove a reaction on an accessible message.
- Non-members cannot react to private Workspace messages.
- Duplicate reaction attempts are idempotent or rejected deliberately.
- Live viewers see updated reaction counts without refresh.

### 3. Mentions

Start simple:

- Parse `@username` from message content.
- Highlight mentions in rendered messages.
- Consider persisting `message_mentions` only when mention queries,
  notifications, or unread mention badges become important.

Possible later model:

- `message_mentions` with `message_id`, `mentioned_user_id`, and maybe
  `workspace_id`.

Important tests:

- Mention parsing resolves only Workspace Members.
- Mentions do not leak user existence outside the Workspace.
- Rendering safely highlights mentions without introducing raw HTML.
- Mention metadata, if persisted, is created in the send workflow after message
  persistence.

### 4. Direct Messages

Design choice from the docs:

- Either model DMs as a separate conversation type or as Channels with a `kind`
  field.
- For this learning project, using Channel processes for DMs is reasonable
  because recent cache, typing, rate limiting, and live events are similar.

Likely model:

- Add a conversation/channel kind, for example `workspace_text` and `dm`.
- Add DM membership/participants if DMs are not tied to Workspace membership.
- Keep runtime identity durable and ID-based.

Important tests:

- Two users can create or find a DM conversation.
- Only DM participants can read, send, type, and receive live events.
- DM messages persist and recover after runtime loss.
- Workspace Channel authorization and DM authorization stay separate.

### 5. Message Rate Limiting In Channel Process State

Why it belongs in ChannelServer:

- Rate-limit counters are temporary and useful right now.
- They should reset naturally after runtime loss or idle shutdown.
- It practices GenServer-owned state without making it durable.

Likely behavior:

- Limit each user to 5 messages per 10 seconds per Channel.
- Store user ID counters/windows in ChannelServer state.
- `Chat.send_message/3` should ask the runtime before persisting.

Important tests:

- The first N messages in a window are accepted.
- The next message is rejected before persistence and before PubSub.
- Counters are per user and per Channel.
- Runtime loss clears temporary counters.

### 6. Voice-Channel Simulation

No actual audio.

Likely model:

- Add voice Channels or a Channel kind.
- Track connected users in a GenServer.
- Render who is connected live.
- Disconnect cleanup should monitor LiveView/process PIDs, similar to workspace
  presence.

Important tests:

- A member can join and leave a simulated voice Channel.
- Other viewers see connected users update without refresh.
- Closing the final connected process removes that user.
- Voice state is temporary and recovers as clients rejoin.

### 7. Channel Analytics

Keep this last because it can sprawl.

Possible metrics:

- messages per hour
- active users
- peak online users
- reaction totals
- busiest Channels

Design choice:

- Decide whether metrics are query-derived from durable data, runtime-derived
  from temporary state, or persisted snapshots. Start with query-derived metrics
  before adding new runtime state.

## Deferred Polish From Earlier Docs

These were repeatedly called out as out of scope in earlier phases. They are
not required before the Phase 10 must-haves, but they are good polish slices.

### Message Composer And Timeline

- Multiline composer behavior.
- Shift+Enter newline handling.
- Richer composer interactions.
- Markdown or rich text rendering.
- Emoji parsing.
- Attachments.
- Embeds.
- Optimistic pending messages.
- Retry or resend UX.
- Client-generated message IDs.
- Better auto-scroll behavior after send and receive.
- Scroll-position preservation after loading older messages.
- Infinite scroll or scroll-triggered pagination.

### Message Management

- Message editing.
- Message deletion.
- Soft deletion or archival of messages after Channel deletion.
- Message search.
- Date separators or grouped message days.
- Relative timestamps.
- Client timezone conversion.

### Workspace And Channel Structure

- Workspace roles beyond the current membership gate.
- Role-based read/send/manage permissions.
- Restricting Channel creation, invite management, member removal, or Channel
  deletion to admin-capable roles.
- Channel descriptions.
- Last selected Workspace memory.
- Manual Channel ordering.
- Default Channel selection UI.
- Polished modal dialogs for create flows.

### Presence And Runtime Hardening

- Away or idle status.
- Rich profile details in the member sidebar.
- Phoenix Presence.
- Distributed Registry/process behavior across multiple BEAM nodes.
- Durable event outbox for persisted events such as message-created.
- Production observability, metrics dashboards, and alerts.

## Recommended Order

1. Unread counts with `channel_reads`.
2. Message reactions.
3. Mentions, starting with parse-and-highlight.
4. Message rate limiting in ChannelServer.
5. Direct messages using Channel runtime patterns.
6. Voice-channel simulation.
7. Channel analytics.
8. Composer/timeline polish and message edit/delete/search.
9. Workspace roles and richer permissions.

This order keeps the app improving visibly while continuing to practice the
project's main lesson:

```text
Important forever?
  -> Postgres

Useful right now?
  -> GenServer/process state
```
