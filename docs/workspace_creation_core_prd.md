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
user can create a workspace, and the system will create the owner's membership
in the same transaction.

This gives the application a trustworthy durable invariant: every workspace
created through the public context starts with an authenticated owner and an
owner membership. Channels are created by a later workflow. A workspace may
temporarily have no default channel, and workspace entry will later resolve a
landing channel by using the explicit default channel when present, falling back
to the oldest channel when needed.

## User Stories

1. As an authenticated user, I want to create a workspace, so that I can start a new collaboration space.
2. As an authenticated user, I want workspace creation to use my logged-in identity, so that ownership cannot be spoofed through request parameters.
3. As a workspace creator, I want duplicate workspace names to be allowed, so that my chosen display name is not blocked by another user's workspace.
4. As a workspace creator, I want my owner membership to be created automatically, so that future access checks recognize me as a member.
5. As a developer, I want workspace creation to be a public context function, so that LiveViews and controllers do not assemble domain state manually.
6. As a developer, I want workspace creation to be transactional, so that partial workspace state is rolled back if any step fails.
7. As a developer, I want caller-provided owner IDs and invite policies to be ignored, so that client params cannot override server-owned workflow decisions.
8. As a developer, I want workspace creation to leave channel setup to a separate workflow, so that workspace ownership and channel lifecycle rules stay readable.
9. As a developer, I want transaction failures to preserve their operation context, so that test failures and form integration remain easy to debug.
10. As a developer, I want every workspace test fixture to use the public context, so that test data follows the same invariants as production data.
11. As a learner, I want this slice to stay focused on durable workspace behavior, so that the next implementation step remains understandable and reviewable.

## Implementation Decisions

- Build the first public workspace workflow: `create_workspace(current_scope, attrs)`.
- The workflow belongs in the Workspaces context, which should remain the public entry point for workspace structure, memberships, channels, invites, and access rules.
- The workflow requires an authenticated scope containing a user. Missing or anonymous users return `{:error, :unauthenticated}`.
- Workspace creation uses one transaction to create the workspace and create the owner membership.
- Keep the existing `workspaces.default_channel_id` model, but allow it to be `nil`.
- A workspace may exist before any channels have been created.
- The workflow accepts a workspace name only. Channel input such as `main_channel_name` is ignored in this workflow.
- Caller-provided owner IDs are ignored. Ownership always comes from the authenticated scope's user.
- Caller-provided invite policy is ignored in this first slice. New workspaces use `owner_only`.
- Owner membership is created with role `owner`.
- The successful return shape is `{:ok, workspace}` with `default_channel_id` left as `nil`.
- Failed transactions preserve the raw multi-step failure shape: `{:error, failed_operation, changeset_or_reason, changes_so_far}`.
- Workspace names remain non-unique.
- Add a workspace fixture helper that creates workspaces through the public context rather than direct schema inserts.
- Do not introduce UI routes or LiveViews in this slice.

## Testing Decisions

- Test external context behavior instead of schema internals.
- The main test surface is the Workspaces context.
- Add workspace fixture coverage through a helper that calls the public creation workflow.
- Use existing account fixture patterns to create authenticated user scopes.
- Good tests should prove durable outcomes: workspace creation returns a workspace with no default channel, creates no channel, and persists an owner membership.
- Test that channel-related params such as `main_channel_name` are ignored by this workflow.
- Test unauthenticated scope handling: missing users return `{:error, :unauthenticated}`.
- Test ownership protection: caller-provided owner IDs do not override the authenticated user.
- Test invite policy protection: caller-provided invite policy does not override the first-slice `owner_only` behavior.
- Similar prior patterns exist in the generated account tests and fixtures, which already test public context behavior through helpers rather than testing only schemas.
- When implementation is complete, run focused workspace tests first, then run the project precommit alias.

## Out of Scope

- Workspace LiveViews, forms, navigation, or router changes.
- Channel creation.
- First-channel default assignment.
- Workspace landing-channel resolution.
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
