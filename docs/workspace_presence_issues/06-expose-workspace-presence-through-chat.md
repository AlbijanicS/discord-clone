# Expose Workspace Presence Through Chat

**Type:** AFK

**Blocked by:** 3. Add Workspace Presence Runtime Foundation, 4. Track Workspace Presence Connections, 5. Broadcast User-Level Workspace Presence Events

**User stories covered:** 18-22, 32-36, 40-42

## What to build

Expose Workspace presence through public Chat context workflows so LiveViews
can subscribe, join, and list online user IDs without knowing about OTP
internals. Each workflow should authorize against workspace membership before
performing its own responsibility.

Joining presence is a command and starts or finds the Workspace runtime.
Listing online user IDs is a query and should not start a runtime. Subscribing
to presence events authorizes and subscribes, but should not start a runtime.

## Acceptance criteria

- [ ] The Chat context exposes a public workflow for subscribing to Workspace
      presence events.
- [ ] The Chat context exposes a public workflow for joining Workspace
      presence.
- [ ] The Chat context exposes a public workflow for listing online Workspace
      user IDs.
- [ ] All three workflows require an authenticated scope.
- [ ] All three workflows reject logged-in users who are not Workspace Members.
- [ ] Subscribing authorizes and subscribes without starting a Workspace
      runtime.
- [ ] Joining authorizes and starts or finds the Workspace runtime.
- [ ] Joining tracks the calling process or explicitly supplied LiveView PID
      according to the chosen API shape.
- [ ] Joining returns success or a domain error, not a snapshot of online
      users.
- [ ] Listing authorizes before reading online IDs.
- [ ] Listing returns an empty list when no Workspace runtime exists.
- [ ] Listing does not start a Workspace runtime.
- [ ] LiveViews still do not call private runtime modules, registries,
      supervisors, or PubSub directly.
- [ ] Focused Chat context tests cover authorization, subscription without
      startup, join startup, list-without-startup, empty absent-runtime reads,
      and event receipt.

## Blocked by

- 3. Add Workspace Presence Runtime Foundation
- 4. Track Workspace Presence Connections
- 5. Broadcast User-Level Workspace Presence Events
