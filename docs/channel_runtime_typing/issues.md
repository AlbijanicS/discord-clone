# Channel Runtime And Typing Indicators Issues

This document breaks `docs/channel_runtime_typing/prd.md` into tracer-bullet
implementation issues using the `to-issues` skill. Each slice is intended to be
independently grabbable and verifiable on its own. The project is using a
docs-first fallback for now, so these are not published to a remote issue
tracker.

The route placement for this phase is intentionally unchanged: Channel LiveViews
stay in the existing authenticated browser pipeline and existing authenticated
LiveView session because Channel runtime behavior requires `current_scope` and
Workspace membership.

## Proposed Breakdown

1. **Start A Channel Runtime When A Member Enters A Channel**
   - **Type:** AFK
   - **Blocked by:** None - can start immediately
   - **User stories covered:** 1-4, 22-27, 38-39
2. **Serve Recent Channel Messages From The Runtime Cache**
   - **Type:** AFK
   - **Blocked by:** 1. Start A Channel Runtime When A Member Enters A Channel
   - **User stories covered:** 5-8, 24, 28-29, 38-39
3. **Recover Recent Messages After Channel Runtime Loss**
   - **Type:** AFK
   - **Blocked by:** 2. Serve Recent Channel Messages From The Runtime Cache
   - **User stories covered:** 6-8, 11, 24, 29, 39
4. **Keep The Runtime Cache Current When Sending Messages**
   - **Type:** AFK
   - **Blocked by:** 2. Serve Recent Channel Messages From The Runtime Cache
   - **User stories covered:** 7-9, 24, 30, 40
5. **Shut Down Idle Channel Runtimes And Restart On Demand**
   - **Type:** AFK
   - **Blocked by:** 4. Keep The Runtime Cache Current When Sending Messages
   - **User stories covered:** 10-12, 24, 39
6. **Show A Typing Indicator When Another Member Types**
   - **Type:** AFK
   - **Blocked by:** 5. Shut Down Idle Channel Runtimes And Restart On Demand
   - **User stories covered:** 13-15, 18-20, 22-24, 31-36, 38
7. **Clear Typing Indicators On Stop And Message Submit**
   - **Type:** AFK
   - **Blocked by:** 6. Show A Typing Indicator When Another Member Types
   - **User stories covered:** 15-17, 19-20, 24, 31-37
8. **Expire Stale Typing Indicators Automatically**
   - **Type:** AFK
   - **Blocked by:** 6. Show A Typing Indicator When Another Member Types
   - **User stories covered:** 15, 19-20, 24, 31-37
9. **Prove Typing And Runtime Boundaries**
   - **Type:** AFK
   - **Blocked by:** 6. Show A Typing Indicator When Another Member Types, 7. Clear Typing Indicators On Stop And Message Submit, 8. Expire Stale Typing Indicators Automatically
   - **User stories covered:** 18-24, 30-37, 40
10. **Finalize Channel Runtime And Typing Acceptance Coverage**
    - **Type:** AFK
    - **Blocked by:** 1-9
    - **User stories covered:** 1-40

## 1. Start A Channel Runtime When A Member Enters A Channel

**Type:** AFK

**Blocked by:** None - can start immediately

**User stories covered:** 1-4, 22-27, 38-39

## What to build

When an authenticated Workspace Member enters a Channel over a connected
LiveView, the app should start or find exactly one supervised runtime process
for that Channel. The behavior should be exposed through the Chat context so the
web layer never calls Registry, DynamicSupervisor, or ChannelServer directly.

This is the first tracer bullet through the runtime: application supervision,
Channel process identity, Chat authorization, connected Channel entry, and tests.

## Acceptance criteria

- [ ] The application starts a Channel runtime Registry and DynamicSupervisor.
- [ ] A ChannelServer can start under the Channel runtime supervisor.
- [ ] ChannelServer process identity uses durable Channel ID.
- [ ] ChannelServer process identity does not use Channel name.
- [ ] ChannelServer initial state includes Channel ID.
- [ ] ChannelServer initial state does not include Workspace ID.
- [ ] ChannelServer initial state does not include channel-scoped online users.
- [ ] Chat exposes an explicit ensure-runtime workflow.
- [ ] Authenticated Workspace Members receive `{:ok, pid}` from the ensure-runtime workflow.
- [ ] Anonymous scopes receive `{:error, :unauthenticated}` from the ensure-runtime workflow.
- [ ] Logged-in non-members receive `{:error, :not_found}` from the ensure-runtime workflow.
- [ ] Missing Channels receive `{:error, :not_found}` from the ensure-runtime workflow.
- [ ] The ensure-runtime workflow authorizes through member-accessible Channel lookup.
- [ ] Channel LiveView calls the public Chat ensure-runtime workflow after Channel access is proven.
- [ ] Channel LiveView starts the runtime only when the socket is connected.
- [ ] Disconnected static render does not start a Channel runtime.
- [ ] Starting the same Channel runtime twice returns the active process.
- [ ] Router placement remains unchanged in the authenticated browser pipeline and authenticated LiveView session.

## Blocked by

None - can start immediately

## 2. Serve Recent Channel Messages From The Runtime Cache

**Type:** AFK

**Blocked by:** 1. Start A Channel Runtime When A Member Enters A Channel

**User stories covered:** 5-8, 24, 28-29, 38-39

## What to build

Channel entry should still render the latest persisted messages, but the recent
message path should now flow through the Channel runtime cache. The Channel
runtime should initialize a bounded latest-message cache from Postgres, and
Chat should read that cache for the Channel LiveView's initial recent-message
load.

This slice proves the cache is real and user-visible without making it the
source of truth for all history.

## Acceptance criteria

- [ ] ChannelServer initializes a latest-message cache from Postgres.
- [ ] Cache initialization loads the latest 50 persisted messages.
- [ ] Cached messages include author data needed for rendering.
- [ ] Cache initialization is synchronous and bounded.
- [ ] Chat recent-message reads ensure or find the Channel runtime.
- [ ] Chat recent-message reads return messages from the runtime cache.
- [ ] Channel LiveView still renders recent messages on entry.
- [ ] Older-history pagination continues reading from Postgres.
- [ ] Recent-message reads still require an authenticated Workspace Member.
- [ ] Postgres remains the source of truth for message history.
- [ ] Tests prove the Channel page renders persisted recent messages through the runtime-backed path.

## Blocked by

- 1. Start A Channel Runtime When A Member Enters A Channel

## 3. Recover Recent Messages After Channel Runtime Loss

**Type:** AFK

**Blocked by:** 2. Serve Recent Channel Messages From The Runtime Cache

**User stories covered:** 6-8, 11, 24, 29, 39

## What to build

If a Channel runtime crashes or is stopped, durable messages must remain
recoverable. The next authorized Channel access or recent-message read should
start a new Channel runtime and rebuild the latest-message cache from Postgres.

This slice demonstrates the durable-versus-temporary boundary: the process may
die, but message history survives.

## Acceptance criteria

- [ ] A Channel runtime can be stopped or killed in tests without deleting persisted messages.
- [ ] The next authorized runtime lookup starts a replacement Channel runtime.
- [ ] The restarted runtime uses the same durable Channel ID.
- [ ] The restarted runtime reloads latest messages from Postgres.
- [ ] Chat recent-message reads succeed after runtime loss.
- [ ] Channel LiveView can render recent messages after runtime loss.
- [ ] Tests use Process.monitor and DOWN assertions rather than sleeps.
- [ ] Tests prove temporary runtime state may reset while durable messages remain.

## Blocked by

- 2. Serve Recent Channel Messages From The Runtime Cache

## 4. Keep The Runtime Cache Current When Sending Messages

**Type:** AFK

**Blocked by:** 2. Serve Recent Channel Messages From The Runtime Cache

**User stories covered:** 7-9, 24, 30, 40

## What to build

When a Workspace Member sends a message, the send workflow should still persist
first, then update the Channel runtime cache, then broadcast the persisted
message event. The sender and other connected members should keep the existing
live-message behavior, while a later recent-message read should include the new
message from the runtime cache.

This slice cuts through the composer, Chat command, Postgres, Channel runtime,
PubSub, and LiveView message stream.

## Acceptance criteria

- [ ] Message send still validates membership before insert.
- [ ] Message send inserts the message into Postgres before runtime cache update.
- [ ] Message send preloads author data before runtime cache update.
- [ ] Message send updates the Channel runtime recent-message cache.
- [ ] Message-created PubSub broadcasting remains owned by Chat.
- [ ] Message-created broadcast happens after the runtime cache update.
- [ ] The sender still sees the sent message immediately.
- [ ] Other connected members still receive the message live.
- [ ] A runtime-backed recent-message read includes the newly sent message.
- [ ] Validation failures do not update the runtime cache or broadcast.
- [ ] Authorization failures do not update the runtime cache or broadcast.
- [ ] Unexpected runtime failures are visible in tests or logs rather than silently hidden.

## Blocked by

- 2. Serve Recent Channel Messages From The Runtime Cache

## 5. Shut Down Idle Channel Runtimes And Restart On Demand

**Type:** AFK

**Blocked by:** 4. Keep The Runtime Cache Current When Sending Messages

**User stories covered:** 10-12, 24, 39

## What to build

Active Channel runtimes should track last activity and stop themselves after 15
minutes with no ensure/read/message activity. A later authorized Channel access
should restart the runtime and rebuild recent messages from Postgres.

Typing activity will also refresh activity once typing lands, but this slice
should prove the lifecycle with the already-built Channel entry, recent read,
and message send paths.

## Acceptance criteria

- [ ] ChannelServer tracks last activity.
- [ ] Ensuring or entering the Channel refreshes last activity.
- [ ] Reading the recent-message cache refreshes last activity.
- [ ] Sending a message refreshes last activity.
- [ ] Idle Channel runtimes stop after the configured inactivity timeout.
- [ ] The inactivity timeout is easy to identify as the selected 15-minute value.
- [ ] Tests do not wait 15 minutes.
- [ ] Runtime shutdown removes the registered process.
- [ ] A later authorized Channel access restarts the runtime.
- [ ] Restart after idle shutdown reloads recent messages from Postgres.

## Blocked by

- 4. Keep The Runtime Cache Current When Sending Messages

## 6. Show A Typing Indicator When Another Member Types

**Type:** AFK

**Blocked by:** 5. Shut Down Idle Channel Runtimes And Restart On Demand

**User stories covered:** 13-15, 18-20, 22-24, 31-36, 38

## What to build

When one Workspace Member types in a Channel, another member viewing the same
Channel should see a typing indicator. The event should flow through the browser
hook, Channel LiveView, public Chat typing API, ChannelServer typing state,
PubSub, and the receiving Channel LiveView.

This is the first typing tracer bullet. It may implement only the start/display
path; explicit stop and expiry are separate follow-up slices.

## Acceptance criteria

- [ ] Chat exposes a public user-started-typing workflow.
- [ ] Chat exposes a public subscribe-to-Channel-typing workflow.
- [ ] Chat exposes a public list-typing-user-IDs workflow.
- [ ] Typing workflows authorize against Channel membership.
- [ ] Anonymous scopes cannot start, subscribe to, or list typing state.
- [ ] Logged-in non-members cannot start, subscribe to, or list typing state.
- [ ] ChannelServer stores typing state as user IDs mapped to deadlines.
- [ ] Typing state does not store user structs or display names.
- [ ] Typing started refreshes the user's typing deadline.
- [ ] Typing started broadcasts only when the user was not already typing.
- [ ] Typing events use the same channel PubSub topic as messages.
- [ ] Typing started event payload contains Channel ID and User ID only.
- [ ] The browser does not send typing-start on every keypress.
- [ ] Channel LiveView subscribes to typing events through Chat.
- [ ] Another member viewing the same Channel sees the typing indicator.
- [ ] Typing display names come from durable member/user data.
- [ ] The UI never displays self-typing.
- [ ] Typing start activity refreshes Channel runtime activity.

## Blocked by

- 5. Shut Down Idle Channel Runtimes And Restart On Demand

## 7. Clear Typing Indicators On Stop And Message Submit

**Type:** AFK

**Blocked by:** 6. Show A Typing Indicator When Another Member Types

**User stories covered:** 15-17, 19-20, 24, 31-37

## What to build

Typing indicators should disappear when the typing member explicitly stops
typing, clears the composer, or submits a message. Submitting a message should
clear typing as part of the existing Chat send workflow so the UI does not rely
on a second client event after a successful send.

This slice cuts through the composer, Chat stop API, ChannelServer typing state,
PubSub stopped event, and receiving Channel LiveView.

## Acceptance criteria

- [ ] Chat exposes a public user-stopped-typing workflow.
- [ ] Explicit stop removes the user from ChannelServer typing state.
- [ ] Explicit stop broadcasts only when the user was previously typing.
- [ ] Typing stopped event payload contains Channel ID and User ID only.
- [ ] Clearing the composer sends an explicit stop event.
- [ ] Sending a message clears the sender's typing state through Chat send.
- [ ] Other viewers remove the sender's typing indicator after explicit stop.
- [ ] Other viewers remove the sender's typing indicator after message submit.
- [ ] Message send still persists first and preserves live message delivery.
- [ ] Stop activity refreshes Channel runtime activity when it changes typing state.
- [ ] Repeated stop calls are harmless and do not rebroadcast stale stopped events.

## Blocked by

- 6. Show A Typing Indicator When Another Member Types

## 8. Expire Stale Typing Indicators Automatically

**Type:** AFK

**Blocked by:** 6. Show A Typing Indicator When Another Member Types

**User stories covered:** 15, 19-20, 24, 31-37

## What to build

Typing state should clear automatically if no refresh arrives within 5 seconds.
This protects the UI from stale typing indicators when a tab closes, a network
event is missed, or a client never sends an explicit stop event.

This slice is server-owned: ChannelServer is authoritative for deadlines and
broadcasts stopped events when expiry fires.

## Acceptance criteria

- [ ] Typing expiry is 5 seconds.
- [ ] Repeated typing-start events refresh the expiry deadline.
- [ ] Expiry removes the user from ChannelServer typing state.
- [ ] Expiry broadcasts a typing stopped event.
- [ ] Other viewers remove the typing indicator after expiry.
- [ ] Disconnect cleanup for typing relies on expiry rather than LiveView PID monitoring.
- [ ] Expiry tests do not wait for real-time 5-second sleeps.
- [ ] Expired typing state is not persisted in Postgres.
- [ ] Expiry behavior does not affect workspace-scoped online presence.

## Blocked by

- 6. Show A Typing Indicator When Another Member Types

## 9. Prove Typing And Runtime Boundaries

**Type:** AFK

**Blocked by:** 6. Show A Typing Indicator When Another Member Types, 7. Clear Typing Indicators On Stop And Message Submit, 8. Expire Stale Typing Indicators Automatically

**User stories covered:** 18-24, 30-37, 40

## What to build

Harden the behavioral boundaries around typing and runtime state. Typing should
be Channel-scoped, self-typing should never display, non-members should not
access typing state, and channel-scoped online presence should not be added.
Persisted message events should still be broadcast by Chat, while temporary
typing events are owned by Channel runtime behavior.

This slice is mostly acceptance hardening across the already-built typing paths.

## Acceptance criteria

- [ ] A user's own typing state is never displayed to that user.
- [ ] Raw typing-user listing may include the current user.
- [ ] The LiveView filters out the current user before display.
- [ ] Typing in one Channel does not display in another Channel.
- [ ] Logged-in non-members cannot start typing in private Workspace Channels.
- [ ] Logged-in non-members cannot subscribe to private Channel typing events.
- [ ] Anonymous users cannot interact with typing APIs.
- [ ] Typing events do not include user structs or display names.
- [ ] ChannelServer does not store channel-scoped online users.
- [ ] Workspace presence behavior still drives online/offline display.
- [ ] Message-created broadcasting remains owned by Chat.
- [ ] Temporary typing stopped events can originate from ChannelServer expiry.
- [ ] Direct PubSub limitations for persisted events remain documented as future outbox work.

## Blocked by

- 6. Show A Typing Indicator When Another Member Types
- 7. Clear Typing Indicators On Stop And Message Submit
- 8. Expire Stale Typing Indicators Automatically

## 10. Finalize Channel Runtime And Typing Acceptance Coverage

**Type:** AFK

**Blocked by:** 1-9

**User stories covered:** 1-40

## What to build

Run a full acceptance sweep over the combined phase. The final state should show
that Channel runtime is on-demand, authorized, recoverable, cache-backed,
bounded by inactivity cleanup, and used by typing indicators without
introducing channel-scoped online presence.

## Acceptance criteria

- [ ] Entering a Channel starts or finds exactly one Channel runtime.
- [ ] Runtime identity uses durable Channel ID.
- [ ] Recent message cache is initialized from Postgres.
- [ ] Recent message cache rebuilds from Postgres after runtime loss.
- [ ] Sending a message persists first, updates runtime cache, clears typing, and broadcasts the persisted message.
- [ ] Existing live message delivery still works for another connected member.
- [ ] Idle Channel runtime shuts down and later restarts cleanly.
- [ ] Typing start, stop, submit-clear, expiry, subscribe, and list behavior are tested.
- [ ] Typing UI shows other users and never shows self.
- [ ] Typing UI is scoped to the selected Channel.
- [ ] Channel-scoped online presence was not introduced.
- [ ] Existing workspace presence behavior still works.
- [ ] Existing persisted chat and older-history behavior still works.
- [ ] Focused tests pass.
- [ ] The project precommit alias passes after implementation changes.

## Blocked by

- 1. Start A Channel Runtime When A Member Enters A Channel
- 2. Serve Recent Channel Messages From The Runtime Cache
- 3. Recover Recent Messages After Channel Runtime Loss
- 4. Keep The Runtime Cache Current When Sending Messages
- 5. Shut Down Idle Channel Runtimes And Restart On Demand
- 6. Show A Typing Indicator When Another Member Types
- 7. Clear Typing Indicators On Stop And Message Submit
- 8. Expire Stale Typing Indicators Automatically
- 9. Prove Typing And Runtime Boundaries
