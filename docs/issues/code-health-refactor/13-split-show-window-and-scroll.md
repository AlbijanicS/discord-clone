Status: ready-for-agent

# 13 — Split ChannelLive.Show: window state + scroll anchoring

## Parent

[Code-Health Refactor PRD](../code_health_refactor_prd.md)

## What to build

Begin breaking up the 2,297-line channel LiveView by peeling off two self-contained
concerns into their own modules: the message-window state (the trim / merge / boundary /
window-meta family that maintains the rendered window as messages arrive and the user
scrolls) and the scroll-anchoring helpers (the preserve/restore-scroll payload building
and numeric parsing). The channel view calls into these instead of owning the logic
inline. Behavior-preserving; protected by the new channel LiveView test.

## Acceptance criteria

- [ ] Message-window state management lives in its own module, called by the channel view.
- [ ] Scroll-anchoring helpers live in their own module, called by the channel view.
- [ ] The channel LiveView test (issue 04) and existing Chat pagination tests pass.
- [ ] Scrolling, trimming, and message-arrival behavior is unchanged.
- [ ] `mix precommit` is green.

## Blocked by

- [04 — ChannelLive.Show LiveView test](04-channel-live-show-liveview-test.md)
- [06 — Extract Chat.MessageWindow](06-extract-chat-message-window.md)
