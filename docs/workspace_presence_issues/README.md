# Workspace Presence Issues

This folder breaks `docs/workspace_presence_prd.md` into small,
independently grabbable tracer-bullet issues. The project is using a
docs-first fallback for now, so these are not published to GitHub Issues.

The route placement for this phase is intentionally unchanged: workspace and
channel LiveViews stay in the existing authenticated browser pipeline and the
existing `live_session :require_authenticated_user`, because workspace
presence requires `current_scope`, an authenticated user, and workspace
membership. No new public unauthenticated presence routes are needed.

## Proposed Breakdown

1. **List Durable Workspace Members**
   - **Type:** AFK
   - **Blocked by:** None - can start immediately
   - **User stories covered:** 4, 15, 20, 23
   - **Issue:** `01-list-durable-workspace-members.md`
2. **Render Offline Member Sidebar In Workspace Shell**
   - **Type:** AFK
   - **Blocked by:** 1. List Durable Workspace Members
   - **User stories covered:** 1, 4-5, 13-15
   - **Issue:** `02-render-offline-member-sidebar.md`
3. **Add Workspace Presence Runtime Foundation**
   - **Type:** AFK
   - **Blocked by:** None - can start immediately
   - **User stories covered:** 21-22, 34, 40-42
   - **Issue:** `03-add-workspace-presence-runtime-foundation.md`
4. **Track Workspace Presence Connections**
   - **Type:** AFK
   - **Blocked by:** 3. Add Workspace Presence Runtime Foundation
   - **User stories covered:** 2-3, 6, 9, 24-25, 32, 34, 40-41
   - **Issue:** `04-track-workspace-presence-connections.md`
5. **Broadcast User-Level Workspace Presence Events**
   - **Type:** AFK
   - **Blocked by:** 4. Track Workspace Presence Connections
   - **User stories covered:** 7-8, 12, 26-29, 35, 37-39
   - **Issue:** `05-broadcast-user-level-presence-events.md`
6. **Expose Workspace Presence Through Chat**
   - **Type:** AFK
   - **Blocked by:** 3. Add Workspace Presence Runtime Foundation, 4. Track Workspace Presence Connections, 5. Broadcast User-Level Workspace Presence Events
   - **User stories covered:** 18-22, 32-36, 40-42
   - **Issue:** `06-expose-workspace-presence-through-chat.md`
7. **Join Presence From Workspace Surfaces**
   - **Type:** AFK
   - **Blocked by:** 1. List Durable Workspace Members, 2. Render Offline Member Sidebar In Workspace Shell, 6. Expose Workspace Presence Through Chat
   - **User stories covered:** 3, 6, 10-11, 17, 20-21, 30-31, 41
   - **Issue:** `07-join-presence-from-workspace-surfaces.md`
8. **Update Member Sidebar From Live Presence Events**
   - **Type:** AFK
   - **Blocked by:** 7. Join Presence From Workspace Surfaces
   - **User stories covered:** 2, 5, 7-8, 12, 30-31, 39
   - **Issue:** `08-update-member-sidebar-from-live-events.md`
9. **Prove Multi-Tab And Last Disconnect Behavior**
   - **Type:** AFK
   - **Blocked by:** 8. Update Member Sidebar From Live Presence Events
   - **User stories covered:** 8-10, 24-29, 41
   - **Issue:** `09-prove-multi-tab-and-last-disconnect-behavior.md`
10. **Handle Presence Runtime Loss And Workspace Cleanup**
    - **Type:** AFK
    - **Blocked by:** 6. Expose Workspace Presence Through Chat, 8. Update Member Sidebar From Live Presence Events
    - **User stories covered:** 13-17, 33, 42-43
    - **Issue:** `10-handle-runtime-loss-and-workspace-cleanup.md`

## Notes For Implementers

- Keep the workspace presence LiveViews inside the existing authenticated
  browser scope and existing `live_session :require_authenticated_user`. This
  keeps `current_scope` available and matches the existing private workspace
  access rules.
- LiveViews should call `DiscordClone.Workspaces` for durable workspace data
  and `DiscordClone.Chat` for runtime presence behavior.
- LiveViews should not call workspace presence OTP modules, registries,
  supervisors, or Phoenix PubSub directly.
- Prefer focused tests first, then `mix precommit` after implementation
  changes.
