Status: ready-for-agent

# 14 — Split ChannelLive.Show: management events + read-range validation

## Parent

[Code-Health Refactor PRD](../code_health_refactor_prd.md)

## What to build

Continue breaking up the channel LiveView. Extract the workspace/channel management
event handlers (create/rename/delete Workspace and Channel, and the related menu/form
state) into a module reusable by the home and entry LiveViews — verify against the
existing home LiveView before extracting so the shared module fits both. Separately,
consolidate the visible-read-range validation so it is performed once: the channel view
currently pre-validates ranges that the Unread context then re-validates; keep only the
cheap shape parsing in the view and rely on the context for the authoritative check.
Behavior-preserving; protected by the channel LiveView test.

## Acceptance criteria

- [ ] Workspace/Channel management event handling is shared, not duplicated between the
      channel view and the home/entry views.
- [ ] Visible-read-range validation is not duplicated across the web and context layers;
      the context is the authoritative validator.
- [ ] The channel LiveView test (issue 04) and existing read-state/unread tests pass.
- [ ] Management and read-observation behavior is unchanged.
- [ ] `mix precommit` is green.

## Blocked by

- [04 — ChannelLive.Show LiveView test](04-channel-live-show-liveview-test.md)
