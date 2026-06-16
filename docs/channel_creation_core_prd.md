# Channel Creation Core PRD

## Problem Statement

The Discord clone can create authenticated workspaces with owner memberships,
but workspace members cannot yet create channels. This blocks the first useful
workspace flow: a user can register, log in, create a workspace, and then create
the first conversation space inside it.

The immediate problem is to add a small, explicit channel creation workflow
without mixing it with workspace landing rules, default-channel settings,
LiveView screens, chat, invites, PubSub, or OTP channel processes.

## Solution

Add a channel creation workflow to the Workspaces context. A logged-in workspace
member can create a channel in a workspace by passing a workspace identifier and
valid channel attributes. The workflow returns the created channel and does not
select or change the workspace landing channel.

This keeps the domain boundary readable: channel creation creates channels,
while landing-channel resolution remains a separate navigation workflow. Until a
future settings flow explicitly selects a default channel, workspace entry can
resolve to the oldest channel.

## User Stories

1. As a workspace member, I want to create a channel, so that my workspace has a place for conversation.
2. As a workspace member, I want the channel to belong to the workspace I selected, so that channels do not accidentally appear in the wrong workspace.
3. As a workspace member, I want channel names to be normalized consistently, so that names like `Main Room` become predictable channel names.
4. As a workspace member, I want invalid channel names to fail clearly, so that I can correct the form instead of creating a broken channel.
5. As a workspace member, I want duplicate channel names in the same workspace to be rejected, so that the channel list stays unambiguous.
6. As a workspace member, I want the same channel name to be allowed in different workspaces, so that each workspace can organize itself independently.
7. As a workspace member, I want channel creation to ignore hidden or spoofed workspace fields, so that the selected workspace remains the source of truth.
8. As a workspace member, I want creating a channel to return the created channel, so that the UI can navigate directly to it later.
9. As a workspace member, I want channel creation to avoid changing the workspace landing channel, so that default-channel selection remains an explicit future setting.
10. As a workspace member, I want a first channel to be creatable even when the workspace has no landing channel set, so that a new workspace can become useful gradually.
11. As a logged-in non-member, I should not be able to create a channel in a workspace I do not belong to, so that private workspace boundaries are respected.
12. As an anonymous visitor, I should not be able to create a channel, so that workspace changes require an authenticated user.
13. As a developer, I want unauthenticated, unauthorized, not-found, and validation failures to have distinct return shapes, so that LiveViews can handle each outcome clearly.
14. As a developer, I want invalid channel input to return an explicit channel validation error with field details, so that forms can show useful errors.
15. As a developer, I want channel forms to use a public context helper, so that web modules do not call schema changesets directly.
16. As a developer, I want workspace membership to be the current permission gate, so that later role-specific permissions can refine the rule without changing the core boundary.
17. As a developer, I want the workflow to accept a workspace identifier, so that callers can pass the workspace value they naturally have from params or assigns.
18. As a learner, I want this slice to stay focused on durable channel behavior, so that the next UI slice remains small and reviewable.

## Implementation Decisions

- Build a public channel creation workflow in the Workspaces context.
- The workflow takes the current scope, a workspace identifier, and channel attributes.
- The workspace identifier is the source of truth for the target workspace.
- Caller-provided workspace identifiers inside channel attributes are ignored.
- The workflow requires an authenticated scope containing a user.
- Anonymous or missing scopes return `{:error, :unauthenticated}`.
- The workflow first resolves the workspace identifier to a workspace.
- A missing workspace returns `{:error, :not_found}`.
- The workflow requires the logged-in user to be a workspace member.
- A logged-in user who is not a workspace member returns `{:error, :unauthorized}`.
- For this slice, any workspace member can create channels.
- Later Discord-like workspace roles can restrict channel creation, invite management, member removal, and channel deletion to admin-capable roles.
- The workflow creates only a channel.
- The workflow does not update the workspace default channel.
- The workflow does not resolve the workspace landing channel.
- Landing-channel resolution remains explicit default channel first, oldest channel fallback second.
- The workflow requires an explicit valid channel name.
- The workflow does not default blank or missing names to `general`.
- Channel names continue to be normalized by the existing channel validation rules.
- Channel names remain unique within a workspace after normalization.
- The same normalized channel name may exist in different workspaces.
- A successful create returns `{:ok, channel}`.
- Invalid channel input returns `{:error, :invalid_channel, changeset}`.
- Add a public channel changeset helper in the Workspaces context for future forms.
- The channel changeset helper should be suitable for LiveView form usage.
- No schema changes are needed.
- No router or LiveView changes are included in this core slice.
- No ADR is needed for this slice because the decisions are lightweight and easy to revisit.

## Testing Decisions

- Test public context behavior instead of schema internals.
- The main test surface is the Workspaces context.
- Existing Workspaces context tests provide the closest prior pattern.
- Existing account and workspace fixtures should be reused to create authenticated scopes and workspaces through public workflows.
- Good tests should prove durable outcomes and return contracts rather than private implementation details.
- Test that an authenticated workspace member can create a channel.
- Test that the created channel belongs to the explicit workspace identifier.
- Test that spoofed workspace fields in attrs are ignored.
- Test that channel names are normalized by the existing channel rules.
- Test that duplicate normalized channel names fail inside the same workspace.
- Test that duplicate normalized channel names are allowed across different workspaces.
- Test that anonymous or missing scopes return `{:error, :unauthenticated}`.
- Test that logged-in non-members return `{:error, :unauthorized}`.
- Test that nonexistent workspaces return `{:error, :not_found}`.
- Test that invalid channel names return `{:error, :invalid_channel, changeset}`.
- Test that creating a channel does not update `default_channel_id`.
- Test that the channel changeset helper returns a changeset suitable for form usage.
- Run focused Workspaces context tests first, then run the project precommit alias.

## Out of Scope

- Workspace LiveViews, channel LiveViews, forms, navigation, or router changes.
- Landing-channel resolution helper.
- Setting or changing a workspace default channel.
- Automatically assigning the first channel as the default channel.
- Channel deletion.
- Default-channel replacement rules.
- Workspace member role permissions beyond the current membership gate.
- Invite creation or invite redemption.
- Message sending, message history, pagination, and persisted chat behavior.
- PubSub broadcasts and live message delivery.
- Channel GenServers, registries, supervisors, presence, typing indicators, and crash recovery.
- Publishing this PRD to an issue tracker.

## Further Notes

This PRD comes from a `grill-with-docs` session about the next small channel
creation slice. The discussion deliberately separated channel creation from
workspace landing-channel selection.

Issue tracker publishing is blocked because this repository does not currently
define the tracker configuration or triage label vocabulary expected by the
local `to-prd` skill. The PRD is written as a docs artifact until that setup is
available.
