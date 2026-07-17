# Friendships and Direct Messages PRD

Status: ready-for-agent

This specification synthesizes the completed Friendships and Direct Messages design session. It is published to the repository's local Markdown issue tracker and uses the canonical vocabulary from the domain glossary and the accepted architectural decisions for this area.

## Problem Statement

Users can currently communicate only through Workspace Channels. This works for group collaboration, but it does not let two Users establish a mutual relationship and continue a private conversation outside a particular Workspace. Treating private messaging as merely another Workspace Channel would expose Direct Conversations to Workspace membership, moderation, invites, roles, and lifecycle rules that do not belong to them.

Users also need one coherent place to find Friends, pending Friend Requests, Direct Conversations, and personally relevant Activity. The existing Activity Feed handles Workspace mentions, but it does not surface Direct Messages or Friend relationship events. Existing Workspace presence cannot accurately show whether a Friend is online when the Users do not share or currently view the same Workspace.

The feature must add these capabilities without duplicating the existing message engine or weakening authorization. Workspace Channels and Direct Conversations share durable timelines, replies, reactions, unread behavior, typing, pagination, soft deletion, runtime caching, and recovery, but they require different participant, recipient, mention, moderation, and send-permission policies.

## Solution

Add mutual Friend Requests addressed by exact global username and owned by a dedicated Friendships context. One canonical Friend relationship record represents the pending-to-accepted lifecycle for each User pair. Friend Requests require acceptance, while crossed requests automatically accept the existing pending relationship. Blocking and global User browsing are not included.

Add one-to-one Direct Conversations that exist independently from Workspaces and Friend relationship rows. Current Friendship is required to create a Direct Conversation and to add new conversational content. A Direct Conversation is created lazily when a Friend first chooses to message the other User. Ending the Friendship preserves the same Conversation and history in read-only mode; restoring the Friendship re-enables it.

Generalize the current Channel-only message foundation into a shared Conversation base with Workspace Channel and Direct Conversation subtypes. Messages, sequencing, reactions, replies, unread state, Activity integration, runtime processes, and PubSub use Conversation identity, while kind-specific policy remains behind public contexts.

Add a top-level Direct Messages destination above Workspace icons. Its shell brings together Friends, incoming and outgoing requests, global online/offline Friend Presence, and recent Direct Conversations. Direct Messages and Friend relationship events enter the Activity Feed. A received Direct Message becomes read after one continuous second of genuine foreground visibility, atomically clearing both its Conversation unread state and its unread Activity Item.

## User Stories

1. As an authenticated User, I want to send a Friend Request using another User's exact username, so that I can connect without first sharing a Workspace.
2. As an authenticated User, I want usernames matched using their canonical normalized identity, so that capitalization does not create ambiguous Friend targets.
3. As a User, I do not want a browsable global User directory, so that connecting by username does not expose every account.
4. As a User, I do not want fuzzy global User search, so that knowing an exact username remains the discovery boundary.
5. As a Workspace Member, I want an Add Friend action for another member, so that I can connect without retyping a known username.
6. As a User, I should not be able to send a Friend Request to myself, so that every relationship contains two distinct Users.
7. As a User, I want an unknown exact username reported without exposing unrelated accounts, so that lookup remains private and understandable.
8. As a requester, I want a successfully sent request listed as outgoing, so that I can see what is awaiting a response.
9. As a recipient, I want a received request listed as incoming, so that I can decide whether to accept it.
10. As a requester, I want repeating the same pending request to be idempotent, so that double submissions do not create duplicates.
11. As a User, I want at most one pending or accepted relationship with another User, so that relationship state cannot contradict itself.
12. As a recipient, I want to accept a pending Friend Request, so that the relationship becomes a mutual Friendship.
13. As a recipient, I want to decline a pending Friend Request, so that I can remove it without creating a Friendship.
14. As a requester, I want to cancel my pending Friend Request, so that I can withdraw it before acceptance.
15. As a User, I want sending a reverse request to automatically accept the existing incoming request, so that mutual intent produces one Friendship.
16. As a User, I want simultaneous crossed requests to resolve to one accepted Friendship, so that concurrency cannot create duplicate or stuck relationships.
17. As a User, I want an accepted Friendship to be mutual rather than directional, so that both Users have the same relationship status.
18. As a User, I want to remove a Friend, so that future private interaction requires a new accepted request.
19. As a User, I want Friend Request and Friendship changes synchronized across my open sessions, so that every tab reflects current state.
20. As a User, I want incoming Friend Requests in my Activity Feed, so that new relationship requests appear with other personally relevant activity.
21. As a requester, I want an Activity Item when my Friend Request is accepted, so that I know the relationship is available.
22. As a recipient, I do not want declining a request to notify the requester, so that declines remain quiet.
23. As a recipient, I want cancellation to remove the pending request Activity Item, so that dead requests do not remain actionable.
24. As a recipient, I want viewing a request Activity Item to mark the item read without resolving the request, so that attention and decision remain separate.
25. As a User, I want Friend relationship Activity delivered only to me, so that requests and acceptances never leak through Workspace topics.
26. As a User, I want a Direct Conversation only with an accepted Friend, so that Workspace membership alone cannot produce unsolicited Direct Messages.
27. As a User, I want Direct Conversations to exist outside Workspaces, so that roles, invites, bans, landing Channels, and Workspace deletion do not govern them.
28. As a User, I want a Direct Conversation created only when either Friend first chooses Message, so that unused Friendships do not create empty chat data automatically.
29. As a User, I want simultaneous first-message actions to find or create one Direct Conversation, so that one pair never receives duplicate timelines.
30. As a User, I want exactly one Direct Conversation with each Friend, so that restoring a Friendship returns to the established history.
31. As a User, I want Direct Conversations restricted to two Users, so that group communication remains a Workspace responsibility.
32. As a User who needs group conversation, I want to use a Workspace Channel, so that Direct Conversations do not grow participant-management rules.
33. As a User, I want ending a Friendship to preserve our Direct Conversation and Messages, so that relationship changes do not erase history.
34. As a former Friend, I want to continue reading the preserved Direct Conversation, so that previous communication remains available.
35. As a former Friend, I should not be able to send or reply, so that new communication requires restored mutual consent.
36. As a former Friend, I should not be able to add reactions or broadcast typing, so that read-only mode does not permit new interaction.
37. As a former Friend, I want to remove my own existing reactions, so that I can clean up content I previously added.
38. As a former Friend, I want to delete my own Direct Messages, so that ownership cleanup remains possible.
39. As a User, I want restoring a Friendship to re-enable the same Direct Conversation, so that no parallel history is created.
40. As a User with an open Direct Conversation, I want Friend removal to switch the screen to read-only immediately, so that the interface reflects current permission without refresh.
41. As a User with an open read-only Conversation, I want Friendship restoration to re-enable interaction immediately, so that I can continue in place.
42. As a User, I want an unsent draft preserved when the Conversation becomes read-only, so that a later restored Friendship does not discard my writing.
43. As a User, I want a clear read-only explanation and Send Friend Request action, so that I understand why interaction is disabled and how to restore it.
44. As a participant, I want to send durable Direct Messages, so that private communication survives reconnects and runtime restarts.
45. As a participant, I want Direct Messages ordered by Conversation-local sequence, so that pagination, replies, unread ranges, and live delivery share one ordering model.
46. As a participant, I want to reply to an earlier Direct Message, so that private responses retain context.
47. As a participant, I want replies to remain flat in the normal timeline, so that Direct Conversations do not create threads.
48. As a participant, I want reply targets restricted to the same Direct Conversation, so that private content cannot cross boundaries.
49. As a participant, I want to react to Direct Messages while we are Friends, so that private conversation has the same lightweight expression as Channels.
50. As a participant, I want reaction changes delivered live, so that both open sessions remain synchronized.
51. As a Direct Message author, I want to soft-delete my own Message for both participants, so that the timeline does not diverge by User.
52. As a recipient, I should not be able to delete the other User's Direct Message, so that authors retain control of their content.
53. As a participant, I want deleted Messages represented by placeholders, so that timeline and reply structure remain coherent.
54. As a participant, I want replies to deleted Messages to show a deleted-message preview, so that deleted content is not exposed.
55. As a participant, I do not want per-User Message hiding, so that both Users share one understandable timeline.
56. As a participant, I want long Direct Conversations paginated through bounded windows, so that history remains usable without unbounded rendering.
57. As a participant, I want recent Direct Messages recovered after runtime loss, so that ephemeral cache failure does not lose durable state.
58. As a current Friend, I want typing indicators in our Direct Conversation, so that private communication feels live.
59. As a participant, I want typing state to expire and remain ephemeral, so that stale typing never becomes durable data.
60. As a User, I do not want `@everyone` to create special behavior in a Direct Conversation, so that Workspace-wide policy cannot leak into private messaging.
61. As a User, I do not want Direct Message mentions to create duplicate mention Activity, so that the direct recipient receives one clear notification path.
62. As a recipient, I want each new Direct Message added to my unread state, so that unseen private communication is discoverable.
63. As a sender, I do not want my own Direct Message marked unread for me, so that unread state represents unseen incoming content.
64. As a recipient, I want each received Direct Message represented in the Activity Feed, so that direct attention appears beside mentions and Friend events.
65. As a recipient, I want a Direct Message to become read only after one continuous second of genuine visibility, so that opening a page does not clear unseen content.
66. As a recipient, I do not want a background or unfocused tab to mark Direct Messages read, so that visibility reflects actual attention.
67. As a recipient, I want the visibility timer cancelled when a Message leaves the viewport, so that brief scrolling does not clear it.
68. As a recipient, I want repeated visibility reports to be idempotent, so that client retries cannot corrupt unread state.
69. As a recipient, I want reading a Direct Message to clear its unread span and Activity Item together, so that notification surfaces do not drift.
70. As a recipient, I want read Direct Message Activity Items removed from the primary unread view, so that handled notifications clear promptly.
71. As a recipient, I want read Direct Message Activity retained in Activity history, so that previously handled events remain discoverable.
72. As a User, I want mention Activity read state to retain its existing independence from Channel Read State, so that this feature does not rewrite established mention semantics.
73. As a User, I want a Direct Messages icon above Workspace icons, so that private communication is a first-class global destination.
74. As a User, I want the icon labeled by an accessible Direct Messages tooltip, so that its meaning is clear without text permanently occupying the rail.
75. As a User, I want an aggregate Direct Message unread badge, so that pending private attention is visible from every authenticated surface.
76. As a User, I want Friends, Friend Requests, and Direct Conversations in one Direct Messages shell, so that private social workflows stay together.
77. As a User, I want incoming and outgoing requests clearly separated, so that actions and waiting states are unambiguous.
78. As a User, I want all created Direct Conversations listed, so that empty and historical Conversations remain reachable.
79. As a former Friend, I want our Conversation labeled read-only in the sidebar, so that its current state is visible before opening it.
80. As a User, I want Direct Conversations ordered by latest Message activity, so that active conversations rise to the top.
81. As a User, I want empty Direct Conversations ordered by creation time, so that newly opened conversations appear predictably.
82. As a User, I want a live Message to move its Conversation to the top, so that the sidebar updates without refresh.
83. As a User, I do not initially need pinning, hiding, closing, or manual ordering, so that the first version remains focused.
84. As a User, I want to see whether a current Friend is globally online or offline, so that presence works even without a shared Workspace.
85. As a User, I want multiple browser tabs to count as one online identity, so that closing one tab does not incorrectly show me offline.
86. As a User, I want Friend Presence visible only to accepted Friends, so that arbitrary Users cannot monitor my connection state.
87. As a former Friend, I want the other User's Friend Presence hidden immediately, so that ending the relationship also ends presence access.
88. As a User, I do not want online status persisted, so that reconnect and process recovery naturally determine current presence.
89. As a User, I want Message sends racing Friend removal to have one deterministic outcome, so that no Message bypasses current Friendship policy.
90. As a User, I want every stale or forged mutation re-authorized by the server, so that disabled controls are never the security boundary.
91. As a non-participant, I should receive not-found behavior for a Direct Conversation or Message, so that private existence is not disclosed.
92. As an authenticated User, I want Friends and Direct Message routes protected by the existing authenticated session boundary, so that `current_scope` governs every workflow.
93. As a Workspace Member, I want existing Channel behavior, moderation, mentions, unread state, and Activity preserved, so that the shared Conversation refactor does not regress Workspaces.
94. As a developer, I want Workspace Channels and Direct Conversations to share one Message engine, so that replies, reactions, pagination, runtime recovery, and unread behavior do not drift.
95. As a developer, I want container-specific authorization and recipient rules behind one policy boundary, so that shared mechanics do not weaken privacy.
96. As a developer, I want Friendships outside the generated Accounts context, so that identity and authentication remain separate from the social graph.
97. As a developer, I want Friend relationship locking exposed through its owning context, so that Chat does not query relationship schemas directly.
98. As a developer, I want one Conversation runtime process per active Conversation, so that Channels and Direct Conversations share cache and typing lifecycle.
99. As a developer, I want every Message, unread update, and Activity Item committed before broadcasts, so that live clients never observe uncommitted state.
100. As a developer, I want hard User deletion rejected until anonymization is deliberately designed, so that stable Direct Conversation identity and history remain valid.

## Implementation Decisions

- Add a dedicated Friendships context. Accounts continues to own User identity, authentication, credentials, tokens, and account notifications.
- Friendships owns Friend Request and Friendship lifecycle, exact-username resolution, pair canonicalization, listing, capability checks, private broadcasts, and lock-aware authorization.
- Represent pending Friend Requests and accepted Friendships in one `friend_relationships` table with a canonical ordered User pair, the requesting User, and a `pending` or `accepted` status.
- Enforce one row per unordered User pair, distinct pair members, a valid requester belonging to the pair, valid statuses, and foreign keys.
- Same-direction duplicate requests return the existing pending relationship. A reverse pending request atomically changes the existing row to accepted.
- Declining, cancelling, and removing a Friend delete the relationship row. Blocking is not represented as a relationship status.
- Allow exact global username targeting and Workspace member actions, but do not add fuzzy global search or a browsable User directory.
- Add a shared `conversations` base containing durable Conversation identity, kind, and the last allocated Message sequence.
- Model Workspace Channels and Direct Conversations as shared-primary-key subtype tables whose primary key is also the Conversation foreign key.
- Keep Workspace ID and Channel name on the Channel subtype, preserving unique Channel names per Workspace and existing landing-Channel semantics.
- Keep the canonical two-User pair on the Direct Conversation subtype. Use restrictive participant foreign keys and enforce one Direct Conversation per pair.
- Create the Conversation base and matching subtype atomically. Do not expose a public workflow that creates a bare Conversation.
- Create Direct Conversations lazily through a find-or-create Chat workflow after verifying accepted Friendship.
- Make concurrent Direct Conversation creation safe through the canonical pair uniqueness boundary and conflict recovery.
- Do not associate Direct Conversation identity with a Friend relationship foreign key; Friend relationship deletion must not delete history.
- Generalize Message ownership from Channel ID to Conversation ID. Preserve content validation, Message-local author identity, soft deletion, reply association, mention-recognition metadata, and durable timestamps.
- Allocate Message sequences by locking the Conversation row, incrementing its last sequence, and inserting the Message in the same transaction.
- Enforce positive Conversation-local sequence values and uniqueness by Conversation and sequence.
- Require reply targets to be non-deleted earlier Messages in the same Conversation. Replies remain flat and preserve deleted-parent placeholders.
- Reuse Message reactions for both Conversation kinds. Apply kind-specific capability checks before adding or removing reactions.
- Permit former Friends to remove their own existing reactions and soft-delete their own Messages, but reject all new content, replies, reactions, and typing.
- Direct Message deletion affects both participants and preserves a placeholder. Do not add per-participant Message visibility state.
- Generalize read-state and unread-span ownership from Channels to Conversations while retaining positive bounds, non-overlap, summary consistency, last-viewed anchors, and transaction locking.
- Remove the legacy cursor-based Channel read model from the target architecture because no production data requires compatibility preservation.
- Resolve Channel recipients through current Workspace membership. Resolve Direct Conversation recipients as exactly the other participant.
- Keep Workspace mention recognition, Everyone Mention role checks, moderation, audit behavior, and Workspace broadcasts limited to Workspace Channels.
- Direct Conversations do not recognize `@everyone`, create mention Activity, or apply Workspace moderation.
- Expand Activity Item kinds to include Direct Messages, received Friend Requests, and accepted Friend Requests alongside existing mention kinds.
- Support Message-backed and Friend relationship-backed Activity sources with kind-appropriate integrity constraints.
- Insert one Direct Message Activity Item for the recipient in the same transaction as Message persistence and unread fanout.
- Incoming Friend Requests create recipient Activity Items. Acceptance creates an Activity Item for the original requester. Declines are silent, and cancellation removes the pending received-request item.
- Keep Direct Message Activity synchronized with Conversation visibility. Keep existing mention Activity independent from Channel Read State.
- Define genuine visibility as one continuous second while the Message remains intersecting, the document is visible, and the window is focused.
- Use a LiveView hook to observe visible Message ranges, cancel incomplete timers, and send idempotent range events.
- In one server transaction, authorize the participant, lock Read State, subtract visible unread spans, update summaries, and mark matching Direct Message Activity Items read.
- Hide read Direct Message items from the primary unread Activity view while retaining them in Activity history.
- Generalize the Channel runtime to a Conversation runtime keyed by Conversation ID. It owns recent-message cache and transient typing only.
- Retain the existing runtime idle-shutdown and PostgreSQL recovery behavior for both Conversation kinds.
- Keep authorization outside the runtime process. Chat and Friendships authorize every subscription and mutation before calling runtime functions.
- Use private per-User PubSub topics for Activity, Friend relationship changes, and Friend Presence. Use Conversation topics for authorized Message, reaction, typing, and read-state updates.
- Broadcast only after successful database commit. Broadcast compact identifiers or change facts and have LiveViews reload authorized state.
- Serialize Direct Message sends against Friend removal by locking the accepted relationship before the Conversation and recipient Read State.
- A send that obtains the relationship lock first may commit before removal; removal that obtains it first causes the send to fail as no longer Friends.
- Maintain the global lock order Friend relationship, Conversation, then Read State to prevent deadlocks.
- Add a Presence boundary with a dynamically supervised per-User presence process and unique Registry identity.
- Treat a User as globally online while at least one authenticated LiveView PID remains monitored. Broadcast only transitions between zero and nonzero connections.
- Stop the per-User process after the final connection exits. Do not persist presence or add richer statuses.
- Authorize Friend Presence subscriptions through accepted Friendship. Remove or ignore subscriptions immediately after unfriend.
- Add a persistent global destination rail shared by Workspace and Direct Messages surfaces.
- Place the Direct Messages destination above Workspace icons with tooltip, unread badge, and stable accessible identity.
- Add authenticated Direct Messages routes for the Friends home, request management, and a selected Direct Conversation inside the existing authenticated router scope and existing authenticated LiveSession.
- Pass `current_scope` through every LiveView and public context workflow. Do not introduce `current_user` assigns.
- The Direct Messages sidebar contains Friends navigation, request counts, and all created Direct Conversations, including empty and former-Friend read-only entries.
- Sort Direct Conversations by latest Message time with Conversation creation time as the empty fallback and a durable ID tie-breaker.
- Update and move sidebar entries through LiveView streams when Messages, unread state, or Friend relationship state changes.
- An open Conversation remains visible after unfriend, recomputes capabilities, stops typing, disables new interaction, hides Friend Presence, and preserves the draft without redirecting.
- Restoring Friendship re-enables the existing open Conversation and Presence subscription.
- Hard User deletion is not supported. Restrict deletion through Direct Conversation participant foreign keys and leave future deactivation or anonymization to a separate design.
- Existing Message author foreign keys may continue to nilify on deletion so historical rendering can use a deleted-User placeholder where deletion is otherwise valid.
- Generate migrations through the repository's migration task. Because no application data must be preserved, do not add dual-read, dual-write, or compatibility-backfill phases.
- Use Tailwind-based components, existing icon helpers, subtle transitions, accessible tooltips, clear loading states, stable DOM IDs, and the established application layout.

## Testing Decisions

- The approved primary testing seam is observable behavior through public context APIs. Friendships, Chat, Workspaces, Accounts, and Presence behavior should be exercised through their public contracts rather than direct schema manipulation or private helpers.
- LiveView tests are the secondary integration seam and should cover only user-visible outcomes and cross-boundary wiring: authenticated navigation, forms, streams, capability changes, badges, Activity synchronization, presence rendering, and multi-session live updates.
- Targeted OTP tests are appropriate only for lifecycle behavior that cannot be proven reliably through public APIs, such as process monitoring, multiple connection ownership, edge-triggered presence broadcasts, idle shutdown, and recovery.
- Good tests assert outcomes, authorization, durable state, and public return contracts. They should not assert internal query shape, private function calls, process state layout, or exact implementation sequencing unless that sequencing is itself the external concurrency contract.
- Add Friendships context tests for exact-username requests, self-target rejection, missing Users, canonical pairs, same-direction idempotency, crossed-request acceptance, and uniqueness under concurrency.
- Add Friendships context tests for incoming/outgoing lists, accept, decline, cancellation, removal, restoration, private broadcasts, and unauthenticated behavior.
- Add Friendships tests proving Workspace membership is neither required for exact-username requests nor sufficient for Direct Message permission without Friendship.
- Add Chat context tests for lazy Direct Conversation find-or-create, one Conversation per pair, participant-only reads, non-participant not-found behavior, and restoration reuse.
- Add Chat tests for Direct Message send, Conversation sequencing, replies, reactions, soft deletion, placeholders, pagination, and runtime recovery through shared public workflows.
- Add policy tests proving current Friends can send, reply, react, and type; former Friends can read and perform only ownership cleanup; and non-participants can do nothing.
- Add concurrency tests proving send-versus-unfriend outcomes are linearized and that simultaneous Direct Conversation creation cannot duplicate a pair.
- Concurrency tests should synchronize through messages, monitors, public calls, and process state barriers rather than sleeps.
- Add Chat unread tests proving only the recipient receives unread spans, the sender does not, summaries remain consistent, and retries are idempotent.
- Add Chat Activity tests proving Direct Message, received-request, and accepted-request items have correct recipients, actors, sources, privacy, uniqueness, and lifecycle cleanup.
- Add visibility workflow tests proving read-span subtraction and Direct Message Activity updates commit together and repeated visible ranges are harmless.
- Add client-hook tests for the continuous one-second threshold, viewport exit cancellation, background document rejection, focus loss, and grouped visible-range events.
- Add runtime tests proving Conversation processes isolate state by Conversation ID, cache both kinds, recover persisted Messages, expire typing, and stop after idle timeout.
- Add Presence public API tests for authentication, Friendship authorization, initial status, multiple connections, final disconnect, private events, and unfriend access removal.
- Add targeted UserPresenceServer tests using supervised processes and monitors to prove connection lifecycle without leaking processes between tests.
- Add router and LiveView tests proving every Direct Messages route requires authentication and receives `current_scope` through the existing authenticated LiveSession.
- Add Friends home LiveView tests for exact-username submission, validation outcomes, incoming/outgoing streams, accept, decline, cancel, and crossed-request UI refresh.
- Add Direct Messages shell tests for icon tooltip, aggregate unread badge, request badge, Conversation list ordering, empty entries, read-only labels, and stable DOM IDs.
- Add Direct Conversation LiveView tests for initial render, sending, replies, reactions, deletion, typing, bounded windows, and live multi-session delivery.
- Add multi-session tests proving unfriend switches an open Conversation to read-only without redirecting, stops typing, hides Presence, rejects stale mutations, and restoration re-enables the same view.
- Add Activity LiveView tests proving Direct Messages and Friend events render in the primary unread view, navigate correctly, clear according to their rules, remain in history when required, and synchronize bell counts across sessions.
- Add regression tests proving Workspace Channel membership, moderation, mentions, Everyone Mention authorization, audit events, unread behavior, Activity cleanup, default Channels, and routing remain unchanged after Conversation generalization.
- Add database-facing invariant tests only where the invariant cannot be demonstrated safely through a public workflow, including canonical pair checks, shared-primary-key subtype integrity, unique Conversation sequences, and restrictive User deletion.
- LiveView tests should use `element/2`, `has_element?/2`, form/event helpers, and stable selectors rather than raw HTML string assertions.
- Streamed collections must be asserted through their stable item IDs and observable ordering or presence, not internal stream assigns.
- Prior art exists in existing Chat context tests for Message authorization, transactions, runtime recovery, reactions, replies, Activity, unread spans, and PubSub behavior.
- Prior art exists in Workspaces context tests for scoped access, Channel lifecycle, role policy, moderation transactions, and cleanup.
- Prior art exists in Activity and Activity synchronization LiveView tests for recipient-private events, unread bell counts, navigation, and multiple sessions.
- Prior art exists in Channel and Workspace LiveView tests for authenticated shells, stable DOM IDs, message streams, bounded windows, typing, reactions, scroll behavior, access changes, and unread badges.
- Prior art exists in the current JavaScript test harness for pointer/focus/timer-oriented hooks and UI interactions.
- Run focused Friendships, Chat, Presence, Activity, and Direct Message LiveView tests during implementation, then run the full required precommit alias and fix every failure.

## Out of Scope

- Group Direct Conversations, participant invitations, participant removal, group ownership, and group history rules.
- Blocking, reporting, abuse review, Friend Request cooldowns, and request rate limiting.
- Fuzzy username search, global User browsing, friend suggestions, contact import, email discovery, and mutual-Friend recommendations.
- Idle, do-not-disturb, invisible, custom Friend Presence, last-seen history, and persisted presence.
- Voice calls, video calls, screen sharing, file uploads, rich embeds, and Direct Message-specific rate limiting.
- Direct Message `@everyone`, Direct Message mention Activity, role mentions, Channel mentions, and Workspace moderation of Direct Conversations.
- Per-User Message hiding, “delete for me,” recipient deletion of another User's Message, and different timelines per participant.
- Pinning, hiding, closing, archiving, folders, favorites, or manual ordering for Direct Conversations.
- A synthetic Direct Messages Workspace or Workspace Membership-based Direct Message authorization.
- Hard User deletion. Account deactivation, anonymization, restoration, and legal retention behavior require a separate design.
- Production-data compatibility, online backfill, dual-read, dual-write, and zero-downtime migration phases.
- Replacing or redesigning the existing Workspace presence system.
- Splitting this specification into implementation issues; that can be done by the issue-breakdown workflow after approval.

## Further Notes

- The accepted domain glossary and ADRs are authoritative if a later implementation detail appears ambiguous.
- The complete ER and architecture design exists as a companion design artifact in the repository documentation.
- This specification deliberately prefers one shared Conversation engine with separate policy over duplicated Channel and Direct Message stacks.
- The current database contains no application data that must survive the Conversation ownership refactor, but migrations must still be generated using repository conventions.
- The authenticated routes belong in the existing `:require_authenticated_user` pipeline and existing `live_session :require_authenticated_user` because Friends, Friend Requests, Presence, and Direct Conversations all require `current_scope`.
- This is a large vertical feature and should be decomposed into independently grabbable tracer-bullet issues before implementation.
