# Unify the message-delete permission rule

**Source:** `docs/architecture_deepening_plan.md` — Step #3

## What to build

The rule for who may delete a message — *actor `owner|admin` may delete a
message authored by `admin|member`; any author may delete their own* — currently
exists twice: enforced in the `Chat` context and independently re-derived in the
channel LiveView to decide whether to render the delete affordance. The two can
drift, so the UI can offer a delete the context then rejects, or hide one it
would allow.

Collapse the rule to a single source of truth: one pure predicate over the two
roles. The context's delete enforcement resolves the actor and author roles and
calls it. A new public capability predicate on `Chat` answers the same question
for the UI, reading the membership map the LiveView has already loaded so it adds
no per-message database queries. The LiveView drops its private re-derivation and
asks the context instead.

Leave the sidebar's role-grouping code alone — grouping members by role for
display is not a permission check.

## Acceptance criteria

- [ ] A single pure predicate expresses the delete rule; both the context's
      enforcement path and the new UI-facing capability predicate call it.
- [ ] The channel view decides whether to show the delete control by asking the
      `Chat` context, not by re-deriving role logic locally.
- [ ] No role strings (`"owner"`, `"admin"`, `"member"`) or deletable-role sets
      remain hard-coded in the web layer for this decision.
- [ ] No additional database queries are introduced in the message render path.
- [ ] Existing delete-authorization tests pass unchanged.
- [ ] `mix precommit` is green.

## Blocked by

None - can start immediately.
