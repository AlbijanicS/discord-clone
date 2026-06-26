# Channel Runtime Recovery And Failure PRD

Status: implemented

Implemented in the recovery pass with:

- Channel LiveView runtime monitoring that clears temporary typing indicators
  after ChannelServer loss.
- Chat context tests for typing recovery and send/broadcast recovery after
  runtime loss.
- LiveView recovery coverage for stale typing indicators.
- A fault-tolerance note in `docs/channel_runtime_fault_tolerance.md`.

## Problem Statement

The Discord clone now has durable workspaces, channels, messages, live message
delivery, workspace-scoped presence, supervised Channel runtimes, recent message
caching, and runtime-owned typing indicators. The app works through the main
loop: authenticated member enters a Workspace, opens a Channel, reads messages,
sends messages, receives live updates, and sees typing indicators.

The remaining learning gap is explicit failure confidence. Channel runtimes own
temporary state, so crashes and idle shutdowns should be boring: durable
messages must recover from Postgres, temporary typing state may disappear, and
LiveViews should keep using public Chat workflows rather than reaching around
the runtime boundary. Without a small recovery pass, the code may work, but the
OTP learning goal is less clear.

## Solution

Add a focused recovery and failure acceptance pass for Channel runtime behavior.

This pass should verify, document, and lightly tighten the existing runtime
boundary. It should prove that ChannelServer crashes do not lose persisted
messages, that a later authorized Chat workflow restarts the runtime and rebuilds
recent messages, and that temporary typing state is intentionally lost or
expires rather than being recovered from durable storage.

The output should include tests plus a short fault-tolerance note that explains
which state is durable, which state is temporary, and how recovery happens.

## User Stories

1. As a workspace member, I want messages to remain available after a Channel runtime crashes, so that process failure does not cause message loss.
2. As a workspace member, I want reopening or reading a Channel after runtime loss to work normally, so that recovery is invisible in normal use.
3. As a workspace member, I want newly sent messages after runtime loss to be persisted and shown, so that a restarted runtime does not block chat.
4. As a workspace member, I want recent messages to reload from Postgres after runtime loss, so that durable history remains the source of truth.
5. As a workspace member, I want older-history loading to remain Postgres-backed, so that pagination is not affected by runtime crashes.
6. As a workspace member, I want stale typing indicators to disappear after runtime loss, so that temporary state does not pretend to be durable.
7. As a workspace member, I want typing to work again after the Channel runtime restarts, so that live behavior recovers naturally.
8. As a workspace member, I want workspace online status to remain workspace-scoped, so that Channel runtime recovery does not create channel presence.
9. As a developer, I want tests to kill or stop Channel runtimes deliberately, so that failure behavior is proven rather than assumed.
10. As a developer, I want recovery tests to use public Chat APIs where possible, so that OTP internals stay hidden behind the context boundary.
11. As a developer, I want ChannelServer-focused tests only where process lifecycle behavior needs direct OTP observation, so that tests remain clear.
12. As a developer, I want no sleeps in recovery tests, so that the suite stays deterministic and fast.
13. As a developer, I want Process.monitor and DOWN assertions for runtime exits, so that tests synchronize with process lifecycle correctly.
14. As a developer, I want runtime restart behavior to use durable Channel IDs, so that Channel names never become process identity.
15. As a developer, I want a short fault-tolerance note, so that future maintainers know which state can be lost safely.
16. As a learner, I want crashes to feel boring, so that OTP supervision and durable state boundaries are concrete.

## Implementation Decisions

- Treat this as Phase 9 from the implementation roadmap.
- Do not add new user-facing product behavior.
- Do not add schema changes or migrations.
- Do not add routes or change router placement.
- Keep Channel LiveViews in the existing authenticated browser pipeline and authenticated LiveView session because Channel access depends on `current_scope` and Workspace membership.
- Keep `DiscordClone.Chat` as the public boundary for runtime workflows.
- Continue hiding Registry, DynamicSupervisor, ChannelServer, Repo, and PubSub details from LiveViews for runtime workflows.
- Use `DiscordClone.Chat.ChannelServer` as the deep runtime module that owns temporary Channel state behind a small interface.
- Use `DiscordClone.Chat.ChannelSupervisor` and the existing Registry for restart/lookup behavior.
- Keep persisted messages in Postgres as the durable source of truth.
- Keep recent message cache rebuilds bounded to the existing latest-message limit.
- Treat typing users and typing deadlines as temporary state.
- Do not recover typing state from Postgres because it is not persisted.
- Preserve workspace-scoped presence as separate from Channel runtime recovery.
- Add or update a short docs note describing recovered durable state, lost temporary state, and existing direct PubSub limitations.
- If the roadmap still implies channel-scoped online presence, update the wording to match the current architecture: workspace presence is workspace-scoped; Channel runtime owns recent cache and typing state.

## Testing Decisions

- Good tests for this pass should verify observable behavior through public interfaces, not private implementation details.
- Chat context tests should prove that messages remain listable after a Channel runtime is killed.
- Chat context tests should prove that sending after runtime loss persists first, restarts/reuses runtime behavior, updates the cache, and broadcasts normally.
- LiveView tests should prove that a Channel page can render persisted messages after runtime loss.
- ChannelServer tests may directly monitor process exits when proving idle shutdown, crash, or registration cleanup behavior.
- Tests should use `Process.monitor/1` and `assert_receive {:DOWN, ...}` instead of `Process.sleep/1`.
- Tests should use `_ = :sys.get_state/1` only as a synchronization point when needed.
- Prior art exists in the Channel runtime tests for idle shutdown and restart.
- Prior art exists in Chat context tests for runtime loss, recent-message recovery, send-after-runtime-loss, typing APIs, and PubSub behavior.
- Prior art exists in Channel LiveView tests for rendering persisted messages after runtime loss, live delivery, typing display, and workspace presence behavior.
- Run the focused runtime, Chat, and Workspace LiveView suites before `mix precommit`.

## Out of Scope

- Replacing direct PubSub with an outbox.
- Persisting typing state.
- Persisting online status.
- Adding channel-scoped online presence.
- Adding unread counts, reactions, mentions, direct messages, attachments, edits, or deletes.
- Adding distributed process registry behavior across multiple BEAM nodes.
- Adding production observability, metrics, dashboards, or alerting.
- Changing authentication, route scopes, or LiveView session placement.
- Refactoring the whole Chat context.

## Further Notes

This PRD is intentionally small. The main app loop is already healthy, so the
next work should make the runtime failure model explicit rather than adding a
new feature. After this pass, the project can move into polish and stretch
features with a clearer foundation.
