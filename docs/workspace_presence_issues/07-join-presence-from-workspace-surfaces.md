# Join Presence From Workspace Surfaces

**Type:** AFK

**Blocked by:** 1. List Durable Workspace Members, 2. Render Offline Member Sidebar In Workspace Shell, 6. Expose Workspace Presence Through Chat

**User stories covered:** 3, 6, 10-11, 17, 20-21, 30-31, 41

## What to build

Wire authenticated workspace LiveViews into the public Chat presence workflows.
After workspace access is proven and durable shell data has loaded, connected
LiveViews inside a Workspace should subscribe to Workspace presence events,
join Workspace presence, list online user IDs, and assign the online IDs in a
set-like structure for rendering.

This slice should cover workspace-scoped surfaces, not just channel pages. A
member should appear online when viewing any selected-workspace surface in the
app, and switching channels inside the same Workspace should preserve the
workspace-scoped model.

## Acceptance criteria

- [ ] Channel pages subscribe to Workspace presence only after existing
      workspace/channel access checks succeed.
- [ ] Workspace invite shell pages subscribe and join presence after workspace
      access and invite-screen authorization succeed.
- [ ] Workspace entry or selected-workspace shell surfaces count as being
      inside the Workspace where they have a connected LiveView.
- [ ] Presence work runs only when the LiveView socket is connected.
- [ ] LiveViews subscribe before joining presence.
- [ ] LiveViews list online user IDs after joining.
- [ ] Online user IDs are stored in a set-like assign.
- [ ] If listing online IDs returns empty because runtime state is unavailable,
      the member sidebar still renders durable members as offline.
- [ ] LiveViews call public Chat workflows, not private runtime or PubSub
      APIs.
- [ ] The route placement remains in the existing authenticated browser
      pipeline and existing `live_session :require_authenticated_user` because
      presence requires `current_scope` and Workspace membership.
- [ ] Focused LiveView tests prove the current user appears online after
      entering a Workspace surface.

## Blocked by

- 1. List Durable Workspace Members
- 2. Render Offline Member Sidebar In Workspace Shell
- 6. Expose Workspace Presence Through Chat
