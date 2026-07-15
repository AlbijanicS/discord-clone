# 03 — Navigate to Reply Parents and Handle Deleted Targets

**What to build:** Make live reply previews navigate to and temporarily highlight their exact parent Message, even when that Message is outside the currently loaded window. Preserve existing replies when a parent is soft-deleted, replace its preview with a non-clickable deleted-message placeholder, and recover safely if a selected composer target is deleted concurrently.

**Blocked by:** 02 — Send and Display Flat Message Replies.

**Status:** ready-for-agent

- [ ] Exact-message navigation resolves the requested Message and sequence through an authorized Chat workflow.
- [ ] Navigation loads a sequence-centered window, scrolls to the target row, and applies a temporary visual highlight.
- [ ] Invalid, deleted, wrong-Channel, and inaccessible target identifiers produce the same privacy-safe not-found outcome.
- [ ] Clicking a live reply preview navigates to its direct parent, including when the parent is outside the current window.
- [ ] Soft-deleting a parent preserves existing replies but replaces author/content preview data with a non-clickable deleted-message placeholder.
- [ ] If a selected reply target is deleted before send, the draft is preserved, the stale target is cleared, and specific feedback is shown.
- [ ] Context and authenticated Channel LiveView tests cover live, out-of-window, deleted, and inaccessible targets through stable selectors.
- [ ] `mix precommit` passes.
