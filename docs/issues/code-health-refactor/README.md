# Code-Health Refactor — Issue Breakdown

Vertical slices (and expand–contract sequences) derived from
[`../../code_health_refactor_prd.md`](../../code_health_refactor_prd.md).

This set is separate from the earlier "Architecture deepening" issues in the parent
directory. Every issue here is behavior-preserving unless it explicitly says otherwise,
and every issue must leave `mix precommit` green before it is considered done
(PRD Story 25).

## Dependency order

| # | Title | Blocked by |
|---|-------|-----------|
| [01](01-uuid-cast-fallback-helper.md) | UUID cast-or-fallback helper | — |
| [02](02-component-attr-types-and-coordinate-parsing.md) | Component `attr` types + defensive coordinate parsing | — |
| [03](03-resolve-test-only-chat-api-and-typing-topic.md) | Resolve test-only `Chat` API + typing-topic redundancy | — |
| [04](04-channel-live-show-liveview-test.md) | New seam: `ChannelLive.Show` LiveView test | — |
| [05](05-latent-bug-regression-tests.md) | Latent-bug regression tests | — |
| [06](06-extract-chat-message-window.md) | Extract `Chat.MessageWindow` | — |
| [07](07-merge-insert-zero-unread-read-states.md) | Merge `insert_zero_unread_read_states` clauses | — |
| [08](08-consolidate-moderation-transactions.md) | Consolidate moderation-transaction functions | 05 |
| [09](09-introduce-workspaces-roles.md) | Introduce `Workspaces.Roles` + migrate callers | — |
| [10](10-route-chat-rules-through-workspaces.md) | Route `Chat` rules through `Workspaces` | 09 |
| [11](11-batched-available-member-actions.md) | Batched `available_member_actions` (N+1 fix) | 05 |
| [12](12-normalize-context-error-tuples.md) | Normalize public context error tuples | — |
| [13](13-split-show-window-and-scroll.md) | Split `ChannelLive.Show`: window state + scroll anchoring | 04, 06 |
| [14](14-split-show-management-events-and-read-range.md) | Split `ChannelLive.Show`: management events + read-range validation | 04 |
| [15](15-runtime-docs-note.md) | Runtime docs note (lazy timeout expiry) | — |
| [16](16-split-home-test-by-feature.md) | Split `home_test.exs` by feature area | — |
| [17](17-add-credo-strict.md) | Add Credo (strict) + fix/annotate | 06–14 |
| [18](18-add-specs-and-docs.md) | Add `@spec`/`@doc` to touched public APIs | 12 |

Issues 01–07, 09, 12, 15, 16 have no blockers and can be picked up immediately.
