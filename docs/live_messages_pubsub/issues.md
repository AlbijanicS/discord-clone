# Live Messages With PubSub Issues

This document breaks `docs/live_messages_pubsub/prd.md` into thin,
independently grabbable vertical slices. The project is using a docs-first
fallback for now, so these are not published to GitHub Issues.

The route placement for this phase is intentionally unchanged: channel chat
stays in the existing authenticated browser pipeline and the existing
`live_session :require_authenticated_user`, because channel messaging requires
`current_scope` and workspace membership.

## Proposed Breakdown

1. **Broadcast Persisted Channel Messages Through Chat PubSub**
   - **Type:** AFK
   - **Blocked by:** None - can start immediately
   - **User stories covered:** 5, 9-10, 12-21, 24, 26-27
2. **Render Incoming PubSub Messages In Subscribed Channel Views**
   - **Type:** AFK
   - **Blocked by:** 1. Broadcast Persisted Channel Messages Through Chat PubSub
   - **User stories covered:** 1, 4-8, 11, 14-17, 20-22, 24, 27
3. **Prevent Sender Duplicates While Keeping Local Send Feedback**
   - **Type:** AFK
   - **Blocked by:** 1. Broadcast Persisted Channel Messages Through Chat PubSub, 2. Render Incoming PubSub Messages In Subscribed Channel Views
   - **User stories covered:** 2-3, 18-20, 23-24, 27
4. **Prove Channel Isolation And Access Boundaries For Live Delivery**
   - **Type:** AFK
   - **Blocked by:** 1. Broadcast Persisted Channel Messages Through Chat PubSub, 2. Render Incoming PubSub Messages In Subscribed Channel Views
   - **User stories covered:** 4-5, 11-18, 24-25, 27
5. **Finalize Phase 6 Acceptance Coverage**
   - **Type:** AFK
   - **Blocked by:** 1. Broadcast Persisted Channel Messages Through Chat PubSub, 2. Render Incoming PubSub Messages In Subscribed Channel Views, 3. Prevent Sender Duplicates While Keeping Local Send Feedback, 4. Prove Channel Isolation And Access Boundaries For Live Delivery
   - **User stories covered:** 1-27

## 1. Broadcast Persisted Channel Messages Through Chat PubSub

**Type:** AFK

**Blocked by:** None - can start immediately

**User stories covered:** 5, 9-10, 12-21, 24, 26-27

## What to build

Add the core PubSub workflow behind the Chat context. A workspace member should
be able to subscribe to live messages for a channel through a public Chat
function, and successful sends should broadcast the persisted message after the
message has been inserted and preloaded with its author.

The PubSub topic should be private to the Chat context and use the durable
channel ID shape selected by the PRD. The subscription workflow should recheck
workspace membership so knowing the topic format is not enough to receive
private messages. Send return values should stay unchanged; PubSub is a side
effect of successful persistence, not a new caller contract.

## Acceptance criteria

- [ ] The Chat context exposes a public workflow for subscribing to channel
      message events.
- [ ] The subscription workflow requires an authenticated scope.
- [ ] The subscription workflow rechecks workspace membership before
      subscribing.
- [ ] Anonymous scopes receive `{:error, :unauthenticated}` when subscribing.
- [ ] Logged-in non-members receive the existing privacy-preserving channel
      access failure when subscribing.
- [ ] Missing or inaccessible channels receive the existing
      privacy-preserving channel access failure when subscribing.
- [ ] Channel PubSub topics are constructed inside the Chat context.
- [ ] Topics use durable channel IDs in the shape `chat:channel:#{channel_id}`.
- [ ] Successful sends broadcast only after membership validation, Postgres
      insert, and author preload.
- [ ] The broadcast event is `{:message_created, message}`.
- [ ] The broadcast payload is the persisted message with author preloaded.
- [ ] `send_message/3` return values remain unchanged.
- [ ] Validation failures do not broadcast.
- [ ] Authorization failures do not broadcast.
- [ ] Read and history-loading workflows do not broadcast.
- [ ] Focused Chat context tests cover successful subscription, successful
      broadcast, event payload shape, unauthenticated subscription,
      non-member subscription, and no-broadcast failure paths.

## Blocked by

None - can start immediately

## 2. Render Incoming PubSub Messages In Subscribed Channel Views

**Type:** AFK

**Blocked by:** 1. Broadcast Persisted Channel Messages Through Chat PubSub

**User stories covered:** 1, 4-8, 11, 14-17, 20-22, 24, 27

## What to build

Wire channel LiveViews into the public Chat subscription workflow. After the
existing channel access checks, workspace and channel lists, and recent message
load have succeeded, a connected channel LiveView should subscribe to the
selected channel's live message stream. When another subscribed sender posts a
message, the receiving LiveView should stream the persisted message at the
bottom of the current message list using the same rendering as loaded and
locally sent messages.

This slice should keep the current router placement unchanged. It should also
preserve persisted-chat state boundaries: incoming live messages should not
reset the composer, update the oldest-message cursor, or change the
has-older-messages flag.

## Acceptance criteria

- [ ] The channel LiveView calls the public Chat subscription workflow rather
      than calling Phoenix PubSub directly.
- [ ] The channel LiveView subscribes only when the LiveView socket is
      connected.
- [ ] Subscription happens only after the existing channel page access and data
      loading workflow succeeds.
- [ ] A failed subscription after earlier access checks uses the existing
      generic channel access recovery.
- [ ] The route remains in the existing authenticated browser pipeline and
      existing `live_session :require_authenticated_user`.
- [ ] A subscribed LiveView handles `{:message_created, message}` events.
- [ ] Incoming messages are inserted at the bottom of the existing message
      stream.
- [ ] Incoming messages use the same message DOM shape and rendering as loaded
      messages.
- [ ] Incoming messages do not clear or replace another user's composer input.
- [ ] Incoming messages do not update the oldest-message cursor.
- [ ] Incoming messages do not update the has-older-messages flag.
- [ ] Incoming messages remain recoverable through refresh because the message
      was persisted before broadcast.
- [ ] Focused channel LiveView tests cover one user sending a message and
      another user seeing it live in the same channel.
- [ ] Focused channel LiveView tests cover incoming live messages leaving an
      in-progress composer value alone when practical with the existing test
      helpers.

## Blocked by

- 1. Broadcast Persisted Channel Messages Through Chat PubSub

## 3. Prevent Sender Duplicates While Keeping Local Send Feedback

**Type:** AFK

**Blocked by:** 1. Broadcast Persisted Channel Messages Through Chat PubSub, 2. Render Incoming PubSub Messages In Subscribed Channel Views

**User stories covered:** 2-3, 18-20, 23-24, 27

## What to build

Keep the sender experience from the persisted-chat phase while adding live
delivery for everyone else. When a user sends a message, their own LiveView
should continue inserting the returned persisted message locally so feedback is
immediate. The PubSub broadcast should exclude the sending process, so the
sender does not receive the same message again through the live handler.

This slice should prove the caller contract remains simple: successful sends
still return the persisted message, invalid sends still return the existing
changeset error shape, and duplicate prevention is handled by PubSub sender
exclusion rather than by adding client-side or stream-level de-duplication
logic.

## Acceptance criteria

- [ ] The sender LiveView keeps the existing local stream insert after a
      successful send.
- [ ] The sender sees their saved message immediately after submit.
- [ ] The PubSub broadcast excludes the sending LiveView process.
- [ ] The sender does not receive or render a second copy of their own message.
- [ ] Duplicate prevention does not require changing the public
      `send_message/3` success return value.
- [ ] Invalid sends keep the existing invalid-message changeset behavior.
- [ ] Invalid sends do not broadcast anything to other subscribed LiveViews.
- [ ] Focused channel LiveView tests prove the sender sees exactly one copy of
      a sent message.
- [ ] Focused Chat context tests prove validation failures do not emit
      `{:message_created, message}` to subscribers.

## Blocked by

- 1. Broadcast Persisted Channel Messages Through Chat PubSub
- 2. Render Incoming PubSub Messages In Subscribed Channel Views

## 4. Prove Channel Isolation And Access Boundaries For Live Delivery

**Type:** AFK

**Blocked by:** 1. Broadcast Persisted Channel Messages Through Chat PubSub, 2. Render Incoming PubSub Messages In Subscribed Channel Views

**User stories covered:** 4-5, 11-18, 24-25, 27

## What to build

Harden the live-delivery boundary so PubSub follows the same privacy and
channel-scoping rules as persisted chat. A message sent in one channel should
only arrive in LiveViews subscribed to that channel, even when another channel
belongs to the same workspace. Logged-in non-members and anonymous scopes
should not be able to subscribe to private workspace channel messages.

The LiveView message handler can trust topic routing for this phase. The goal
is to prove that topic construction, subscription authorization, and broadcast
routing are correct rather than hiding mistakes behind an extra defensive
channel guard in the web layer.

## Acceptance criteria

- [ ] Live delivery is scoped to the selected channel ID.
- [ ] A message sent in one channel does not render live in another channel in
      the same workspace.
- [ ] Channel names are not used in PubSub topics.
- [ ] Workspace IDs are not required in PubSub topics for this phase.
- [ ] Logged-in non-members cannot subscribe to private workspace channel
      messages.
- [ ] Anonymous scopes cannot subscribe to channel messages.
- [ ] Missing or inaccessible channels use the same privacy-preserving access
      behavior as existing Chat workflows.
- [ ] The LiveView message handler does not add an extra channel guard that
      could hide incorrect topic routing.
- [ ] Focused Chat context tests cover unauthorized and anonymous subscription
      attempts.
- [ ] Focused channel LiveView tests cover two channels in the same workspace
      and prove no cross-channel delivery.

## Blocked by

- 1. Broadcast Persisted Channel Messages Through Chat PubSub
- 2. Render Incoming PubSub Messages In Subscribed Channel Views

## 5. Finalize Phase 6 Acceptance Coverage

**Type:** AFK

**Blocked by:** 1. Broadcast Persisted Channel Messages Through Chat PubSub, 2. Render Incoming PubSub Messages In Subscribed Channel Views, 3. Prevent Sender Duplicates While Keeping Local Send Feedback, 4. Prove Channel Isolation And Access Boundaries For Live Delivery

**User stories covered:** 1-27

## What to build

Finish the PubSub phase with an acceptance sweep. A workspace member should be
able to enter a channel, send a persisted message, see it immediately in their
own LiveView exactly once, and have another workspace member viewing the same
channel see the message live without refresh. Refresh and history loading
should still recover messages from Postgres, which remains the source of
truth.

This slice should also preserve the boundary to later phases. Do not introduce
ChannelServer processes, presence, typing indicators, optimistic send state,
retry UX, scroll hooks, multiline composer behavior, or message management
features while finishing PubSub.

## Acceptance criteria

- [ ] User A can send a message and User B sees it live in the same channel.
- [ ] User A sees their sent message exactly once.
- [ ] User B can refresh and still see the message from Postgres.
- [ ] Existing recent-message loading still reads from Postgres.
- [ ] Existing older-history loading still reads from Postgres.
- [ ] Existing invalid-message behavior still preserves the typed value and
      shows field-level errors.
- [ ] Existing workspace and channel shell behavior still works while live
      message delivery is enabled.
- [ ] No schema changes or migrations are introduced for this phase.
- [ ] No new routes or router scope changes are introduced for this phase.
- [ ] No ChannelServer, ChannelRegistry, ChannelSupervisor, recent-message
      cache, presence, typing, optimistic send, retry, or scroll-hook behavior
      is introduced.
- [ ] Deliberately deferred polish and OTP items remain documented in the PRD.
- [ ] Focused Chat context tests pass.
- [ ] Focused channel LiveView tests pass.
- [ ] The project precommit alias passes.

## Blocked by

- 1. Broadcast Persisted Channel Messages Through Chat PubSub
- 2. Render Incoming PubSub Messages In Subscribed Channel Views
- 3. Prevent Sender Duplicates While Keeping Local Send Feedback
- 4. Prove Channel Isolation And Access Boundaries For Live Delivery
