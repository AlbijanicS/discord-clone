Status: ready-for-agent

# 11 — Batched available_member_actions (N+1 fix)

## Parent

[Code-Health Refactor PRD](../code_health_refactor_prd.md)

## What to build

Fix the N+1 when the channel view builds the per-member action map. Computing available
member actions for a Workspace Member currently issues roughly three queries per member
(actor role, active mute, active timeout), and the channel view runs it across the whole
member list on mount and again on every moderation refresh. Add a batched availability
function that loads the active moderations for all target Workspace Members in one query
and computes each member's action set in memory, fetching the actor's Role once. The
channel view uses it for the initial member-action map and on refresh.

## Acceptance criteria

- [ ] A batched member-action availability function exists that does not scale query count
      linearly with the number of members.
- [ ] The channel view uses it in mount and on moderation refresh.
- [ ] The action sets produced (including mute→unmute and timeout→remove-timeout swaps,
      and empty sets for self/owner targets) match the per-member behavior exactly, as
      asserted by a context test over a mixed-state member list.
- [ ] `mix precommit` is green.

## Blocked by

- [05 — Latent-bug regression tests](05-latent-bug-regression-tests.md)
