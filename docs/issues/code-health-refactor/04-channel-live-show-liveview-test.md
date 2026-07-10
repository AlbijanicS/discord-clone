Status: ready-for-agent

# 04 — New seam: ChannelLive.Show LiveView test

## Parent

[Code-Health Refactor PRD](../code_health_refactor_prd.md)

## What to build

Add the one new test seam the refactor needs: a LiveView test for the channel view,
which currently has no dedicated LiveView-level test. It must exercise the channel
surface end-to-end through `Phoenix.LiveViewTest` so the later split of that file is
protected by a real safety net rather than only by context tests.

Cover: initial render of a Channel with messages; sending a message; deleting a
message; toggling a reaction; the unauthorized-access redirect (a non-member or
missing Workspace/Channel is redirected with a flash); and moderation-menu visibility
for different actor/target Workspace Role combinations, including that a forged
member-action event from a non-permitted actor is rejected through the LiveView event
path (not only at the context).

## Acceptance criteria

- [ ] A LiveView test file for the channel view exists and passes.
- [ ] Render, send-message, delete-message, and toggle-reaction paths are asserted via
      stable DOM IDs and LiveView helpers (no raw-HTML assertions).
- [ ] The unauthorized-access redirect + flash is asserted.
- [ ] Moderation-menu affordances are asserted present for permitted and absent for
      forbidden actor/target Role pairs.
- [ ] A forged member-action event from a non-permitted actor produces no state change.
- [ ] `mix precommit` is green.

## Blocked by

None - can start immediately. (Prior art: the home LiveView test and the invite
controller test.)
