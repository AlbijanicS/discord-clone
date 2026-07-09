# Architecture deepening — issues

Vertical-slice issues broken out from `../architecture_deepening_plan.md`. Each
is independently grabbable and lands with `mix precommit` green. Contexts stay
the facade throughout, so the web layer is untouched except where a slice names
it.

| # | Issue | Blocked by |
|---|-------|-----------|
| 01 | [Unify message-delete permission](01-unify-message-delete-permission.md) | — |
| 02 | [Extract MemberActions helper](02-extract-member-actions-helper.md) | — |
| 03 | [Extract pure Chat.Unread.Spans](03-extract-unread-spans-pure-module.md) | — |
| 04 | [Extract Chat.Unread vertical](04-extract-chat-unread-vertical.md) | 03 |
| 05 | [Split Chat.PresenceEvents](05-split-workspace-presence-events.md) | — |
| 06 | [Chat.Runtime facade](06-introduce-chat-runtime-facade.md) | 05 |

**Startable now (parallel):** 01, 02, 03, 05
**Dependency edges:** 04 ← 03 · 06 ← 05
