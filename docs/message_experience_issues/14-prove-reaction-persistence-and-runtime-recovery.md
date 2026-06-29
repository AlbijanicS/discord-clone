# Prove Reaction Persistence And Runtime Recovery

**Type:** AFK

**Blocked by:** 8. Add Durable Message Reaction Toggle, 9. Load Reaction Summaries For Rendered Messages

**User stories covered:** 26-27, 38-39

## What to build

Prove that reactions are durable product state and are not owned by the Channel
runtime. Reaction counts and current-User reacted state should survive page
refreshes and Channel runtime loss because they are loaded from Postgres.

This slice is primarily acceptance and regression coverage around the project's
durable-versus-temporary state boundary.

## Acceptance criteria

- [ ] Reaction summaries survive page refresh.
- [ ] Reaction summaries survive Channel runtime crash or restart.
- [ ] Reaction data remains available through Chat after ChannelServer state is
      lost.
- [ ] No reaction counts or reaction rows are stored in ChannelServer state.
- [ ] Documentation or comments clarify that reactions are Postgres-owned
      durable state where useful.
- [ ] Focused tests prove runtime loss does not delete or hide persisted
      reactions.

## Blocked by

- 8. Add Durable Message Reaction Toggle
- 9. Load Reaction Summaries For Rendered Messages
