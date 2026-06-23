# Add Workspace Presence Runtime Foundation

**Type:** AFK

**Blocked by:** None - can start immediately

**User stories covered:** 21-22, 34, 40-42

## What to build

Add the minimal supervised runtime foundation for Workspace presence under the
Chat runtime area. The application should supervise a Registry and
DynamicSupervisor for Workspace presence processes, and the private Workspace
runtime should be startable and findable by durable Workspace ID.

This slice should prove process identity and supervision only. It should not
track users, monitor LiveViews, broadcast presence events, or expose the final
public Chat presence API yet. Keeping the foundation narrow makes the OTP
pieces easier to review and learn.

## Acceptance criteria

- [ ] The application supervision tree starts a Workspace presence Registry.
- [ ] The application supervision tree starts a Workspace presence
      DynamicSupervisor.
- [ ] Workspace presence processes are addressed by durable Workspace ID.
- [ ] Starting a runtime for the same Workspace twice does not create duplicate
      active processes.
- [ ] The private Workspace runtime initializes with minimal inspectable state
      for the Workspace ID.
- [ ] The runtime modules remain hidden behind the Chat namespace or Chat
      runtime area.
- [ ] Web modules do not call the Registry, DynamicSupervisor, or private
      runtime module.
- [ ] The slice does not add presence users, monitors, PubSub events, or UI
      behavior.
- [ ] Focused runtime tests use `start_supervised!/1` where appropriate and
      prove start/find behavior without sleeps.

## Blocked by

None - can start immediately.
