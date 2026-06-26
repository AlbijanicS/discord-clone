# Implementation Roadmap

This roadmap uses a hybrid approach. Some work is horizontal because it creates
shared foundations. Other work is vertical because it proves a user workflow end
to end.

Each phase should leave the app in a working, testable state.

## How To Decide Build Order

Experienced engineers usually order work by dependency and risk:

1. Build the source of truth first.
2. Add the smallest user-facing path through that truth.
3. Keep workflows vertical enough to prove they work end to end.
4. Add live/in-memory behavior only after durable behavior is correct.
5. Make failure recovery explicit once processes own state.

For this project, that means Postgres and schemas come before GenServers,
because channel processes need stable channel IDs and persisted messages to
attach to.

## Horizontal Versus Vertical Work

Horizontal work builds a layer many features depend on.

Examples:

- database migrations
- schema modules
- authentication infrastructure
- shared layout shell
- OTP supervision tree

Horizontal work is useful when many later features need the same foundation. It
becomes risky when it goes too long without proving a user workflow.

Vertical work builds a thin path through multiple layers.

Examples:

- register, create workspace, create a channel, and enter it
- accept invite and enter workspace
- send a message and see it after reload
- send a message and see it live in another browser

Vertical work is useful because it exposes integration problems early. It
becomes risky when every slice invents its own foundation instead of sharing a
clean core.

The approach for this project:

```text
small horizontal foundation
-> vertical slice through it
-> next horizontal capability
-> next vertical slice through the same app
```

This keeps the architecture orderly while still giving us pages we can use
throughout the build.

## Phase 1: Durable Data Root

Type: horizontal foundation.

Goal: create the database structure and schema modules.

Build:

- `DiscordClone.Accounts.User`
- `DiscordClone.Workspaces.Workspace`
- `DiscordClone.Workspaces.WorkspaceMembership`
- `DiscordClone.Workspaces.WorkspaceInvite`
- `DiscordClone.Workspaces.Channel`
- `DiscordClone.Chat.Message`
- migrations for all core tables
- foreign keys and indexes
- basic changesets

Prove:

- migrations run cleanly
- schemas compile
- associations match the entity relationship document
- uniqueness constraints are in the database, not only changesets

Important decisions:

- `workspaces.default_channel_id` points to the workspace landing channel.
- workspace creation creates the workspace, owner membership, and default
  `general` landing channel in one transaction.
- channel creation is separate and does not update the workspace's default
  channel.
- workspace landing resolves to the stored default channel.
- messages are always persisted in Postgres.

## Phase 2: Authentication

Type: horizontal foundation with immediate user-facing pages.

Goal: users can register, log in, and log out.

Build:

- Accounts context authentication functions
- user registration
- login/logout
- session handling
- generated Phoenix auth routes and templates adapted to the app

Prove:

- protected routes require a logged-in user
- authenticated LiveViews receive the current user or current scope
- user creation validates email, username, and password rules

## Phase 3: Workspace And Channel Core

Type: first major vertical slice.

Goal: authenticated users can create and enter workspaces with channels.

Build:

- create workspace flow
- owner membership creation
- workspace list
- workspace show page
- basic channel page shell
- channel list
- create channel
- delete channel with default-channel replacement rule
- access checks based on workspace membership

Prove:

- creating a workspace creates owner membership and a default `general` landing
  channel
- creating a channel does not change the workspace default channel
- workspace entry resolves the stored landing channel
- owner can see the workspace
- non-members cannot access workspace channels
- deleting the default channel requires selecting a replacement
- the app has a navigable path from login to workspace to channel

## Phase 4: Invites And Joining

Type: vertical slice.

Goal: users can join existing workspaces through invite links.

Build:

- create workspace invite
- accept invite by code
- reject revoked, expired, or fully-used invites
- increment invite usage
- join workspace by creating membership
- navigate joined user to the workspace landing channel

Prove:

- invite redemption is transactional
- duplicate membership is handled cleanly
- invite permission follows workspace `invite_policy`

## Phase 5: Persisted Chat Slice

Type: vertical slice.

Goal: users can send and read messages without live behavior yet.

Build:

- channel page message history
- latest 50 message query
- older message pagination query
- message composer
- `DiscordClone.Chat.send_message/3`

Prove:

- send flow validates workspace membership
- send flow persists first
- channel reload shows the sent message
- scrolling/history fetch reads older messages from Postgres

Message order:

```text
validate membership
-> insert message in Postgres
-> return persisted message
```

## Phase 6: Live Messages With PubSub

Type: vertical enhancement of the existing chat slice.

Goal: messages appear in other connected clients without refresh.

Build:

- channel PubSub topic naming
- subscribe on channel LiveView mount
- broadcast after message insert
- handle broadcast in LiveView
- stream new messages into the UI

Prove:

- User A sends a message and User B sees it instantly
- refreshing still recovers all messages from Postgres
- duplicate rendering is avoided for the sender

Message order:

```text
validate membership
-> insert message in Postgres
-> broadcast persisted message
```

## Phase 7: Channel Process Foundation

Type: horizontal OTP foundation.

Goal: each active channel has a supervised GenServer for live state.

Build:

- `DiscordClone.Chat.ChannelRegistry`
- `DiscordClone.Chat.ChannelSupervisor`
- `DiscordClone.Chat.ChannelServer`
- lookup-or-start API hidden behind `DiscordClone.Chat`
- process naming by durable `channel_id`
- recent message cache initialized from Postgres
- inactivity timeout

Prove:

- entering a channel starts or finds its process
- process state uses channel ID, not channel name
- crashing a process does not lose durable messages
- restarted process can reload latest 50 messages

## Phase 8: Presence And Typing

Type: vertical slice on top of the channel process foundation.

Goal: channel process state drives channel typing indicators while workspace
presence remains workspace-scoped.

Build:

- typing started/stopped events
- typing expiry
- PubSub broadcasts for typing changes
- keep online users in the workspace presence runtime

Prove:

- typing disappears automatically
- process crash clears temporary typing state and rebuilds as LiveViews rejoin
- workspace online status remains separate from channel runtime recovery

## Phase 9: Recovery And Failure Tests

Type: horizontal reliability pass.

Goal: verify the OTP learning goals explicitly.

Build:

- tests that kill a channel process
- tests that assert supervisor restart behavior
- tests that assert messages remain available from Postgres
- short fault-tolerance note documenting lost and recovered state

Prove:

- crashes are boring
- temporary state is allowed to disappear
- durable state remains correct

## Phase 10: Polish And Stretch Goals

Type: vertical slices, one feature at a time.

Goal: improve usability without disturbing the core architecture.

Possible work:

- unread counts with `channel_reads`
- reactions
- mentions
- direct messages
- message rate limiting in channel process state
- voice-channel simulation
- channel analytics

Only add these after the main loop is healthy:

```text
auth -> workspace -> channel -> message -> live update -> recovery
```

## Working Rule

After each phase:

```sh
mix precommit
```

Fix any issue before moving on.
