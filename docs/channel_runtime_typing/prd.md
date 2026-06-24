# Channel Runtime And Typing Indicators PRD

## Problem Statement

The Discord clone already has authenticated workspace membership, workspace
entry, channel navigation, persisted chat, live message delivery through PubSub,
and workspace-scoped online presence. A workspace member can enter a Channel,
read recent durable messages, send messages, see other members' messages live,
and see which Workspace Members are online in the workspace.

The next gap is channel-local runtime state. Messages are durable and belong in
Postgres, but active Channel behavior also needs an in-memory owner. Without a
Channel runtime process, typing indicators have no correct place to live, recent
message caching would be scattered or ornamental, and the project would skip the
OTP learning goal of on-demand process startup, process identity, temporary
state, crash recovery, and idle process shutdown.

The user-facing feature is typing indicators. The learning feature is the
ChannelServer foundation that makes typing state legitimate instead of tacked
onto the LiveView. This PRD covers both as one phase with two explicitly ordered
milestones. Channel Runtime Foundation must be implemented first. Typing
Indicators are built on top of that runtime second.

This PRD deliberately excludes channel-scoped online presence. Workspace
presence already answers the product need: if a user is in a Channel, they are
inside the Workspace and therefore online in that Workspace.

## Solution

Add a supervised Channel runtime behind the Chat context, then add typing
indicators on top of it.

Milestone 1 introduces a ChannelRegistry, ChannelSupervisor, and ChannelServer.
An authenticated Workspace Member entering a Channel calls a public Chat API to
ensure the Channel runtime exists after Channel access is proven and only after
the LiveView websocket is connected. Channel processes are named by durable
Channel ID, not Channel name. Each ChannelServer owns temporary state for one
active Channel: the Channel ID, a latest-message cache, a last-activity
timestamp, and eventually typing user deadlines.

The latest-message cache is initialized synchronously from Postgres with the
latest 50 persisted messages. Postgres remains the source of truth. If a
ChannelServer crashes or shuts down after inactivity, the next lookup starts it
again and rebuilds the cache from durable messages. Once runtime startup is
proven, recent message reads move through the ChannelServer cache via the Chat
context.

Message sending remains a persist-first workflow. Chat validates membership,
inserts the message into Postgres, preloads the author, updates the
ChannelServer recent-message cache, clears the sender's typing state, and then
broadcasts the persisted message event. Direct PubSub is acceptable for this
phase because reload and history loading recover from Postgres if a live event
is missed. A future production-hardening phase may introduce an outbox for
persisted message events.

Milestone 2 adds typing indicators. The browser throttles typing notifications.
The LiveView calls public Chat APIs to start and stop typing. The ChannelServer
stores only user IDs mapped to typing deadlines. Typing expires after 5 seconds,
and expiry broadcasts a stopped event. Normal UI transitions, such as clearing
the composer or submitting a message, send explicit stop signals. Unexpected
disconnects rely on expiry rather than LiveView PID monitoring in this first
typing milestone.

Typing events use the existing channel PubSub topic and carry only Channel ID
and User ID. The UI never displays the current user's own typing state, even if
the LiveView receives self-originating typing events. Display names come from
durable member/user data already available to the workspace UI, not from the
ChannelServer.

## User Stories

1. As a workspace member, I want entering a Channel to start or find its runtime process, so that active Channels can own temporary live state.
2. As a workspace member, I want Channel runtime startup to happen only after access is proven, so that private Workspace activity stays protected.
3. As a workspace member, I want Channel runtime startup to avoid disconnected static renders, so that merely rendering the first HTTP response does not create unnecessary processes.
4. As a workspace member, I want Channel processes to use durable Channel IDs, so that Channel renames do not break runtime identity.
5. As a workspace member, I want recent message loading to continue showing the latest persisted messages, so that the Channel still opens with useful history.
6. As a workspace member, I want recent message reads to recover if the Channel runtime was restarted, so that a process crash does not hide durable messages.
7. As a workspace member, I want sent messages to remain durable in Postgres, so that runtime failures never become message loss.
8. As a workspace member, I want sent messages to update the active Channel cache, so that the runtime state reflects the latest persisted conversation.
9. As a workspace member, I want another member's sent messages to continue arriving live, so that Channel runtime work does not regress PubSub messaging.
10. As a workspace member, I want inactive Channel runtime processes to shut down after a while, so that temporary processes do not live forever.
11. As a workspace member, I want reopening an inactive Channel to restart its runtime and reload recent messages, so that idle cleanup is invisible to normal use.
12. As a workspace member, I want reading, sending, and typing activity to keep the Channel runtime alive, so that active Channels are not shut down prematurely.
13. As a workspace member, I want to see when another member is typing in the current Channel, so that the chat surface feels responsive and alive.
14. As a workspace member, I want typing indicators to appear quickly but not send every keypress to the server, so that the feature feels live without noisy events.
15. As a workspace member, I want typing indicators to disappear automatically, so that stale typing state does not linger after a tab closes or a network event is missed.
16. As a workspace member, I want typing to stop when a message is sent, so that the UI does not show someone typing after their message appears.
17. As a workspace member, I want typing to stop when the composer is cleared, so that the indicator matches the user's visible intent.
18. As a workspace member, I do not want to see my own typing indicator, so that the UI does not show redundant "you are typing" state.
19. As a workspace member, I want typing indicators to stay scoped to the selected Channel, so that activity does not leak across Channels.
20. As a workspace member, I want typing state to be temporary, so that it is never persisted in Postgres.
21. As a workspace member, I want online status to remain workspace-scoped, so that the right sidebar does not duplicate channel-local presence.
22. As a logged-in non-member, I should not be able to start, read, subscribe to, or publish Channel runtime state, so that private Workspace activity remains private.
23. As an anonymous visitor, I should not be able to interact with Channel runtime state, so that runtime behavior always attaches to an authenticated User.
24. As a developer, I want all Channel runtime behavior hidden behind the Chat context, so that LiveViews do not call Registry, DynamicSupervisor, ChannelServer, Repo, or PubSub directly for runtime workflows.
25. As a developer, I want an explicit Chat API for ensuring Channel runtime, so that process startup is visible and testable.
26. As a developer, I want the ensure-runtime API to return the Channel process PID, so that process reuse and crash recovery are easy to prove in tests and IEx.
27. As a developer, I want ChannelServer state to avoid durable Workspace data, so that the process does not become a shadow copy of database records.
28. As a developer, I want recent-message cache initialization to be bounded to 50 messages, so that synchronous startup remains simple and predictable.
29. As a developer, I want cache rebuilds to read from Postgres, so that crash recovery reinforces the durable-versus-temporary state boundary.
30. As a developer, I want message-created broadcasts to remain owned by Chat, so that persisted command workflows publish persisted events from one public boundary.
31. As a developer, I want ChannelServer to broadcast temporary typing events, so that in-memory state changes are announced by the process that owns that state.
32. As a developer, I want typing APIs to be public Chat workflows, so that LiveViews stay ignorant of runtime internals.
33. As a developer, I want typing state to store user IDs and deadlines only, so that display data remains durable member/user data.
34. As a developer, I want typing event payloads to contain only Channel ID and User ID, so that event handling stays small and explicit.
35. As a developer, I want typing reads to return raw runtime state, including the current user if present, so that API truth is separated from UI display rules.
36. As a developer, I want the LiveView to filter self-typing before display, so that transport choices do not affect the user-facing rule.
37. As a developer, I want typing disconnect cleanup to rely on expiry for now, so that typing does not duplicate presence-like PID tracking.
38. As a learner, I want this phase split into small ordered slices, so that Channel runtime mechanics are understood before typing UI is added.
39. As a learner, I want runtime failure and restart behavior tested explicitly, so that temporary state loss is expected rather than surprising.
40. As a future maintainer, I want direct PubSub limitations documented, so that a later outbox/event pipeline can be introduced intentionally for persisted events.

## Implementation Decisions

- Build this as one PRD with two ordered milestones: Channel Runtime Foundation first, Typing Indicators second.
- Do not implement typing before Channel runtime startup, lookup, cache, and recovery behavior are boring and tested.
- Add a ChannelRegistry, ChannelSupervisor, and ChannelServer under the Chat runtime area.
- Register Channel processes by durable Channel ID.
- Do not register or look up Channel processes by Channel name.
- Add public Chat runtime workflow `ensure_channel_runtime/2`.
- `ensure_channel_runtime/2` returns `{:ok, pid}` on success.
- `ensure_channel_runtime/2` returns `{:error, :unauthenticated}` when no authenticated scope is available.
- `ensure_channel_runtime/2` returns `{:error, :not_found}` when the Channel is missing or the user is not a Workspace Member.
- `ensure_channel_runtime/2` authorizes by fetching the member-accessible Channel through the same membership join shape used by existing Chat Channel access workflows.
- `ensure_channel_runtime/2` does not need to preload or store Workspace data.
- Channel LiveViews should call the public ensure-runtime workflow when connected and after Channel access is proven.
- The route placement remains unchanged: Channel LiveViews stay in the existing authenticated browser pipeline and existing authenticated LiveView session because they require `current_scope` and Workspace membership.
- ChannelServer initial state should include Channel ID, latest-message cache, last-activity timestamp, and typing user deadlines.
- ChannelServer state should not include Workspace ID for now.
- ChannelServer state should not include Channel name for now.
- ChannelServer state should not include channel-scoped online users.
- ChannelServer state should not include full user structs.
- The latest-message cache should be initialized synchronously during ChannelServer startup.
- Cache initialization should load the latest 50 persisted messages from Postgres.
- Cache initialization should preload author data needed for message rendering.
- Keep synchronous initialization because the query is bounded, small, and simpler for the first ChannelServer milestone.
- Document async cache warmup as a possible future optimization if startup latency becomes visible.
- Postgres remains the source of truth for all message history.
- The ChannelServer cache is an acceleration and coordination layer, not durable storage.
- `list_recent_messages/2` should move to ensure/start the Channel runtime and read from the ChannelServer cache after `ensure_channel_runtime/2` is implemented and tested.
- Older message pagination should continue reading from Postgres.
- Sending a message remains a persist-first workflow.
- Message send order is: validate membership, insert message in Postgres, preload author, update ChannelServer recent-message cache, clear the sender's typing state, broadcast the persisted message event.
- If the Channel process crashed before cache update, Chat should ensure or restart the process and allow it to rebuild from Postgres.
- Unexpected runtime errors should be visible in tests/logs rather than silently swallowed as if the cache were correct.
- Returning a validation-style error after a successful database insert would be misleading and should be avoided.
- Chat continues to own PubSub broadcasting for persisted message-created events.
- ChannelServer may own PubSub broadcasting for temporary typing state events.
- Direct PubSub remains acceptable for this phase because missed live message events can be recovered from Postgres through reload or history loading.
- A future production-hardening phase may add an outbox/event pipeline for persisted events such as message-created.
- Do not persist typing events or typing state in an outbox.
- Add public Chat typing workflows: user started typing, user stopped typing, subscribe to Channel typing, and list typing user IDs.
- Typing workflows should authorize the current scope against Channel membership before reading or mutating runtime typing state.
- Typing PubSub uses the same channel topic as message events.
- Typing event names should be distinct from message events.
- Typing event payloads contain Channel ID and User ID only.
- Typing state stores only `user_id => expires_at`.
- Typing expiry is 5 seconds.
- Typing started refreshes the user's expiry.
- Typing started broadcasts only when the user was not already typing.
- Typing stopped removes the user and broadcasts only when the user was previously typing.
- ChannelServer broadcasts typing stopped when a typing expiry fires.
- The client should throttle typing-start events rather than sending every keypress.
- The server remains authoritative for typing expiry.
- Submitting a message clears the sender's typing state through the send workflow.
- Clearing the composer or other normal UI transitions should explicitly call the stop-typing workflow.
- Unexpected disconnects rely on the 5-second typing expiry in the first typing milestone.
- Do not add LiveView PID monitoring for typing cleanup in this phase.
- `list_typing_user_ids/2` returns raw runtime state and may include the current user.
- The LiveView filters out the current user before displaying typing indicators.
- The UI must never display self-typing.
- Typing display names should come from durable member/user data, not typing event payloads.
- Activity should update `last_activity_at` when the runtime is ensured, recent cache is read, a message is sent, or typing state changes.
- Idle ChannelServer processes should shut down after 15 minutes without ensure/read/message/typing activity.
- The inactivity timeout should be a module attribute or otherwise easy to identify.
- Tests should not wait 15 minutes; timeout behavior should be tested through direct messages, short configured values, or focused helper paths.
- No schema changes are expected.
- No migration is expected.
- No new route is expected.
- Do not introduce channel-scoped online presence.

## Testing Decisions

- Test public behavior before private implementation details.
- Use public Chat APIs wherever possible for context and runtime tests.
- Add focused tests for `ensure_channel_runtime/2`.
- Ensure-runtime tests should prove authenticated Workspace Members can start a Channel process.
- Ensure-runtime tests should prove duplicate starts reuse the same process.
- Ensure-runtime tests should prove anonymous scopes receive `{:error, :unauthenticated}`.
- Ensure-runtime tests should prove logged-in non-members and missing Channels receive `{:error, :not_found}`.
- Add ChannelServer-focused tests for process state, cache initialization, cache updates, typing state, expiry, and inactivity shutdown.
- ChannelServer tests should use standard OTP test patterns: `start_supervised!/1`, `Process.monitor/1`, DOWN assertions, and sys-state synchronization where needed.
- ChannelServer tests should avoid `Process.sleep/1`.
- Add Chat context tests proving `list_recent_messages/2` reads from the runtime cache once runtime-backed reads are introduced.
- Add Chat context tests proving crash/restart rebuilds recent messages from Postgres.
- Add Chat context tests proving sending a message persists first, updates the cache, clears typing state, and broadcasts the persisted message.
- Add Chat context tests proving runtime startup and runtime mutation are hidden behind Chat.
- Add Chat context tests for all public typing APIs.
- Typing API tests should prove started, stopped, subscribe, and list behavior.
- Typing API tests should prove non-members and anonymous scopes cannot interact with typing state.
- Typing API tests should prove event payloads contain Channel ID and User ID.
- Typing API tests should prove typing started is not rebroadcast repeatedly while a user is already typing.
- Typing API tests should prove typing stopped is broadcast when a user explicitly stops or expiry fires.
- Typing API tests should prove `list_typing_user_ids/2` returns raw state and may include the current user.
- Add Channel LiveView tests for runtime startup on connected mount if practical with existing LiveView test helpers.
- Add Channel LiveView tests proving typing indicators render for another Workspace Member in the same Channel.
- Add Channel LiveView tests proving self-typing is not displayed.
- Add Channel LiveView tests proving typing is scoped to one Channel and does not appear in another Channel.
- Add Channel LiveView tests proving sending a message clears that user's typing indicator for other viewers.
- Add Channel LiveView tests using stable DOM IDs and LiveViewTest helpers rather than raw HTML assertions.
- Existing Chat context tests provide prior art for channel authorization, message persistence, PubSub subscription, and broadcast behavior.
- Existing Workspace presence runtime tests provide prior art for Registry, DynamicSupervisor, GenServer, process reuse, and PubSub runtime events.
- Existing Channel LiveView tests provide prior art for channel page mount, message streams, message composer submission, and access recovery.
- Run focused Channel runtime tests first.
- Run focused Chat context tests second.
- Run focused Channel LiveView tests after UI integration.
- Run the project precommit alias after implementation changes.

## Out of Scope

- Channel-scoped online presence.
- Replacing workspace-scoped presence.
- Storing online users in ChannelServer state.
- Persisting typing state in Postgres.
- Persisting typing events in an outbox.
- Building a production outbox/event pipeline in this phase.
- Distributed process registry across multiple BEAM nodes.
- Phoenix Presence.
- Loading all messages into ChannelServer state.
- Making ChannelServer the durable source of truth for messages.
- Older-history pagination through ChannelServer.
- Channel permissions beyond the existing Workspace membership gate.
- Role-specific typing or sending permissions.
- Rate limiting.
- Unread counts.
- Mentions.
- Message edits.
- Message deletion.
- Reactions.
- Attachments.
- Rich text or markdown rendering.
- Multiline composer behavior unless needed minimally for typing hooks.
- Broad UI polish beyond the typing indicator surface.
- New routes or router scope changes.
- Publishing implementation issues to a remote tracker.

## Further Notes

This PRD comes from a capped `grill-me` session for the next in-memory phase.
The central decision is to keep one PRD while preserving two ordered milestones.
The first milestone teaches on-demand Channel processes, Registry,
DynamicSupervisor, GenServer state, cache rebuild, and idle shutdown. The second
milestone uses that foundation for typing indicators.

The strongest non-goal is channel-scoped online presence. Workspace presence
already tracks whether a User is online in the Workspace. If a User is in a
Channel, they are in the Workspace. Duplicating that state locally inside every
Channel process would make the mental model worse.

Direct PubSub for persisted message events is accepted for this phase. A serious
production system may later store an outbox event in the same database
transaction as the message insert, then have a worker publish and mark the event
processed. That would improve crash recovery for event delivery. It is not part
of this phase because Postgres already remains the source of truth and this
phase is focused on Channel runtime and typing state.

Issue tracker publishing is blocked because this repository does not currently
define the tracker configuration or triage label vocabulary expected by the
local `to-prd` skill. Existing PRDs in this repository use the same docs-first
fallback. This PRD is written as a docs artifact until tracker setup is
available.
