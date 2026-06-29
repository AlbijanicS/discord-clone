# Message Experience Issues

This folder breaks `docs/message_experience_prd.md` into small,
independently grabbable tracer-bullet issues. The project is using a
docs-first fallback for now, so these are not published to GitHub Issues.

The route placement for this phase is intentionally unchanged: Channel
LiveViews stay in the existing authenticated browser pipeline and existing
`live_session :require_authenticated_user`, because message reading, message
grouping, emoji rendering, and reactions require `current_scope`, an
authenticated User, and Workspace membership. No new routes or router scopes
are needed.

## Proposed Breakdown

1. **Stabilize The Channel Message Row Layout**
   - **Type:** AFK
   - **Blocked by:** None - can start immediately
   - **User stories covered:** 1-2, 7, 9, 11-12, 33
   - **Issue:** `01-stabilize-channel-message-row-layout.md`
2. **Add Simple Same-Author Message Grouping**
   - **Type:** AFK
   - **Blocked by:** 1. Stabilize The Channel Message Row Layout
   - **User stories covered:** 3-6, 33
   - **Issue:** `02-add-simple-same-author-message-grouping.md`
3. **Preserve Grouping Across Live Inserts And Older History**
   - **Type:** AFK
   - **Blocked by:** 2. Add Simple Same-Author Message Grouping
   - **User stories covered:** 7-8, 33
   - **Issue:** `03-preserve-grouping-across-live-inserts-and-older-history.md`
4. **Polish Message Hover And Composer Spacing**
   - **Type:** AFK
   - **Blocked by:** 1. Stabilize The Channel Message Row Layout
   - **User stories covered:** 10, 13
   - **Issue:** `04-polish-message-hover-and-composer-spacing.md`
5. **Review Timeline Feel Before Adding Reactions**
   - **Type:** HITL
   - **Blocked by:** 1. Stabilize The Channel Message Row Layout, 2. Add Simple Same-Author Message Grouping, 3. Preserve Grouping Across Live Inserts And Older History, 4. Polish Message Hover And Composer Spacing
   - **User stories covered:** 1-4, 10, 13
   - **Issue:** `05-review-timeline-feel-before-adding-reactions.md`
6. **Add Minimal Emoji Normalization And Validation**
   - **Type:** AFK
   - **Blocked by:** None - can start immediately
   - **User stories covered:** 17, 30, 34
   - **Issue:** `06-add-minimal-emoji-normalization-and-validation.md`
7. **Render Supported Emoji Shortcodes In Message Content**
   - **Type:** AFK
   - **Blocked by:** 6. Add Minimal Emoji Normalization And Validation
   - **User stories covered:** 14-17, 34
   - **Issue:** `07-render-supported-emoji-shortcodes-in-message-content.md`
8. **Add Durable Message Reaction Toggle**
   - **Type:** AFK
   - **Blocked by:** 6. Add Minimal Emoji Normalization And Validation
   - **User stories covered:** 19-20, 23-24, 26-28, 30-32, 35, 38
   - **Issue:** `08-add-durable-message-reaction-toggle.md`
9. **Load Reaction Summaries For Rendered Messages**
   - **Type:** AFK
   - **Blocked by:** 8. Add Durable Message Reaction Toggle
   - **User stories covered:** 21-22, 29, 36
   - **Issue:** `09-load-reaction-summaries-for-rendered-messages.md`
10. **Render Reaction Pills Under Messages**
    - **Type:** AFK
    - **Blocked by:** 5. Review Timeline Feel Before Adding Reactions, 9. Load Reaction Summaries For Rendered Messages
    - **User stories covered:** 18, 21-22, 29
    - **Issue:** `10-render-reaction-pills-under-messages.md`
11. **Add Fixed Reaction Palette Controls**
    - **Type:** AFK
    - **Blocked by:** 10. Render Reaction Pills Under Messages
    - **User stories covered:** 18-20, 22, 30
    - **Issue:** `11-add-fixed-reaction-palette-controls.md`
12. **Refresh Reaction Summaries After Local Toggle**
    - **Type:** AFK
    - **Blocked by:** 11. Add Fixed Reaction Palette Controls
    - **User stories covered:** 19-22, 24, 29
    - **Issue:** `12-refresh-reaction-summaries-after-local-toggle.md`
13. **Broadcast Reaction Changes To Connected Channel Viewers**
    - **Type:** AFK
    - **Blocked by:** 12. Refresh Reaction Summaries After Local Toggle
    - **User stories covered:** 25, 37
    - **Issue:** `13-broadcast-reaction-changes-to-connected-channel-viewers.md`
14. **Prove Reaction Persistence And Runtime Recovery**
    - **Type:** AFK
    - **Blocked by:** 8. Add Durable Message Reaction Toggle, 9. Load Reaction Summaries For Rendered Messages
    - **User stories covered:** 26-27, 38-39
    - **Issue:** `14-prove-reaction-persistence-and-runtime-recovery.md`
15. **Final Message Experience Acceptance Pass**
    - **Type:** AFK
    - **Blocked by:** 7. Render Supported Emoji Shortcodes In Message Content, 13. Broadcast Reaction Changes To Connected Channel Viewers, 14. Prove Reaction Persistence And Runtime Recovery
    - **User stories covered:** 1-40
    - **Issue:** `15-final-message-experience-acceptance-pass.md`

## Notes For Implementers

- Keep the Channel LiveView inside the existing authenticated browser scope and
  existing `live_session :require_authenticated_user`. This keeps
  `current_scope` available and matches the existing private Workspace access
  rules.
- LiveViews should call `DiscordClone.Chat` for message, emoji, reaction, and
  PubSub workflows.
- LiveViews should not call Repo, ChannelServer, registries, supervisors, or
  Phoenix PubSub directly for this feature.
- Message grouping and parsed emoji presentation are rendering concerns unless
  future features require persisted message-token metadata.
- Reactions are durable product state and belong in Postgres, not ChannelServer.
- Prefer focused tests first, then `mix precommit` after implementation
  changes.
