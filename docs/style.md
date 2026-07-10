# Project Style Guide

This guide is for every agent working on the Discord clone from this point
forward. The next phases are the core learning goal of the project: OTP,
in-memory state, process lifecycle, supervision, and recovery. Treat this work
as the spine of the project, not as a quick feature pass.

## Working Posture

- Move in small, reviewable slices.
- Prefer boring, idiomatic Elixir over clever abstractions.
- Make state ownership explicit.
- Keep every step easy to explain against the project's docs and learning goals.
- Prefer established Phoenix, OTP, Ecto, and well-maintained ecosystem
  capabilities over custom infrastructure when they fit the problem.
- Do not jump ahead from process foundation into presence, typing, rate limits,
  or UI polish until the current slice is proved.
- Run focused tests first, then `mix precommit` after implementation changes.

The goal is not to build a production Discord clone. The goal is to understand
why OTP exists, when processes should own state, and how Phoenix, PubSub,
Postgres, and supervised processes fit together.

## Implementation Standard Going Forward

Future features should use the best available production-shaped option before
building custom project-specific infrastructure.

Decision order:

1. Use official Phoenix/Ecto/LiveView/OTP features when they fit.
2. Use a proven, actively maintained library when the framework does not cover
   the problem directly.
3. Build custom infrastructure only when the project has a clear learning goal,
   product requirement, or integration constraint that the existing options do
   not satisfy.

Examples:

- Prefer Phoenix Presence for future presence-style features instead of
  expanding the current hand-rolled presence runtime.
- Prefer Phoenix Channels when a feature needs channel/socket semantics beyond
  LiveView events and PubSub subscriptions.
- Prefer LiveView uploads and Phoenix-supported upload patterns for file and
  image upload flows.
- Document any deliberate custom implementation with the reason it is better
  for this project than the available framework or library option.

## Near-Term Product Direction

The next product slices should be planned in this order:

1. Simple role-based permissions with `owner`, `admin`, and `user` roles.
2. File and image uploads in messages.
3. Voice-channel simulation before any real audio implementation.

The permissions slice should come first because channel read/send/manage
capabilities will shape uploads, voice channels, private channels, unread
fanout, and future moderation behavior.

## Architectural Boundaries

Keep the existing core/web split intact.

- `lib/discord_clone` owns application behavior, contexts, schemas, Ecto
  queries, PubSub orchestration, and OTP processes.
- `lib/discord_clone_web` owns routes, controllers, LiveViews, components,
  forms, hooks, and rendering.
- LiveViews call public context APIs such as `DiscordClone.Workspaces` and
  `DiscordClone.Chat`.
- LiveViews must not directly call `Repo`, `DynamicSupervisor`, `Registry`, or
  internal channel process modules.
- OTP internals should live under `DiscordClone.Chat.*` and be hidden behind
  `DiscordClone.Chat`.

If a web module needs to enter a channel, send a typing event, query presence,
or interact with a channel process, add a public `DiscordClone.Chat` function
for that workflow.

## Durable Versus In-Memory State

Use this rule throughout the project:

```text
Important forever?
  -> Postgres

Useful right now?
  -> GenServer/process state
```

Persist in Postgres:

- users
- workspaces
- workspace memberships
- channels
- workspace invites
- messages

Keep in process state:

- online users for a channel
- typing users for a channel
- recent-message cache
- rate-limit counters
- last activity timestamp
- inactivity timers

Temporary process state may be lost on crash. That is acceptable and should be
tested and documented. Durable messages and membership rules must remain
recoverable from Postgres.

## OTP Style

Use standard OTP primitives directly:

- `GenServer`
- `Registry`
- `DynamicSupervisor`
- regular `Supervisor` children in `DiscordClone.Application`
- `Process.monitor/1` where lifecycle tracking is needed

Do not add helper libraries or macro wrappers for OTP. Saša Jurić's own
current guidance around GenServer examples points toward using regular
`GenServer`, and this project should keep the learning mechanics visible.

Preferred shape for process modules:

- public API functions at the top
- `start_link/1`
- small `child_spec/1` only when the default child spec is not enough
- explicit `via_tuple/1` or registry helper where useful
- callbacks grouped by callback type
- small private helpers for state transitions

Prefer messages and state that are easy to inspect in tests. Avoid hiding core
process behavior behind broad helper functions that make supervision and
recovery harder to understand.

## Channel Process Direction

The next major target is the channel process foundation.

Expected modules:

- `DiscordClone.Chat.ChannelRegistry`
- `DiscordClone.Chat.ChannelSupervisor`
- `DiscordClone.Chat.ChannelServer`

Expected first slice:

- start/find a channel process by durable `channel_id`
- register processes by channel ID, not by channel name
- expose lookup/start through `DiscordClone.Chat`
- initialize minimal channel state
- prove that entering a channel starts or finds the process
- prove that duplicate processes are not created for one channel
- prove that durable messages are not lost if the process crashes

Do not add presence and typing in the same slice as the initial process
foundation. Those should come after process startup, lookup, and recovery are
boring.

## Runtime Timers and Lazy Expiry

The runtime processes hold timers, but the database — not a timer firing on time —
is the source of truth. Timers are an optimization for the online case; the
correct state is always recoverable from Postgres.

**Member-timeout expiry (`WorkspaceServer`).** When a member timeout is created,
its expiry is scheduled as an active future timer inside that workspace's
presence process. Because the presence process only runs while someone is online,
the timer exists only when it can. Timers are re-scheduled whenever presence
starts — `join_workspace_presence/3` calls `schedule_existing_timeout_expiries/1`,
which reloads the active future timeouts from Postgres and re-arms them. If no one
is online when a timeout elapses, no timer fires at the deadline; the timeout is
instead expired lazily on the next relevant action (moderation queries treat a
timeout whose `expires_at` has passed as already inactive, and the next check
writes the expiry audit event). So a timeout's *effect* ends exactly at its
`expires_at`; only the audit-writing side effect may lag until the next action or
the next time presence starts. `expire_member_timeout/1` re-checks `expires_at`
before writing, so a stale or duplicate timer cannot expire a timeout early.

**Channel runtime (`ChannelServer`).** A channel process caches recent messages
and transient typing indicators. Both are in-memory only: on the 15-minute idle
shutdown or on a crash they reset, and the supervisor reloads recent messages
from Postgres on next start. Durable messages, reactions, and read state survive;
the cache and typing set do not, and that is intentional.

**Disconnect-grace window (`@disconnect_grace_ms 50`).** When a member's LiveView
process goes `:DOWN`, the presence server does not broadcast "user left"
immediately — it schedules a 50 ms grace timer and keeps the user in
`online_user_ids` meanwhile. This is intentional: navigating between channels in
the same workspace unmounts one LiveView a few milliseconds before the next one
joins, and without the grace window presence would flicker offline→online on
every navigation. A rejoin within the window cancels the pending-left timer, so a
genuine disconnect still resolves to "left" after ~50 ms while an in-app
navigation stays continuously online.

## PubSub Style

`DiscordClone.Chat` owns PubSub topic construction and broadcasting decisions.

Current message topics use durable channel IDs:

```elixir
"chat:channel:#{channel_id}"
```

Future presence and typing events should follow the same principle: keep topic
shape and event construction centralized in the Chat context or its internal
modules. LiveViews should subscribe or publish through public Chat APIs, not by
assembling topics themselves.

## Testing Style

Tests should prove behavior at the public boundary first.

For context and OTP tests:

- use public `DiscordClone.Chat` and `DiscordClone.Workspaces` APIs when
  possible
- use `start_supervised!/1` for supervised processes in tests
- avoid `Process.sleep/1`
- use `Process.monitor/1` and `assert_receive {:DOWN, ...}` when testing
  process shutdown
- use `_ = :sys.get_state(pid)` when synchronization with a process mailbox is
  needed
- test crash and restart behavior explicitly once channel processes exist

For LiveView tests:

- use stable DOM IDs
- prefer `element/2`, `has_element?/2`, `form/3`, and LiveView helpers
- avoid raw HTML assertions
- test visible outcomes, not private implementation details

When adding OTP behavior, include tests that clarify what state survives and
what state is allowed to disappear.

## Documentation Expectations

When making an OTP design decision, update or add docs if the decision changes
the mental model.

Good documentation topics for the next phases:

- channel process lifecycle
- what state lives in Postgres versus process memory
- what happens on channel process crash
- how presence rebuilds after reconnect
- how typing indicators expire
- why inactive channels shut down

Short, accurate notes are better than sprawling documents. The docs should help
future agents and the project owner stay oriented.

## Code Review Checklist

Before finishing an OTP/in-memory slice, check:

- Is the change small enough to review comfortably?
- Does web code call only public context APIs?
- Is process identity based on durable IDs?
- Is durable state still sourced from Postgres?
- Is temporary state allowed to reset on crash?
- Are process startup, lookup, and failure paths tested?
- Did the change avoid unnecessary dependencies?
- Did focused tests pass?
- Did `mix precommit` pass after implementation changes?
