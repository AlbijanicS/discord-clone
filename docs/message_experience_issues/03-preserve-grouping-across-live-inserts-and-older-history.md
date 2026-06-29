# Preserve Grouping Across Live Inserts And Older History

**Type:** AFK

**Blocked by:** 2. Add Simple Same-Author Message Grouping

**User stories covered:** 7-8, 33

## What to build

Make the message grouping behavior hold up when the timeline changes. New live
messages should appear with correct grouping relative to the current newest
message, and older-history pagination should preserve sensible grouping at the
boundary between newly prepended older messages and already rendered messages.

This slice should keep LiveView streams if grouping can remain correct with
bounded restreaming or boundary re-evaluation.

## Acceptance criteria

- [ ] A new live message from the same author within the grouping window renders
      as a compact continuation row.
- [ ] A new live message from another author renders as a full row.
- [ ] Loading older messages preserves correct grouping inside the older page.
- [ ] Loading older messages re-evaluates the boundary between older messages
      and the previously oldest rendered message.
- [ ] Existing scroll-to-bottom behavior after sending and receiving messages
      continues to work.
- [ ] Existing older-message pagination behavior continues to work.
- [ ] Focused tests cover live insert grouping and older-history boundary
      grouping.

## Blocked by

- 2. Add Simple Same-Author Message Grouping
