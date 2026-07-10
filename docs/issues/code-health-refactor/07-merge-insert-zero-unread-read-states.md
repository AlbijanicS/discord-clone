Status: ready-for-agent

# 07 — Merge insert_zero_unread_read_states clauses

## Parent

[Code-Health Refactor PRD](../code_health_refactor_prd.md)

## What to build

The Unread submodule has two nearly identical private functions that bulk-insert
zero-unread Read State rows, differing only in whether the `user_id` comes from each
row or is a single shared value. Merge them behind one function that takes a small
row-shaping function (or equivalent), so Read State initialization has one code path.
Behavior-preserving; verified through the Chat/Unread context seam.

## Acceptance criteria

- [ ] There is one zero-unread Read State insertion path.
- [ ] Both the per-user-invite initialization and the per-channel-member initialization
      use it, with the same on-conflict behavior as before.
- [ ] Read State initialization behavior is unchanged as asserted by existing tests.
- [ ] `mix precommit` is green.

## Blocked by

None - can start immediately.
