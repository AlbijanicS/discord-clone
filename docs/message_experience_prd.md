# Message Experience: Timeline Polish, Emoji Parsing, And Reactions PRD

Status: ready-for-agent

This PRD comes from a `grill-me` design session for the next Phase 10 feature
after unread counts. The project is using a docs-first fallback for now, so
this document is the ready-for-agent product artifact rather than a published
external tracker item.

## Problem Statement

The Discord clone now has durable Workspaces, Channels, persisted messages,
live message delivery, unread counts, workspace-scoped presence, typing
indicators, and explicit Channel runtime recovery. A Workspace Member can
participate in conversation, but the message timeline still feels visually
rough. Individual messages appear as detached rows, short back-and-forth
conversation is harder to scan than it should be, and the interface does not
yet support lightweight social feedback through reactions.

The next phase should make the Channel conversation feel closer to a real team
messenger without turning the project into a full Slack or Discord clone. The
goal is not pixel-perfect product mimicry. The goal is a cleaner, calmer
message surface that can support simple emoji parsing and durable reactions
without violating the project's current boundaries.

## Solution

Improve the message experience as one coherent vertical phase:

- Reshape the Channel timeline into a more anchored, Slack-like layout.
- Group consecutive messages from the same author with a simple rendering rule.
- Parse a small, safe subset of emoji shortcodes in message content.
- Add durable message reactions backed by Postgres.
- Render reaction summaries under messages and let Workspace Members toggle
  their own reactions.
- Broadcast reaction changes through Chat-owned PubSub contracts so connected
  Channel viewers refresh reaction summaries without a page reload.

Message text, reaction state, and reaction counts should remain recoverable
from Postgres. ChannelServer should continue to own temporary Channel state such
as recent-message cache and typing indicators; it should not become the source
of truth for reactions.

No new route or router scope is required. This work belongs in the existing
authenticated Channel LiveView flow because Channel reading, message sending,
and reactions all depend on `current_scope` and Workspace membership.

## User Stories

1. As a Workspace Member, I want messages to align in a stable timeline, so that conversation is easier to scan.
2. As a Workspace Member, I want each full message group to show the author's avatar, name, and timestamp, so that I can understand who spoke and when.
3. As a Workspace Member, I want consecutive messages from the same author to group visually, so that rapid chat does not repeat unnecessary chrome.
4. As a Workspace Member, I want grouped follow-up messages to align with the parent message body, so that the conversation column feels anchored.
5. As a Workspace Member, I want grouping to use a simple time window, so that messages separated by enough time still show fresh author context.
6. As a Workspace Member, I want messages from different authors to always start a new visual group, so that speaker changes are obvious.
7. As a Workspace Member, I want the selected Channel timeline to keep its current live behavior, so that new messages still appear without refresh.
8. As a Workspace Member, I want loading older messages to preserve sensible grouping at the page boundary, so that older history does not look broken.
9. As a Workspace Member, I want the empty Channel state to remain clear, so that a quiet Channel is not confused with a failed timeline.
10. As a Workspace Member, I want message hover states to reveal useful affordances without cluttering the default view, so that the timeline stays calm.
11. As a Workspace Member, I want message text to preserve line breaks, so that multi-line messages still read correctly.
12. As a Workspace Member, I want long words and emoji-heavy messages to wrap safely, so that content does not break the layout.
13. As a Workspace Member, I want the composer spacing to visually belong to the timeline, so that the bottom of the screen feels intentional.
14. As a Workspace Member, I want common emoji shortcodes such as `:thumbsup:` and `:heart:` to render as emoji, so that chat feels more natural.
15. As a Workspace Member, I want unknown shortcodes to remain plain text, so that accidental or unsupported input is not destructive.
16. As a Workspace Member, I want shortcode parsing to be safe, so that message rendering does not introduce raw HTML risks.
17. As a Workspace Member, I want Unicode emoji typed directly into the composer to remain visible, so that normal emoji keyboard input works.
18. As a Workspace Member, I want a small reaction palette on messages, so that I can respond quickly without typing a new message.
19. As a Workspace Member, I want clicking a reaction to add my reaction, so that I can acknowledge or respond to a message.
20. As a Workspace Member, I want clicking my existing reaction to remove it, so that reaction toggling feels natural.
21. As a Workspace Member, I want each reaction pill to show the emoji and count, so that I can see how others responded.
22. As a Workspace Member, I want my own reactions to have a distinct visual state, so that I know what I have already selected.
23. As a Workspace Member, I want multiple users to be able to use the same reaction, so that counts reflect shared sentiment.
24. As a Workspace Member, I want one user to react once per emoji per message, so that counts cannot be inflated by repeated clicks.
25. As a Workspace Member, I want reaction counts to update live, so that other members' reactions appear without refresh.
26. As a Workspace Member, I want reactions to survive Channel runtime crashes, so that social state is not lost with temporary process state.
27. As a Workspace Member, I want reactions to survive page refreshes, so that the message history remains consistent.
28. As a Workspace Member, I want reaction state to be scoped to Workspace membership, so that non-members cannot react to private Workspace messages.
29. As a Workspace Member, I want reaction state to be scoped to the current User, so that another member's reaction does not make the UI think I reacted.
30. As a Workspace Member, I want invalid reaction payloads rejected, so that clients cannot store blank, oversized, or malformed reaction values.
31. As a logged-in non-member, I should not be able to add reactions to Workspace messages, so that membership remains the access boundary.
32. As an anonymous visitor, I should not be able to add reactions, so that reactions always attach to an authenticated User.
33. As a developer, I want message grouping to stay in the web/rendering layer, so that Chat continues returning durable messages rather than presentation annotations.
34. As a developer, I want emoji normalization in a small Chat-owned module, so that validation and parsing can be tested without LiveView.
35. As a developer, I want reactions behind public Chat APIs, so that LiveViews do not call Repo or assemble authorization queries directly.
36. As a developer, I want reaction summaries loaded for bounded message lists, so that the timeline avoids one query per message.
37. As a developer, I want reaction PubSub payloads to be small, so that subscribers refresh authorized summaries instead of trusting full broadcast state.
38. As a developer, I want reaction rows to be durable Postgres state, so that ChannelServer remains focused on temporary state.
39. As a developer, I want reaction behavior documented as Phase 10 product state, so that future features do not accidentally place it in GenServer memory.
40. As a future maintainer, I want custom emoji, full markdown, and rich composer behavior explicitly out of scope, so that this phase stays reviewable.

## Implementation Decisions

- Build this as the next Phase 10 message-experience feature after unread counts.
- Treat the phase goal as improving the Channel chat experience, not only adding a reaction table.
- Keep the first implementation small and reviewable even though the user-facing theme spans layout, emoji, and reactions.
- Do not add new routes.
- Keep the Channel LiveView inside the existing authenticated browser pipeline and authenticated LiveView session because the screen depends on `current_scope`.
- Continue to pass `current_scope` into the app layout and Chat context workflows.
- Keep LiveViews calling public `DiscordClone.Chat` APIs.
- Do not call Repo, Registry, DynamicSupervisor, or ChannelServer internals directly from LiveViews for this feature.
- Improve the message row layout before adding reaction affordances.
- Use a stable avatar column and stable message-content column.
- Render a full message row when the previous visible message is absent, has a different author, or falls outside the grouping window.
- Render a compact continuation row when the previous visible message has the same author and is within the grouping window.
- Use a simple grouping window for v1. The recommended value is five minutes.
- Keep grouping as a rendering concern in the web layer, not a Chat context concern.
- Introduce a small web-side view model or helper if needed so grouping logic can be tested separately from the full LiveView.
- Preserve LiveView streams for the message collection unless implementation proves that grouping cannot be kept correct at stream boundaries.
- When older messages are prepended, re-evaluate grouping for affected boundary messages.
- When new messages are inserted, re-evaluate grouping for the new message and the immediately adjacent existing message if needed.
- Keep date separators out of the first pass unless they are trivial after grouping is stable.
- Keep hover action chrome subtle and secondary to timeline readability.
- Do not implement threads, message actions menus, editing, deletion, or attachments in this PRD.
- Add a small `DiscordClone.Chat.Emoji` module.
- `DiscordClone.Chat.Emoji` should expose a simple interface for normalization, validation, and shortcode parsing.
- Treat the emoji module as a deep module: a small public API hides Unicode/string details and can be tested in isolation.
- For reaction validation, accept exactly one normalized grapheme after trimming, with blank and oversized payloads rejected.
- The UI should expose only a fixed reaction palette in v1.
- The fixed palette should be small and familiar, such as thumbs up, heart, laugh, party, and eyes.
- The backend should not be hard-coded only to the fixed UI palette; accepting one normalized grapheme keeps the data model flexible.
- Do not add a full Unicode emoji database in v1.
- Do not add custom Workspace emoji in v1.
- Add a tiny shortcode parser for message content.
- The shortcode parser should support only an explicit allowlist in v1.
- Unknown shortcodes should remain unchanged.
- Shortcode parsing should produce safe text output for HEEx rendering.
- Message content should continue to be stored as the User typed it; parsed emoji are a rendering concern for v1.
- Add a durable `message_reactions` table.
- Store `message_id`, `user_id`, `emoji`, and UTC timestamps.
- Enforce one row per `message_id`, `user_id`, and `emoji`.
- Add indexes that support reaction lookup by message and cleanup by user.
- Message deletion should delete related reaction rows.
- User deletion should delete related reaction rows.
- Add a Chat-owned MessageReaction schema module.
- Reaction rows are durable product state and belong in Postgres.
- Do not store reaction counts only; derive counts from reaction rows.
- Do not store reaction state in ChannelServer.
- Add public Chat API `toggle_reaction(scope, message_id, emoji)`.
- `toggle_reaction/3` should validate that the current User is a Workspace Member for the message's Channel.
- `toggle_reaction/3` should normalize and validate the emoji before insert or delete.
- `toggle_reaction/3` should add a missing reaction and remove an existing reaction for the same User, message, and emoji.
- `toggle_reaction/3` should not trust client-supplied user IDs, Channel IDs, or Workspace IDs.
- Add public Chat API for listing reaction summaries for bounded message lists.
- Reaction summaries should include counts and whether the current User reacted for each emoji.
- Reaction summaries should be keyed by message ID for efficient rendering.
- Load reaction summaries for the initially loaded recent messages.
- Load or refresh reaction summaries for older messages when older history is prepended.
- Refresh reaction summaries for an affected message after the current User toggles a reaction.
- Broadcast reaction changes after durable mutation succeeds.
- Keep reaction PubSub topic construction private to Chat.
- Reuse the Channel message topic only if the event names remain clear and Chat owns the contract.
- Reaction broadcast payloads should be small, such as message ID and emoji.
- Connected Channel LiveViews that receive reaction events should refresh authorized summaries through Chat.
- Do not broadcast full Message, User, or reaction-row records for reaction changes.
- Render reaction pills under the message body.
- Reaction buttons should have stable DOM IDs for tests.
- Reaction buttons should use accessible labels that identify the emoji and whether the current User has reacted.
- Use Tailwind classes and existing `<.icon>` component where icons are needed.
- Do not introduce external scripts, external stylesheets, daisyUI-specific dependencies, or inline script tags.
- Keep the visual direction Slack-like but not Slack-perfect.

## Testing Decisions

- Good tests should prove behavior through public context APIs, LiveView interactions, and visible outcomes.
- Avoid tests that depend on private helper names, exact query structure, or fragile raw HTML.
- Add isolated tests for `DiscordClone.Chat.Emoji`.
- Emoji tests should cover trimming, blank rejection, oversized rejection, one-grapheme validation, direct Unicode emoji, supported shortcode parsing, and unknown shortcode passthrough.
- Add Chat context tests for `toggle_reaction/3`.
- Reaction toggle tests should prove a Workspace Member can add a reaction.
- Reaction toggle tests should prove clicking the same emoji again removes the reaction.
- Reaction toggle tests should prove duplicate reaction rows are not created.
- Reaction toggle tests should prove different Users can react with the same emoji and increase the count.
- Reaction toggle tests should prove one User can react with different emoji to the same message.
- Reaction toggle tests should prove non-members cannot react to private Workspace messages.
- Reaction toggle tests should prove anonymous scopes are rejected.
- Reaction toggle tests should prove invalid emoji payloads are rejected before durable mutation.
- Add Chat context tests for reaction summaries.
- Summary tests should prove counts are grouped by message and emoji.
- Summary tests should prove the current User's reacted state is viewer-specific.
- Summary tests should prove bounded message-list loading does not require one query per message where practical.
- Add persistence tests showing reactions survive Channel runtime loss because they are Postgres-backed.
- Add LiveView tests for timeline structure using stable element IDs and selectors.
- Timeline tests should verify full message rows and compact continuation rows exist under the intended same-author grouping scenario.
- Timeline tests should avoid asserting raw HTML strings.
- Add LiveView tests for supported shortcode rendering where selectors can verify rendered content safely.
- Add LiveView tests for reaction buttons and reaction pills.
- LiveView reaction tests should use `element/2`, `has_element?/2`, and click helpers.
- LiveView tests should verify the current User can toggle a visible reaction.
- LiveView tests should verify reaction counts update after toggling.
- LiveView tests should verify another connected viewer can observe refreshed reaction state without a page reload if the existing test harness supports multi-view PubSub scenarios.
- Prior art for context tests exists in the Chat and Workspaces test suites.
- Prior art for LiveView selectors exists in the Workspace and Channel LiveView tests.
- Run focused tests first, then `mix precommit` after implementation changes.

## Out of Scope

- Full Slack visual parity.
- Full Discord visual parity.
- Custom Workspace emoji.
- Full Unicode emoji property parsing.
- Emoji picker search.
- Emoji skin tone picker.
- Uploading emoji assets.
- Markdown parsing.
- Rich text composer behavior.
- Message editing.
- Message deletion.
- Threads.
- Attachments.
- Embeds.
- Mentions.
- Direct messages.
- Notification badges for reactions.
- Persisting parsed message-content tokens.
- Storing reaction counts as a separate counter table.
- Storing reaction state in ChannelServer.
- Changing authentication routes or router scopes.

## Further Notes

- Recommended implementation order:
  1. Stabilize the message timeline layout and grouping behavior.
  2. Add the small emoji normalization and shortcode parsing module.
  3. Add durable message reactions and Chat context APIs.
  4. Render reaction summaries and palette controls.
  5. Add live reaction refresh through Chat-owned PubSub events.
- The most important design decision from the grill session is that this phase
  is a message-experience phase. Reactions and emoji are included because they
  belong to that experience, but the visual message row should be improved
  before adding new hover controls and reaction pills.
- The durable-versus-temporary state rule remains unchanged:

```text
Important forever?
  -> Postgres

Useful right now?
  -> GenServer/process state
```

- Reactions are important product state and therefore belong in Postgres.
- Message grouping and parsed emoji presentation are rendering concerns unless
  future features require persisted message-token metadata.
