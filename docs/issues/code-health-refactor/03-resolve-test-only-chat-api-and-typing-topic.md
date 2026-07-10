Status: ready-for-agent

# 03 — Resolve test-only Chat API + typing-topic redundancy

## Parent

[Code-Health Refactor PRD](../code_health_refactor_prd.md)

## What to build

Tighten the Chat context's public surface. Several public Chat functions are called
only from tests and never from production code (subscribe-to-typing, add-unread-range,
clear-unread, list-recent-messages, list-older-messages). For each, either delete it
(if the behavior it covers is reachable through another public function the tests can
use instead) or explicitly mark it as a deliberate test seam. Resolve the typing
subscription redundancy: today the typing subscription targets the same PubSub topic
as the message subscription, and the channel view bypasses it with a private no-op
stub — decide on either a dedicated typing topic that the view actually uses, or
remove the separate function.

## Acceptance criteria

- [ ] Each test-only public Chat function is either removed or clearly annotated as a
      test seam, with tests still passing.
- [ ] Typing subscription is no longer a silent duplicate of the message subscription:
      it either has its own topic that the channel view uses, or it no longer exists as
      a separate public function.
- [ ] No production caller loses functionality; presence/typing behavior at the channel
      view is unchanged.
- [ ] `mix precommit` is green.

## Blocked by

None - can start immediately.
