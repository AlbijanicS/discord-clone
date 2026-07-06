# Unread Counts Issues

Status: superseded by `docs/unread_ranges_issues/README.md`.

These v1 cursor-read issues are retained for historical context only. New unread
work should follow `docs/unread_ranges_prd.md` and
`docs/unread_ranges_issues/README.md`, where unread spans are canonical,
read states are summary state, and `channel_reads` cursor rows are compatibility
or backfill input rather than active runtime unread behavior. The route
placement remains unchanged in the range design: Channel LiveViews stay in the
existing `:browser` pipeline and existing `live_session :require_authenticated_user`.
Chat unread workflows preserve the privacy semantics from the range PRD:
unauthenticated scopes return `{:error, :unauthenticated}` and logged-in
non-members receive `{:error, :not_found}`.

This document breaks `docs/unread_counts_prd.md` into thin, independently
grabbable tracer-bullet issues using the `to-issues` skill. The project is
using a docs-first fallback for now, so these are not published to GitHub
Issues.

The route placement for this phase is intentionally unchanged: Channel
LiveViews stay in the existing authenticated browser pipeline and existing
`live_session :require_authenticated_user`, because unread counts require
`current_scope`, an authenticated User, and Workspace membership. No new routes
or router scopes are needed.

## Proposed Breakdown

1. **Create Durable Channel Read Positions**
   - **Type:** AFK
   - **Blocked by:** None - can start immediately
   - **User stories covered:** 8-10, 12-14, 16, 33-46, 53
2. **List Workspace Unread Counts Through Chat**
   - **Type:** AFK
   - **Blocked by:** 1. Create Durable Channel Read Positions
   - **User stories covered:** 1-2, 10-12, 21-23, 35-42, 46
3. **Mark Channels Read And Advance Sender Cursors**
   - **Type:** AFK
   - **Blocked by:** 1. Create Durable Channel Read Positions, 2. List Workspace Unread Counts Through Chat
   - **User stories covered:** 3-8, 29, 34, 45, 49-50
4. **Initialize And Clean Up Reads From Workspace Workflows**
   - **Type:** AFK
   - **Blocked by:** 1. Create Durable Channel Read Positions
   - **User stories covered:** 14-20, 38, 43-44, 51
5. **Render Initial Channel Sidebar Badges**
   - **Type:** AFK
   - **Blocked by:** 2. List Workspace Unread Counts Through Chat, 3. Mark Channels Read And Advance Sender Cursors
   - **User stories covered:** 1-4, 9, 22-25, 29, 37, 40-42, 52
6. **Refresh Badges From Workspace Message Events**
   - **Type:** AFK
   - **Blocked by:** 2. List Workspace Unread Counts Through Chat, 3. Mark Channels Read And Advance Sender Cursors, 5. Render Initial Channel Sidebar Badges
   - **User stories covered:** 4-6, 30-32, 47-50, 52
7. **Keep Badges Correct During Sidebar Actions**
   - **Type:** AFK
   - **Blocked by:** 5. Render Initial Channel Sidebar Badges, 6. Refresh Badges From Workspace Message Events
   - **User stories covered:** 24-28, 31, 52
8. **Finalize Unread Counts Acceptance Coverage**
   - **Type:** AFK
   - **Blocked by:** 1-7
   - **User stories covered:** 1-54

## 1. Create Durable Channel Read Positions

**Type:** AFK

**Blocked by:** None - can start immediately

**User stories covered:** 8-10, 12-14, 16, 33-46, 53

## What to build

Add the durable read-position foundation for unread counts. A Workspace
Member's read position for a Channel should be represented by a Postgres-backed
Channel read row owned by the Chat context, keyed by durable Channel ID and User
ID. This slice should establish the schema, associations, backfill behavior for
existing Workspace Members, and database cleanup semantics without wiring the
Channel sidebar yet.

Read positions store cursors, not counters. Empty Channels should have explicit
read rows with no cursor, and missing or nil cursors should remain compatible
with the later membership-time fallback behavior.

## Acceptance criteria

- [ ] A migration creates `channel_reads` with `channel_id`, `user_id`,
      nullable `last_read_message_id`, and UTC timestamps.
- [ ] The migration is generated with `mix ecto.gen.migration`.
- [ ] A unique index prevents duplicate read rows for one Channel and User.
- [ ] An index exists for User-scoped read cleanup and lookup.
- [ ] Read rows do not store `workspace_id`; Workspace scope is derived through
      Channel.
- [ ] Channel deletion removes read rows through the Channel foreign key.
- [ ] User deletion removes read rows through the User foreign key.
- [ ] Message deletion nilifies `last_read_message_id` without deleting the
      read row.
- [ ] A Chat-owned ChannelRead schema exists.
- [ ] Channel has the needed ChannelRead association.
- [ ] Existing Workspace Members are backfilled read-through-latest for
      existing Channels.
- [ ] Empty Channels receive read rows with `last_read_message_id: nil`.
- [ ] The durable read model is documented as Postgres-owned, not
      ChannelServer-owned.
- [ ] Focused schema, migration, and Chat context tests cover uniqueness,
      cascades, nilified cursors, and backfill behavior.

## Blocked by

None - can start immediately

## 2. List Workspace Unread Counts Through Chat

**Type:** AFK

**Blocked by:** 1. Create Durable Channel Read Positions

**User stories covered:** 1-2, 10-12, 21-23, 35-42, 46

## What to build

Expose the first complete unread-count read path through `DiscordClone.Chat`.
A caller with an authenticated Workspace Member scope should be able to request
unread counts for a Workspace and receive a sparse map of Channel IDs to exact
numeric counts. The query should count only messages visible through that
Workspace membership boundary, should ignore the current User's own messages,
and should treat messages with deleted authors as not-own messages.

This slice should prove the durable read-position model can answer the sidebar
question in one aggregate query without any LiveView integration yet.

## Acceptance criteria

- [ ] Chat exposes `list_unread_counts(scope, workspace_id)`.
- [ ] Authenticated Workspace Members receive `{:ok, %{channel_id => count}}`.
- [ ] The count map is sparse and omits Channels with zero unread messages.
- [ ] Count map keys are integer Channel IDs.
- [ ] Counts are exact and uncapped.
- [ ] The workflow uses one aggregate query rather than one query per Channel.
- [ ] Anonymous scopes receive `{:error, :unauthenticated}`.
- [ ] Logged-in non-members receive `{:error, :not_found}`.
- [ ] Counts include only Channels in the requested Workspace.
- [ ] Messages from the current User do not count unread.
- [ ] Messages with nil authors count unread when they are otherwise eligible.
- [ ] Missing or nil read cursors fall back to the member's Workspace
      membership timestamp.
- [ ] The membership timestamp fallback does not count pre-join history as
      unread.
- [ ] Focused Chat context tests cover access, scoping, sparse-map shape, own
      messages, nil authors, and fallback cursor behavior.

## Blocked by

- 1. Create Durable Channel Read Positions

## 3. Mark Channels Read And Advance Sender Cursors

**Type:** AFK

**Blocked by:** 1. Create Durable Channel Read Positions, 2. List Workspace Unread Counts Through Chat

**User stories covered:** 3-8, 29, 34, 45, 49-50

## What to build

Add the write side of read-position behavior through the Chat context. Opening
a Channel should mark it read for the current Workspace Member, creating or
repairing a missing read row when the member is valid. Sending a message should
advance the sender's read position to the saved message before broadcasts so
the sender never sees their own message as unread after a count refresh.

Read-position updates should be monotonic and silent: stale events or older
LiveViews must not move a cursor backward, and private read state should not be
broadcast to other Workspace Members.

## Acceptance criteria

- [ ] Chat exposes `mark_channel_read(scope, channel_id)`.
- [ ] Marking a Channel read requires an authenticated Workspace Member.
- [ ] Anonymous scopes receive `{:error, :unauthenticated}`.
- [ ] Logged-in non-members cannot mark private Channels read.
- [ ] Opening a Channel advances the read row to the latest message in that
      Channel.
- [ ] Empty Channels can be marked read and keep a nil cursor.
- [ ] Missing read rows are created or repaired for valid Workspace Members.
- [ ] Read-position updates never move `last_read_message_id` backward.
- [ ] Nil cursors are treated as lower than any message ID.
- [ ] Marking a Channel read does not broadcast.
- [ ] `send_message/3` advances the sender's read row to the sent message
      before message broadcasts.
- [ ] The current User's sent messages do not create self-unread counts.
- [ ] Read state survives Channel runtime loss because it is Postgres-backed.
- [ ] Focused Chat context tests cover mark-read success, repair, access
      failures, monotonic cursors, send behavior, and runtime-loss durability.

## Blocked by

- 1. Create Durable Channel Read Positions
- 2. List Workspace Unread Counts Through Chat

## 4. Initialize And Clean Up Reads From Workspace Workflows

**Type:** AFK

**Blocked by:** 1. Create Durable Channel Read Positions

**User stories covered:** 14-20, 38, 43-44, 51

## What to build

Wire read-position initialization and cleanup into the Workspaces workflows
that create or remove membership and Channel structure. Workspaces should
continue deciding when Workspaces, Workspace Memberships, and Channels exist;
Chat should own read-position persistence behind a public initialization API.

Initialization must happen transactionally with the parent domain operation so
the app never creates a Workspace, membership, or Channel without the matching
baseline read state. Existing-member invite acceptance should remain
navigation-only and must not rewrite read positions.

## Acceptance criteria

- [ ] Chat exposes `initialize_workspace_reads_for_user(user_id, workspace_id)`.
- [ ] Initialization requires the User to already be a Workspace Member.
- [ ] Initialization is idempotent and non-regressive.
- [ ] Initialization sets read rows to each Channel's latest message.
- [ ] Initialization creates nil-cursor rows for empty Channels.
- [ ] Workspace creation initializes owner read rows after the `general`
      Landing Channel exists.
- [ ] Workspace creation rolls back if read initialization fails.
- [ ] New-member invite acceptance initializes read rows inside the invite
      transaction.
- [ ] Existing-member invite acceptance does not reset, repair, or otherwise
      change read positions.
- [ ] Channel creation initializes empty read rows for all current Workspace
      Members inside the Channel creation transaction.
- [ ] Leaving a Workspace deletes that User's read rows for Channels in that
      Workspace inside the leave transaction.
- [ ] Focused Workspaces tests cover workspace creation, invite acceptance,
      existing-member invite behavior, Channel creation, leaving, and rollback
      behavior where practical.

## Blocked by

- 1. Create Durable Channel Read Positions

## 5. Render Initial Channel Sidebar Badges

**Type:** AFK

**Blocked by:** 2. List Workspace Unread Counts Through Chat, 3. Mark Channels Read And Advance Sender Cursors

**User stories covered:** 1-4, 9, 22-25, 29, 37, 40-42, 52

## What to build

Add the first LiveView badge path. Entering a Channel should mark the selected
Channel read, reload unread counts from Chat, and pass the sparse count map
into the shared Workspace shell. The Channel sidebar should render compact
numeric badges for nonzero unread counts while suppressing the badge for the
selected Channel.

This slice should keep route placement unchanged and preserve the existing
authenticated Channel access flow. The web layer should call public Chat APIs
instead of assembling read queries directly.

## Acceptance criteria

- [ ] Channel LiveView disconnected mount assigns empty unread counts.
- [ ] Channel LiveView connected mount marks the selected Channel read before
      loading unread counts.
- [ ] Mark-read failure on mount follows existing access recovery and redirect
      behavior.
- [ ] Channel LiveView loads unread counts through Chat.
- [ ] Channel LiveView passes `channel_unread_counts` into the shared Workspace
      shell.
- [ ] The shared Workspace shell renders numeric badges beside Channels with
      nonzero unread counts.
- [ ] Channels with zero or missing sparse-map counts show no badge.
- [ ] The selected Channel suppresses its badge even if the count map contains
      a transient nonzero count.
- [ ] Large exact counts remain readable and do not break the sidebar layout.
- [ ] Badges include accessible labels.
- [ ] Opening or clicking a Channel with a badge clears that badge after the
      Channel opens.
- [ ] The route remains in the existing authenticated browser pipeline and
      existing `live_session :require_authenticated_user`.
- [ ] Focused LiveView tests cover initial badge rendering, selected-Channel
      suppression, accessible/stable selectors, exact counts, and badge clear
      on Channel open.

## Blocked by

- 2. List Workspace Unread Counts Through Chat
- 3. Mark Channels Read And Advance Sender Cursors

## 6. Refresh Badges From Workspace Message Events

**Type:** AFK

**Blocked by:** 2. List Workspace Unread Counts Through Chat, 3. Mark Channels Read And Advance Sender Cursors, 5. Render Initial Channel Sidebar Badges

**User stories covered:** 4-6, 30-32, 47-50, 52

## What to build

Add workspace-level message refresh events for unread badges without mixing
them into timeline rendering. Successful sends should still use the existing
Channel-level full message event for selected-Channel timeline delivery, and
should also emit a small Workspace-level event that prompts LiveViews in that
Workspace to reload unread counts from the database.

For events in the selected Channel, the LiveView should mark the Channel read
first and then reload counts. For events in sibling Channels, it should reload
counts without inserting anything into the message stream.

## Acceptance criteria

- [ ] Chat owns workspace-level message topic construction.
- [ ] Chat exposes a public workflow for subscribing to Workspace-level message
      refresh events.
- [ ] Workspace-level message events carry a small payload with Workspace ID,
      Channel ID, Message ID, and User ID.
- [ ] `send_message/3` broadcasts the workspace-level event after advancing the
      sender's read row.
- [ ] Workspace-level broadcasts reach sender sessions so they can refresh
      counts.
- [ ] Channel-level full message events remain responsible for timeline
      rendering.
- [ ] Channel LiveView subscribes to workspace-level events only when
      connected.
- [ ] Selected-Channel workspace events mark the Channel read before reloading
      counts.
- [ ] Sibling-Channel workspace events reload counts without touching the
      message stream.
- [ ] The workspace-level event handler never inserts messages into the
      message stream.
- [ ] The channel-level message handler does not own unread-count refresh.
- [ ] Transient mark-read or count-refresh failures during live events do not
      kick the user out of the Channel.
- [ ] Focused Chat and LiveView tests cover event payloads, sender refresh,
      selected-Channel behavior, sibling-Channel badge updates, and no timeline
      duplication.

## Blocked by

- 2. List Workspace Unread Counts Through Chat
- 3. Mark Channels Read And Advance Sender Cursors
- 5. Render Initial Channel Sidebar Badges

## 7. Keep Badges Correct During Sidebar Actions

**Type:** AFK

**Blocked by:** 5. Render Initial Channel Sidebar Badges, 6. Refresh Badges From Workspace Message Events

**User stories covered:** 24-28, 31, 52

## What to build

Harden badge behavior around existing sidebar actions. Channel rename mode,
context menus, restream paths, and Channel deletion should keep unread badge
state fresh and visually coherent without turning the Workspace shell into the
owner of read-position queries.

This slice should add or update a combined Channel restream helper where
sidebar state can be affected, and should ensure badge rendering survives
normal Channel management interactions.

## Acceptance criteria

- [ ] Channel restream paths that can affect sidebar badge state also reload
      unread counts.
- [ ] Channel context menu interactions do not stale or hide unrelated unread
      badges.
- [ ] Rename mode keeps badges visible for non-selected Channels when layout
      allows it cleanly.
- [ ] Selected-Channel badge suppression still applies during rename mode.
- [ ] Channel deletion refreshes unread state so removed Channels leave no
      badge behind.
- [ ] Badge labels and layout remain stable after Channel actions.
- [ ] Focused LiveView tests cover rename mode, context menu paths, Channel
      deletion refresh, and no duplicate selected-Channel timeline messages.

## Blocked by

- 5. Render Initial Channel Sidebar Badges
- 6. Refresh Badges From Workspace Message Events

## 8. Finalize Unread Counts Acceptance Coverage

**Type:** AFK

**Blocked by:** 1-7

**User stories covered:** 1-54

## What to build

Finish the unread-count phase with an end-to-end acceptance sweep. A Workspace
Member should see exact numeric Channel badges for unread activity in sibling
Channels, opening a Channel should clear its badge, selected-Channel live
messages should render exactly once without showing a badge, own messages
should never create self-unread state, and all read positions should remain
durable across refreshes, reconnects, and Channel runtime loss.

This slice should also make narrow documentation or roadmap updates if the
implemented behavior changes project orientation, without broad rewrites of
unrelated Phase 9 documents.

## Acceptance criteria

- [ ] The full unread-count workflow is covered across Chat context,
      Workspaces context, and LiveView tests.
- [ ] Unread counts are scoped per User, Workspace, and Channel ID.
- [ ] Own messages never create unread counts for the sender.
- [ ] Deleted-author messages still count unread when appropriate.
- [ ] Existing members, new members, new Channels, and leaving Workspaces all
      preserve the PRD's read-position semantics.
- [ ] Badge rendering remains exact, accessible, and selected-Channel
      suppressed.
- [ ] Workspace-level unread refresh events do not duplicate selected-Channel
      messages.
- [ ] Durable read state survives page refreshes, LiveView reconnects, and
      Channel runtime loss.
- [ ] Out-of-scope decisions remain out of scope: no count caps, dot-only
      indicators, scroll-position read receipts, per-message read receipts, or
      read-state broadcasting.
- [ ] Focused test files pass before `mix precommit`.
- [ ] `mix precommit` passes.

## Blocked by

- 1. Create Durable Channel Read Positions
- 2. List Workspace Unread Counts Through Chat
- 3. Mark Channels Read And Advance Sender Cursors
- 4. Initialize And Clean Up Reads From Workspace Workflows
- 5. Render Initial Channel Sidebar Badges
- 6. Refresh Badges From Workspace Message Events
- 7. Keep Badges Correct During Sidebar Actions
