# Unread Ranges And First Unread Navigation PRD

Status: ready-for-agent

This PRD comes from a `grill-me` design session about replacing the current
cursor-based unread behavior with Discord-like unread navigation. The project is
using a docs-first fallback for now, so this document is the ready-for-agent
product artifact rather than a published external tracker item.

This PRD supersedes the read-on-open behavior in the earlier unread-counts PRD.
The existing `channel_reads` cursor model remains useful as migration input,
but it is not expressive enough for the final unread behavior described here.

## Problem Statement

Workspace Members can already see numeric unread badges backed by durable
Postgres state, but the current model treats read state as one cursor per User
and Channel. That works only when the User reads every message in order. It
breaks once the app behaves like a real chat product where a User can open a
Channel, land near recent unread messages, jump around, read only visible
messages, or intentionally skip unread history.

The current behavior also clears a Channel when it is opened. That is too
aggressive. Opening a Channel does not prove the User actually saw every unread
message, especially when the Channel contains hundreds of unread messages,
history is loaded in pages, or the browser tab is hidden.

The desired experience is closer to Discord: unread state should reflect what
the User actually observed or explicitly dismissed, the Channel should help the
User navigate to unread history, and the message list should support smooth
bidirectional history loading without keeping unlimited messages rendered.

## Solution

Replace the single cursor as the unread source of truth with per-user unread
ranges. Each Message receives a stable Channel-local sequence number. Unread
state is stored as one or more unread spans for each User and Channel, while a
separate read-state row stores fast sidebar summary fields.

Opening a Channel no longer marks it read. Instead, it records that the User
opened the Channel and chooses a landing window:

- If unread is small, land near the oldest unread message.
- If unread is large, land near the newest unread area and show a sticky unread
  action bar with `Jump to oldest unread` and `Mark as read`.
- If there is no unread state, land near the User's last viewed anchor when
  available; otherwise land at the latest messages.

Messages become read automatically only when the browser confirms they were
actually visible: at least 60 percent of the message row must be visible for 1
second while the tab is visible and the window is focused. Explicit actions can
clear all unread state: `Mark as read` clears the Channel without moving the
User, while `Jump to latest` clears unread state and navigates to the newest
messages. `Jump to oldest unread` navigates only; it does not clear unread.

The message list should support automatic bidirectional pagination by sequence
number. The database history remains unlimited, but the rendered message window
is capped so the browser and LiveView do not keep growing forever.

No route or router scope changes are required. Channel LiveViews stay in the
existing authenticated browser pipeline and existing
`live_session :require_authenticated_user` because all unread workflows require
`current_scope`, an authenticated User, and Workspace membership.

## User Stories

1. As a Workspace Member, I want opening a Channel to preserve unread state, so that messages are not marked read before I actually see or dismiss them.
2. As a Workspace Member, I want unread badges to reflect messages I have not observed, so that the sidebar remains trustworthy.
3. As a Workspace Member, I want unread state to support gaps, so that reading recent messages does not erase older unread messages.
4. As a Workspace Member, I want a Channel with a small unread backlog to open near the oldest unread message, so that I can start reading naturally.
5. As a Workspace Member, I want a Channel with a large unread backlog to open near recent unread messages, so that I am not thrown far back into history.
6. As a Workspace Member, I want a sticky unread action bar when older unread messages are outside the current window, so that I can jump to the oldest unread message or mark the Channel read.
7. As a Workspace Member, I want `Jump to oldest unread` to take me to the first unread message without clearing unread state, so that I can read from the beginning.
8. As a Workspace Member, I want `Mark as read` to clear all unread messages in the Channel without moving me, so that I can dismiss unread state intentionally.
9. As a Workspace Member, I want `Jump to latest` to clear all unread messages and move me to the newest messages, so that intentionally skipping backlog has one clear action.
10. As a Workspace Member, I want my own sent messages to be treated as read for me, so that sending never creates self-unread state.
11. As a Workspace Member, I want sending a message to leave older unread messages unread unless they are visible or explicitly dismissed, so that replying does not silently clear backlog.
12. As a Workspace Member, I want messages to become read only after they are substantially visible for a short time, so that fast scrolling does not mark unseen messages read.
13. As a Workspace Member, I want read detection to pause when the tab is hidden or the window is not focused, so that background pages do not clear unread state.
14. As a Workspace Member, I want visible messages to become read while I am typing, so that active focused conversation still counts as reading.
15. As a Workspace Member, I want incoming messages in the currently open Channel to create unread state first, so that being in a Channel does not imply I am at the bottom or paying attention.
16. As a Workspace Member, I want visible incoming messages to clear after the visibility rule is satisfied, so that open focused Channels quickly settle to correct unread state.
17. As a Workspace Member, I want an unread divider to mark where unread began in the current window, so that I understand why I landed there.
18. As a Workspace Member, I want the unread divider to stay visually stable while I read, so that it does not chase my scroll position.
19. As a Workspace Member, I want the unread divider to disappear when unread state is cleared, so that the UI stops labeling read messages as new.
20. As a Workspace Member, I want a Channel context-menu `Mark as read` action, so that I can clear unread state from the sidebar without navigating.
21. As a Workspace Member, I want `Mark as read` to work for non-selected Channels, so that I can clean up the sidebar quickly.
22. As a Workspace Member, I want read-state changes to sync across my own open tabs or devices, so that clearing unread in one place updates the others.
23. As a Workspace Member, I do not want my private read state broadcast to other members, so that unread state remains personal.
24. As a Workspace Member, I want exact sidebar unread counts to remain fast, so that high-activity Workspaces do not require scanning all Messages.
25. As a Workspace Member, I want no unread Channel to reopen where I last left off, so that the app remembers my reading position.
26. As a Workspace Member, I want no unread Channel to offer `Jump to latest` when I reopen away from the bottom, so that I can quickly return to the present.
27. As a Workspace Member, I want unread landing to win over my last viewed position, so that Channels with unread badges help me resolve unread state.
28. As a Workspace Member, I want smooth automatic loading when I scroll near the top or bottom, so that the old manual `Load older` button disappears.
29. As a Workspace Member, I want to scroll through all Channel history without an artificial message cap, so that local history remains available.
30. As a Workspace Member, I want the app to render only a bounded message window, so that long history does not make the browser slow.
31. As a Workspace Member, I want my scroll position preserved when older messages load above me, so that the viewport does not jump.
32. As a Workspace Member, I want loading states at the top or bottom of the message list, so that history fetches feel smooth rather than broken.
33. As a Workspace Member, I want new Workspace membership to start with existing history treated as read, so that joining a Workspace does not create old unread backlog.
34. As a Workspace Member, I want a newly created Channel to start read for all current members, so that empty structure does not create unread state.
35. As a Workspace Member, I want leaving a Workspace to delete my read state for that Workspace, so that private per-user state is cleaned up.
36. As a developer, I want unread truth stored in Postgres, so that Channel process crashes do not lose read state.
37. As a developer, I want unread state outside ChannelServer, so that GenServers remain responsible only for temporary runtime state.
38. As a developer, I want Chat to own unread workflows behind public APIs, so that LiveViews do not assemble unread queries directly.
39. As a developer, I want Workspaces to keep owning membership and Channel lifecycle events, so that read-state initialization happens at the right domain boundary.
40. As a developer, I want Channel recipients hidden behind one boundary, so that future private Channels can change recipient selection without rewriting message send logic.
41. As a developer, I want message send and unread fanout to be synchronous initially but isolated behind a boundary, so that a future outbox worker can replace it cleanly.
42. As a developer, I want visible-read range subtraction to be idempotent, so that duplicate browser events cannot corrupt unread state.
43. As a developer, I want visible-read broadcasts only when state actually changes, so that duplicate no-op events do not churn the UI.
44. As a developer, I want message pagination by Channel-local sequence number, so that unread, jumps, dividers, and history loading share one ordering model.
45. As a developer, I want separate constants for page size and unread landing policy, so that loading behavior and UX thresholds can evolve independently.
46. As a developer, I want tests that prove behavior through public context APIs and LiveView outcomes, so that implementation details can change safely.

## Implementation Decisions

- Add Channel-local message sequencing.
- Add `seq` to Messages as a `bigint` Channel-local positive sequence.
- Add `last_message_seq` to Channels as a non-null `bigint` summary that starts
  at zero for empty Channels.
- Roll the sequence migration out in stages: add nullable fields, backfill,
  validate constraints, then enforce non-null where appropriate.
- Backfill Message sequences per Channel using chronological order, with durable ID as the tie-breaker.
- Add a unique constraint for each Channel and sequence pair.
- Add an index that supports Message window queries by `channel_id` and `seq`.
- Assign new Message sequences by locking the Channel row inside the Message transaction, incrementing `last_message_seq`, and inserting the Message with that sequence.
- Use `messages.seq` for unread logic, pagination, jump targets, dividers, and rendered ordering.
- Replace cursor source-of-truth semantics with unread spans.
- Add `channel_unread_spans` as the canonical unread-detail table.
- Each unread span stores User, Channel, `from_seq`, and `to_seq`.
- Do not store `message_count` on unread spans; derive a span's count from `to_seq - from_seq + 1`.
- Enforce positive span bounds and reject `from_seq > to_seq`.
- Prevent overlapping unread spans for the same User and Channel at the database
  level. The intended Postgres invariant is an exclusion constraint over
  `user_id`, `channel_id`, and the inclusive `int8range(from_seq, to_seq)`;
  enable the `btree_gist` extension if needed for equality on integer IDs.
- Always merge adjacent or overlapping unread spans.
- Visible-read operations subtract only the overlapping unread portions of a submitted range.
- Repeating the same visible-read operation must be idempotent.
- Do not add client event IDs for visible-read deduplication; span subtraction already gives state correctness.
- Broadcast read-state changes only when unread state actually changed.
- Add `channel_read_states` as the fast per-user Channel summary.
- `channel_read_states` stores `unread_count`, `first_unread_seq`, `last_unread_seq`, `last_viewed_anchor_seq`, and `last_opened_at`.
- `first_unread_seq` always means the oldest unread Message.
- `last_unread_seq` always means the newest unread Message.
- `last_viewed_anchor_seq` means where the User last meaningfully was in the Channel UI and may move forward or backward.
- Do not store `last_seen_seq`; unread spans are the read truth, and `last_viewed_anchor_seq` is the useful resume-position field.
- Keep sidebar unread counts sourced from `channel_read_states`.
- Keep unread spans as the canonical detail for what remains unread.
- Every add, subtract, and clear operation for one User and Channel runs in one
  transaction and serializes through the matching `channel_read_states` row with
  a row-level lock before reading or mutating spans.
- If a valid member is missing a read-state row, the workflow creates the row
  first, then locks it before mutating unread spans.
- Read-state summaries are recomputed or updated transactionally with span
  mutations, so `unread_count`, `first_unread_seq`, and `last_unread_seq` never
  describe a different set of spans.
- Existing `channel_reads` cursor rows are migration/backfill input only after the new model is introduced.
- Stop using `channel_reads` as the active unread source once read states and unread spans are live.
- Backfill existing read states and unread spans from the old cursor model.
- For existing users, preserve the old meaning: Messages after the old cursor become unread spans, with own Messages excluded from unread counts.
- Missing or nil old cursor rows use the existing membership-time fallback
  semantics from the cursor model.
- Messages with a nil author count as not-own Messages during backfill and
  unread fanout when they are otherwise eligible.
- New Workspace Members start with current history treated as read.
- New Channel creation initializes zero-unread read states for all current Workspace Members.
- Leaving a Workspace deletes that User's read states and unread spans for Channels in the Workspace.
- Chat unread APIs keep the existing Chat privacy shape for unread workflows:
  unauthenticated scopes return `{:error, :unauthenticated}` and logged-in
  non-members return `{:error, :not_found}`.
- Use "Channel recipients" as the internal boundary for unread fanout.
- Today, Channel recipients are all Workspace Members for the Channel's Workspace except the sender.
- Future private Channels or Channel permissions should change the recipient query, not the send workflow.
- On message send, insert the Message and create unread state for recipients in the same transaction for now.
- Message and workspace broadcasts happen only after the Message, sequence, and
  unread fanout transaction succeeds.
- Keep unread fanout behind one internal boundary so it can move to a durable outbox or worker later.
- Sender's own Message is never unread for the sender.
- Sending a Message does not clear the sender's older unread backlog.
- Opening a Channel calls a Chat-owned open workflow that validates access and updates `last_opened_at`.
- Opening a Channel does not clear unread spans.
- LiveView chooses the presentation landing policy from the read state returned by Chat.
- The opening policy is: unread wins; no unread uses `last_viewed_anchor_seq` when available; otherwise latest.
- If unread count is less than or equal to the small unread landing limit, land around `first_unread_seq`.
- If unread count is greater than the small unread landing limit, land near recent unread by targeting a sequence slightly before `last_unread_seq`.
- Start `@message_page_size` at 50.
- Start `@small_unread_landing_limit` at 50.
- Keep these constants separate even if they start with the same value.
- Targeted windows use a biased split: 15 Messages before the target and 35 after.
- Large unread landing should target about 20 Messages before `last_unread_seq` when possible before applying the targeted window.
- Latest loading fetches the latest page ending at `channel.last_message_seq`.
- `Jump to oldest unread` navigates to a targeted window around `first_unread_seq`.
- `Jump to oldest unread` does not clear unread state.
- `Jump to latest` clears all unread spans for the Channel and navigates to the latest Messages.
- `Mark as read` clears all unread spans for the Channel and keeps the User at the same scroll position.
- Keep `Mark as read` and `Jump to latest` as separate public actions even if they share an internal clear function.
- When unread is cleared, set `unread_count` to zero and clear `first_unread_seq` and `last_unread_seq`.
- After `Jump to latest`, update `last_viewed_anchor_seq` to the Channel's latest sequence.
- After `Mark as read`, do not move the User; update read state and remove unread UI immediately.
- The Channel context menu should include `Mark as read` for Channels with unread messages.
- Context-menu `Mark as read` works for selected and non-selected Channels.
- User-scoped read-state PubSub broadcasts update the same User's other LiveViews.
- User-scoped read-state broadcasts include the updated summary payload for direct UI updates, including `workspace_id`, `channel_id`, `unread_count`, `first_unread_seq`, and `last_unread_seq`.
- Shared workspace or Channel message broadcasts must not include user-private unread state.
- Do not suppress unread state for the selected Channel; create unread first, then let observation clear it.
- Selected-Channel incoming Messages are rendered immediately only when the
  current loaded window is at or near latest. If the User is reading older
  history, do not force-scroll or inject a distant latest Message into the
  current window; update window metadata so newer history exists and keep `Jump
  to latest` available.
- The browser hook uses IntersectionObserver or equivalent viewport observation
  rooted at the Channel message container, not the browser viewport.
- A normal-height Message counts as read when at least 60 percent of its row is
  visible for 1 second.
- A Message taller than the message container counts as read when the visible
  pixels reach the smaller of 60 percent of the row height or 60 percent of the
  message-container height for 1 second.
- The read observer pauses or cancels timers when the document is hidden or the window is unfocused.
- The read observer cancels timers and unobserves rows when LiveView patches,
  trims, or removes Message rows.
- Typing in the message input still counts as active focused use.
- Visible-read events submit compact sequence ranges.
- Server-side visible-read validation requires Workspace membership, valid Channel sequence bounds, ordered range values, and a maximum range size.
- Cap each visible-read range at 50 Messages.
- Reject oversized visible-read ranges rather than silently accepting them.
- Validate visible-read ranges against Channel sequence bounds instead of querying every Message row.
- The LiveView accepts visible-read events only for Message sequences currently
  present in the rendered window and observed by the client hook.
- The JS hook should split larger observed sets into valid ranges.
- Add a debounced scroll anchor update from the browser to the server.
- The scroll anchor should use the center-most visible Message.
- Start the scroll-anchor debounce around 1.5 seconds.
- Scroll-anchor writes update `last_viewed_anchor_seq`; they do not mark Messages read.
- The unread divider is stable within the current loaded window and does not chase the first remaining unread Message after every visible-read event.
- Recalculate the unread divider when opening, jumping, replacing the message window, or clearing all unread.
- Render an inline unread divider only when its target Message is loaded.
- Show a fixed or sticky unread action bar under the Channel header when unread exists outside the current loaded window and the inline divider is not useful.
- The sticky unread action bar shows `Jump to oldest unread` and `Mark as read`.
- Hide the sticky unread action bar after `Jump to oldest unread` if the inline divider is visible.
- Do not show directional unread counts inside the message pane; the sidebar badge owns exact counts.
- Do not add `Jump to next unread`.
- Show `Jump to latest` when the User is away from latest; clicking it clears all unread.
- The internal action may remain named `jump_to_latest`, but the visible UI must
  make the dismissive behavior explicit, for example with `Skip to latest` copy
  or an accessible label that says unread will be marked read.
- Replace the old manual `Load older` button with automatic scroll-edge loading.
- Trigger older or newer page loading when the User scrolls near the relevant edge of the message container.
- Start the scroll-edge trigger distance around 300 pixels.
- Track older and newer loading state to prevent duplicate page requests.
- Support bidirectional pagination: load older before the current oldest sequence and newer after the current newest sequence.
- Support loading a message window around a target sequence.
- Cap rendered Messages at 300.
- Database history is not capped.
- When the rendered window exceeds the cap, trim from the side opposite the User's scroll direction.
- Never trim currently visible Messages.
- Trimming must prune all per-Message LiveView state for removed Messages,
  including stream items, row metadata maps, reaction summaries, and client
  observer state.
- Preserve scroll position when older Messages are prepended.
- Use edge loading indicators rather than manual loading buttons.
- Keep ChannelServer responsible only for temporary runtime state such as recent cache and typing users.
- Do not store unread spans, read states, or resume anchors in GenServer state as the source of truth.
- Keep Channel LiveViews inside the existing authenticated browser pipeline and existing `live_session :require_authenticated_user`.
- The route placement stays unchanged because unread workflows require `current_scope`, authenticated User identity, and Workspace membership.

## Testing Decisions

- Good tests should prove observable behavior through public Chat APIs, Workspaces workflows, and LiveView outcomes.
- Avoid tests that depend on private helper names or exact query implementation.
- Add schema and migration tests for Message sequence uniqueness, Channel `last_message_seq`, read states, and unread spans.
- Test backfilling Message sequences per Channel in chronological order.
- Test assigning unique sequences when multiple Messages are sent in the same Channel.
- Test that Message send creates unread spans for all current Channel recipients except the sender.
- Test that sending a Message does not clear the sender's older unread spans.
- Test unread fanout through the public send workflow, while keeping the internal boundary replaceable later.
- Test that new Workspace Members start with existing history treated as read.
- Test that new Channel creation initializes zero-unread read states for current Workspace Members.
- Test that leaving a Workspace deletes relevant unread spans and read states.
- Test span merge behavior for adjacent and overlapping spans.
- Test span subtraction for exact overlap, partial overlap, middle splits, non-overlap, and duplicate submissions.
- Test that visible-read subtraction updates `unread_count`, `first_unread_seq`, and `last_unread_seq`.
- Test that concurrent range mutations for the same User and Channel serialize
  correctly and do not leave overlapping spans or stale read-state summaries.
- Test that duplicate visible-read events do not broadcast when state is unchanged.
- Test visible-read range validation for unauthenticated scopes, non-members, invalid ranges, out-of-bounds ranges, and oversized ranges.
- Test `open_channel` updates `last_opened_at` without clearing unread state.
- Test small unread landing chooses the oldest unread target.
- Test large unread landing chooses a recent unread target near newest unread.
- Test no-unread landing uses `last_viewed_anchor_seq` when present.
- Test unread landing wins over `last_viewed_anchor_seq`.
- Test `Jump to oldest unread` navigates without clearing unread.
- Test `Jump to latest` or `Skip to latest` clears unread and returns or loads the latest window with UI copy that makes the clearing behavior explicit.
- Test `Mark as read` clears unread without requiring navigation.
- Test context-menu `Mark as read` for selected and non-selected Channels.
- Test user-scoped read-state broadcasts update only the same User's sessions.
- Test private read-state broadcasts include Workspace ID and do not affect other
  open Workspaces for the same User.
- Test shared message broadcasts do not include user-private unread summaries.
- Test automatic older and newer pagination by sequence.
- Test loading around a target sequence with the 15-before and 35-after split.
- Test latest loading ends at the Channel's latest sequence.
- Test selected-Channel incoming Messages while at latest and while reading older
  history, proving they do not force-scroll or become read without observation.
- Test virtualization keeps the rendered window at or below the configured cap after trimming.
- Test trim behavior does not remove currently visible Messages.
- Test trim behavior removes server-side per-Message assigns for trimmed
  Messages.
- Test scroll anchor updates use the center-most visible Message through a debounced client event where practical.
- Test visible-read hooks with container-rooted visibility, tall Message rows,
  document hidden, window unfocused, LiveView row removal, and rendered-window
  validation where practical.
- LiveView tests should use stable DOM IDs and LiveView helpers such as `element/2`, `has_element?/2`, and event rendering helpers instead of raw HTML assertions.
- JavaScript hook behavior should be covered at the highest practical level available in the project. If full browser tests are not present, keep the hook small, deterministic, and verified through LiveView event contracts plus focused JS checks where feasible.
- Existing Chat context tests provide prior patterns for membership access, message sending, PubSub behavior, and unread count behavior.
- Existing Workspaces context tests provide prior patterns for Workspace creation, invite acceptance, Channel creation, leaving Workspaces, and transaction behavior.
- Existing Channel LiveView tests provide prior patterns for shell rendering, message streams, context menus, selected Channel navigation, and access recovery.
- Focused verification should run Chat, Workspaces, and Workspace/Channel LiveView tests before the project precommit alias.

## Out of Scope

- Per-message read receipts visible to other Workspace Members.
- Showing which members have read a Message.
- Broadcasting private read state to other Workspace Members.
- OS notifications, push notifications, or mention notifications.
- Direct messages.
- Channel-specific membership or private Channels.
- Production-scale async unread fanout or durable outbox processing.
- Metrics dashboards for unread processing.
- Search across history.
- Artificial history caps or premium-style history limits.
- Editing or deleting Message behavior beyond preserving sequence ordering and unread consistency where existing workflows require it.
- A full rewrite of ChannelServer or message runtime supervision.
- New routes or router scope changes.
- `Jump to next unread`.
- Directional unread counts inside the message pane.

## Further Notes

This is a medium-large architectural upgrade, not a rewrite. The existing app
already has durable Messages, Workspace membership boundaries, Channel
LiveViews, sidebar badges, and cursor-based read rows. The new design keeps the
same broad boundaries:

- Workspaces owns Workspace membership and Channel lifecycle events.
- Chat owns message history, unread persistence, read-state workflows, and
  PubSub orchestration.
- LiveViews call public context APIs and own presentation policy.
- ChannelServer remains temporary runtime state only.

The hardest product risk is scroll and navigation polish, not the sidebar
count. Landing in the middle of history requires bidirectional pagination,
scroll anchoring, bounded rendering, and careful unread UI. These should be
implemented in small slices.

The hardest data risk is unread fanout. Synchronous fanout is acceptable for
this local learning app and keeps behavior easy to reason about, but the code
should keep fanout behind a boundary that could later become an outbox worker.

The old `channel_reads` cursor table should not be deleted immediately. It is
valuable for migration and rollback confidence. Once the new read states and
spans are trusted, active unread reads and writes should no longer depend on
the cursor table.
