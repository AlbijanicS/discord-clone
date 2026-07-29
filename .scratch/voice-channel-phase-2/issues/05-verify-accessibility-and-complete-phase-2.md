# 05 — Verify accessibility and complete Phase 2

**What to build:** The complete browser microphone spike is usable by keyboard and screen-reader users, passes its focused and project verification, and is recorded as complete in the Voice Channel roadmap only after all Phase 2 commitments are demonstrably met.

**Blocked by:** 02 — Preserve the Voice Owner Tab across authenticated navigation; 03 — Handle microphone failures and cleanup; 04 — Coordinate same-browser Voice Owner Tab takeover.

**Status:** ready-for-agent

- [ ] Voice Channel activation and global microphone controls use accessible button semantics and descriptive labels.
- [ ] The Voice controls popover supports Escape-to-close with sensible focus return, and important status transitions are announced without unexpectedly moving focus.
- [ ] LiveView and controller tests cover the settled visible behavior; the manual localhost checklist verifies real permission, release, navigation, takeover, and failure paths.
- [ ] `mix precommit` passes after application changes.
- [ ] Only after every Phase 2 build/proof criterion, automated check, and manual verification succeeds, the roadmap marks Phase 2 `Complete` and records concise implementation notes with date, files changed, final decisions, behavior proven, tests run, and follow-up work.
