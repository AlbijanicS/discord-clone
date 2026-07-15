# Message Replies, Mentions, and Global Activity Feed PRD

Status: ready-for-agent

This PRD synthesizes the completed `grill-with-docs` design session. The
project uses a docs-first issue-tracker fallback, so this document is the
ready-for-agent product artifact rather than a published external tracker
item. Canonical domain vocabulary comes from `CONTEXT.md`.

## Problem Statement

Workspace Members can exchange durable messages in Channels, react to them,
track unread ranges, and receive live updates, but conversations still lack two
important coordination tools. A member cannot attach a response directly to an
earlier message, so context becomes unclear in a busy Channel. A member also
cannot explicitly request another member's attention or reach the Workspace
audience through a controlled mention.

Even if mentions were highlighted in the Channel timeline, Users would still
have no durable place to find mentions across all of their Workspaces. Ordinary
Channel unread state answers “what have I not read?” but does not answer “where
did someone specifically request my attention?” Treating those as the same
state would make both behaviors difficult to understand.

The application therefore needs flat Message Replies, explicit User Mentions,
role-gated Everyone Mentions, and a global Activity Feed. These features must
preserve the existing authorization, sequencing, unread, runtime-recovery, and
soft-deletion guarantees.

## Solution

Add a flat reply relationship to Channel messages. A Message Reply references
one earlier message in the same Channel, remains in the ordinary timeline, and
shows a compact quoted preview. Replies do not create threads or nested
conversations, and replying does not implicitly mention the referenced author.

Recognize explicit `@username` User Mentions and authorized `@everyone`
Everyone Mentions when a message is sent. Resolve recipients against the
current Workspace membership, persist one durable User Activity per recipient,
and keep the resolution fixed even if usernames or memberships later change.
Owners and admins may create Everyone Mentions; regular members cannot.

Add a global Activity Feed reached through a bell in the authenticated
workspace rail. The feed aggregates relevant mentions from all of the User's
Workspaces, provides independent unread state, and links every Activity Item to
the exact source message. Activity state is durable Postgres state; private
per-User PubSub events keep bell counts and open feeds synchronized across tabs.

## User Stories

1. As a Workspace Member, I want to reply to an earlier Channel message, so that my response retains its conversational context.
2. As a Workspace Member, I want replies to remain in the normal Channel timeline, so that I do not need to enter a separate thread view.
3. As a Workspace Member, I want a reply to reference exactly one message, so that reply context stays simple and predictable.
4. As a Workspace Member, I want to reply to a message that is itself a Message Reply, so that natural back-and-forth conversation remains possible.
5. As a Workspace Member, I want a reply-to-reply to preview only its direct parent, so that nested reply chains do not clutter the timeline.
6. As a Workspace Member, I want the Reply action available on non-deleted messages, so that I can begin a contextual response from the relevant row.
7. As a Workspace Member, I want the selected reply target shown above the composer, so that I know which message I am answering.
8. As a Workspace Member, I want the reply target to show the author's name and truncated content, so that I can confirm the context before sending.
9. As a Workspace Member, I want to cancel a selected reply target without losing my draft, so that changing my mind is inexpensive.
10. As a Workspace Member, I want a successful send to clear the reply target, so that later messages do not accidentally reference it.
11. As a Workspace Member, I want validation failures to preserve my draft and valid reply target, so that I can correct the message without starting over.
12. As a Workspace Member, I want a stale deleted reply target removed with clear feedback while my draft remains, so that concurrent deletion does not destroy my work.
13. As a Workspace Member, I should not be able to start a new reply to a deleted message, so that replies do not deliberately target tombstones.
14. As a Workspace Member, I want an existing reply to survive deletion of its parent, so that the conversation sequence remains coherent.
15. As a Workspace Member, I want a deleted reply parent represented by a placeholder, so that deleted content is not exposed.
16. As a Workspace Member, I want a live reply preview to be clickable, so that I can jump to the referenced message.
17. As a Workspace Member, I want an out-of-window reply parent loaded and highlighted, so that navigation works across long Channel histories.
18. As a Workspace Member, I do not want a deleted-parent placeholder to be clickable, so that the interface does not promise an unavailable destination.
19. As a Workspace Member, I want to type `@username` to address a current Workspace Member, so that I can explicitly request that person's attention.
20. As a Workspace owner or admin, I want to type `@everyone`, so that I can address the Workspace-wide audience when necessary.
21. As a regular Workspace Member, I should not be able to create an Everyone Mention, so that broad alerts remain controlled.
22. As a regular Workspace Member, I want unauthorized `@everyone` text to remain ordinary message content, so that my message is not rejected or silently changed.
23. As a Workspace Member, I want unknown or non-member usernames to remain ordinary text, so that mentions do not reveal or target inaccessible Users.
24. As a Workspace Member, I want punctuation after a valid username to preserve the mention, so that normal sentences parse naturally.
25. As a Workspace Member, I do not want email-like text interpreted as a mention, so that ordinary content does not create accidental activity.
26. As a Workspace Member, I want mention matching to be case-insensitive, so that capitalization mistakes do not prevent an intended mention.
27. As a Workspace Member, I want repeated references to the same User in one message to create one Activity Item, so that the recipient is not spammed.
28. As a mentioned User, I want a message containing both my username and `@everyone` to create one Activity Item, so that one message appears once in my feed.
29. As a directly mentioned User, I want the direct mention to take precedence over `@everyone` as the Activity Item kind, so that the more specific reason is retained.
30. As a User, I do not want my own `@username` or `@everyone` message to create activity for me, so that my feed represents attention requested by other people.
31. As a Workspace Member, I want an `@` autocomplete menu, so that I can select valid mention targets without memorizing exact usernames.
32. As a Workspace Member, I want autocomplete to search current Workspace Members, so that suggestions stay relevant and authorized.
33. As a Workspace owner or admin, I want `@everyone` available in autocomplete, so that the special mention is discoverable.
34. As a regular Workspace Member, I should not see `@everyone` as an actionable autocomplete option, so that the UI reflects my capabilities.
35. As a keyboard User, I want to navigate and select mention suggestions without a mouse, so that the composer remains accessible and efficient.
36. As a Workspace Member, I want manually typed valid mentions to work without autocomplete, so that autocomplete remains assistance rather than authority.
37. As a User, I want `everyone` reserved from registration, so that `@everyone` has one deterministic meaning.
38. As a mentioned User, I want mention recipients fixed when the message is sent, so that later username changes do not rewrite history.
39. As a Workspace Member who joins later, I should not receive historical Everyone Mention activity, so that alerts reflect the audience at send time.
40. As a User, I want a bell in global authenticated navigation, so that mention activity is visible from Workspace and Channel surfaces.
41. As a User, I want the bell to show my unread Activity Item count, so that I can see when attention is waiting.
42. As a User, I want the Activity Feed to span all my Workspaces, so that I have one dependable inbox.
43. As a User, I want each Activity Item to identify its Workspace and Channel, so that I understand the source context.
44. As a User, I want each Activity Item to identify the User who authored the mention, so that I know who requested my attention.
45. As a User, I want each Activity Item to preview the original message content, so that I can triage it before navigating.
46. As a User, I want current Workspace and Channel names displayed, so that renamed collaboration spaces are not shown with stale labels.
47. As a User, I want a missing source author displayed as “Former member,” so that historical activity remains understandable without a broken association.
48. As a User, I want Activity Items ordered newest first, so that recent requests appear first.
49. As a User, I want older Activity Items loaded incrementally, so that a large history does not make the page slow.
50. As a User, I want opening the Activity Feed to leave items unread, so that browsing the inbox does not silently clear it.
51. As a User, I want opening an Activity Item to mark that item read, so that the bell reflects what I have handled.
52. As a User, I want an Activity Item to navigate to the exact source message, so that I can respond in context.
53. As a User, I want source navigation to load and highlight a message outside the current Channel window, so that old mentions remain usable.
54. As a User, I want inaccessible, missing, or deleted targets handled without revealing message existence, so that authorization remains intact.
55. As a User, I want to mark all Activity Items as read, so that I can clear attention I have already handled elsewhere.
56. As a User, I want new activity arriving during “Mark all as read” to remain unread, so that concurrent mentions are not lost.
57. As a User, I want Activity read state independent from Channel Read State, so that attention and timeline progress retain distinct meanings.
58. As a User, I do not want opening one Activity Item to clear all Channel unread state, so that unseen messages remain discoverable.
59. As a User, I do not want marking a Channel read to clear Activity Items automatically, so that direct requests remain in my inbox.
60. As a User with multiple tabs, I want bell counts and Activity Items synchronized live, so that every session reflects the same durable state.
61. As a User, I want deleted source messages removed from my Activity Feed, so that moderated or deleted content does not linger as a dead destination.
62. As a former Workspace Member, I should lose that Workspace's Activity Items, so that the feed never exposes content I can no longer access.
63. As a User who later rejoins a Workspace, I should not regain old removed Activity Items, so that membership cleanup remains final.
64. As a Workspace Member, I want message sending and Activity creation to succeed or fail together, so that no mention disappears between the Channel and feed.
65. As a Workspace Member, I want replies and mentions to survive Channel runtime loss, so that important conversation state remains durable.
66. As a developer, I want replies, mention resolution, User Activities, and authorization behind public Chat workflows, so that the web layer remains thin.
67. As a developer, I want one User Activity row per recipient, so that each User has independent read and cleanup state.
68. As a developer, I want Everyone Mention recipients inserted in bulk, so that one message does not cause an application-level insert loop.
69. As a developer, I want User Activity broadcasts private to the recipient, so that mention metadata does not leak through Workspace topics.
70. As a developer, I want compact post-commit broadcasts, so that LiveViews refresh authorized state rather than trusting broadcast records.
71. As a developer, I want the User Activity model reusable for future direct-message activity, so that the global feed does not require replacement later.
72. As a developer, I want Activity Feed queries cursor-paginated with stable ordering, so that concurrent inserts do not destabilize pages.
73. As a developer, I want tests at public Chat and authenticated LiveView seams, so that behavior is proven without coupling tests to query internals.
74. As a future maintainer, I want threads and implicit reply mentions explicitly excluded, so that the flat reply model is not accidentally expanded.

## Implementation Decisions

- Keep replies, mention resolution, User Activities, and their PubSub contracts
  in the Chat context because they derive from persisted messages.
- Keep LiveViews thin. They call public Chat workflows with the current
  authenticated Scope and do not query Repo or runtime processes directly.
- Continue deriving the current User from `current_scope.user`; do not introduce
  a separate `current_user` assign.
- Add the global `/activity` LiveView route to the existing authenticated
  browser pipeline and existing `live_session :require_authenticated_user`.
  The feed contains private User-specific data and therefore requires login.
- Reuse the authenticated application shell for Workspace home, Channel, and
  Activity surfaces. Settings may remain outside that shell.
- Place the activity bell in the global workspace rail and make it available
  even when no Workspace is selected.
- Keep all durable reply and activity state in Postgres. ChannelServer continues
  to own only ephemeral Channel state such as typing and the recent-message
  cache.
- Add a nullable self-reference from a Message to its directly referenced
  Message.
- Treat the reply reference as immutable after message insertion.
- Validate reply targets inside Chat, not only in the LiveView.
- Require the reply target to exist, belong to the selected Channel, precede
  the new message by Channel sequence, and not already be deleted.
- Permit a Message Reply to target another Message Reply while retaining only
  the direct reference.
- Do not calculate or persist transitive reply chains.
- Do not let a reply relationship implicitly create a User Mention.
- Preload or batch-load direct reply targets needed by bounded message windows;
  avoid one query per rendered message.
- Render a compact reply preview above the reply's message content.
- A live reply preview displays the current available author label and truncated
  source content.
- A reply whose target was soft-deleted displays a deleted-message placeholder
  without the source content.
- Preserve existing Message Replies when their targets are soft-deleted.
- Hide reply actions for deleted messages and reject stale attempts through the
  Chat context.
- Add a Reply action to non-deleted message controls.
- Store reply-composer selection as explicit LiveView state separate from the
  message content form.
- Show a reply-target bar above the existing composer with author, truncated
  content, and an accessible cancel control.
- Clear reply state after successful send. Preserve it across ordinary message
  validation failures.
- When a target is deleted concurrently, preserve the draft, remove the stale
  target, and show specific feedback.
- Use the same exact-message navigation mechanism for reply previews and
  Activity Items.
- Encode the source `message_id` as a query parameter on the existing
  authenticated Channel route.
- Resolve the source Message and its sequence through an authorized Chat
  workflow.
- Load a sequence-centered message window, scroll to the target row, and apply
  a temporary visual highlight.
- Return a safe not-found outcome for invalid, deleted, wrong-Channel, or
  inaccessible source IDs.
- Introduce a small Chat-owned mention parser/resolver boundary so parsing,
  recipient resolution, and authorization do not spread through LiveViews.
- Recognize only User Mentions and Everyone Mentions in this pass. Do not add
  role or Channel mentions.
- Recognize a mention only when `@` is not immediately preceded by a username
  character and the candidate ends before a non-username character or the end
  of the message.
- Match usernames case-insensitively while preserving original message content.
- Allow normal punctuation after a mention.
- Do not interpret email-like text as mentions.
- Leave unknown usernames and usernames belonging to non-members as plain text.
- Collapse repeated references to the same recipient within one message.
- Reserve `everyone` as a forbidden username in Accounts validation.
- Check existing data for an `everyone` username before enabling the reserved
  name constraint.
- Allow only Workspace owners and admins to resolve an Everyone Mention.
- Treat a regular member's literal `@everyone` as plain content rather than a
  failed message.
- Resolve User Mentions only to current Workspace Members.
- Resolve mention recipients when the message is sent and persist User IDs, not
  mutable username strings.
- Resolve Everyone Mention recipients from the membership audience at send
  time. Do not create historical activity for later joiners.
- Exclude the message author from every mention audience.
- Add mention autocomplete to the existing composer.
- Search current Workspace Members by username and support keyboard navigation
  and selection.
- Offer `@everyone` through autocomplete only when the current member has the
  owner or admin capability.
- Keep manual mention syntax authoritative on send; autocomplete is only a
  composition aid.
- Add a generic durable User Activity schema rather than a mention-specific
  notification table.
- Each User Activity belongs to one recipient User and optionally identifies
  the actor User who caused it.
- Store the Activity Item ID, recipient User ID, actor User ID, source Message
  ID, source Channel ID, nullable Workspace ID, kind, read timestamp, and
  insertion timestamp.
- Keep Workspace ID nullable so the model can later support non-Workspace
  conversations such as direct messages.
- Start with `user_mention` and `everyone_mention` kinds. Reserve additional
  kinds, such as direct-message activity, for later migrations.
- Treat routing identifiers on User Activity as deliberate denormalization for
  global feed queries, membership cleanup, authorization, and navigation.
- Keep the source Message authoritative for displayed message content; do not
  copy content into User Activity.
- Resolve current Workspace and Channel labels while rendering the feed.
- Resolve the current actor username when available and use “Former member” if
  the actor association no longer exists.
- Enforce one mention Activity Item per recipient and source Message. If both a
  direct User Mention and Everyone Mention concern the same recipient, store one
  row with `user_mention` precedence.
- Extend the existing sequenced send transaction so Message insertion, Channel
  sequencing, reply validation, mention resolution, User Activity insertion,
  and unread fan-out succeed or fail atomically.
- Perform runtime cache updates and PubSub broadcasts only after the database
  transaction commits.
- Bulk-insert Everyone Mention Activity Items from the eligible membership
  audience in one database operation. Do not spawn per-recipient tasks or
  perform an application-level insert loop.
- Use uniqueness constraints as the final defense against duplicate Activity
  Items.
- Index stable global feed pagination by recipient, insertion time, and ID.
- Add an index supporting unread Activity lookup by recipient and read state.
- Query the Activity Feed newest first with stable cursor pagination on
  insertion time and ID.
- Load 50 Activity Items initially and provide incremental older loading without
  requiring a total count.
- Maintain the unread bell count as a separate aggregate from the paginated
  feed collection.
- Opening the Activity Feed does not update read state.
- Opening a valid Activity Item marks only that item read and navigates to its
  source message.
- “Mark all as read” captures a server-side cutoff and updates only unread
  Activity Items at or before that cutoff. Later commits remain unread.
- Keep Activity read state independent from per-Channel Read State and Unread
  Spans.
- Exact-message navigation may cause existing visibility observation to mark
  actually observed Channel ranges, but it must not clear the whole Channel as
  a side effect of reading one Activity Item.
- Marking a Channel read does not mark its User Activities read.
- Delete User Activities for a Message in the same transaction that soft-deletes
  that Message.
- Ensure bulk moderation cleanup also removes affected User Activities.
- Permanently remove a User's Workspace-specific Activity Items when their
  membership is removed through leave, kick, or ban workflows.
- Do not restore removed historical Activity Items if the User later rejoins.
- Add private per-User Chat PubSub topics for Activity changes.
- Broadcast compact post-commit events when Activity Items are created, read,
  marked all read, or removed.
- Authenticated Workspace and Channel LiveViews subscribe for their current User
  and refresh the bell count through authorized Chat APIs.
- The Activity LiveView subscribes to the same private topic and streams or
  refreshes affected feed state.
- Keep private topic construction and broadcast contracts inside Chat.
- Do not broadcast full Message, User, or User Activity structs.
- Preserve LiveView streams for the Activity Feed and existing message
  collection.
- Give the bell, feed, feed controls, reply actions, reply previews,
  reply-target bar, autocomplete, and exact-message target stable unique DOM
  IDs for behavior tests.
- Use existing Tailwind and component conventions for the new surfaces,
  including the imported icon component for the bell and action icons.
- Do not add external scripts, stylesheets, component libraries, or raw inline
  scripts.

## Testing Decisions

- Prefer the highest existing behavioral seams: public Chat context APIs for
  durable domain behavior and authenticated LiveViews for composition,
  navigation, rendering, and live synchronization.
- Good tests prove externally observable outcomes and authorization. They do not
  assert private helper names, exact SQL shape, internal process state, or raw
  HTML strings.
- Keep isolated parser tests only where the mention parser is deliberately a
  small deep module with a stable public contract.
- Add Message changeset or Chat workflow tests proving a Message may omit a
  reply target.
- Add Chat tests proving a valid same-Channel earlier Message can be referenced.
- Add Chat tests rejecting missing, cross-Channel, future-sequence, and deleted
  reply targets.
- Add Chat tests proving a reply may reference another reply without persisting
  a transitive chain.
- Add Chat tests proving the reply relationship is durable across Channel
  runtime loss.
- Add Chat tests proving parent soft deletion preserves the reply while hiding
  deleted content from its preview.
- Add parser tests for start/end boundaries, punctuation, case-insensitive
  matching, repeated mentions, email-like text, unknown usernames, and
  `@everyone`.
- Add Accounts tests proving `everyone` is rejected as a username without
  weakening existing username normalization and uniqueness behavior.
- Add Chat tests proving User Mentions resolve only current Workspace Members.
- Add Chat tests proving owners and admins may create Everyone Mentions while a
  regular member's token remains plain text.
- Add Chat tests proving the author is excluded from direct and Everyone Mention
  activity.
- Add Chat tests proving direct and Everyone Mention overlap creates one
  recipient Activity Item with direct-mention precedence.
- Add Chat tests proving recipients are fixed at send time despite later
  username or membership changes.
- Add transaction tests proving invalid reply or Activity persistence rolls back
  the entire message send and its sequence/unread effects.
- Add Chat tests proving Everyone Mention fan-out creates one durable Activity
  Item for every eligible recipient and no duplicates.
- Test public outcomes of bulk fan-out rather than asserting a particular Ecto
  function or query plan.
- Add Chat tests for global Activity Feed authorization, newest-first ordering,
  stable cursor pagination, and the initial 50-item boundary.
- Add Chat tests proving User Activities expose their recipient, actor, source,
  kind, and read outcome without leaking inaccessible Workspace data.
- Add Chat tests proving opening one item marks only that item read.
- Add Chat tests proving “Mark all as read” respects its cutoff and leaves a
  concurrently inserted Activity Item unread.
- Add Chat tests proving Activity read operations do not mutate Channel Read
  State or Unread Spans.
- Add existing unread-workflow tests proving Channel read operations do not
  mutate User Activity read state.
- Add Chat and Workspaces workflow tests proving message deletion, bulk message
  moderation, leave, kick, and ban remove the required Activity Items.
- Add tests proving rejoining does not restore previously removed activity.
- Add PubSub contract tests proving only the intended recipient topic receives
  compact creation, read, mark-all, and deletion events.
- Add multi-session LiveView tests proving bell counts synchronize after mention
  creation and Activity read changes.
- Add Channel LiveView tests for Reply selection, cancellation, successful send,
  validation preservation, and concurrent target deletion.
- Add Channel LiveView tests proving reply previews render live and deleted
  states using stable selectors.
- Add Channel LiveView tests proving clicking a reply preview loads, scrolls to,
  and highlights an out-of-window parent.
- Add composer tests for mention autocomplete visibility, current-member
  filtering, owner/admin `@everyone` capability, keyboard selection, and manual
  entry fallback.
- Add Activity LiveView tests for the global bell link, unread badge, empty
  state, 50-item initial page, incremental loading, read styling, and mark-all
  control.
- Add Activity navigation tests proving a valid item reaches the exact Workspace,
  Channel, and Message.
- Add navigation tests proving invalid, deleted, cross-Channel, and inaccessible
  Message IDs return safe outcomes without leaking source existence.
- Use `element/2`, `has_element?/2`, form helpers, and stable IDs for LiveView
  assertions rather than matching raw rendered HTML.
- Prior art for public behavior and transaction tests exists in the Chat and
  Workspaces context suites.
- Prior art for message composition, PubSub synchronization, bounded message
  windows, exact scrolling, and stable selectors exists in the Channel and
  Workspace LiveView suites.
- Prior art for membership cleanup exists in invite, moderation, unread, and
  Workspace lifecycle tests.
- Start supervised processes with `start_supervised!/1`; synchronize through
  monitors or `:sys.get_state/1` rather than sleeps or process-liveness polling.
- Run focused parser, context, and LiveView tests while implementing, then run
  the complete `mix precommit` alias before considering the feature complete.

## Out of Scope

- Threaded conversations or a separate thread view.
- Nested or transitive reply-chain rendering.
- Implicitly mentioning an author merely because their message was replied to.
- Replying to an already deleted message.
- Message editing.
- Role mentions.
- Channel mentions.
- `@here` or presence-dependent audience mentions.
- Mentions of Users who are not current Workspace Members.
- Browser, operating-system, email, mobile, or push notifications.
- Reaction activity, invite activity, moderation activity, or ordinary-message
  activity in the global feed.
- Direct Messages and direct-message Activity Item creation. The User Activity
  schema is designed to accommodate them later, but this PRD does not implement
  them.
- Restoring old Activity Items after a User rejoins a Workspace.
- Copying message content or mutable Workspace and Channel display names into
  User Activity rows.
- Replacing existing Channel Read State or Unread Span behavior with Activity
  read state.
- Storing reply, mention, or Activity state only in ChannelServer memory.
- Exposing private User Activity events on Workspace-wide PubSub topics.
- Total-count pagination for the Activity Feed.

## Further Notes

- Recommended delivery can be split into many vertical specs or issues. A
  sensible dependency order is:
  1. Reserve the `everyone` username and add the durable User Activity model.
  2. Add flat reply persistence and Chat validation.
  3. Add mention parsing, recipient resolution, and transactional Activity
     fan-out.
  4. Add private per-User Activity PubSub and unread count APIs.
  5. Add reply composer and timeline navigation behavior.
  6. Add mention autocomplete and highlighted message rendering.
  7. Add the global bell, Activity Feed, pagination, and exact-message routing.
  8. Integrate deletion, membership cleanup, moderation cleanup, and final
     multi-session acceptance coverage.
- The key model distinction is intentional: Channel Read State tracks timeline
  progress, while Activity Item read state tracks whether a specific request for
  attention has been handled.
- User Activity is generic by design. Mention activity is the only producer in
  this PRD, but nullable Workspace association and explicit kinds leave room for
  future direct-message activity.
- An Everyone Mention uses fan-out-on-write because recipient-specific read
  state, send-time audience semantics, membership cleanup, and global feed
  queries all require durable per-User rows.
- The route placement is explicit: `/activity` belongs inside the existing
  authenticated browser scope and the existing
  `live_session :require_authenticated_user`, because anonymous and
  unauthenticated Users must never receive private Activity Feed data.
