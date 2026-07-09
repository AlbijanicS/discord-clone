# Split the pure presence-event translation out of WorkspacePresence

**Source:** `docs/architecture_deepening_plan.md` — Step #2 (prefactor)

## What to build

The presence module mixes two unrelated concerns behind one name: a pure
event-translation half (turning raw PubSub messages into presence events), which
the web layer uses directly in three LiveViews, and a PubSub plumbing half
(subscribe, broadcast, topic), which only the runtime uses.

Split off the pure translation into its own small stateless module and point the
three LiveViews at it. Exposing a pure value-translation module to the web layer
is fine — it holds no state, like a view helper. Leave the plumbing where it is
for now; the next issue absorbs it into the runtime facade. This prefactor
isolates the pure half so the facade work has a clean seam to build against.

## Acceptance criteria

- [ ] A new stateless module holds the presence-event translation functions.
- [ ] The three LiveViews that translate presence events use the new module.
- [ ] Presence behavior in the UI is unchanged.
- [ ] `mix precommit` is green.

## Blocked by

None - can start immediately.
