# Render Offline Member Sidebar In Workspace Shell

**Type:** AFK

**Blocked by:** 1. List Durable Workspace Members

**User stories covered:** 1, 4-5, 13-15

## What to build

Render all durable Workspace Members in the workspace shell's right sidebar,
with every member shown as offline for now. Channel pages and workspace shell
surfaces should keep their existing navigation and content behavior while
adding a stable member-list region that future presence slices can update.

This slice should route member data through existing LiveView mount workflows
and the shared shell component. It should not add OTP runtime state, Chat
presence APIs, PubSub subscriptions, or live online updates yet. The goal is a
complete, user-visible offline member list backed by durable membership data.

## Acceptance criteria

- [ ] The relevant workspace LiveViews load durable Workspace Members through
      the public Workspaces workflow.
- [ ] The shared workspace shell accepts and renders a member list without
      reaching into the database.
- [ ] The right sidebar has a stable DOM ID suitable for LiveView tests.
- [ ] Each rendered member has a stable DOM ID derived from durable member or
      user identity.
- [ ] Every member renders as offline in this slice.
- [ ] Offline styling is visually distinct and accessible enough to scan.
- [ ] The selected channel message surface still works with the new sidebar.
- [ ] Workspace invite and workspace entry shell surfaces can render the member
      sidebar when a selected Workspace is available.
- [ ] The route placement remains in the existing authenticated browser
      pipeline and existing `live_session :require_authenticated_user` because
      the member list is private workspace data and needs `current_scope`.
- [ ] Focused LiveView tests use stable selectors to prove all durable members
      render and appear offline.

## Blocked by

- 1. List Durable Workspace Members
