# List Durable Workspace Members

**Type:** AFK

**Blocked by:** None - can start immediately

**User stories covered:** 4, 15, 20, 23

## What to build

Add the first durable member-list workflow for workspace presence. A workspace
member should be able to ask the Workspaces context for all Workspace Members
in a Workspace, including the user display data needed by the right sidebar.
The workflow should follow the same workspace membership authorization boundary
as the rest of the private workspace behavior.

This slice is intentionally durable-only. It does not introduce online status,
OTP processes, Chat APIs, PubSub events, or right-sidebar rendering. It gives
later presence slices a stable source of truth for who belongs to the
Workspace.

## Acceptance criteria

- [x] The Workspaces context exposes a public workflow for listing Workspace
      Members in a Workspace.
- [x] The workflow requires an authenticated scope.
- [x] Anonymous scopes receive `{:error, :unauthenticated}`.
- [x] Logged-in users who are not Workspace Members cannot list members.
- [x] Missing or inaccessible Workspaces use the existing private workspace
      access behavior.
- [x] Returned data includes the durable user display fields needed by the
      member sidebar.
- [x] Returned data is ordered predictably enough for stable rendering and
      tests.
- [x] The web layer does not assemble membership queries itself.
- [x] No online or offline runtime state is added in this slice.
- [x] Focused Workspaces context tests cover successful listing,
      unauthenticated access, non-member access, and returned user display data.

## Blocked by

None - can start immediately.
