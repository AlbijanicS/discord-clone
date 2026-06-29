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

- [ ] Full message rows, compact grouped rows, empty state, older-message
      loading, live inserts, and composer spacing still work together.
- [ ] Supported emoji shortcodes render safely in message content.
- [ ] Unknown shortcodes remain unchanged.
- [ ] Reaction pills render counts and current-User reacted state.
- [ ] Fixed palette controls can add and remove reactions.
- [ ] Other connected Channel viewers can observe reaction count changes
      without refresh where practical.
- [ ] Non-members and anonymous scopes cannot react to private Workspace
      messages.
- [ ] Invalid emoji payloads are rejected.
- [ ] Reaction summaries survive refresh and Channel runtime loss.
- [ ] Reaction controls and summaries include accessible labels.
- [ ] No route or router-scope changes were introduced.
- [ ] The web layer still uses public Chat APIs rather than Repo or runtime
      internals.
- [ ] Focused tests and `mix precommit` pass.

## Blocked by

- 7. Render Supported Emoji Shortcodes In Message Content
- 13. Broadcast Reaction Changes To Connected Channel Viewers
- 14. Prove Reaction Persistence And Runtime Recovery
