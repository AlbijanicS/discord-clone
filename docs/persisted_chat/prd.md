# Persisted Chat PRD

## Problem Statement

The Discord clone now has authenticated users, workspace creation, channel
navigation, workspace invites, and a desktop-style workspace shell. A workspace
member can enter a channel, but the main channel surface still shows a disabled
message composer placeholder. That means the app cannot yet prove the most
important collaboration loop: a workspace member writes a message, the message
is durably stored, and the same channel shows that message after reload.

The immediate problem is to build the smallest persisted chat slice before
adding PubSub, channel processes, presence, typing indicators, or other live
state. Durable message behavior should become boring and trustworthy first, so
later real-time delivery and OTP state can build on the same source of truth.

## Solution

Add persisted message workflows to the Chat context and replace the channel
placeholder with a real message history surface and composer.

An authenticated workspace member opening a channel sees the latest 50
messages in chronological display order. They can send a plain-text single-line
message through the existing channel page. The send workflow validates channel
access, persists the message in Postgres, returns the persisted message with
its author preloaded, and inserts it into the sender's current LiveView stream.
Other connected browsers do not update until refresh in this phase.

Older history is available through a simple "Load older" button backed by a
stable cursor using `inserted_at` plus `id`. This proves pagination without
introducing infinite-scroll hooks before live messaging exists.

## User Stories

1. As a workspace member, I want to open a channel and see recent messages, so that the channel feels like a real conversation space.
2. As a workspace member, I want messages to persist in the database, so that chat history survives refreshes and server restarts.
3. As a workspace member, I want the latest messages to load when I enter a channel, so that I can quickly catch up.
4. As a workspace member, I want messages shown oldest-to-newest on screen, so that the conversation reads naturally.
5. As a workspace member, I want to send a plain-text message, so that I can participate in the channel.
6. As a workspace member, I want my sent message to appear immediately in my current channel view, so that I get feedback that it was saved.
7. As a workspace member, I want a sent message to still appear after refresh, so that I know it was durably stored.
8. As a workspace member, I want each message to show the author's username, so that I know who wrote it.
9. As a workspace member, I want each message to show a compact timestamp, so that I have basic conversation context.
10. As a workspace member, I want message content rendered as escaped plain text, so that unsafe HTML is not executed.
11. As a workspace member, I want leading and trailing whitespace trimmed, so that accidental spacing does not create messy messages.
12. As a workspace member, I want blank messages rejected, so that empty chat entries are not persisted.
13. As a workspace member, I want overly long messages rejected, so that the message table and UI stay bounded.
14. As a workspace member, I want validation errors shown near the composer, so that I can correct invalid input without leaving the channel.
15. As a workspace member, I want my invalid message content to remain in the composer, so that I do not lose what I typed.
16. As a workspace member, I want the composer cleared after a successful send, so that I can type the next message immediately.
17. As a workspace member, I want to load older messages when history exists, so that I can read beyond the first page.
18. As a workspace member, I want older messages inserted above the currently visible messages, so that conversation order remains stable.
19. As a workspace member, I want the "Load older" action to disappear when there is no older history, so that unavailable actions are not shown.
20. As a workspace member, I want an empty channel state when no messages exist, so that a new channel does not look broken.
21. As a workspace member, I want the composer available as soon as the channel page loads, so that I can start writing without extra setup.
22. As a logged-in non-member, I should not be able to read channel messages, so that private workspace boundaries are preserved.
23. As a logged-in non-member, I should not be able to send messages to a private workspace channel, so that chat access follows workspace membership.
24. As an anonymous visitor, I should not be able to load or send messages, so that chat always attaches to an authenticated user.
25. As a workspace member, I want message history and sending to use the selected channel ID, so that messages do not leak across channels.
26. As a workspace member, I want channel deletion to remove its messages, so that deliberate channel deletion removes the channel's conversation.
27. As a developer, I want message read and send workflows behind the Chat context, so that LiveViews do not assemble chat domain rules directly.
28. As a developer, I want Chat workflows to authorize channel membership themselves, so that web modules cannot accidentally bypass access rules.
29. As a developer, I want sent messages and listed messages to use the same preloaded message shape, so that PubSub can broadcast the same value later.
30. As a developer, I want the persisted message returned from send, so that Phase 6 can broadcast after successful persistence without reshaping data.
31. As a developer, I want latest-message and older-message queries to share one ordering policy, so that pagination does not duplicate or skip messages.
32. As a developer, I want cursor pagination based on `inserted_at` plus `id`, so that messages with the same timestamp still page predictably.
33. As a developer, I want the channel LiveView to own chat behavior, so that the shared workspace shell does not grow into the whole product.
34. As a developer, I want the shell to preserve workspace and channel navigation while chat is shown, so that the app still feels like a desktop chat client.
35. As a learner, I want this phase to prove durable chat before PubSub, so that real-time behavior does not hide persistence mistakes.

## Implementation Decisions

- Build this as Phase 5, the persisted chat slice.
- Keep this phase non-live across clients. The sender's LiveView updates from the returned persisted message, while other connected sessions update only after refresh until Phase 6.
- Add public Chat context workflows for changing a message form, listing recent messages, listing older messages, and sending messages.
- The Chat context should be the public entry point for persisted message behavior.
- Chat workflows should authorize by querying channel and workspace membership data directly.
- A user may read and send messages in any channel inside a workspace where they are a workspace member.
- Missing or inaccessible channels should recover through the same generic channel access behavior used elsewhere in the app.
- Message content remains plain text only.
- Message content is trimmed before validation.
- Blank content is invalid.
- Message content keeps the existing maximum length of 4,000 characters.
- No markdown, rich formatting, mentions, emoji parsing, attachments, embeds, edits, or deletes are included in this phase.
- The composer is single-line for this phase.
- Enter submits through the normal LiveView form behavior.
- Multiline composition is deferred until after persisted chat and PubSub are stable.
- Latest channel entry loads at most 50 messages.
- Older history pagination also loads at most 50 messages per request.
- Database queries may fetch newest-first for efficiency, but public Chat list APIs should return messages oldest-to-newest for rendering.
- Older history pagination uses a cursor made from the oldest loaded message's `inserted_at` and `id`.
- Message list APIs return persisted message structs with the author preloaded.
- The send workflow returns the persisted message with the author preloaded.
- The same message shape should be usable by initial load, load older, local send, future PubSub broadcasts, and future channel process caches.
- The LiveView should use streams for message rendering.
- The message stream belongs to the channel show LiveView.
- The shared workspace shell should remain responsible for the desktop app frame, sidebars, selected workspace and channel controls, and navigation.
- The channel main area should be provided by the channel show LiveView through a small slot-style shell refactor.
- The shell must continue to allow fast workspace navigation, channel navigation, invite creation, workspace creation, channel creation, rename, delete, and leave actions while the chat surface is visible.
- On successful send, reset the composer form and insert the returned message at the bottom of the message stream.
- On validation failure, keep the composer content and show field-level errors.
- On send authorization or channel lookup failure, redirect to the workspace index with a generic access flash.
- Render each message with author username, compact server-rendered timestamp, and escaped content.
- Use a semantic time element with a datetime value so richer timestamp formatting can be added later.
- Do not add client timezone conversion, relative timestamps, or date separators in this phase.
- Render a "Load older" button above the stream when there may be older history.
- Hide the "Load older" button once a page smaller than 50 messages is returned.
- Empty channels show a small empty state instead of a load-older action.
- Keep scroll behavior minimal and server-only. Do not add auto-scroll or scroll-position preservation hooks yet.
- Channel deletion continues to delete its messages through the existing database foreign key behavior.
- No schema changes are expected because the messages table and message schema already exist.

## Testing Decisions

- Test public behavior rather than private helper implementation.
- Add focused Chat context tests for form changesets, recent message loading, older message pagination, sending, validation failures, authorization, and reload persistence.
- Add channel LiveView tests for rendering existing messages, empty state, successful send, validation errors, load-older behavior, and access recovery.
- Do not add schema-only message tests unless new validation logic appears that cannot be naturally covered through the Chat context.
- Chat context tests should create users, workspaces, memberships, and channels through existing public workflows or fixtures.
- Chat context tests should prove non-members cannot list or send messages.
- Chat context tests should prove anonymous scopes return unauthenticated outcomes.
- Chat context tests should prove messages are scoped to the selected channel.
- Chat context tests should prove messages are returned with author preloaded.
- Chat context tests should prove list APIs return messages oldest-to-newest.
- Chat context tests should prove pagination does not duplicate the cursor message.
- Chat context tests should prove messages with the same timestamp can still paginate by `id`.
- Chat context tests should prove `send_message` trims content, rejects blank content, rejects overlong content, and returns a changeset for invalid content.
- LiveView tests should use stable DOM IDs with `element/2`, `has_element?/2`, `form/3`, and `render_submit/1`.
- LiveView tests should not assert raw HTML.
- LiveView tests should cover the shell staying present while the chat surface is rendered.
- LiveView tests should cover the message composer replacing the disabled placeholder.
- LiveView tests should cover successful send clearing the form and showing the new message.
- LiveView tests should cover validation failure keeping the form open with errors.
- LiveView tests should cover refresh showing a previously sent message by loading from Postgres.
- LiveView tests should cover the load-older button prepending older messages.
- Existing Workspaces context tests provide prior art for public context authorization and return contracts.
- Existing workspace LiveView tests provide prior art for shell rendering, streams, form submission, and access recovery.
- Run focused Chat context tests first, then focused channel LiveView tests, then the project precommit alias.

## Out of Scope

- PubSub cross-client message delivery.
- ChannelServer or any OTP-backed channel state.
- Presence tracking.
- Typing indicators.
- Online user lists.
- Multiline composer behavior.
- Shift+Enter newline handling.
- Automatic scrolling after send.
- Scroll-position preservation after loading older messages.
- Infinite scroll or scroll-triggered pagination.
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
- Publishing this PRD to an issue tracker.

## Further Notes

This PRD comes from a 20-question `grill-me` session about Phase 5. The session
intentionally separated persisted chat from Phase 6 PubSub and Phase 7 OTP
channel processes. The key architectural decision is to make Postgres the
source of truth first, then make the same persisted message shape easy to pass
through PubSub and future channel process caches.

Deferred polish items should be revisited after Phase 5 and Phase 6 are both
working: multiline composer behavior, richer formatting, message edit/delete,
automatic scroll handling, infinite scroll, and richer empty/loading states.

Issue tracker publishing is blocked because this repository still does not
define the tracker configuration or triage label vocabulary expected by the
local `to-prd` skill. Existing PRDs in this repository use the same docs-first
fallback and note that tracker setup has not been completed.
