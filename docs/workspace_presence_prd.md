# Workspace Presence PRD

## Problem Statement

The Discord clone now has authenticated workspace membership, workspace and
channel navigation, persisted chat, and live message delivery through PubSub.
However, the app still does not show who is currently online. A workspace
member can chat live with another member, but the product does not yet feel
alive in the Discord-like way described by the original project brief.

The immediate problem is to add the first in-memory OTP state slice in a way
that supports the project's learning goals. Workspace membership is durable and
belongs in Postgres, while online status is temporary and belongs in process
state. The app should show all workspace members in a right sidebar, mark the
currently online members, and recover gracefully if temporary presence state is
lost.

This PRD deliberately focuses on workspace-scoped presence, not channel-scoped
presence. If a user has any workspace surface open, they are considered online
in that workspace, regardless of which channel they are viewing.

## Solution

Add workspace presence as the first OTP-backed in-memory state slice.

The durable member list comes from the Workspaces context. The temporary online
state lives in a new workspace runtime process hidden behind the Chat context.
LiveViews join workspace presence after workspace access is proven and only
when the LiveView websocket is connected. The workspace runtime tracks LiveView
processes with monitors, supports multiple tabs per user, and broadcasts
granular joined/left events when a user's online status changes.

The UI renders a right sidebar listing workspace members. Members are marked
online if their user ID is currently present in the workspace runtime state. If
the workspace runtime is missing or has crashed, the durable member list still
renders and all members appear offline until connected LiveViews rejoin.

The first workspace presence PRD may be split into many small implementation
issues. Individual implementation issues should remain narrow and reviewable,
with the project preference that each issue stays small rather than attempting
to deliver the full PRD in one patch.

## User Stories

1. As a workspace member, I want to see a member list for the current workspace, so that the app feels like a shared collaboration space.
2. As a workspace member, I want to see which workspace members are online, so that I know who is currently around.
3. As a workspace member, I want online status to be workspace-scoped, so that a member appears online no matter which channel they are viewing in the workspace.
4. As a workspace member, I want the right sidebar to show all workspace members, so that offline members remain visible.
5. As a workspace member, I want offline members to be visually distinct from online members, so that presence is easy to scan.
6. As a workspace member, I want my own user to appear online after I enter a workspace, so that the UI reflects my active session.
7. As a workspace member, I want another member to appear online when they open the same workspace, so that presence updates without refresh.
8. As a workspace member, I want another member to appear offline when they close their last active workspace tab, so that stale presence disappears.
9. As a workspace member, I want a user with multiple open tabs to remain online until their last tab disconnects, so that online status does not flicker incorrectly.
10. As a workspace member, I want switching channels inside the same workspace to preserve workspace online status, so that channel navigation does not make me appear offline.
11. As a workspace member, I want workspace invite and other workspace shell surfaces to count as being inside the workspace, so that presence is tied to workspace activity rather than only channel activity.
12. As a workspace member, I want presence updates to arrive live, so that I do not need to refresh to see who is online.
13. As a workspace member, I want the member list to continue rendering if temporary presence state is unavailable, so that the UI remains useful after a process crash.
14. As a workspace member, I want temporary presence failure to fall back to all members offline, so that the app avoids showing stale online users.
15. As a workspace member, I want durable membership data to remain the source of names and account display information, so that temporary runtime state does not become a second user database.
16. As a workspace member, I want online status to be temporary, so that it is not persisted in Postgres.
17. As a workspace member, I want online state to rebuild as connected LiveViews rejoin after a runtime restart, so that presence recovers naturally.
18. As a logged-in non-member, I should not be able to subscribe to or join workspace presence, so that private workspace activity remains private.
19. As an anonymous visitor, I should not be able to subscribe to or join workspace presence, so that online status always attaches to an authenticated user.
20. As a workspace member, I want workspace presence to use the same authorization boundary as other private workspace behavior, so that access rules stay consistent.
21. As a developer, I want workspace presence hidden behind the Chat context, so that LiveViews do not call OTP modules directly.
22. As a developer, I want the WorkspaceServer to be a private runtime module, so that process internals can evolve without changing LiveViews.
23. As a developer, I want Workspaces to provide durable member listing, so that the web layer does not assemble membership queries itself.
24. As a developer, I want the workspace runtime to track LiveView PIDs with monitors, so that closed tabs and crashed LiveViews are cleaned up automatically.
25. As a developer, I want the workspace runtime to track multiple LiveView PIDs per user, so that multi-tab behavior is correct.
26. As a developer, I want first-connection joins to broadcast a user-joined event, so that subscribers update only when online status changes.
27. As a developer, I want additional connections for an already-online user not to broadcast another joined event, so that events represent user-level presence.
28. As a developer, I want disconnecting one of several connections not to broadcast a left event, so that a user remains online while another tab is still open.
29. As a developer, I want disconnecting the last connection for a user to broadcast a left event, so that presence accurately transitions offline.
30. As a developer, I want presence events to be idempotent in LiveViews, so that receiving an event caused by the same LiveView is harmless.
31. As a developer, I want LiveViews to store online user IDs in a set-like assign, so that joined and left events are easy to apply.
32. As a developer, I want join and list operations to be separate, so that commands and queries stay easy to reason about.
33. As a developer, I want listing online workspace user IDs not to start a runtime process, so that reads do not create side effects.
34. As a developer, I want joining workspace presence to start or find the runtime process, so that the first active user activates the workspace runtime.
35. As a developer, I want subscribing to presence events to be separate from joining presence, so that PubSub subscription and runtime tracking remain distinct.
36. As a developer, I want presence subscription to authorize access but not start the runtime process, so that a subscription remains a PubSub concern.
37. As a developer, I want WorkspaceServer to broadcast presence events directly after state changes, so that the process owning state also owns state-change notifications.
38. As a developer, I want workspace presence events to include workspace ID and user ID, so that event handlers are simple and debuggable.
39. As a developer, I want user display data to come from durable members rather than event payloads, so that events do not carry stale user structs.
40. As a learner, I want this slice to use plain OTP primitives, so that I learn monitors, process state, supervision, registry lookup, and PubSub rather than hiding them behind Phoenix Presence.
41. As a learner, I want this work split into small reviewable steps, so that each OTP concept is understandable.
42. As a future maintainer, I want workspace presence and channel behavior to remain independent, so that a presence process crash does not interrupt chat.
43. As a future maintainer, I want runtime cleanup for deleted workspaces to be considered explicitly, so that deleted workspace processes do not hang around indefinitely.

## Implementation Decisions

- Build this as the first workspace-scoped presence PRD.
- Workspace presence means the user has at least one connected LiveView inside the workspace.
- Presence is workspace-scoped, not channel-scoped.
- A user is online in the workspace no matter which channel or workspace shell surface they are viewing.
- Channel-specific state remains future work for ChannelServer, especially typing indicators, recent-message cache, rate limits, and channel-local activity.
- Do not return to channel-scoped presence for this PRD, even though the original project brief described online users in channel process state.
- Keep the mentor project's OTP learning goal intact by building the runtime state with plain OTP primitives rather than Phoenix Presence.
- Use standard OTP primitives directly: GenServer, Registry, DynamicSupervisor, Process.monitor, and PubSub.
- Do not add helper libraries or macro wrappers for OTP.
- Add a public Workspaces workflow to list workspace members for an authorized workspace member.
- The member-list workflow returns durable member/user data suitable for rendering all members in the right sidebar.
- The member-list workflow belongs to Workspaces because workspace membership is durable workspace structure.
- Add a right sidebar to the workspace shell that can render all workspace members.
- The right sidebar marks members online based on runtime online user IDs.
- If runtime online state is missing or empty, all durable members render offline.
- Add WorkspaceRegistry, WorkspaceSupervisor, and WorkspaceServer under the Chat runtime area.
- WorkspaceServer is the private OTP state holder for workspace presence.
- Chat is the public runtime API used by LiveViews.
- LiveViews must not call WorkspaceServer, WorkspaceSupervisor, Registry, or PubSub directly for presence workflows.
- Workspaces remains responsible for durable workspace membership queries and access checks.
- Chat remains responsible for live/runtime behavior, including presence process access and PubSub subscription APIs.
- The public Chat API should include a workspace-presence join workflow.
- The public Chat API should include a workspace-presence subscription workflow.
- The public Chat API should include a workflow for listing currently online workspace user IDs.
- Prefer explicit presence naming at the Chat boundary, such as "join workspace presence", to avoid confusion with invite-based workspace joining.
- Joining workspace presence is a command.
- Joining workspace presence starts or finds the WorkspaceServer.
- Joining workspace presence authorizes the current scope against workspace membership before tracking the LiveView PID.
- Joining workspace presence tracks the calling LiveView PID with Process.monitor.
- Joining workspace presence is idempotent for the same user and LiveView PID.
- Joining workspace presence returns only success or a domain error; it does not return online users.
- Listing online workspace user IDs is a query.
- Listing online workspace user IDs authorizes the current scope before reading runtime state.
- Listing online workspace user IDs does not start a WorkspaceServer.
- Listing online workspace user IDs returns an empty list if the WorkspaceServer is not running.
- Subscribing to workspace presence events authorizes the current scope before subscribing.
- Subscribing to workspace presence events does not start a WorkspaceServer.
- LiveViews subscribe to presence events separately from joining presence.
- LiveViews join workspace presence in mount after workspace access is proven and only when the socket is connected.
- LiveViews should not perform presence work during disconnected HTTP render.
- LiveViews should subscribe before joining so the presence stream is ready to receive updates.
- The normal connected mount flow is: authorize workspace access, load durable members, subscribe to presence events, join workspace presence, list online user IDs, then render.
- WorkspaceServer state should track users by user ID and connections by LiveView PID.
- WorkspaceServer state should also track monitor references so DOWN messages can be mapped back to the user and connection that disappeared.
- Use a two-index state shape conceptually equivalent to:

```elixir
%{
  workspace_id: workspace_id,
  users: %{user_id => MapSet.new([pid])},
  monitors: %{monitor_ref => {user_id, pid}}
}
```

- The users index makes it easy to decide whether a join is the first connection or a disconnect is the last connection.
- The monitors index makes cleanup from DOWN messages direct.
- Do not store full user structs in WorkspaceServer state.
- User names and display data come from the durable member list.
- WorkspaceServer broadcasts directly after its state changes.
- WorkspaceServer broadcasts only when user-level online status changes.
- The first connection for a user broadcasts a joined event.
- Additional connections for an already-online user do not broadcast another joined event.
- Disconnecting a non-last connection does not broadcast a left event.
- Disconnecting the last connection for a user broadcasts a left event.
- Presence event payloads are granular, not full snapshots.
- Presence event payloads include workspace ID and user ID.
- The joined event shape should communicate "workspace user joined" with workspace ID and user ID.
- The left event shape should communicate "workspace user left" with workspace ID and user ID.
- Presence events may be received by the LiveView that caused them.
- LiveView handlers must be idempotent.
- Store online user IDs in LiveView assigns as a MapSet.
- On joined events, add the user ID to the MapSet.
- On left events, remove the user ID from the MapSet.
- Use durable member list data plus the online user ID MapSet to render online/offline status.
- Keep workspace presence independent from future channel processes.
- A WorkspaceServer crash should not interrupt persisted chat, message PubSub, or future channel-local behavior.
- If WorkspaceServer crashes, presence may be lost and should rebuild as connected LiveViews rejoin.
- If WorkspaceServer crashes or is absent, the right sidebar should still show durable members as offline.
- Runtime cleanup for deleted workspaces should be handled deliberately once runtime processes exist.
- The project owner wants to avoid hanging runtime processes after workspace deletion.
- This PRD should not force nested supervision between workspace runtime and channel runtime.
- Domain containment does not automatically imply supervision containment.
- Sibling workspace and channel process families remain acceptable unless a later lifecycle requirement justifies nesting.
- Individual implementation issues should stay small and reviewable.
- This PRD may be implemented through many small issues rather than one large patch.
- Keep implementation aligned with the style guide for OTP/in-memory phases.

## Testing Decisions

- Test public behavior before private implementation details.
- Add Workspaces context tests for listing workspace members.
- Workspaces member-list tests should prove authentication is required.
- Workspaces member-list tests should prove only workspace members can list members.
- Workspaces member-list tests should prove durable members are returned with the user data needed for rendering.
- Add WorkspaceServer tests for joining presence.
- WorkspaceServer tests should prove the first connection for a user creates online state.
- WorkspaceServer tests should prove duplicate joins for the same PID are idempotent.
- WorkspaceServer tests should prove multiple PIDs for the same user are tracked correctly.
- WorkspaceServer tests should prove closing one of multiple PIDs does not mark the user offline.
- WorkspaceServer tests should prove closing the last PID marks the user offline.
- WorkspaceServer tests should use Process.monitor and DOWN assertions rather than sleeps.
- WorkspaceServer tests should avoid Process.sleep.
- WorkspaceServer tests may use sys state synchronization where needed.
- Add Chat context tests for the public workspace presence APIs.
- Chat presence tests should prove unauthorized users cannot subscribe, join, or list online users for private workspaces.
- Chat presence tests should prove joining starts or finds a WorkspaceServer.
- Chat presence tests should prove listing online user IDs returns an empty list if no runtime exists.
- Chat presence tests should prove subscription receives joined and left events.
- Chat presence tests should prove event payloads contain workspace ID and user ID.
- Add LiveView tests for the member sidebar and online/offline rendering.
- LiveView tests should use stable DOM IDs and LiveViewTest helpers rather than raw HTML assertions.
- LiveView tests should prove all durable members render in the right sidebar.
- LiveView tests should prove members render offline when runtime online state is empty.
- LiveView tests should prove one member opening the workspace causes another subscribed member to see them online.
- LiveView tests should prove closing the last connected view eventually marks the user offline.
- LiveView tests should keep assertions focused on user-visible outcomes.
- Existing Workspaces context tests provide prior art for public authorization behavior.
- Existing Chat context tests provide prior art for PubSub subscription and broadcast behavior.
- Existing workspace LiveView tests provide prior art for shell rendering, stable DOM IDs, streams, and access recovery.
- Run focused Workspaces tests first.
- Run focused Chat and WorkspaceServer tests next.
- Run focused workspace LiveView tests after UI integration.
- Run the project precommit alias after implementation changes.

## Out of Scope

- ChannelServer implementation.
- Channel-scoped presence.
- Typing indicators.
- Recent-message cache in process state.
- Channel rate limiting.
- Channel last-activity tracking.
- Channel inactivity shutdown.
- Phoenix Presence.
- Distributed presence across multiple BEAM nodes.
- Nested workspace runtime supervision of channel processes.
- Replacing the current message PubSub flow.
- Changing persisted chat behavior.
- Changing invite membership behavior.
- Persisting online/offline status in Postgres.
- Showing away or idle status.
- Showing all offline workspace members with rich profile details beyond what existing durable membership data supports.
- Direct messages.
- Voice-channel simulation.
- Message reactions, mentions, or unread counts.
- Full workspace deletion runtime cleanup if no runtime processes exist yet.
- Publishing implementation issues as part of this PRD.

## Further Notes

This PRD comes from a focused OTP design grill about the next in-memory phase.
The project owner wants this phase to prioritize learning and reviewability:
small steps, idiomatic OTP, and clear state ownership.

The key architectural decision is that workspace-wide online status belongs to
a workspace presence process, while future channel-specific state belongs to a
future channel process. Workspace presence should not be allowed to interrupt
chat if it crashes. Durable membership stays in Postgres, temporary online
status stays in process memory, and the UI merges the two.

Phoenix Presence was discussed as the production Phoenix tool for presence, but
it is intentionally out of scope for this slice. The learning value comes from
building a small supervised presence process directly with OTP primitives.

Issue tracker publishing is blocked because this repository does not currently
define the tracker configuration or triage label vocabulary expected by the
local `to-prd` skill. Existing PRDs in this repository use the same docs-first
fallback. This PRD is written as a docs artifact until tracker setup is
available.

