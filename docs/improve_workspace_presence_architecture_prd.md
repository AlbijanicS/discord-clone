# Improve Workspace Presence Architecture PRD

## Problem Statement

The Discord clone now has workspace-scoped presence that is functional,
tested, and intentionally built with plain OTP primitives. The implementation
successfully teaches how a Workspace runtime process can track connected
LiveViews, handle multi-tab behavior, broadcast online/offline transitions, and
recover from temporary runtime loss.

The next problem is architectural clarity. The presence slice was built in
small reviewable steps, which was good for learning, but a few seams are now
starting to show friction. Some OTP lifecycle knowledge still sits in the Chat
context. Some LiveView surfaces still repeat the same durable Workspace Member
and temporary online state setup. Presence event tuples are useful, but their
shape is informal. Some web tests know private OTP details that are better kept
inside runtime-focused tests.

The goal is not to rewrite the feature. The goal is to deepen the existing
Modules so that the important behavior remains easy to understand, easy to
test, and easy to extend when future Channel runtime work begins.

## Solution

Improve the architecture around workspace presence by preserving the parts that
are already deep and tightening the shallow seams around them.

The Workspace runtime should remain the Module that owns multi-tab online state,
process monitors, pending leave timers, and user-level joined/left broadcasts.
Callers should not learn that internal state shape.

The Chat context should remain the public interface for live runtime behavior,
but private workspace presence lifecycle details should move behind a deeper
runtime-facing Module. That Module should own finding, starting, reading, and
stopping the Workspace presence runtime.

The web layer should get a deeper presence/shell Module that prepares durable
Workspace Members and temporary online state together after Workspace access is
proven. Channel and invite surfaces should not have to remember the full mount
sequence for member streams and presence joining.

Presence events should become a named interface. Callers and tests should no
longer need to repeat raw tuple and payload details everywhere.

Tests should keep OTP mechanics local to runtime tests and keep LiveView tests
focused on user-visible Workspace Member online/offline behavior.

## User Stories

1. As a learner, I want the workspace presence architecture to stay readable, so that I can understand why each Module exists.
2. As a learner, I want the Workspace runtime to keep hiding monitor and timer details, so that I can focus on behavior before internals.
3. As a learner, I want the public Chat interface to remain the main entry point for runtime behavior, so that I know where LiveViews are allowed to call.
4. As a learner, I want private OTP lifecycle rules to live in one place, so that I can study process lookup and supervision without hunting through callers.
5. As a learner, I want the difference between durable Workspace Members and temporary online state to stay explicit, so that I do not confuse Postgres data with process memory.
6. As a learner, I want presence events to have a named interface, so that I can learn the event contract directly instead of memorizing raw tuples.
7. As a learner, I want runtime tests and LiveView tests to teach different lessons, so that OTP mechanics and user-visible behavior do not blur together.
8. As a developer, I want the Workspace runtime Module to remain deep, so that callers get multi-tab correctness through a small interface.
9. As a developer, I want to avoid extracting monitor and timer helpers into public Modules, so that shallow pass-through Modules do not make the system harder to navigate.
10. As a developer, I want Chat to delegate private runtime lifecycle work, so that Chat remains a public workflow interface rather than an OTP assembly point.
11. As a developer, I want runtime start/find/list/stop behavior to have locality, so that future process lifecycle changes happen in one Module.
12. As a developer, I want listing online Workspace Members to remain a query, so that reads do not start runtime processes.
13. As a developer, I want joining workspace presence to remain a command, so that runtime activation stays deliberate.
14. As a developer, I want subscribing to workspace presence to remain separate from joining, so that PubSub listening and runtime tracking stay distinct.
15. As a developer, I want workspace deletion cleanup to remain deliberate, so that deleted Workspace runtime processes do not linger.
16. As a developer, I want Channel and invite LiveViews to share the same presence mounting behavior, so that new Workspace surfaces do not copy subtle setup logic.
17. As a developer, I want Workspace Member streams to be prepared consistently, so that online/offline rendering stays stable across surfaces.
18. As a developer, I want presence event handling to be idempotent, so that duplicate events do not create duplicate member rows or wrong state.
19. As a developer, I want presence event payloads to avoid user structs, so that durable display data remains owned by Workspaces.
20. As a developer, I want presence event names and payloads to live behind a named interface, so that changing the event shape has locality.
21. As a developer, I want web tests to avoid private runtime details where possible, so that refactoring OTP internals does not break product-level tests.
22. As a developer, I want one focused runtime test surface for OTP behavior, so that monitor, timer, and restart behavior remains proven.
23. As a developer, I want Chat context tests to prove public return contracts, so that unauthorized, missing, and runtime-loss cases remain stable.
24. As a developer, I want LiveView tests to prove visible Workspace Member online/offline outcomes, so that tests match the user's experience.
25. As a maintainer, I want the workspace presence runtime to stay independent from persisted chat, so that presence crashes do not interrupt messages.
26. As a maintainer, I want the workspace presence runtime to stay independent from future Channel runtime work, so that Channel state can evolve separately.
27. As a maintainer, I want future Channel runtime Modules to learn from this presence shape, so that new OTP state slices begin behind clear public interfaces.
28. As a maintainer, I want architectural vocabulary to stay consistent, so that future reviews can talk precisely about Modules, Interfaces, Depth, Seams, Adapters, Leverage, and Locality.
29. As a future agent, I want the PRD to record why these changes are being made, so that I do not flatten a deep Module or reintroduce shallow seams.
30. As a future agent, I want the PRD to describe what is out of scope, so that a small architecture improvement does not turn into a broad redesign.

## Implementation Decisions

- Preserve the current Workspace runtime Module as the owner of workspace-scoped temporary online state.
- Treat the Workspace runtime Module as already deep because it hides multiple LiveView PIDs per User, monitor references, pending leave timers, online user queries, and user-level broadcasts behind a small interface.
- Do not split monitor handling, pending leave timer handling, or user connection bookkeeping into public helper Modules.
- Add or deepen a private workspace presence runtime Module behind Chat.
- The private runtime Module should own finding an existing Workspace runtime.
- The private runtime Module should own starting or finding a Workspace runtime for join commands.
- The private runtime Module should own reading online User identifiers without starting a missing runtime.
- The private runtime Module should own stopping a Workspace runtime during Workspace deletion cleanup.
- Chat remains the public interface for workspace presence workflows.
- Chat remains responsible for authorizing the current scope before runtime operations are attempted.
- Chat should call the private runtime Module after authorization succeeds.
- Workspaces remains responsible for durable Workspace structure and access rules.
- Workspaces remains responsible for durable Workspace Member listing.
- The web layer remains responsible for rendering and LiveView socket state.
- Add or deepen a web-side workspace presence Module for preparing Workspace Member stream state and temporary online state together.
- The web-side Module should run only after Workspace access has already been proven by the calling LiveView.
- The web-side Module should preserve the connected-socket rule: presence work happens only after the LiveView websocket is connected.
- The web-side Module should subscribe before joining so that joined events can be received.
- The web-side Module should join workspace presence through Chat, not by calling OTP runtime Modules directly.
- The web-side Module should list online User identifiers through Chat, not by calling runtime Modules directly.
- The web-side Module should assign an empty online set when runtime state is unavailable or authorization fails after access changes.
- The web-side Module should keep member streams stable by re-streaming durable Workspace Members when online state changes.
- Presence event names and payloads should become a named interface.
- The event interface should keep joined and left events granular.
- The event interface should keep payloads limited to Workspace Identifier and User identifier.
- The event interface should not carry User structs, Workspace Member structs, or full snapshots.
- Presence broadcasts should continue to happen from the Module that owns the state transition.
- Presence subscription should continue not to start a Workspace runtime.
- Listing online User identifiers should continue not to start a Workspace runtime.
- Joining workspace presence should continue to start or find the Workspace runtime.
- Workspace runtime absence should continue to mean all durable Workspace Members render offline.
- Workspace runtime crash should continue not to interrupt persisted chat.
- Workspace deletion should continue to stop any active Workspace presence runtime.
- No router changes are needed.
- Workspace, Channel, and invite LiveViews should remain in the existing authenticated browser pipeline and existing authenticated LiveView session because workspace presence depends on current scope and Workspace membership.
- No database schema changes are needed.
- No new dependencies are needed.
- Phoenix Presence remains out of scope because this project phase is intentionally learning plain OTP primitives.
- These changes should be small architecture improvements, not a rewrite of workspace presence behavior.
- The implementation should prefer preserving existing public behavior over inventing new product behavior.

## Testing Decisions

- Good tests should use the intended interface as the test surface.
- Runtime mechanics should be tested at the private runtime seam.
- Public workflow behavior should be tested through Chat.
- User-visible behavior should be tested through LiveView tests.
- Tests should preserve the existing rule to avoid sleeping.
- Tests that wait for process exits should use process monitors and assert on DOWN messages.
- Tests that need runtime synchronization may use system state synchronization where appropriate.
- Runtime tests should prove that starting the same Workspace runtime twice returns the active process.
- Runtime tests should prove that listing online User identifiers does not mutate runtime state.
- Runtime tests should prove that the first connection for a User broadcasts joined.
- Runtime tests should prove that duplicate joins do not broadcast duplicate joined events.
- Runtime tests should prove that additional tabs for an already-online User do not broadcast joined again.
- Runtime tests should prove that closing one tab for a multi-tab User does not broadcast left.
- Runtime tests should prove that closing the final tab broadcasts left.
- Runtime tests should prove that quick same-Workspace channel navigation does not produce an offline flicker.
- Chat tests should prove that subscribe, join, list, and stop workflows keep their public return contracts.
- Chat tests should prove that unauthorized Users cannot subscribe, join, or list online state for a private Workspace.
- Chat tests should prove that listing online User identifiers returns an empty list when no runtime exists.
- Chat tests should prove that joining workspace presence starts or finds the runtime.
- Chat tests should prove that workspace presence runtime loss does not interrupt persisted messages.
- LiveView tests should focus on stable member rows and visible online/offline state.
- LiveView tests should prove that durable Workspace Members render offline when no runtime state exists.
- LiveView tests should prove that the current member becomes online after entering a Workspace surface.
- LiveView tests should prove that another member entering the Workspace updates the sidebar without refresh.
- LiveView tests should prove that another member closing their final connected surface updates the sidebar without refresh.
- LiveView tests should prove that duplicate presence events do not duplicate Workspace Member rows.
- LiveView tests should avoid reaching into private OTP Modules unless the behavior cannot be synchronized through the public interface.
- Existing workspace presence runtime tests provide prior art for OTP behavior.
- Existing Chat context tests provide prior art for public workflow behavior and PubSub outcomes.
- Existing Workspace LiveView tests provide prior art for stream assertions, stable DOM IDs, and user-visible online/offline behavior.
- Run focused tests around Chat, workspace presence runtime, and Workspace LiveViews after implementation changes.
- Run the project precommit alias after all implementation changes are complete.

## Out of Scope

- Replacing the plain OTP implementation with Phoenix Presence.
- Adding distributed presence across multiple BEAM nodes.
- Adding channel-scoped presence.
- Adding typing indicators.
- Adding recent-message cache in process state.
- Adding Channel runtime processes.
- Changing persisted chat behavior.
- Changing message PubSub behavior.
- Changing Workspace membership rules.
- Changing Workspace invite rules.
- Changing Workspace roles or permissions.
- Changing Workspace, Channel, or message schemas.
- Adding routes or changing router scopes.
- Moving authenticated Workspace routes out of the existing authenticated LiveView session.
- Redesigning the Workspace shell UI.
- Rewriting all tests.
- Publishing implementation issues as part of this PRD.

## Further Notes

This PRD comes from an architecture review of the completed workspace presence
slice. The review used the architecture vocabulary of Module, Interface,
Implementation, Depth, Seam, Adapter, Leverage, and Locality.

The most important conclusion is that the Workspace runtime Module should be
preserved as deep. The architecture work should happen around it: reduce caller
knowledge of runtime lifecycle, consolidate repeated LiveView presence setup,
name the presence event interface, and keep OTP details local to runtime tests.

Issue tracker publishing is blocked because this repository does not currently
define the tracker configuration or triage label vocabulary expected by the
local `to-prd` skill. Existing PRDs in this repository use the same docs-first
fallback, so this PRD is written as a docs artifact until tracker setup is
available.
