# Add Automatic Bidirectional History Loading

**Type:** AFK

**Blocked by:** 9. Add Sequence-Based Message Windows, 10. Replace Channel Mount With Landing Windows

**User stories covered:** 28-29, 31-32, 44-46

## What to build

Replace the manual `Load older` interaction with automatic scroll-edge loading
for older and newer Message pages. A Workspace Member should be able to move
through Channel history in either direction while the LiveView requests pages
by sequence number.

This slice should preserve scroll position when older Messages are prepended
and show edge loading states instead of relying on a manual button.

## Acceptance criteria

- [ ] The old manual `Load older` button is removed from the Channel timeline.
- [ ] The message container has a stable DOM ID for scroll-edge hooks and
      tests.
- [ ] Scrolling near the top requests older Messages before the current oldest
      sequence.
- [ ] Scrolling near the bottom requests newer Messages after the current
      newest sequence when newer history exists.
- [ ] The edge trigger distance starts around 300 pixels.
- [ ] Older and newer loading states prevent duplicate page requests.
- [ ] Loading older Messages preserves the visible scroll position.
- [ ] Loading newer Messages appends in sequence order.
- [ ] When a selected-Channel Message arrives while the User is away from latest,
      the LiveView marks newer history as available instead of force-loading or
      force-scrolling the Message into view.
- [ ] When the User is already at or near latest, incoming selected-Channel
      Messages append in sequence order and remain eligible for visible-read
      observation.
- [ ] Top and bottom loading indicators render while fetches are in flight.
- [ ] Empty Channels and end-of-history states render without broken controls.
- [ ] Focused LiveView tests verify event contracts and state transitions
      without raw HTML assertions, including selected-Channel incoming Messages
      while at latest and while reading older history.

## Blocked by

- 9. Add Sequence-Based Message Windows
- 10. Replace Channel Mount With Landing Windows
