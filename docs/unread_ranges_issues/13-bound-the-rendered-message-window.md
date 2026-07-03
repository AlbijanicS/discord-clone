# Bound The Rendered Message Window

**Type:** AFK

**Blocked by:** 12. Add Automatic Bidirectional History Loading

**User stories covered:** 29-32, 44, 46

## What to build

Cap the rendered Message window so long Channel history remains available in
Postgres without causing the browser or LiveView state to grow forever. The
database history should remain unlimited, while the rendered window starts with
a cap of 300 Messages.

This slice adds trimming behavior to automatic pagination without removing
Messages currently visible to the User.

## Acceptance criteria

- [ ] The rendered Message window cap starts at 300 Messages.
- [ ] Database Message history remains uncapped.
- [ ] When the rendered window exceeds the cap, the LiveView trims from the
      side opposite the User's scroll direction.
- [ ] Trimming never removes currently visible Messages.
- [ ] The LiveView tracks enough boundary metadata to continue older and newer
      pagination after trimming.
- [ ] Trimming removes all server-side per-Message state for trimmed Messages,
      including stream entries, message-row metadata maps, reaction summaries,
      and any other assign keyed by Message ID.
- [ ] Trimming notifies or lets the client hook clean up observer state for
      removed Message rows.
- [ ] Scroll position remains stable when older Messages are prepended and the
      opposite side is trimmed.
- [ ] Unread divider and sticky-action state remain consistent after trimming.
- [ ] Edge loading indicators still render correctly near trimmed boundaries.
- [ ] Focused tests cover cap enforcement, trim direction, visible-window
      protection, per-Message assign pruning, observer cleanup, and pagination
      continuation.

## Blocked by

- 12. Add Automatic Bidirectional History Loading
