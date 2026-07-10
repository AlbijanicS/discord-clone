Status: ready-for-agent

# 10 — Route Chat rules through Workspaces

## Parent

[Code-Health Refactor PRD](../code_health_refactor_prd.md)

## What to build

Stop the Chat context from re-implementing rules the Workspaces context owns. Chat
currently queries the moderation table directly (with raw type strings) to decide
whether a Workspace Member is muted or timed out, and re-implements the
owner/admin-may-delete-admin/member message-delete rule. Expose the needed capability
functions from Workspaces (a participation/mute-timeout check, and the message-delete
capability) and have Chat call them, so "blocked from participating" and "may delete
this message" each live in one context. Membership reads for channel-access checks may
remain in Chat (hot path), but the moderation and delete-rule decisions route through
Workspaces. Keeps the dependency acyclic (Chat → Workspaces).

## Acceptance criteria

- [ ] Chat no longer queries the moderation table with raw type strings to decide
      participation; it calls a Workspaces capability.
- [ ] The message-delete capability rule has a single definition used by both the context
      enforcement path and the UI affordance.
- [ ] Send/react/typing blocking on mute/timeout and message-delete authorization behave
      exactly as before (context and LiveView tests pass).
- [ ] No cyclic dependency is introduced.
- [ ] `mix precommit` is green.

## Blocked by

- [09 — Introduce Workspaces.Roles](09-introduce-workspaces-roles.md)
