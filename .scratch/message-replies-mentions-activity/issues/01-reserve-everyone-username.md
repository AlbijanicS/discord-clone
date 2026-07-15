# 01 — Reserve `everyone` as a Username

**What to build:** Make `everyone` a reserved username across registration and username-change workflows so the Everyone Mention always has one deterministic meaning. Before enforcing the rule, provide a safe check for conflicting existing data and preserve all current username normalization and uniqueness behavior.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] Existing data can be checked safely for a username that normalizes to `everyone` before the constraint is enabled.
- [ ] Registration rejects `everyone` regardless of letter case and reports a field-level validation error.
- [ ] Username changes reject `everyone` through the same public Accounts behavior.
- [ ] Other username normalization and uniqueness behavior remains unchanged.
- [ ] Authenticated and unauthenticated form behavior is covered at the existing Accounts and LiveView seams.
- [ ] `mix precommit` passes.
