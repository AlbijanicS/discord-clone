Status: ready-for-agent

# 16 — Split home_test.exs by feature area

## Parent

[Code-Health Refactor PRD](../code_health_refactor_prd.md)

## What to build

The home LiveView test file is very large (thousands of lines, many describe blocks
spanning unrelated features). Split it by feature area (for example: unread / read-state,
moderation, invites, channel management) into separate, navigable files. This is a pure
reorganization: no assertions are added, removed, or changed — the same tests run, just
grouped so failures are easier to locate.

## Acceptance criteria

- [ ] The oversized home test file is split into feature-area files.
- [ ] No assertion is changed; the total set of tests and their outcomes are identical.
- [ ] Test setup/fixtures remain readable and are shared without duplication where sensible.
- [ ] `mix precommit` is green.

## Blocked by

None - can start immediately.
