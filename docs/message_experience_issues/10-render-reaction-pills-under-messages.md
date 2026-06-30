# Render Reaction Pills Under Messages

**Type:** AFK

**Blocked by:** 5. Review Timeline Feel Before Adding Reactions, 9. Load Reaction Summaries For Rendered Messages

**User stories covered:** 18, 21-22, 29

## What to build

Render loaded reaction summaries under each message body as compact reaction
pills. A Workspace Member should see the emoji, count, and whether they have
already reacted, without being able to add new reactions from the palette yet.

This slice should attach reaction display to the reviewed timeline layout while
keeping mutation controls for a later issue.

## Acceptance criteria

- [x] Reaction pills render under messages with reaction summaries.
- [x] Each pill shows the emoji and count.
- [x] Pills for the current User's reactions have a distinct visual state.
- [x] Messages without reactions do not show empty reaction chrome.
- [x] Reaction pill layout works for full rows and compact grouped rows.
- [x] Reaction pill buttons or containers have stable DOM IDs for tests.
- [x] Reaction pills include accessible labels.
- [x] Focused LiveView tests verify reaction pill rendering and current-User
      reacted state through selectors.

## Blocked by

- 5. Review Timeline Feel Before Adding Reactions
- 9. Load Reaction Summaries For Rendered Messages
