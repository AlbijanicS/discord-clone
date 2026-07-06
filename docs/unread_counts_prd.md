# Unread Counts With Channel Reads PRD

Status: superseded by `docs/unread_ranges_prd.md`

> This v1 cursor-read PRD is retained for historical context only. The active
> unread model is the range-based design in `docs/unread_ranges_prd.md`: unread
> spans are the canonical source of truth, read states are summary rows for
> sidebar counts and landing decisions, and `channel_reads` cursor rows are only
> compatibility/backfill input. The route placement decision is unchanged: the
> Channel LiveViews remain in the existing `:browser` pipeline and existing
> `live_session :require_authenticated_user`. Chat unread workflows keep the
> same privacy shape: unauthenticated scopes return
> `{:error, :unauthenticated}`, while logged-in non-members receive
> `{:error, :not_found}`.

This PRD comes from a `grill-me` design session for the first Phase 10 feature.
The project is using a docs-first fallback for now, so this document is the
ready-for-agent product artifact rather than a published external tracker item.

## Problem Statement

The Discord clone now has durable Workspaces, Channels, persisted messages, live
message delivery, workspace-scoped presence, typing indicators, and explicit
Channel runtime recovery. A Workspace Member can open a Channel and participate
in live conversation, but the Channel sidebar gives no durable indication that
other Channels have new messages.

Without unread counts, Workspace Members must manually inspect Channels to know
where conversation changed. A live message in a Channel they are not viewing can
be missed until they navigate around. This also leaves a product gap in the
durable-versus-temporary state model: read positions are important user state
and should survive Channel runtime crashes, idle shutdowns, and LiveView
reconnects.

## Solution

Add durable per-user Channel read positions backed by a `channel_reads` table
and expose unread-count workflows through the Chat context.

Opening a Channel marks all current messages in that Channel read for the
current Workspace Member. Live messages in the currently selected Channel are
marked read immediately. Messages in other Channels increase compact numeric
badges in the Channel sidebar after unread counts are reloaded. The current
User's own sent messages never increase their unread counts.

Read positions are stored in Postgres, not in ChannelServer state. ChannelServer
may continue owning temporary state such as typing indicators and recent
message cache, but read/unread state is durable user state. Existing Workspace
Members, new Workspace Members, and new Channels all receive baseline read
state so historical messages are not retroactively treated as unread.

No new route or router scope is required. The feature belongs in the existing
authenticated browser pipeline and existing authenticated LiveView session
because Channel pages already require `current_scope` and Workspace membership.

## User Stories

1. As a Workspace Member, I want a numeric unread badge beside Channels with new messages, so that I can quickly see where conversation changed.
2. As a Workspace Member, I want Channels with no unread messages to show no badge, so that the sidebar stays quiet and scannable.
3. As a Workspace Member, I want opening a Channel to mark it read, so that the badge disappears once I view the conversation.
4. As a Workspace Member, I want live messages in the Channel I am currently viewing to be read immediately, so that the open Channel never shows a confusing unread badge.
5. As a Workspace Member, I want messages in other Channels to update unread badges while I stay in my current Channel, so that I do not miss live activity elsewhere in the Workspace.
6. As a Workspace Member, I want my own sent messages to never increase my unread counts, so that sending does not create false unread state.
7. As a Workspace Member, I want my own sent message to advance my read position, so that my read cursor reflects the conversation I just saw.
8. As a Workspace Member, I want unread counts to survive Channel runtime crashes, so that process failure does not reset read state.
9. As a Workspace Member, I want unread counts to survive page refreshes and LiveView reconnects, so that read state is durable.
10. As a Workspace Member, I want unread counts to be scoped to my User, so that another member's reading behavior does not change my badges.
11. As a Workspace Member, I want unread counts to be scoped to the selected Workspace, so that activity in one Workspace does not pollute another Workspace sidebar.
12. As a Workspace Member, I want unread counts to be scoped to Channel ID, so that Channel renames do not reset read state.
13. As a Workspace Member, I want a newly created empty Channel to start with no unread badge, so that new structure does not look like unread conversation.
14. As a Workspace Member, I want existing Channel history to be treated as read when I join a Workspace, so that accepting an invite does not overwhelm me with old messages.
15. As an existing Workspace Member, I want accepting another invite to the same Workspace to leave my read positions unchanged, so that an already-member invite does not clear or rewrite my unread state.
16. As a Workspace owner, I want owner read positions initialized during Workspace creation, so that the initial `general` Landing Channel starts in a consistent read state.
17. As a Workspace Member, I want unread counts to remain correct after new Channels are created, so that every member has baseline read state for the new Channel.
18. As a Workspace Member, I want leaving a Workspace to remove my read rows for that Workspace, so that private read state is cleaned up with membership.
19. As a Workspace Member, I want deleted Channels to remove their read rows, so that stale read positions do not remain for removed Channels.
20. As a Workspace Member, I want deleted Users to remove their read rows, so that user cleanup also cleans unread state.
21. As a Workspace Member, I want messages from deleted authors to still count unread when appropriate, so that durable Channel history still behaves like history.
22. As a Workspace Member, I want unread badges to render exact numeric counts, so that I know the real amount of unread activity.
23. As a Workspace Member, I want large unread counts to remain readable, so that high-activity Channels do not break the sidebar layout.
24. As a keyboard or screen reader user, I want unread badges to have accessible labels, so that unread state is not visual-only.
25. As a Workspace Member, I want a selected Channel to suppress its badge even if a transient count exists, so that the open Channel does not visually contradict the read-on-open rule.
26. As a Workspace Member, I want badges to remain visible when a different Channel is being renamed, so that editing structure does not hide unread state.
27. As a Workspace Member, I want Channel context menus and rename flows to keep badges fresh, so that sidebar state does not go stale after UI actions.
28. As a Workspace Member, I want Channel deletion to refresh unread state, so that removed Channels do not leave badges behind.
29. As a Workspace Member, I want clicking a Channel with a badge to clear that badge after the Channel opens, so that navigation and read state feel connected.
30. As a Workspace Member, I want unread counts to reload from the source of truth after message events, so that the UI stays correct across races and reconnects.
31. As a Workspace Member, I want selected-Channel live messages to render exactly once, so that unread refresh events do not duplicate timeline messages.
32. As a Workspace Member, I want another user's message in a sibling Channel to update the sidebar without rendering in my current timeline, so that Channel boundaries remain clear.
33. As a Workspace Member, I want unread counts to remain correct if a read row is missing, so that old or partially repaired data does not count pre-join history as unread.
34. As a Workspace Member, I want read positions to move forward only, so that stale events or older LiveViews cannot undo newer read state.
35. As a logged-in non-member, I should not be able to list unread counts for a private Workspace, so that Workspace membership remains the access boundary.
36. As an anonymous visitor, I should not be able to list or mutate unread state, so that unread workflows always attach to an authenticated User.
37. As a developer, I want unread workflows behind the Chat context, so that LiveViews do not assemble read-position queries directly.
38. As a developer, I want Workspaces to decide when memberships and Channels are created, so that read initialization happens at the same transaction boundary as the domain event that requires it.
39. As a developer, I want Chat to own read-position persistence, so that unread behavior stays near message access rules.
40. As a developer, I want one aggregate query for unread counts, so that the Channel sidebar does not perform one query per Channel.
41. As a developer, I want unread counts returned as a sparse map, so that the UI treats missing Channel IDs as zero unread.
42. As a developer, I want integer Channel IDs in unread count maps, so that callers can use Channel structs directly.
43. As a developer, I want read initialization APIs to be idempotent, so that backfill and repair paths can safely repeat work.
44. As a developer, I want read rows for empty Channels to exist with no cursor, so that "initialized but no messages yet" is explicit.
45. As a developer, I want the read cursor to use message IDs, so that read-position updates are simple and monotonic.
46. As a developer, I want missing read cursors to fall back to membership time, so that new members never inherit old unread history even under partial data.
47. As a developer, I want workspace-level message events to carry small payloads, so that sidebar refresh does not depend on full message preload shape.
48. As a developer, I want channel-level message events to remain responsible for timeline rendering, so that message streams do not mix concerns with unread refresh.
49. As a developer, I want sender read positions advanced before message broadcasts, so that sender sessions that refresh unread counts see their own message as read.
50. As a developer, I want read-position updates to be silent, so that private read state is not broadcast to other members.
51. As a developer, I want initialization failures to roll back parent operations, so that Workspaces, memberships, and Channels are not created without baseline read state.
52. As a developer, I want tests to prove behavior through public context and LiveView contracts, so that implementation details can change safely.
53. As a future maintainer, I want the durable unread model documented separately from Channel runtime state, so that later features do not put read state in GenServers.
54. As a future maintainer, I want explicit out-of-scope decisions for scroll-based read positions and count caps, so that v1 stays focused.

## Implementation Decisions

- Build this as the first Phase 10 feature.
- Add a durable `channel_reads` table for per-user Channel read positions.
- Store `channel_id`, `user_id`, nullable `last_read_message_id`, and UTC timestamps.
- Add a unique index on `channel_id` plus `user_id`.
- Add an index on `user_id`.
- Do not add `workspace_id` to read rows; derive Workspace through the Channel.
- Channel deletion cascades read rows through `channel_id`.
- User deletion cascades read rows through `user_id`.
- Message deletion nilifies `last_read_message_id`; it does not delete the read row.
- Do not add a database-level composite constraint proving `last_read_message_id` belongs to the same Channel in v1.
- Add a Chat-owned ChannelRead schema module.
- Add a Channel association for Channel reads.
- Do not add User-side or Message-side ChannelRead associations for v1.
- The ChannelRead changeset may cast `channel_id`, `user_id`, and `last_read_message_id` because the schema is internal to context workflows, not direct user input.
- Use message ID ordering for read cursors.
- Treat read positions as monotonic. Updates must never move `last_read_message_id` backward.
- For monotonic comparisons, treat `nil` as lower than any message ID.
- A read row with `last_read_message_id` set to `nil` means the member has initialized read state but has no concrete message cursor yet.
- For a `nil` or missing read cursor, unread counting falls back to the member's Workspace membership timestamp.
- The fallback timestamp boundary is inclusive: messages at or after membership creation may count unread if no read cursor exists.
- Initialized read rows remain the primary model; the membership timestamp fallback protects missing or partially repaired data.
- Backfill existing Workspace memberships so existing members start read through each Channel's latest message.
- Create read rows for empty Channels during initialization with `last_read_message_id` as `nil`.
- Existing Workspace Members should not suddenly see old history as unread when this feature is introduced.
- Add public Chat API `list_unread_counts(scope, workspace_id)`.
- `list_unread_counts/2` returns `{:ok, %{channel_id => count}}`.
- The unread count map is sparse and includes only nonzero counts.
- Channel IDs in the count map are integers.
- `list_unread_counts/2` returns `{:error, :unauthenticated}` for anonymous scopes.
- `list_unread_counts/2` returns `{:error, :not_found}` for logged-in Users who are not Workspace Members.
- `list_unread_counts/2` uses a single aggregate query, not one query per Channel.
- The aggregate query counts only accessible Channels in the requested Workspace.
- The aggregate query excludes messages whose `user_id` is the current User.
- Messages with `user_id` set to `NULL` count as not-own messages.
- Add public Chat API `mark_channel_read(scope, channel_id)`.
- `mark_channel_read/2` returns `:ok` or `{:error, reason}`.
- `mark_channel_read/2` is idempotent and self-healing: valid members can create or repair a missing read row by opening the Channel.
- `mark_channel_read/2` sets the read position to the latest message in that Channel.
- `mark_channel_read/2` may set the cursor to the latest message even if that message was sent by the current User.
- `mark_channel_read/2` creates or leaves a `nil` cursor for empty Channels.
- `mark_channel_read/2` does not broadcast read-position changes.
- Add public Chat API `initialize_workspace_reads_for_user(user_id, workspace_id)`.
- `initialize_workspace_reads_for_user/2` returns `:ok` or `{:error, :not_found}`.
- `initialize_workspace_reads_for_user/2` requires the User to already be a Workspace Member.
- `initialize_workspace_reads_for_user/2` is idempotent and non-regressive.
- Keep `initialize_workspace_reads_for_user/2` public because Workspaces decides when memberships exist and Chat owns read-position persistence.
- Workspace creation initializes owner read positions after the `general` Landing Channel exists.
- Workspace creation read initialization happens inside the same transaction as Workspace creation.
- Invite acceptance initializes read positions only for new Workspace Members.
- Existing-member invite acceptance does not reset, repair, or otherwise change read positions.
- Invite acceptance read initialization for new members happens inside the invite transaction.
- Channel creation initializes empty read rows for all current Workspace Members.
- Channel creation read initialization happens inside the same transaction as Channel creation.
- Leaving a Workspace deletes that User's read rows for Channels in that Workspace inside the leave transaction.
- If read initialization fails during Workspace creation, invite acceptance, or Channel creation, the parent operation rolls back.
- Add a workspace-level Chat message PubSub topic for unread refresh signals.
- Workspace-level message events use small payloads such as Workspace ID, Channel ID, Message ID, and User ID.
- The workspace-level message event exists to trigger unread count reloads, not to render timeline messages.
- Use regular PubSub broadcast for workspace-level events so sender sessions can refresh counts too.
- Keep existing channel-level full message events for timeline rendering.
- Channel-level full message events remain responsible for streaming selected-Channel messages into the timeline.
- `send_message/3` advances the sender's read row to the sent message before broadcasting either channel-level or workspace-level events.
- `send_message/3` keeps the existing direct return value for sender LiveView rendering.
- The sender LiveView keeps inserting its own returned message directly; no change is needed for sender duplicate prevention.
- The workspace-level event may cause one extra unread count reload for the sending LiveView.
- The Channel LiveView subscribes to workspace-level message events only when connected.
- Initial disconnected Channel mount assigns empty unread counts rather than doing duplicate database work.
- Initial connected Channel mount loads the Channel page, marks the selected Channel read, then loads unread counts.
- On mount, mark-read failure should follow existing access recovery and redirect with a flash.
- During live workspace message events, mark-read or count-refresh failures should not kick the user out for transient races.
- For workspace-level events in the selected Channel, the LiveView marks the Channel read first and then reloads unread counts.
- For workspace-level events in other Channels, the LiveView reloads unread counts without touching the message stream.
- The workspace-level event handler never inserts messages into the message stream.
- The channel-level message handler never owns unread-count refresh.
- Add or update a combined Channel restream helper that also reloads unread counts.
- Existing Channel restream paths should use the combined helper where sidebar badge state can be affected.
- Pass `channel_unread_counts` into the shared Workspace shell.
- Render exact numeric badges beside nonzero Channel unread counts.
- Suppress badges for the selected Channel even if the count map contains a transient nonzero count.
- Badge layout should grow horizontally for large exact counts rather than requiring a fixed circle.
- Badges should include accessible labels such as unread message count.
- Badges should remain visible during Channel rename mode when the renamed Channel is not selected and layout allows it cleanly.
- No route changes are required.
- Keep Channel LiveViews in the existing authenticated browser pipeline and authenticated LiveView session because Channel access depends on `current_scope` and Workspace membership.
- Do not put unread state in ChannelServer.
- Do not serialize `mark_channel_read/2` and `send_message/3` with locks in v1. A message inserted just after a read query may remain unread if a disconnect happens before the live event is handled; this is acceptable for v1.
- Narrowly update docs or roadmap state when this feature is implemented, without broad rewrites of unrelated Phase 9 documents.

## Testing Decisions

- Good tests for this feature should verify observable behavior through public context APIs, Workspaces workflows, and LiveView behavior.
- Avoid tests that depend on private helper names or exact query structure.
- Add migration/schema coverage for the read row uniqueness and delete behavior where naturally testable through the Repo and public workflows.
- Test that only one read row can exist for a User and Channel.
- Test that deleting a Channel cleans up its read rows.
- Test that deleting a User cleans up their read rows.
- Test that deleting a last-read message nilifies the read cursor without deleting the read row if message deletion is practical to exercise directly.
- Add Chat context tests for `list_unread_counts/2`.
- `list_unread_counts/2` tests should cover unauthenticated scopes.
- `list_unread_counts/2` tests should cover logged-in non-members receiving `:not_found`.
- `list_unread_counts/2` tests should cover counts only for accessible Channels in the requested Workspace.
- `list_unread_counts/2` tests should prove sparse maps omit zero-count Channels.
- `list_unread_counts/2` tests should prove Channel IDs are integers.
- `list_unread_counts/2` tests should prove messages from other Users count unread when they are newer than the read cursor.
- `list_unread_counts/2` tests should prove the current User's own messages do not count unread.
- `list_unread_counts/2` tests should prove messages with deleted authors or `NULL` authors still count as not-own messages.
- `list_unread_counts/2` tests should prove missing or nil cursors use membership timestamp fallback and do not count pre-join history.
- Add Chat context tests for `mark_channel_read/2`.
- `mark_channel_read/2` tests should prove opening a Channel clears unread count for that Channel.
- `mark_channel_read/2` tests should prove an empty Channel can be marked read.
- `mark_channel_read/2` tests should prove a missing read row is created or repaired for a valid member.
- `mark_channel_read/2` tests should prove read positions do not move backward.
- `mark_channel_read/2` tests should prove non-members cannot mark private Channels read.
- Add Chat context tests for `initialize_workspace_reads_for_user/2`.
- Initialization tests should prove new read rows point to each Channel's latest message.
- Initialization tests should prove empty Channels receive read rows with nil cursors.
- Initialization tests should prove the API requires existing Workspace membership.
- Initialization tests should prove repeated initialization is idempotent and non-regressive.
- Add Chat context tests for `send_message/3` read-position behavior.
- Send tests should prove the sender's read row advances before unread counts are reloaded.
- Send tests should prove own sent messages do not create self-unread counts.
- Send tests should prove read state survives Channel runtime loss because it is Postgres-backed.
- Add Workspaces tests for Workspace creation read initialization.
- Add Workspaces tests for invite acceptance read initialization for new members.
- Add Workspaces tests proving existing-member invite acceptance does not change read positions.
- Add Workspaces tests for Channel creation read rows for all current Workspace Members.
- Add Workspaces tests for leaving a Workspace cleaning that User's read rows for the Workspace.
- Add LiveView tests for opening a Channel with a badge and seeing the badge clear.
- Add LiveView tests for a message sent in another Channel showing a numeric badge in the sidebar.
- Add LiveView tests for a live message in the selected Channel rendering without creating an unread badge.
- Add LiveView tests for clicking a Channel with a badge clearing that badge.
- Add LiveView tests proving badges are scoped per User and per Workspace.
- Add LiveView tests proving selected Channels do not show badges.
- Add LiveView tests proving exact counts render and use stable selectors or accessible labels.
- LiveView tests should use stable DOM IDs, `element/2`, `has_element?/2`, `render_submit/1`, and related helpers instead of raw HTML assertions.
- Prior art exists in Chat context tests for membership-based Channel access, PubSub subscription and broadcast behavior, runtime recovery, and send workflows.
- Prior art exists in Workspaces context tests for Workspace creation, invite acceptance, Channel creation, leaving Workspaces, and transaction behavior.
- Prior art exists in Channel LiveView tests for message streams, live message delivery, shell rendering, selected Channel navigation, context menus, and access recovery.
- Focused verification should run Chat, Workspaces, and Workspace/Channel LiveView tests before the project precommit alias.

## Out of Scope

- Dot-only unread indicators.
- Capping counts, such as rendering `99+`.
- Scroll-position-based read receipts.
- Per-message read receipts.
- Broadcasting read-position changes to other Workspace Members.
- Showing which members have read a message.
- Persisting unread counters directly.
- Storing unread state in ChannelServer.
- Serializing read updates and message sends with channel locks.
- Adding a durable outbox for workspace-level message events.
- Live synchronization of newly created, renamed, or deleted Channels across other users' open sidebars.
- New routes or router scope changes.
- Channel-scoped online presence.
- Direct messages.
- Mentions.
- Reactions.
- Notification preferences.
- Push notifications, email notifications, or desktop notifications.
- Message edits or deletes beyond the foreign-key behavior required for read cursors.
- Role-based read permissions beyond current Workspace membership.
- Manual Channel ordering.
- Last-selected Channel memory.
- Production metrics or dashboards for unread behavior.

## Further Notes

The durable model is read positions, not unread counters. Counts are derived
from messages, membership, and read cursors. This keeps the source of truth
small while allowing the UI to render badges from a simple sparse map.

The main implementation boundary should stay deep and narrow: LiveViews ask
Chat for unread counts and mark-read side effects, while Chat hides the aggregate
query, upsert rules, monotonic cursor behavior, and membership fallback logic.
Workspaces remains responsible for the moments when membership or Channel
structure is created and therefore when baseline read state must be initialized.

The workspace-level PubSub event is deliberately a sidebar refresh signal. It
should not become a second message-rendering path. Timeline rendering continues
to use the selected Channel's existing full message event.
