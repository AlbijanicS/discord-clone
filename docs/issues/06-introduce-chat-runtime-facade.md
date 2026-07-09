# Collapse the runtime wrappers behind a deep Chat.Runtime facade

**Source:** `docs/architecture_deepening_plan.md` — Step #2

## What to build

The chat runtime is spread across five modules with three shallow pass-throughs:
a single presence-join is three hops through wrapper modules whose interfaces are
as complex as their bodies. The `Chat` context reaches into five runtime modules
directly, and the runtime tests couple to the process topology (registries and
internal server state).

Introduce one deep facade that becomes the single door for all runtime
operations. It owns every piece of process machinery: registry lookups, starting
supervised processes, the ensure-a-process-exists pattern, and the timeout-expiry
scheduling (including the coordination that currently reaches from the chat
runtime into the workspaces context). The two GenServers are demoted to
state-only — they keep their state operations but no longer expose lookup or
start-or-create to callers. Absorb the presence PubSub plumbing left over from
the previous issue into the facade. Delete the three now-empty wrapper modules;
the OTP supervisors and registries themselves stay in the supervision tree.

After this, nothing outside the facade references a registry or a dynamic
supervisor for the chat runtime. Rework the runtime tests to drive behavior
through the facade and assert on observable outcomes (presence lists, delivered
messages) rather than poking at registries or internal server state, following
the project's test guidance (supervised start, monitor-and-assert-down, no
sleeps).

## Acceptance criteria

- [ ] A single facade module is the only place that references the registries or
      dynamic supervisors for the chat runtime.
- [ ] The two GenServers expose only their state operations; lookup and
      start-or-create live in the facade.
- [ ] The three wrapper modules are deleted; the supervision tree in the
      application startup is unchanged.
- [ ] The presence PubSub plumbing lives in the facade; the web layer is
      unchanged except the presence-events alias from the previous issue.
- [ ] Runtime tests assert through the facade seam, not the process topology.
- [ ] `mix precommit` is green.

## Blocked by

- `docs/issues/05-split-workspace-presence-events.md` (the facade absorbs the
  presence plumbing left after the split).
