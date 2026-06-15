# Discord Clone in Elixir/Phoenix

## Overview

Build a simplified Discord-like application using:

- Elixir
- Phoenix
- Phoenix LiveView
- Ecto
- PostgreSQL
- OTP (GenServer, Registry, DynamicSupervisor)
- PubSub

The goal is NOT to build a production Discord clone.

The goal is to learn:

- Full-stack Elixir development
- Phoenix architecture
- OTP fundamentals
- Real-time systems
- Process-oriented design
- State management
- Testing
- Scalability concepts

---

# Learning Goals

By the end of this project you should understand:

## Phoenix

- Routing
- Controllers
- Contexts
- LiveView
- Authentication
- Ecto

## OTP

- GenServer
- Registry
- DynamicSupervisor
- Supervision Trees
- Process lifecycle
- Fault tolerance

## System Design

- Process boundaries
- Localized state
- Persistent vs in-memory state
- Event-driven architecture

---

# High Level Architecture

```text
Workspace
  ├── Channels
  │     ├── General
  │     ├── Random
  │     └── Engineering
  │
  └── Users
```

Each channel has:

```text
Channel Process
      +
Database Storage
```

Database stores durable information.

GenServer stores live information.

---

# Core Features

## Users

Users can:

- Register
- Login
- Logout

Store users in Postgres.

Fields:

```elixir
id
email
username
password_hash
inserted_at
updated_at
```

---

## Workspaces

Users can:

- Create workspace
- Join workspace
- Leave workspace

Fields:

```elixir
id
name
owner_id
```

---

## Channels

Users can:

- Create channel
- Delete channel
- List channels

Examples:

```text
#general
#random
#engineering
```

Fields:

```elixir
id
workspace_id
name
```

---

## Messages

Users can:

- Send message
- View history

Fields:

```elixir
id
channel_id
user_id
content
inserted_at
```

Persist all messages in Postgres.

---

# Real-Time Features

Implement using:

- Phoenix PubSub
- LiveView

Requirements:

## Live Messages

When User A sends a message:

```text
User A
   ↓
Server
   ↓
Broadcast
   ↓
User B sees message instantly
```

No page refresh allowed.

---

## Online Presence

Show:

```text
Aleksa ● Online
John ○ Offline
```

Track online users in memory.

DO NOT store online status in database.

---

## Typing Indicator

Example:

```text
Aleksa is typing...
```

Requirements:

- Appears instantly
- Disappears automatically
- Uses PubSub

DO NOT persist typing status.

---

# OTP Section

This is the most important part of the project.

---

# Channel Processes

Each channel should have its own GenServer.

Example:

```text
#general
    ↓
ChannelProcess
```

```text
#engineering
    ↓
ChannelProcess
```

```text
#random
    ↓
ChannelProcess
```

---

# What Does A Channel Process Own?

The process should own temporary state.

Example:

```elixir
%{
  online_users: MapSet.new(),
  typing_users: MapSet.new(),
  recent_messages: [],
  last_activity_at: nil
}
```

---

# What Should NOT Be Stored In The Process?

Do NOT store:

- all messages
- users
- permissions
- workspaces

Those belong in Postgres.

Rule:

```text
Important forever?
    → Database

Useful right now?
    → GenServer
```

---

# Dynamic Channel Creation

When a channel becomes active:

```text
Request arrives
      ↓
Channel process doesn't exist
      ↓
Start process
      ↓
Handle request
```

Use:

```elixir
DynamicSupervisor
```

---

# Registry

Processes should be discoverable.

Example:

```elixir
ChannelRegistry
```

Lookup:

```elixir
general
```

Returns:

```elixir
PID<0.xxx.0>
```

Required learning:

- process registration
- lookup
- naming

---

# Inactive Channel Shutdown

Implement inactivity timeout.

Example:

```text
No activity for 30 minutes
       ↓
Process stops
```

When activity returns:

```text
Process starts again
```

Questions to think about:

- What state should be restored?
- What state can be lost?

Document your decisions.

---

# Supervision

Build a supervision tree.

Example:

```text
Application
│
├── Repo
├── PubSub
├── Registry
└── ChannelSupervisor
      └── Channel Processes
```

---

# Failure Testing

Prove fault tolerance.

Example:

```elixir
Process.exit(pid, :kill)
```

Verify:

```text
Channel crashes
      ↓
Supervisor restarts
      ↓
System keeps working
```

Create a short document explaining:

- what happened
- why it restarted
- what state was lost

---

# Stretch Goals

## Unread Counts

Track:

```text
#general (4 unread)
```

---

## Mentions

Support:

```text
@aleksa
```

---

## Reactions

Support:

```text
👍
❤️
🔥
```

---

## Direct Messages

Users can create:

```text
Aleksa ↔ John
```

Question:

Should a DM be a channel process?

Explain your reasoning.

---

## Voice Channel Simulation

No actual audio.

Track:

```text
Connected users
```

inside a GenServer.

---

## Message Rate Limiting

Prevent spam.

Example:

```text
Maximum 5 messages
per 10 seconds
```

Store counters in process state.

---

## Channel Analytics

Track:

```text
messages_per_hour
active_users
peak_users
```

Expose metrics page.

---

# Testing Requirements

Minimum:

## Unit Tests

- Contexts
- Channel Process
- Authentication

---

## Integration Tests

- Message sending
- Workspace creation
- Channel creation

---

## OTP Tests

Verify:

- channel starts
- channel stops
- channel restarts
- registry lookup works

---

# Documentation Requirements

Create:

## Architecture Diagram

Show:

```text
User
 ↓
LiveView
 ↓
PubSub
 ↓
Channel Process
 ↓
Database
```

---

## Process Lifecycle Diagram

Show:

```text
Channel Requested
       ↓
Start Process
       ↓
Handle Events
       ↓
Inactive
       ↓
Shutdown
       ↓
Restart If Needed
```

---

# Success Criteria

A successful project demonstrates:

- Good Phoenix structure
- Understanding of LiveView
- Understanding of OTP
- Proper use of GenServers
- Proper use of Supervisors
- Proper use of Registry
- Clear separation between:
  - persistent state
  - in-memory state
- Good tests
- Good documentation

The primary goal is NOT features.

The primary goal is understanding why OTP exists and when processes should own state.

# Look & Feel Requirements

The app should feel like a small Discord clone, not a plain CRUD dashboard.

The user should understand immediately:

- which workspace they are in
- which channel they are viewing
- who is online
- who is typing
- when new messages arrive
- what action they can take next

---

## Layout

Use a three-column layout.

```text
┌──────────────┬────────────────────┬──────────────────┐
│ Workspaces   │ Channels           │ Chat             │
│              │                    │                  │
│ Decidr       │ # general          │ # general        │
│ Personal     │ # engineering      │                  │
│              │ # random           │ messages...      │
│              │                    │                  │
│              │                    │ input box        │
└──────────────┴────────────────────┴──────────────────┘
```

Minimum layout requirements:

- Left sidebar: workspaces
- Middle sidebar: channels in selected workspace
- Main area: selected channel messages
- Bottom input: message composer
- Optional right sidebar: online users

Do not spend weeks polishing CSS. The goal is functional real-time UX.

---

## Workspace Sidebar

The workspace sidebar should show all workspaces the user belongs to.

Each workspace item should:

- show the workspace name or initials
- be clickable
- visually indicate the currently selected workspace

Example:

```text
[D] Decidr
[P] Personal
[T] Test Workspace
```

When the user switches workspace:

- the channel list updates
- the selected channel changes
- messages update
- online users update

---

## Channel List

Channels should look similar to Discord or Slack.

Example:

```text
# general
# engineering
# random
```

Requirements:

- Current channel is visually highlighted
- Clicking a channel opens it
- Channel messages load from the database
- The channel process starts if it is not already running

This is important: entering a channel should be one of the triggers that activates the channel GenServer.

---

## Chat Header

The top of the chat area should show the current channel.

Example:

```text
# general
Company-wide discussion
```

Optional metadata:

- number of online users
- channel description
- last activity time

The user should never be confused about which channel they are currently viewing.

---

## Message List

Messages should be displayed in chronological order.

Each message should show:

```text
Username
Timestamp
Message content
```

Example:

```text
Aleksa  14:32
Can you check the Phoenix PubSub implementation?

Intern  14:33
Yes, looking at it now.
```

Requirements:

- New messages appear at the bottom
- The page should not refresh when a message arrives
- Messages should be broadcast through PubSub
- Messages should also be persisted in Postgres
- When the user joins a channel, previous messages should load from Postgres

Important rule:

```text
Postgres = source of truth
PubSub = real-time delivery
GenServer = temporary channel state
```

---

## Instant Message Arrival

When User A sends a message in `#general`, User B should see it immediately if they are also viewing `#general`.

Expected flow:

```text
User A submits message
        ↓
Server saves message to Postgres
        ↓
Server broadcasts message through PubSub
        ↓
All connected users in that channel receive update
        ↓
Message appears in UI without page refresh
```

Acceptance criteria:

- Open two browser windows
- Login as two different users
- Join the same channel
- Send message from Window A
- Message appears in Window B without refreshing

This is one of the most important features in the project.

---

## Message Composer

At the bottom of the chat there should be an input box.

Example:

```text
Message #general...
```

Requirements:

- Pressing Enter sends the message
- Empty messages cannot be sent
- Very long messages should either be rejected or limited
- After sending, the input clears
- The sent message appears immediately

Optional:

- Shift + Enter creates a new line
- Send button
- Markdown preview

---

## Online Status

Users should have visible presence.

Example:

```text
● Aleksa
● Intern
○ Offline User
```

Status examples:

```text
Online
Offline
Away
```

Minimum requirement:

- Show who is currently online in the selected channel

Recommended implementation:

- Track presence in memory
- Use Phoenix Presence or a channel GenServer
- Do not persist online/offline status in Postgres

Reason:

Online status is temporary. It changes constantly and does not need historical storage.

Acceptance criteria:

- User joins channel → appears online
- User leaves/closes tab → eventually disappears
- Other users see the change without refresh

---

## Typing Indicator

When a user is typing, other users should see it.

Example:

```text
Aleksa is typing...
```

If multiple people are typing:

```text
Aleksa and Intern are typing...
```

Requirements:

- Trigger when user starts typing
- Broadcast typing event to other users in the same channel
- Do not show typing indicator to the user who is typing
- Remove typing indicator after a short timeout
- Do not store typing status in database

Recommended behavior:

```text
User types key
      ↓
Send "typing" event
      ↓
Channel process stores typing user temporarily
      ↓
Broadcast to channel subscribers
      ↓
Clear typing status after 3-5 seconds of inactivity
```

This is a good place to practice timers inside GenServers.

---

## User List

Show users currently active in the channel.

Example:

```text
Online
● Aleksa
● Intern

Offline
○ John
○ Maria
```

Minimum version:

- Show online users only

Better version:

- Show all workspace members
- Separate online and offline users

This helps the intern think through the difference between:

```text
workspace membership = database state
currently online = in-memory state
```

---

## Channel Activity State

A channel should feel alive.

Examples of temporary channel state:

```elixir
%{
  online_users: MapSet.new(),
  typing_users: MapSet.new(),
  recent_messages: [],
  last_activity_at: DateTime.utc_now()
}
```

This state should live in the channel GenServer.

The channel process should update when:

- user joins
- user leaves
- user types
- user sends message
- timeout happens

---

## Inactive Channels

Inactive channels should eventually shut down.

Example behavior:

```text
No users connected
No messages sent
No typing events
No activity for 30 minutes
        ↓
Channel GenServer stops
```

When someone opens the channel again:

```text
User opens #general
        ↓
System starts Channel GenServer
        ↓
Recent messages load from Postgres
        ↓
Temporary state begins fresh
```

This teaches that in-memory state is disposable.

---

## Empty States

Do not leave blank pages.

Examples:

No messages yet:

```text
No messages yet. Start the conversation.
```

No channels yet:

```text
No channels yet. Create #general to begin.
```

No workspace selected:

```text
Select a workspace to continue.
```

Empty states matter because they make the app usable instead of confusing.

---

## Loading States

Show simple loading feedback when switching workspaces or channels.

Examples:

```text
Loading messages...
Loading channels...
```

This does not need to be fancy.

The point is to avoid UI jumps where the user does not know what is happening.

---

## Error States

Show errors clearly.

Examples:

```text
Message could not be sent.
Channel could not be loaded.
You do not have access to this workspace.
```

Do not fail silently.

Acceptance criteria:

- Invalid channel ID does not crash the UI
- Unauthorized user cannot access private workspace/channel
- Failed message send gives visible feedback

---

## UI Quality Bar

The UI does not need to be beautiful.

It does need to be:

- clear
- usable
- real-time
- consistent
- hard to break

Bad:

```text
A form that creates messages and requires refresh.
```

Good:

```text
Two users can chat in the same channel and see messages, online status, and typing state update live.
```

---

# Main UX Acceptance Test

The final demo should support this flow:

1. Open Browser A as User A.
2. Open Browser B as User B.
3. Both users enter the same workspace.
4. Both users open `#general`.
5. User A appears online for User B.
6. User B appears online for User A.
7. User A starts typing.
8. User B sees `User A is typing...`.
9. User A sends a message.
10. User B sees the message instantly.
11. User A closes the tab.
12. User B eventually sees User A disappear from the online list.
13. Refresh the page.
14. Message history is still there.

If this works, the intern has built the core of a real-time Phoenix/OTP application.