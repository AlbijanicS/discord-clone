# Refresh Reaction Summaries After Local Toggle

**Type:** AFK

**Blocked by:** 11. Add Fixed Reaction Palette Controls

**User stories covered:** 19-22, 24, 29

## What to build

After the current User toggles a reaction, refresh the affected message's
reaction summary so the local Channel view immediately shows the new count and
current-User reacted state. Adding and removing reactions should both feel
instant and should not duplicate rows or leave stale pill state.

This slice focuses on the local viewer after their own click. Cross-view live
updates are handled in a later issue.

## Acceptance criteria

- [ ] Toggling a reaction locally refreshes the affected message's reaction
      summary.
- [ ] Adding a reaction updates the visible count and current-User reacted
      state.
- [ ] Removing a reaction updates the visible count and current-User reacted
      state.
- [ ] A reaction with count zero disappears from the visible summary.
- [ ] Repeated toggles do not create duplicate reaction rows.
- [ ] Only the affected message summary is refreshed where practical.
- [ ] Focused LiveView tests verify add and remove behavior through visible
      reaction pills.

## Blocked by

- 11. Add Fixed Reaction Palette Controls
