# Replace Channel Mount With Landing Windows

**Type:** AFK

**Blocked by:** 8. Add Channel Open Landing Decisions, 9. Add Sequence-Based Message Windows

**User stories covered:** 1, 4-5, 15-17, 25-28, 38, 46

## What to build

Update the Channel LiveView mount flow to use the new open-channel landing
decision and sequence-based message windows. A Workspace Member should enter a
Channel at the right unread, anchor, or latest window without clearing unread
state.

This slice keeps the current route placement and authenticated LiveView
session unchanged.

## Acceptance criteria

- [ ] Channel LiveView remains in the existing authenticated browser pipeline
      and existing `live_session :require_authenticated_user`.
- [ ] The route placement is unchanged because the workflow requires
      `current_scope`, an authenticated User, and Workspace membership.
- [ ] Disconnected mount avoids side effects and renders a safe initial state.
- [ ] Connected mount calls the Chat open-channel workflow.
- [ ] Connected mount removes the old read-on-open side effect and does not call
      cursor-based `mark_channel_read`.
- [ ] Mount loads the Message window selected by the landing decision.
- [ ] Opening a Channel with unread does not mark it read.
- [ ] Small unread backlog opens near the oldest unread Message.
- [ ] Large unread backlog opens near recent unread Messages.
- [ ] No-unread Channels reopen around `last_viewed_anchor_seq` when present.
- [ ] No-unread Channels with no anchor load latest Messages.
- [ ] The existing Channel message hook no longer blindly scrolls to bottom on
      mount; scrolling is driven by the selected landing target.
- [ ] Selected-Channel incoming Messages are appended and observed only when the
      loaded window is at or near latest.
- [ ] If the User is reading older history, selected-Channel incoming Messages do
      not force-scroll or inject distant latest Messages into the current
      window; the LiveView updates newer-history metadata and keeps a latest
      navigation affordance available.
- [ ] The LiveView uses stable DOM IDs for the message window and key controls.
- [ ] Focused LiveView tests verify landing outcomes and unread preservation
      through public UI behavior, including no read-on-open and no forced
      scrolling away from older history.

## Blocked by

- 8. Add Channel Open Landing Decisions
- 9. Add Sequence-Based Message Windows
