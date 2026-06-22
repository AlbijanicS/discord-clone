# Live Messages With PubSub PRD

## Problem Statement

The Discord clone now has authenticated users, workspace creation, channel
navigation, workspace invites, a desktop-style workspace shell, and persisted
chat. A workspace member can enter a channel, read recent messages, send a
plain-text message, load older history, refresh the page, and recover chat
history from Postgres.

The remaining gap in the core chat loop is live delivery. When one connected
workspace member sends a message, another member viewing the same channel still
does not see it until refresh. That makes the chat surface durable, but not yet
collaborative in the way users expect from a Discord-style application.

The immediate problem is to add the smallest possible live message delivery
slice on top of the existing persisted chat behavior. PubSub should deliver
newly persisted messages to other connected channel views without introducing
ChannelServer processes, presence, typing indicators, scroll hooks, optimistic
send state, or richer composer behavior.

## Solution

Add Phoenix PubSub delivery for newly created channel messages.

An authenticated workspace member opening a channel subscribes to that
channel's message topic after channel access is proven and only after the
LiveView websocket is connected. When a member sends a message, the existing
Chat send workflow continues to validate membership, insert the message in
Postgres, preload the author, and return the persisted message. After
successful persistence and preload, the Chat context broadcasts the persisted
message to the selected channel topic.

The sender's LiveView keeps the existing local stream insert after the send
workflow returns. The PubSub broadcast excludes the sender process, so the
sender does not render a duplicate. Other connected LiveViews subscribed to the
same channel topic receive the persisted message and stream it at the bottom of
their message list. Refreshing or loading history still reads from Postgres,
which remains the source of truth.

## User Stories

1. As a workspace member, I want another member's new message to appear while I am viewing the same channel, so that the conversation feels live.
2. As a workspace member, I want my sent message to keep appearing immediately in my own channel view, so that I get fast feedback that the message was saved.
3. As a workspace member, I want my sent message to appear only once in my own channel view, so that local insertion and live delivery do not create duplicates.
4. As a workspace member, I want live messages to appear only in the channel where they were sent, so that conversations do not leak across channels.
5. As a workspace member, I want live delivery to use durable channel identity, so that channel renames do not break subscriptions.
6. As a workspace member, I want a newly received live message to use the same rendering as loaded messages, so that the chat surface stays visually consistent.
7. As a workspace member, I want incoming live messages to leave my composer text alone, so that another member's activity does not erase what I am typing.
8. As a workspace member, I want incoming live messages not to disturb older-history pagination, so that "Load older" keeps using the oldest loaded message as its cursor.
9. As a workspace member, I want a refresh to still recover all sent messages from Postgres, so that live delivery is not the only way to see chat history.
10. As a workspace member, I want a missed PubSub event to be recoverable through refresh or history loading, so that temporary live delivery issues do not lose messages.
11. As a workspace member, I want the app to keep using the selected channel ID for sending and receiving, so that the current channel remains the chat boundary.
12. As a logged-in non-member, I should not be able to subscribe to a private channel's live messages, so that workspace privacy is preserved.
13. As an anonymous visitor, I should not be able to subscribe to channel messages, so that live chat always attaches to an authenticated user.
14. As a workspace member whose access changes mid-load, I want the app to recover through the existing generic channel access behavior, so that inconsistent access state does not expose private messages.
15. As a developer, I want PubSub topic construction hidden behind the Chat context, so that LiveViews do not assemble topic strings directly.
16. As a developer, I want channel subscription to be a public Chat workflow, so that chat access rules stay in the application core.
17. As a developer, I want the Chat context to recheck membership before subscribing, so that knowing a topic shape is not enough to receive private messages.
18. As a developer, I want broadcasting to happen inside the Chat send workflow, so that every future send path gets live delivery after persistence.
19. As a developer, I want send return values to stay unchanged, so that PubSub is a side effect of successful persistence rather than a new caller contract.
20. As a developer, I want the broadcast payload to be the persisted message with the author preloaded, so that subscribers do not reshape raw input or perform extra fetches.
21. As a developer, I want the broadcast event to be a simple tagged tuple, so that this phase stays understandable while there is only one event type.
22. As a developer, I want event construction centralized in the Chat context, so that a later event struct can be introduced without spreading PubSub internals through the web layer.
23. As a developer, I want sender duplicate prevention to use PubSub sender exclusion, so that the existing local sender insert remains simple.
24. As a developer, I want tests for live message delivery at both context and LiveView levels, so that broadcast wiring and user-visible behavior are covered.
25. As a developer, I want no cross-channel delivery tests in the same workspace, so that the selected topic shape is proven rather than accidentally passing through workspace boundaries.
26. As a learner, I want this phase to prove PubSub delivery without adding OTP channel processes, so that the next phase can focus cleanly on ChannelServer behavior.
27. As a learner, I want this phase to keep Postgres as the source of truth, so that live delivery does not hide persistence or recovery mistakes.

## Implementation Decisions

- Build this as Phase 6, the live messages with PubSub slice.
- Keep the phase scoped to messages only.
- Use Phoenix PubSub through the existing application PubSub process.
- Use channel-level topics in the shape `chat:channel:#{channel_id}`.
- Use durable channel IDs in topics.
- Do not include channel names in topics because channel names can change.
- Do not include workspace IDs in topics for this phase because channel IDs are globally unique database IDs and workspace identity is redundant for routing.
- The topic shape should not fight the later ChannelServer design, which will also address channels by durable channel ID.
- The Chat context should own topic construction.
- The channel topic helper should stay private to the Chat context.
- Add a public Chat subscription workflow for channel messages.
- The subscription workflow should require an authenticated scope.
- The subscription workflow should recheck channel membership before subscribing.
- Unauthorized subscription attempts should return the same privacy-preserving errors as existing Chat workflows.
- Authenticated members should receive `:ok` from the subscription workflow.
- Anonymous scopes should receive `{:error, :unauthenticated}` from the subscription workflow.
- Missing or inaccessible channels should receive `{:error, :not_found}` from the subscription workflow.
- Channel LiveViews should call the public Chat subscription workflow rather than calling Phoenix PubSub directly.
- Channel LiveViews should subscribe in mount only after workspace, channel, channel list, workspace list, and recent message loading have succeeded.
- Channel LiveViews should subscribe only when the LiveView socket is connected.
- A failed subscription after earlier access checks should use the same generic channel access recovery as other channel access failures.
- Router placement should remain unchanged.
- Channel chat should remain inside the existing authenticated browser scope.
- Channel chat should remain inside the existing `live_session` that requires authenticated users.
- The route placement is unchanged because channel chat requires `current_scope` and workspace membership.
- Broadcasting should happen inside the Chat send workflow.
- Broadcasting should happen only after membership validation, successful Postgres insert, and author preload.
- The persisted message remains the source of truth.
- PubSub delivery is best-effort live delivery layered on top of persistence.
- A successful Postgres insert and preload should still return success even if live delivery misses a subscriber.
- Send return contracts should remain unchanged.
- Validation failures should not broadcast anything.
- Authorization failures should not broadcast anything.
- Read operations should not broadcast anything.
- Initial recent-message loading should not broadcast anything.
- Older-history loading should not broadcast anything.
- The only PubSub event in this phase should be a message-created event.
- The event payload should be the persisted message struct with its author preloaded.
- The event shape should be a simple tagged tuple.
- A separate event module or event struct should not be introduced in this phase.
- Event construction should remain centralized in the Chat context so a later event struct can be introduced if typing, presence, or channel process coordination make it useful.
- Sender duplicate prevention should use PubSub sender exclusion.
- The sender LiveView should keep the existing local stream insert after the send workflow returns.
- The PubSub broadcast should exclude the sending process.
- Other subscribed LiveViews should receive the broadcast and stream the message.
- Incoming PubSub messages should be inserted at the bottom of the existing message stream.
- Incoming PubSub messages should not reset or modify the composer form.
- Incoming PubSub messages should not update the oldest-message cursor.
- Incoming PubSub messages should not update the has-older-messages flag.
- The oldest-message cursor means the oldest loaded top-of-history message used for older-history pagination.
- Only prepending older messages should update the oldest-message cursor.
- Topic routing should be trusted in the LiveView message handler for this phase.
- The LiveView message handler should not add an extra channel guard that could hide topic-routing mistakes.
- No schema changes are expected.
- No migration is expected.
- No new route is expected.

## Testing Decisions

- Test public behavior rather than private helper implementation.
- Add focused Chat context tests for PubSub subscription and broadcast behavior.
- Add focused channel LiveView tests for user-visible live delivery behavior.
- Context tests should prove a subscribed process receives a message-created event after a successful send.
- Context tests should prove the event contains the persisted message with the author preloaded.
- Context tests should prove validation failures do not broadcast.
- Context tests should prove unauthenticated scopes cannot subscribe.
- Context tests should prove logged-in non-members cannot subscribe to private workspace channels.
- Context tests should use public Chat APIs rather than calling private topic helpers.
- LiveView tests should use two authenticated users who are both workspace members for the main live-delivery workflow.
- LiveView tests should prove User A can send a message and User B sees it live in the same channel.
- LiveView tests should prove the sender sees the sent message exactly once.
- LiveView tests should prove no cross-channel delivery using two channels in the same workspace.
- LiveView tests should prove incoming live messages do not clear another user's composer content if practical with existing LiveView test helpers.
- LiveView tests should use stable DOM IDs with `element/2`, `has_element?/2`, form helpers, and LazyHTML selectors where counts matter.
- LiveView tests should avoid raw HTML assertions.
- Tests should preserve the existing persisted-chat guarantees that refresh and history loading read from Postgres.
- Existing Chat context tests provide prior art for authorization, return contracts, validation failures, and message shape assertions.
- Existing channel LiveView tests provide prior art for shell rendering, message streams, form submission, and access recovery.
- Run focused Chat context tests first.
- Run focused channel LiveView tests second.
- Run the project precommit alias after implementation is complete.

## Out of Scope

- Typing indicators.
- Presence tracking.
- Online user lists.
- ChannelServer or any OTP-backed channel state.
- ChannelRegistry.
- ChannelSupervisor.
- Recent-message cache.
- Channel process inactivity timeout.
- LiveView process monitoring for presence or typing.
- Typing expiry.
- Optimistic pending messages.
- Retry or resend UX.
- Client-generated message IDs.
- Auto-scroll after sending a message.
- Auto-scroll after receiving a live message.
- Scroll-position preservation after loading older messages.
- Infinite scroll.
- Scroll-triggered pagination.
- Multiline composer behavior.
- Shift+Enter newline handling.
- Richer composer interactions.
- Markdown or rich text rendering.
- Mentions.
- Emoji parsing.
- Attachments.
- Embeds.
- Reactions.
- Message editing.
- Message deletion.
- Soft deletion or archival of messages after channel deletion.
- Role-based read or send permissions beyond the current workspace membership gate.
- Client timezone conversion.
- Relative timestamps.
- Date separators or grouped message days.
- Rate limiting.
- Message search.
- Dedicated PubSub event module or event struct.
- New routes or router scope changes.
- Publishing this PRD to an issue tracker.

## Further Notes

This PRD comes from a capped 23-question `grill-me` session about Phase 6.
The session intentionally kept PubSub focused on live message delivery and
preserved the clean separation between Phase 5 persisted chat, Phase 6 PubSub,
Phase 7 OTP channel processes, and Phase 8 presence and typing.

The central architectural decision is that Postgres remains the source of
truth. PubSub is a delivery mechanism for messages that have already been
persisted. If a live event is missed, refresh or history loading should recover
the message from Postgres.

The most important deliberately deferred items are ChannelServer work,
presence, typing indicators, retry/resend pending UX, and scroll behavior.
Those features should be revisited after basic live delivery is boring and
well-tested.

Several items are deliberately left out even though a real chat product should
eventually have them. They are deferred to keep this phase PubSub-focused, not
because they are unimportant:

- automatic scroll after the sender sends a message
- automatic scroll when an incoming live message arrives and the viewer is
  already near the bottom
- preserving scroll position when older messages are prepended
- optimistic pending messages with sent/failed status
- retry or resend controls for messages that fail before persistence
- multiline composer behavior
- richer composer keyboard handling
- message editing
- message deletion
- markdown or richer text formatting
- mentions
- reactions
- typing indicators
- presence and online user lists

The likely follow-up order is to finish and test PubSub first, then add the
minimal scroll behavior needed for a pleasant chat experience, then revisit
composer and message-management polish around the same time as the later OTP
channel process work.

Issue tracker publishing is blocked because this repository still does not
define the tracker configuration or triage label vocabulary expected by the
local `to-prd` skill. Existing PRDs in this repository use the same docs-first
fallback and note that tracker setup has not been completed.
