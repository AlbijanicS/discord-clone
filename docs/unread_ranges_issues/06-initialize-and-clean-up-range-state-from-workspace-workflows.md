# Initialize And Clean Up Range State From Workspace Workflows

**Type:** AFK

**Blocked by:** 2. Create Unread Span And Read-State Storage

**User stories covered:** 33-35, 39, 46

## What to build

Wire read-state initialization and cleanup into Workspace membership and
Channel lifecycle workflows. New Workspace Members should start with existing
history treated as read, new Channels should start read for all current
Workspace Members, and leaving a Workspace should remove private unread state.

Workspaces should continue owning membership and Channel lifecycle decisions;
Chat should provide the unread initialization and cleanup APIs.

## Acceptance criteria

- [ ] Chat exposes an idempotent workflow to initialize read states for a User
      in a Workspace.
- [ ] New Workspace Members receive zero-unread read states for existing
      Channels.
- [ ] New Workspace Members do not receive unread spans for pre-join history.
- [ ] New Channel creation initializes zero-unread read states for all current
      Workspace Members.
- [ ] Workspace creation initializes the owner read state after the Landing
      Channel exists.
- [ ] Leaving a Workspace deletes that User's read states and unread spans for
      Channels in that Workspace.
- [ ] Initialization and cleanup happen inside the parent Workspaces
      transaction where practical.
- [ ] Existing-member invite acceptance does not reset unread spans, read
      states, or anchors.
- [ ] Workspaces tests cover workspace creation, invite acceptance, existing
      member invite behavior, Channel creation, and leaving.

## Blocked by

- 2. Create Unread Span And Read-State Storage
