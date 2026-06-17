# Workspace Entry Shell PRD

## Problem Statement

The Discord clone has durable workspace and channel creation workflows, but a
logged-in user still cannot move through the product like a chat application.
They can authenticate and the core can create workspaces and channels, but
there is no authenticated app shell that lists their workspaces, resolves
workspace entry into a landing channel, shows channels in the selected
workspace, or gives them a basic channel surface to enter before persisted chat
is implemented.

The immediate problem is to build the smallest end-to-end Phase 3 path through
the existing durable model: authenticated user enters the app, creates or
selects a workspace, creates or selects a channel, and lands in a stable
three-column shell that feels like a small Discord or Slack-style chat product
instead of a plain CRUD dashboard.

## Solution

Add scoped workspace read and navigation workflows to the Workspaces context,
then build an authenticated LiveView shell around them.

The shell uses the product's target three-column layout: workspaces on the
left, channels for the selected workspace in the middle, and the selected
channel surface in the main area. Workspace entry resolves to the workspace's
stored default channel. A newly created channel becomes the selected channel,
but creating a channel does not change the workspace's landing channel.

The slice should stop before persisted chat, PubSub, channel GenServers,
presence, typing indicators, invites, and channel deletion. The main channel
area should show a disabled message composer placeholder so the layout matches
the future chat experience without pretending that message sending exists.

## User Stories

1. As an authenticated user, I want to land on the workspace app after logging in, so that I can immediately continue into the collaboration product.
2. As an anonymous visitor, I want the public root page to remain accessible, so that the app can still explain itself before login.
3. As a logged-in user visiting the public root page, I want to be sent to my workspace app, so that I am not stranded on the public page.
4. As an authenticated user, I want to see all workspaces I belong to, so that I can choose where to continue.
5. As an authenticated user with no workspaces, I want the create-workspace form to be visible by default, so that I know how to start.
6. As an authenticated user with existing workspaces, I want workspace creation behind a compact plus action, so that the workspace sidebar stays calm and stable.
7. As an authenticated user, I want newly created workspaces to appear first, so that I get immediate feedback after creating one.
8. As a workspace member, I want selecting a workspace to enter the correct channel automatically when one exists, so that workspace switching feels like a chat app.
9. As a workspace member, I want workspace entry to use the workspace landing channel, so that workspace defaults are respected.
10. As a workspace member, I want a new workspace to start with a `general` landing channel, so that workspace entry is always useful.
11. As a workspace member, I want the channel sidebar to show the default `general` channel immediately after workspace creation, so that the workspace does not feel empty.
12. As a workspace member, I want the create-channel action available in the channel sidebar, so that I can add more channels without hunting for an action.
13. As a workspace member, I want the channel create action near the Channels heading, so that channel creation appears where I expect it in the sidebar.
14. As a workspace member, I want channel creation to use an inline form for this slice, so that I stay in context while creating a channel.
15. As a workspace member, I want channels listed in stable oldest-first order, so that the channel sidebar does not rearrange itself while I use it.
16. As a workspace member, I want the selected channel visibly highlighted, so that I always know which channel I am viewing.
17. As a workspace member, I want clicking a channel to update the main area, so that navigation feels like entering a channel.
18. As a workspace member, I want creating a channel to navigate me into the new channel, so that the channel I just made is ready to use.
19. As a workspace member, I want channel creation to leave the workspace landing channel unchanged, so that entering the workspace remains stable.
20. As a workspace member, I want invalid channel names to keep the inline form open with field errors, so that I can correct the problem.
21. As an authenticated user, I want invalid workspace names to keep the inline form open with field errors, so that I can correct the problem.
22. As a logged-in non-member, I should not see or enter a workspace I do not belong to, so that private workspace boundaries are preserved.
23. As a logged-in user, I want missing or unauthorized workspace access to return me to the workspace app with a clear flash, so that the app recovers instead of crashing.
24. As a logged-in user, I want missing or unauthorized channel access to return me to the workspace app with a clear flash, so that invalid URLs do not expose private state.
25. As a workspace member, I want the URL to identify both workspace and channel when a channel is selected, so that refreshes and direct links restore the same surface.
26. As a workspace member, I want a disabled message composer placeholder in the channel surface, so that the shell resembles the future chat layout without enabling unfinished behavior.
27. As a developer, I want public Workspaces read/navigation APIs to authorize themselves, so that LiveViews cannot accidentally bypass membership checks.
28. As a developer, I want workspace listing to use workspace memberships as the access boundary, so that ownership and membership do not become competing authorization paths.
29. As a developer, I want workspace and channel ordering to live in the Workspaces context, so that LiveViews render domain results instead of rebuilding ordering rules.
30. As a developer, I want the LiveViews to reset streams after workspace or channel creation, so that the UI reflects the context's ordering rules.
31. As a developer, I want a shared app shell component, so that the product frame is defined once and LiveViews stay focused on loading data and handling events.
32. As a developer, I want the shared shell to render sidebar forms, so that workspace and channel creation controls stay consistent across shell states.
33. As a learner, I want this slice to teach authenticated LiveView routing, context-backed forms, streams, redirects, and thin web modules without jumping ahead into chat or OTP.

## Implementation Decisions

- Add scoped read and navigation APIs to the Workspaces context.
- Add a workspace listing workflow that requires an authenticated scope and returns only workspaces where the current user is a workspace member.
- Order listed workspaces by newest membership first.
- Add a narrow workspace fetch workflow that returns only the accessible workspace, not preloaded channels.
- Add a channel listing workflow that requires an authenticated workspace member and returns channels for the workspace.
- Order listed channels oldest first for a stable chat sidebar.
- Add a landing-channel resolution workflow that authorizes access itself.
- Landing-channel resolution returns the workspace's stored default channel.
- Landing-channel resolution returns an explicit error if the stored default channel is missing, because that indicates broken workspace state.
- Missing workspace identifiers return a not-found outcome.
- Logged-in users who are not workspace members receive an unauthorized outcome.
- Anonymous or missing scopes receive an unauthenticated outcome.
- Public context workflows should defend their own boundary even when called from authenticated routes.
- Keep channel creation separate from landing-channel selection.
- Creating a channel should navigate to the newly created channel.
- Creating a channel should not update the workspace default channel.
- Add an authenticated workspace index LiveView for `/workspaces`.
- `/workspaces` renders the full three-column app shell with no workspace selected.
- The no-workspace-selected main area should show a clear empty state such as "Select a workspace to continue."
- Add a workspace entry LiveView for `/workspaces/:workspace_id`.
- Workspace entry redirects or navigates to `/workspaces/:workspace_id/channels/:channel_id` for the landing channel.
- Workspace entry redirects to `/workspaces` with a flash if the landing channel is missing.
- Add a channel show LiveView for `/workspaces/:workspace_id/channels/:channel_id`.
- The channel show route renders the full app shell with selected workspace, selected channel, channel list, and a disabled composer placeholder.
- The channel show route must verify that the selected channel belongs to the selected workspace and is visible to the current workspace member.
- Add a shared app-specific shell component for the three-column product frame.
- The shared shell is render-only. It does not query the database and does not own authorization decisions.
- The shared shell renders workspace sidebar, channel sidebar, selected states, plus actions, inline create forms, empty states, and the main content surface.
- The shared shell may accept form assigns and visibility flags because it is app-specific, not a generic layout framework.
- Use LiveView streams for workspace and channel sidebars.
- Track selected workspace and selected channel as separate assigns because streams are not enumerable state.
- After workspace creation, refetch workspaces through the Workspaces context and reset the workspace stream.
- After channel creation, refetch channels through the Workspaces context and reset the channel stream.
- Workspace creation form is visible by default only when the user belongs to zero workspaces.
- Workspace creation is hidden behind a compact plus action when the user already belongs to at least one workspace.
- Channel creation appears near the Channels heading in the channel sidebar.
- Channel creation uses an inline form for this slice instead of a modal.
- Channel creation is available from the channel sidebar for adding channels beyond the default `general` channel.
- Invalid workspace or channel validation keeps the relevant inline form open and renders field errors.
- Unauthorized or missing workspace/channel access redirects to `/workspaces` with a flash.
- Successful login redirects authenticated users to `/workspaces`.
- The public root route remains public for anonymous users.
- Logged-in users visiting the public root route redirect to `/workspaces`.
- Routes for this feature belong in the existing authenticated browser scope and existing authenticated LiveView session.
- These routes require the browser pipeline plus authenticated-user plug because workspace/channel structure is private to workspace members.
- LiveViews must receive `current_scope` from the authenticated LiveView session and pass it to the app layout.
- Templates must use `@current_scope.user` when deriving the user, never `@current_user`.
- No schema changes are needed for this slice.
- No ADR is needed because the decisions align with existing docs and remain easy to revise.

## Testing Decisions

- Test public context behavior instead of private helper implementation.
- The main context test surface is the Workspaces context.
- Workspaces context tests should cover workspace listing, workspace fetching, channel listing, and landing-channel resolution.
- Context tests should reuse existing account and workspace fixtures.
- Context tests should create channels through the public channel creation workflow.
- Test that workspace listing requires authentication.
- Test that workspace listing returns only workspaces where the user is a workspace member.
- Test that workspace listing orders by newest membership first.
- Test that workspace fetch returns not-found for missing workspaces.
- Test that workspace fetch returns unauthorized for logged-in non-members.
- Test that channel listing requires an authorized workspace member.
- Test that channel listing orders channels oldest first.
- Test that landing-channel resolution returns the stored default channel.
- Test that landing-channel resolution returns an explicit error if the stored default channel is missing.
- Test that landing-channel resolution distinguishes unauthenticated, unauthorized, and not-found outcomes.
- LiveView tests should use Phoenix LiveViewTest and assert through stable DOM IDs rather than brittle raw HTML.
- LiveView tests should cover `/workspaces` requiring authentication through the router.
- LiveView tests should cover `/workspaces` rendering the shell and no-workspace-selected empty state.
- LiveView tests should cover a zero-workspace user seeing the create-workspace form by default.
- LiveView tests should cover a user with workspaces seeing a compact create action instead of an always-open form.
- LiveView tests should cover successful workspace creation refetching/resetting the sidebar and navigating into workspace entry.
- LiveView tests should cover invalid workspace creation keeping the inline form open with field errors.
- LiveView tests should cover workspace entry redirecting to the landing channel.
- LiveView tests should cover missing landing-channel recovery with a redirect and flash.
- LiveView tests should cover the default `general` channel appearing in the channel sidebar.
- LiveView tests should cover successful channel creation navigating to the new channel.
- LiveView tests should cover invalid channel creation keeping the inline form open with field errors.
- LiveView tests should cover channel show rendering selected workspace, selected channel, stable channel sidebar, and disabled composer placeholder.
- LiveView tests should cover unauthorized or missing workspace/channel URLs redirecting to `/workspaces` with flash.
- Existing generated auth LiveView and controller tests provide route/authentication prior art.
- Existing Workspaces context tests provide public-context prior art.
- Run focused Workspaces context tests first, then focused LiveView tests, then the project precommit alias.

## Out of Scope

- Persisted message sending.
- Message history queries.
- Message pagination.
- PubSub broadcasts.
- Live message delivery.
- Channel GenServers.
- Channel registries or dynamic supervisors.
- Presence tracking.
- Typing indicators.
- Online user sidebar behavior.
- Invite creation.
- Invite redemption.
- Workspace join flow through invites.
- Channel deletion.
- Default-channel selection UI.
- Default-channel replacement rules when deleting channels.
- Manual channel ordering.
- Workspace roles beyond the existing membership gate.
- Channel descriptions.
- Last activity tracking.
- Remembering the user's last selected workspace.
- Polished modal dialogs for create flows.
- Publishing this PRD to an issue tracker.

## Further Notes

This PRD comes from a `grill-with-docs` session focused on the smallest
end-to-end Phase 3 path. The discussion deliberately moved the UI toward the
three-column chat shell described in the project notes rather than a separate
CRUD-style workspace details page.

The shared app shell is the main deep web module opportunity in this slice: it
can hide repetitive layout and sidebar rendering behind a stable render-only
interface while keeping data loading, authorization, and event handling in the
LiveViews and Workspaces context.

Issue tracker publishing is blocked because this repository does not currently
define the tracker configuration or triage label vocabulary expected by the
local `to-prd` skill. The repository has a GitHub remote, but the setup flow has
not been completed to confirm GitHub Issues, label names, and domain-doc
layout. This PRD is written as a docs artifact until that setup is available.
