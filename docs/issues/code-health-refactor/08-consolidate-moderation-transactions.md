Status: ready-for-agent

# 08 — Consolidate moderation-transaction functions

## Parent

[Code-Health Refactor PRD](../code_health_refactor_prd.md)

## What to build

Collapse the five near-identical moderation transaction functions in the Workspaces
context (mute, unmute, timeout, remove-timeout, expire) behind shared helpers. Each
currently repeats the same shape: build a moderation insert/update step, add an audit
insert step, run the transaction, then a copy-pasted `case` that broadcasts on success
and maps the two changeset-error branches. Introduce a `run_moderation_multi/2` that
owns the shared transaction-result handling, and an `end_moderation_with_audit` for the
three "end a moderation" variants (unmute, remove-timeout, expire) that differ only in
event type and success side effect. Behavior-preserving: the same audit events,
broadcasts, and timer scheduling/cancellation happen as before.

## Acceptance criteria

- [ ] The five moderation flows share one transaction-result helper and one end-moderation
      helper; no flow inlines the copy-pasted `case` any longer.
- [ ] Audit events written, PubSub broadcasts, and timeout timer scheduling/cancellation
      are unchanged for every flow.
- [ ] The moderation regression tests (issue 05) and existing Workspaces tests pass.
- [ ] `mix precommit` is green.

## Blocked by

- [05 — Latent-bug regression tests](05-latent-bug-regression-tests.md)
