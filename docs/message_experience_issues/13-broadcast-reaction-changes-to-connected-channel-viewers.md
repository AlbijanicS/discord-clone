# Broadcast Reaction Changes To Connected Channel Viewers

**Type:** AFK

**Blocked by:** 12. Refresh Reaction Summaries After Local Toggle

**User stories covered:** 25, 37

## What to build

Broadcast successful reaction changes through a Chat-owned PubSub contract so
other connected Channel viewers refresh the affected message's reaction
summary without a page reload. Broadcast payloads should stay small and should
not include full Message, User, or reaction-row records.

This slice should preserve the existing channel message event contract while
adding a clear reaction-change event.

## Acceptance criteria

- [ ] Successful reaction toggles broadcast a Chat-owned reaction-change event.
- [ ] The event payload is small, such as message ID and emoji.
- [ ] PubSub topic construction remains private to Chat.
- [ ] Channel LiveViews subscribe through public Chat APIs.
- [ ] Connected viewers refresh authorized reaction summaries after receiving
      the event.
- [ ] The reaction event does not insert timeline messages.
- [ ] The existing message-created event behavior continues to work.
- [ ] Focused LiveView or PubSub tests prove another connected viewer can see a
      refreshed reaction count without page reload where practical.

## Blocked by

- 12. Refresh Reaction Summaries After Local Toggle
