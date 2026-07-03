# Unread Ranges Issues

This folder breaks `docs/unread_ranges_prd.md` into small, independently
grabbable tracer-bullet issues. The project is using a docs-first fallback for
now, so these are not published to GitHub Issues.

The route placement for this phase is intentionally unchanged: Channel
LiveViews stay in the existing authenticated browser pipeline and existing
`live_session :require_authenticated_user`, because unread ranges require
`current_scope`, an authenticated User, and Workspace membership. No new routes
or router scopes are needed.

## Proposed Breakdown

1. **Add Channel-Local Message Sequencing**
   - **Type:** AFK
   - **Blocked by:** None - can start immediately
   - **User stories covered:** 24, 29, 36, 38, 44-46
   - **Issue:** `01-add-channel-local-message-sequencing.md`
2. **Create Unread Span And Read-State Storage**
   - **Type:** AFK
   - **Blocked by:** 1. Add Channel-Local Message Sequencing
   - **User stories covered:** 2-3, 24, 36-38, 42-43, 46
   - **Issue:** `02-create-unread-span-and-read-state-storage.md`
3. **Backfill Range State From Cursor Reads**
   - **Type:** AFK
   - **Blocked by:** 1. Add Channel-Local Message Sequencing, 2. Create Unread Span And Read-State Storage
   - **User stories covered:** 1-3, 10-11, 24, 36, 46
   - **Issue:** `03-backfill-range-state-from-cursor-reads.md`
4. **Implement Span Merge And Subtract Workflows**
   - **Type:** AFK
   - **Blocked by:** 2. Create Unread Span And Read-State Storage
   - **User stories covered:** 2-3, 12, 16, 24, 42-43, 46
   - **Issue:** `04-implement-span-merge-and-subtract-workflows.md`
5. **Create Message Send Unread Fanout**
   - **Type:** AFK
   - **Blocked by:** 1. Add Channel-Local Message Sequencing, 4. Implement Span Merge And Subtract Workflows
   - **User stories covered:** 10-11, 15-16, 24, 36-41, 46
   - **Issue:** `05-create-message-send-unread-fanout.md`
6. **Initialize And Clean Up Range State From Workspace Workflows**
   - **Type:** AFK
   - **Blocked by:** 2. Create Unread Span And Read-State Storage
   - **User stories covered:** 33-35, 39, 46
   - **Issue:** `06-initialize-and-clean-up-range-state-from-workspace-workflows.md`
7. **Expose Read-State Summaries And Private PubSub**
   - **Type:** AFK
   - **Blocked by:** 4. Implement Span Merge And Subtract Workflows, 5. Create Message Send Unread Fanout
   - **User stories covered:** 2, 22-24, 37-38, 43, 46
   - **Issue:** `07-expose-read-state-summaries-and-private-pubsub.md`
8. **Add Channel Open Landing Decisions**
   - **Type:** AFK
   - **Blocked by:** 7. Expose Read-State Summaries And Private PubSub
   - **User stories covered:** 1, 4-5, 25-27, 38, 45-46
   - **Issue:** `08-add-channel-open-landing-decisions.md`
9. **Add Sequence-Based Message Windows**
   - **Type:** AFK
   - **Blocked by:** 1. Add Channel-Local Message Sequencing, 8. Add Channel Open Landing Decisions
   - **User stories covered:** 4-5, 7, 9, 25-29, 44-46
   - **Issue:** `09-add-sequence-based-message-windows.md`
10. **Replace Channel Mount With Landing Windows**
    - **Type:** AFK
    - **Blocked by:** 8. Add Channel Open Landing Decisions, 9. Add Sequence-Based Message Windows
    - **User stories covered:** 1, 4-5, 15-17, 25-28, 38, 46
    - **Issue:** `10-replace-channel-mount-with-landing-windows.md`
11. **Add Explicit Channel Read Actions**
    - **Type:** AFK
    - **Blocked by:** 4. Implement Span Merge And Subtract Workflows, 9. Add Sequence-Based Message Windows, 10. Replace Channel Mount With Landing Windows
    - **User stories covered:** 6-9, 17-21, 26, 46
    - **Issue:** `11-add-explicit-channel-read-actions.md`
12. **Add Automatic Bidirectional History Loading**
    - **Type:** AFK
    - **Blocked by:** 9. Add Sequence-Based Message Windows, 10. Replace Channel Mount With Landing Windows
    - **User stories covered:** 28-29, 31-32, 44-46
    - **Issue:** `12-add-automatic-bidirectional-history-loading.md`
13. **Bound The Rendered Message Window**
    - **Type:** AFK
    - **Blocked by:** 12. Add Automatic Bidirectional History Loading
    - **User stories covered:** 29-32, 44, 46
    - **Issue:** `13-bound-the-rendered-message-window.md`
14. **Add Visible-Read Observation Hook**
    - **Type:** AFK
    - **Blocked by:** 4. Implement Span Merge And Subtract Workflows, 10. Replace Channel Mount With Landing Windows
    - **User stories covered:** 2-3, 12-16, 42-43, 46
    - **Issue:** `14-add-visible-read-observation-hook.md`
15. **Persist Scroll Anchors From Visible Messages**
    - **Type:** AFK
    - **Blocked by:** 9. Add Sequence-Based Message Windows, 10. Replace Channel Mount With Landing Windows
    - **User stories covered:** 25-27, 31, 38, 46
    - **Issue:** `15-persist-scroll-anchors-from-visible-messages.md`
16. **Render Unread Divider And Sticky Actions**
    - **Type:** AFK
    - **Blocked by:** 10. Replace Channel Mount With Landing Windows, 11. Add Explicit Channel Read Actions, 14. Add Visible-Read Observation Hook
    - **User stories covered:** 6-8, 17-19, 46
    - **Issue:** `16-render-unread-divider-and-sticky-actions.md`
17. **Add Sidebar Mark-As-Read Controls**
    - **Type:** AFK
    - **Blocked by:** 7. Expose Read-State Summaries And Private PubSub, 11. Add Explicit Channel Read Actions
    - **User stories covered:** 8, 20-24, 46
    - **Issue:** `17-add-sidebar-mark-as-read-controls.md`
18. **Sync Read State Across User Sessions**
    - **Type:** AFK
    - **Blocked by:** 7. Expose Read-State Summaries And Private PubSub, 11. Add Explicit Channel Read Actions, 14. Add Visible-Read Observation Hook
    - **User stories covered:** 16, 22-24, 43, 46
    - **Issue:** `18-sync-read-state-across-user-sessions.md`
19. **Retire Cursor-Read Runtime Behavior**
    - **Type:** AFK
    - **Blocked by:** 3. Backfill Range State From Cursor Reads, 5. Create Message Send Unread Fanout, 7. Expose Read-State Summaries And Private PubSub, 10. Replace Channel Mount With Landing Windows, 11. Add Explicit Channel Read Actions, 14. Add Visible-Read Observation Hook, 18. Sync Read State Across User Sessions
    - **User stories covered:** 1-3, 10-11, 24, 36-38, 46
    - **Issue:** `19-retire-cursor-read-runtime-behavior.md`
20. **Finalize Unread Ranges Acceptance Coverage**
    - **Type:** AFK
    - **Blocked by:** 1-19
    - **User stories covered:** 1-46
    - **Issue:** `20-finalize-unread-ranges-acceptance-coverage.md`

## Notes For Implementers

- Keep Channel LiveViews inside the existing authenticated browser scope and
  existing `live_session :require_authenticated_user`. This keeps
  `current_scope` available and matches private Workspace access rules.
- LiveViews should call `DiscordClone.Chat` for unread, message-window,
  read-action, pagination, and PubSub workflows.
- Workspaces should continue owning membership and Channel lifecycle workflows;
  Chat should own unread persistence behind public APIs.
- Unread spans are the source of truth. Read states are fast per-User Channel
  summaries for sidebars and landing decisions.
- ChannelServer must not store unread spans, read states, or resume anchors as
  source-of-truth state.
- Shared Workspace or Channel broadcasts must not include user-private unread
  summaries. User-scoped read-state broadcasts are private to the same User's
  sessions.
- `Replace Channel Mount With Landing Windows` removes the old read-on-open
  side effect; `Retire Cursor-Read Runtime Behavior` is the later audit that
  proves no runtime unread path still depends on `channel_reads`.
- Selected-Channel incoming Messages still create unread state first. The
  LiveView may append and observe them when the User is at latest, but it must
  not force-scroll or inject distant latest Messages while the User is reading
  older history.
- Prefer focused tests for Chat, Workspaces, and Channel LiveViews before
  running `mix precommit`.
