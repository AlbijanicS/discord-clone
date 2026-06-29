# Load Reaction Summaries For Rendered Messages

**Type:** AFK

**Blocked by:** 8. Add Durable Message Reaction Toggle

**User stories covered:** 21-22, 29, 36

## What to build

Expose a bounded reaction-summary read path through Chat. A Channel viewer
should be able to load reaction summaries for the messages currently rendered
in the timeline, including each emoji count and whether the current User has
reacted.

This slice should make reaction data available to the web layer without
rendering reaction pills yet.

## Acceptance criteria

- [ ] Chat exposes a public workflow for loading reaction summaries for a
      bounded list of message IDs.
- [ ] The workflow requires an authenticated scope.
- [ ] The workflow verifies Workspace membership through the messages'
      Channels.
- [ ] Summaries are keyed by message ID.
- [ ] Each summary includes emoji counts.
- [ ] Each summary includes whether the current User reacted for each emoji.
- [ ] The current User's reacted state is viewer-specific.
- [ ] Summary loading avoids one query per message.
- [ ] The Channel LiveView can assign reaction summaries for initially loaded
      recent messages without rendering pills yet.
- [ ] Focused Chat context tests cover counts, viewer-specific reacted state,
      scoping, and bounded loading.

## Blocked by

- 8. Add Durable Message Reaction Toggle
