# Expose Read-State Summaries And Private PubSub

**Type:** AFK

**Blocked by:** 4. Implement Span Merge And Subtract Workflows, 5. Create Message Send Unread Fanout

**User stories covered:** 2, 22-24, 37-38, 43, 46

## What to build

Expose fast read-state summary APIs through Chat and publish private read-state
events only to the same User's sessions. Sidebar unread badges should be able
to read exact counts from `channel_read_states` without scanning Messages.

This slice creates the server contract for LiveViews but does not need to
redesign the Channel message pane yet.

## Acceptance criteria

- [ ] Chat exposes a Workspace-scoped read-state summary list for the current
      User.
- [ ] Summary results include Workspace ID, Channel ID, unread count, first
      unread sequence, and last unread sequence.
- [ ] Zero-unread Channels can be omitted or represented consistently according
      to the existing sidebar data shape.
- [ ] Summary reads require authenticated Workspace membership.
- [ ] Unauthenticated scopes return `{:error, :unauthenticated}` and logged-in
      non-members return `{:error, :not_found}`.
- [ ] Sidebar unread counts are sourced from `channel_read_states`.
- [ ] Read-state changes publish user-scoped PubSub events for the same User's
      sessions.
- [ ] Private read-state events include the updated summary payload needed for
      direct UI updates, including Workspace ID so multi-workspace sessions can
      filter events without guessing.
- [ ] Shared Workspace or Channel message events do not include user-private
      unread summaries.
- [ ] Duplicate no-op read-state changes do not publish events.
- [ ] Focused tests prove summary access, exact counts, user scoping, and
      payload privacy across different Users and Workspaces.

## Blocked by

- 4. Implement Span Merge And Subtract Workflows
- 5. Create Message Send Unread Fanout
