# 06 — Open an Activity Item at Its Exact Source Message

**What to build:** Let a User open one Activity Item, mark only that item read, and navigate to the exact source Message using the same authorized, sequence-centered navigation behavior as reply previews. Unauthorized or unavailable destinations must not reveal whether the source Message exists.

**Blocked by:** 03 — Navigate to Reply Parents and Handle Deleted Targets; 05 — Browse the Global Activity Feed.

**Status:** ready-for-agent

- [ ] Opening a valid Activity Item marks only that recipient's selected item read and refreshes the unread bell count.
- [ ] The User is navigated to the source Workspace, Channel, and exact Message.
- [ ] Out-of-window source Messages are loaded, scrolled into view, and temporarily highlighted.
- [ ] Invalid, deleted, wrong-Channel, missing, and inaccessible sources return a consistent privacy-safe outcome.
- [ ] Reading one Activity Item does not clear all Activity Items or the entire Channel's unread state.
- [ ] Actually observed Channel ranges may follow existing visibility behavior without treating Activity read state as Channel Read State.
- [ ] Public Chat and authenticated LiveView tests cover individual read behavior, navigation, out-of-window loading, and safe failures.
- [ ] `mix precommit` passes.
