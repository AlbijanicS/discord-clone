# Use a browser-wide controller for Phase 2 microphone ownership

Status: accepted

Phase 2 will keep microphone capture in a browser-wide, in-memory controller for
the lifetime of the Voice Owner Tab, rather than in any individual LiveView
hook. The current LiveView only renders and controls that controller because
authenticated destinations are separate LiveViews and would otherwise stop
capture during normal navigation. The controller requests capture directly from
the Voice Channel click, owns `MediaStreamTrack` mute/release/late-result
cleanup, and uses best-effort same-browser tab messaging for automatic newest-
click-wins takeover. This does not create durable, server, or authoritative
voice state; Phase 6 remains responsible for server-enforced Voice Session
ownership.

## Considered Options

- Mount the controller in each workspace shell hook. Rejected because normal
  LiveView navigation destroys that hook and would release capture.
- Add server runtime ownership in Phase 2. Rejected because it would preempt
  the signaling and supervised Voice runtime work scheduled for Phases 3 and 6.
