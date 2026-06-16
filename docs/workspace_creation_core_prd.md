# Workspace Creation Core PRD

## Problem Statement

The Discord clone has durable database tables and schema modules for users,
workspaces, channels, memberships, invites, and messages, but the workspace
domain does not yet expose behavior for creating a valid workspace. A user can
register and log in, but there is no public context function that creates the
first usable collaboration space.

The immediate problem is to move from schema foundation to a small, reliable
workspace workflow without jumping ahead into LiveView screens, invites, chat,
PubSub, or OTP processes.

## Solution

Add a workspace creation workflow to the Workspaces context. An authenticated
user can create a workspace, and the system will create the workspace's main
channel, assign it as the workspace default channel, and create the owner's
membership in a single transaction.

This gives the application a trustworthy durable invariant: every workspace
created through the public context starts with a default channel and an owner
membership. Future UI, invite, channel, and chat features can build on that
invariant.

## User Stories

1. As an authenticated user, I want to create a workspace, so that I can start a new collaboration space.
2. As an authenticated user, I want workspace creation to use my logged-in identity, so that ownership cannot be spoofed through request parameters.
3. As a workspace creator, I want the workspace to automatically include a main channel, so that the workspace is usable immediately.
4. As a workspace creator, I want the main channel to default to `general` when I leave the field blank, so that I can create a workspace with minimal setup.
5. As a workspace creator, I want to provide a custom main channel name, so that the initial channel can match the workspace's purpose.
6. As a workspace creator, I want custom channel names to be normalized consistently, so that names like `Main Room` become predictable channel names.
7. As a workspace creator, I want invalid custom channel names to fail clearly, so that the app does not silently create an unexpected fallback channel.
8. As a workspace creator, I want duplicate workspace names to be allowed, so that my chosen display name is not blocked by another user's workspace.
9. As a workspace creator, I want my owner membership to be created automatically, so that future access checks recognize me as a member.
10. As a future workspace visitor, I want each workspace to have a default channel, so that opening or joining a workspace has a clear landing point.
11. As a future invite recipient, I want accepted invites to have a default channel target, so that joining a workspace can navigate me somewhere useful.
12. As a developer, I want workspace creation to be a public context function, so that LiveViews and controllers do not assemble domain state manually.
13. As a developer, I want workspace creation to be transactional, so that partial workspace state is rolled back if any step fails.
14. As a developer, I want the returned workspace to include its default channel, so that callers can navigate without making another design decision.
15. As a developer, I want transaction failures to preserve their operation context, so that test failures and form integration remain easy to debug.
16. As a developer, I want channel names to remain unique within a workspace, so that a workspace cannot contain two channels with the same normalized name.
17. As a developer, I want every workspace test fixture to use the public context, so that test data follows the same invariants as production data.
18. As a learner, I want this slice to stay focused on durable workspace behavior, so that the next implementation step remains understandable and reviewable.

## Implementation Decisions

- Build the first public workspace workflow: `create_workspace(current_scope, attrs)`.
- The workflow belongs in the Workspaces context, which should remain the public entry point for workspace structure, memberships, channels, invites, and access rules.
- The workflow requires an authenticated scope containing a user. Missing or anonymous users return `{:error, :unauthenticated}`.
- Workspace creation uses one transaction to create the workspace, create the main channel, update the workspace default channel, and create the owner membership.
- Keep the existing `workspaces.default_channel_id` model. The workspace row points to the main/default channel.
- The workflow accepts a workspace name and optional main channel name.
- Missing or blank main channel names default to `general`.
- Non-blank main channel names are validated and normalized by the existing channel changeset rules.
- Invalid non-blank main channel names fail the transaction with the channel changeset error.
- The workflow treats the main channel name as workflow input, not a workspace field.
- Caller-provided owner IDs are ignored. Ownership always comes from the authenticated scope's user.
- Caller-provided invite policy is ignored in this first slice. New workspaces use `owner_only`.
- Owner membership is created with role `owner`.
- The successful return shape is `{:ok, workspace}` with the workspace's default channel preloaded.
- Failed transactions preserve the raw multi-step failure shape: `{:error, failed_operation, changeset_or_reason, changes_so_far}`.
- Workspace names remain non-unique.
- Channel names remain unique within each workspace.
- Add a workspace fixture helper that creates workspaces through the public context rather than direct schema inserts.
- Do not introduce UI routes or LiveViews in this slice.

## Testing Decisions

- Test external context behavior instead of schema internals.
- The main test surface is the Workspaces context.
- Add workspace fixture coverage through a helper that calls the public creation workflow.
- Use existing account fixture patterns to create authenticated user scopes.
- Good tests should prove durable outcomes: workspace creation returns a workspace with a preloaded default channel, persists the channel, and persists an owner membership.
- Test the default main channel path: blank or missing main channel name creates `general`.
- Test the custom main channel path: a custom name is normalized by existing channel rules.
- Test invalid custom channel input: invalid non-blank names fail and do not leave partial workspace state.
- Test unauthenticated scope handling: missing users return `{:error, :unauthenticated}`.
- Test ownership protection: caller-provided owner IDs do not override the authenticated user.
- Test invite policy protection: caller-provided invite policy does not override the first-slice `owner_only` behavior.
- Similar prior patterns exist in the generated account tests and fixtures, which already test public context behavior through helpers rather than testing only schemas.
- When implementation is complete, run focused workspace tests first, then run the project precommit alias.

## Out of Scope

- Workspace LiveViews, forms, navigation, or router changes.
- Channel creation after the initial main channel.
- Channel deletion and default channel replacement rules.
- Workspace list or workspace show pages.
- Invite creation, invite redemption, invite permissions, and invite landing navigation.
- Message sending, message history, pagination, and persisted chat behavior.
- PubSub broadcasts and live message delivery.
- Channel GenServers, registries, supervisors, presence, typing indicators, and crash recovery.
- Password-based registration changes.
- Workspace name uniqueness.
- Publishing this PRD to an issue tracker.

## Further Notes

This PRD comes from the completed grill session about the next implementation
slice. The user explicitly instructed that no implementation should happen as
part of producing the PRD.

Issue tracker publishing is blocked because this repository does not currently
define the tracker configuration or triage label vocabulary expected by the
local `to-prd` skill. The repo has a GitHub remote, but the skill's tracker
setup requires a separate confirmation flow before writing tracker metadata or
assuming the `ready-for-agent` label exists.
