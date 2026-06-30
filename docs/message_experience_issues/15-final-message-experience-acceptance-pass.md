# Final Message Experience Acceptance Pass

**Type:** AFK

**Blocked by:** 7. Render Supported Emoji Shortcodes In Message Content, 13. Broadcast Reaction Changes To Connected Channel Viewers, 14. Prove Reaction Persistence And Runtime Recovery

**User stories covered:** 1-40

## What to build

Close the message-experience phase by checking the whole flow together:
timeline layout, grouping, emoji shortcode rendering, reaction display,
reaction toggling, live reaction refresh, authorization, accessibility labels,
and runtime durability. This slice should fill gaps discovered after the
vertical slices land and ensure the feature set is ready for the next Phase 10
work.

This should not expand scope into custom emoji, markdown, threads, attachments,
mentions, or direct messages.

## Acceptance criteria

- [x] Full message rows, compact grouped rows, empty state, older-message
      loading, live inserts, and composer spacing still work together.
- [x] Supported emoji shortcodes render safely in message content.
- [x] Unknown shortcodes remain unchanged.
- [x] Reaction pills render counts and current-User reacted state.
- [x] Fixed palette controls can add and remove reactions.
- [x] Other connected Channel viewers can observe reaction count changes
      without refresh where practical.
- [x] Non-members and anonymous scopes cannot react to private Workspace
      messages.
- [x] Invalid emoji payloads are rejected.
- [x] Reaction summaries survive refresh and Channel runtime loss.
- [x] Reaction controls and summaries include accessible labels.
- [x] No route or router-scope changes were introduced.
- [x] The web layer still uses public Chat APIs rather than Repo or runtime
      internals.
- [x] Focused tests and `mix precommit` pass.

## Blocked by

- 7. Render Supported Emoji Shortcodes In Message Content
- 13. Broadcast Reaction Changes To Connected Channel Viewers
- 14. Prove Reaction Persistence And Runtime Recovery
