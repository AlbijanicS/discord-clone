# Extract the pure unread-span algebra into its own module

**Source:** `docs/architecture_deepening_plan.md` — Steps #1 and #5 (prefactor)

## What to build

The `Chat` context holds a cluster of pure, total interval-algebra functions that
merge and subtract Unread Spans and convert message sequences into spans. They
have no database dependency, yet today they are private and reachable only
through a full transaction, so every edge case is exercised indirectly through
database round-trips and none is tested directly.

Move this pure algebra into its own module — the interval math only, expressed
over `{from, to}` integer tuples with no repository or schema references. The
`Chat` context keeps calling it internally; nothing about the public context API
changes. This is the prefactor that the `Chat.Unread` extraction builds on.

Add a dedicated test file that covers the algebra's edge cases directly and fast.

## Acceptance criteria

- [ ] A new module holds the interval algebra (merge, subtract, sequence→spans)
      with no repository or schema dependency.
- [ ] The `Chat` context delegates to it internally; the public context API is
      unchanged.
- [ ] A dedicated unit-test file covers: adjacent-span coalescing at `+1`,
      splitting one span into two, an over-large range, empty input, a single
      span, and fully-overlapping and disjoint inputs.
- [ ] Existing unread integration tests pass unchanged.
- [ ] `mix precommit` is green.

## Blocked by

None - can start immediately.
