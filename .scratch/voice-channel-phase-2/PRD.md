# Phase 2: Browser Microphone Ownership Spike PRD

Status: ready-for-agent

This PRD specifies Phase 2 of the accepted Voice Channel roadmap. It follows
ADR 0016 and ADR 0017: a Voice Channel is a durable Workspace resource; this
phase proves only the Voice Owner Tab's browser-side microphone lifecycle. It
does not create a Voice Session, signaling connection, or media connection.

## Problem Statement

A Workspace Member can create and see durable Voice Channels, but clicking one
does not yet prove that the browser can safely request, mute, release, and clean
up microphone capture. A naive LiveView hook would also be destroyed whenever
the user navigates between authenticated destinations, unexpectedly stopping
capture even though a voice application should let the Voice Owner Tab continue
while the user reads text Channels, Direct Conversations, Friends, or Activity.

The application needs a small, understandable microphone ownership spike before
WebRTC signaling and Voice runtime work begins. It must make browser permission
and failure states visible, prevent obvious multi-tab capture conflicts, and
leave no hidden microphone capture after a user leaves, logs out, navigates
away, or loses their device.

## Solution

Add a browser-wide, in-memory microphone controller for the lifetime of one
Voice Owner Tab. A Workspace Member explicitly starts capture by clicking a
Voice Channel; the controller calls the browser microphone API directly from
that gesture, owns the resulting local audio track, and reports compact UI
state to whichever authenticated LiveView is currently visible.

The active Workspace gets a microphone badge in the global destination rail.
Its badge opens a compact popover that shows the active Voice Channel, current
state, Mute, Leave Voice, and actionable retry/error feedback. When the
Workspace channel sidebar is visible, the active Voice Channel is highlighted.
The controller survives LiveView navigation because it is not owned by any one
LiveView hook. It uses best-effort same-browser tab coordination so the newest
Voice Channel click takes ownership and causes a prior owner tab to release.

## User Stories

1. As a Workspace Member, I want clicking a Voice Channel to request microphone access, so that I only see the browser permission prompt when I use a voice feature.
2. As a Workspace Member, I do not want microphone permission requested on page load, so that simply opening the app never starts capture.
3. As a Workspace Member, I want a Voice Channel click to be a real browser user gesture, so that the permission prompt can open reliably.
4. As a Workspace Member, I want to see that the app is waiting for browser permission, so that a pending prompt does not look like a frozen app.
5. As a Workspace Member, I want to see that local microphone capture is active for my chosen Voice Channel, so that I understand the current local state.
6. As a Workspace Member, I want to mute without leaving, so that I can remain ready to resume speaking.
7. As a Workspace Member, I want unmute to restore my local audio track without another permission request, so that mute feels immediate.
8. As a Workspace Member, I want Leave Voice to release the microphone fully, so that the browser capture indicator turns off.
9. As a Workspace Member, I want the active Voice Channel highlighted in its Workspace sidebar, so that I can identify where my microphone is assigned.
10. As a Workspace Member, I want the active Workspace to carry a microphone badge in the global destination rail, so that I can see active voice while using other destinations.
11. As a Workspace Member, I want the microphone badge to open Voice controls, so that I can mute or leave from authenticated destinations outside the selected Workspace.
12. As a Workspace Member, I want a clear message when I deny permission, so that I know how to retry after changing browser settings.
13. As a Workspace Member, I want a clear message when no microphone is available, so that I can connect or select a usable input device outside this phase.
14. As a Workspace Member, I want an explanation when the browser requires a secure connection, so that I understand why deployed plain HTTP cannot capture while localhost development can.
15. As a Workspace Member, I want a clear unsupported-browser and unknown-error state, so that failures are not mistaken for a successful join.
16. As a Workspace Member, I want an error or release message if my microphone is unplugged or capture ends externally, so that the UI never claims I still own audio.
17. As a Workspace Member, I want to keep local microphone ownership while I navigate among authenticated app destinations, so that normal navigation does not end voice use.
18. As a Workspace Member, I want a newly rendered LiveView to reflect the existing microphone state, so that navigation does not trigger another browser permission prompt.
19. As a Workspace Member, I want logging out to release the microphone, so that capture cannot remain active outside my authenticated session.
20. As a Workspace Member, I want leaving while a browser prompt is pending to remain effective, so that a late Allow action does not silently resume capture.
21. As a Workspace Member, I want clicking the active Voice Channel repeatedly to be safe, so that I do not create duplicate prompts or tracks.
22. As a Workspace Member, I want switching to a different Voice Channel to release the prior capture before starting the new one, so that this spike has one clear local owner.
23. As a Workspace Member, I want a newer Voice Channel click in another app tab to take over automatically, so that the same browser does not keep two microphone owners.
24. As a Workspace Member, I want the previous owner tab to explain that another tab took over, so that capture ending is not mysterious.
25. As a Workspace Member, I want simultaneous same-browser requests to resolve predictably, so that tabs do not continually fight for ownership.
26. As a keyboard user, I want to join a Voice Channel and open Voice controls with standard button keys, so that I do not need a mouse.
27. As a screen-reader user, I want controls to identify their purpose and state changes to be announced, so that microphone state is understandable without visual indicators.
28. As a keyboard user, I want to close the Voice controls popover with Escape and return to its trigger, so that focus remains predictable.
29. As a privacy-conscious Workspace Member, I do not want device IDs, microphone permissions, selected Voice Channels, mute state, or ownership claims stored durably, so that this spike keeps browser-only state ephemeral.
30. As a developer, I want Phase 2 to prove microphone ownership without signaling or WebRTC transport, so that later network failures can be isolated from browser capture behavior.
31. As a future maintainer, I want Phase 2 marked complete in the roadmap only after all its build and proof criteria are complete, so that the roadmap remains trustworthy.

## Implementation Decisions

- Preserve the accepted vocabulary: Voice Channel is durable; Voice Session is later runtime-only; Voice Owner Tab is the browser tab with local microphone ownership.
- Add one browser-wide microphone controller as the owner of local `MediaStream` and `MediaStreamTrack` lifecycle. It is in-memory only for the tab lifetime.
- Treat current LiveViews and their hooks as UI adapters. They attach to the controller on mount, render its current state, and detach without stopping a still-owned track during authenticated navigation.
- Start `getUserMedia` directly from the Voice Channel button's browser click handler. Do not wait for a server event before requesting capture.
- Use the following local states: idle, requesting permission, capturing, muted, permission denied, no device, insecure context, unsupported, released, externally ended, and taken over by another tab. Unknown browser failures use a safe generic error presentation.
- Map browser capability and microphone failures to those user-understandable states. Localhost is supported without separately configuring HTTPS; non-local deployed capture requires a secure browser context.
- Muting sets every owned local audio track's `enabled` property to false. Unmuting restores it to true. Neither action stops the track or requests permission again.
- Leaving, logging out, switching Voice Channels, hook removal outside authenticated voice UI, page/tab teardown on a best-effort basis, late permission resolution after leave, and externally ended tracks stop all owned tracks and clear local ownership.
- A late `getUserMedia` resolution after Leave Voice is immediately stopped and discarded. It must not re-enter capturing state.
- The active Voice Channel row is an accessible button rather than a route. Clicking the same active row is idempotent; clicking a different row performs release before a new request, with conflicting join actions disabled during request/switch work.
- Add a microphone badge to the active Workspace in the global destination rail. The badge is an accessible control that opens a non-modal Voice controls popover containing Voice Channel identity, state, Mute, Leave Voice, retry when applicable, and a close action.
- Highlight the active Voice Channel whenever its Workspace sidebar is rendered. The global-rail badge provides the cross-destination control surface.
- Use a polite live-status region for capture, mute, release, takeover, and error updates. The popover closes with Escape and returns focus to its trigger.
- Use best-effort same-browser tab messaging with a generated tab identifier. A newer Voice Channel click takes over automatically; equal click timestamps use the tab identifier to break the tie deterministically. The losing tab releases and reports takeover.
- Browser tab coordination is not security or durable authorization. Do not add a database row, session value, device preference, Phoenix Channel, Voice process, or server-side Voice Session in this phase. Phase 6 will enforce Voice Session ownership authoritatively.
- Keep all existing Voice Channel authorization and visibility behavior. This phase changes the authenticated Voice Channel UI from display-only to browser-local capture controls; it does not add a Voice Channel route or roster.
- After implementation, and only after the build and proof criteria below are satisfied, update the Phase 2 row in the Voice Channel roadmap to `Complete` with the completion date. Replace its `Implementation Notes` with concise files changed, final decisions, behavior proven, tests run, and follow-up work. Do not mark the phase complete merely because the code compiles.

## Testing Decisions

- Good tests prove public browser-controller behavior and visible application behavior, rather than private listener arrangement or raw HTML output.
- The primary new seam is the browser microphone controller's public lifecycle interface. Keep browser API access behind that seam so tests can provide fake media devices, streams, tracks, tab messages, and lifecycle events.
- Controller tests should prove explicit gesture initiation; pending, success, mute/unmute, release, repeated-click idempotence, channel switch, late permission resolution, externally ended track, unknown errors, logout, and teardown cleanup.
- Controller tests should prove that mute toggles track enabled state while Leave stops tracks, and that no stopped or late stream becomes active.
- Controller tests should prove automatic cross-tab takeover, newest-click-wins behavior, deterministic ties, losing-tab cleanup, and safe behavior when tab messaging is unavailable.
- Add browser-level/manual localhost verification for real permission prompt, permission denial, no-device behavior where reproducible, mute/unmute, visible browser capture indicator, release indicator removal, navigation reattachment, logout cleanup, two-tab takeover, and device/track ending.
- Add LiveView tests at the existing authenticated workspace and global-destination-rail seams. Assert stable element IDs and accessible attributes with `element/2` and `has_element?/2`, not raw HTML strings.
- LiveView tests should prove Voice Channel controls are visible only in the authenticated UI, that active/muted/error state surfaces and the global-rail badge/popover render, and that the active channel is distinguishable when its Workspace sidebar is present.
- LiveView tests should cover keyboard-accessible control semantics, Escape close/focus behavior where practical, and stable status-region presence. Real browser permission itself remains a controller/manual-browser concern.
- Reuse the existing Node hook tests as prior art for isolated browser behavior and the Workspace shell management LiveView tests as prior art for Voice Channel and rail UI assertions.
- Run focused JavaScript and LiveView tests while implementing, then run `mix precommit` after all application changes. Record the exact checks and manual verification performed in the Phase 2 roadmap notes before marking it complete.

## Out of Scope

- Phoenix Channel signaling, SDP, ICE, `RTCPeerConnection`, ExWebRTC, RTP, remote audio playback, or media forwarding.
- Voice runtime processes, a Voice Session record, server-side roster, capacity enforcement, heartbeat, reconnect protocol, or server-authoritative ownership.
- Deafen, a local audio meter, speaking indicators, push-to-talk, device picker, device preferences, noise controls, recording, transcription, video, or screen sharing.
- Persisting microphone device IDs, permissions, selected Voice Channel, mute state, or tab ownership.
- A Voice Channel route, a Voice Channel detail screen, or durable changes to existing Workspaces authorization.
- Cross-device ownership coordination and any guarantee beyond best-effort same-browser tab messaging.
- Production HTTPS, STUN/TURN, network deployment, or automated permission emulation beyond the manual localhost checklist.

## Further Notes

- This PRD implements only Phase 2 of the Voice Channel roadmap and must preserve the boundaries in ADR 0016 and ADR 0017.
- A browser-wide controller is required because the app's authenticated destinations are distinct LiveViews even when they share visual shell components.
- The feature uses the existing authenticated browser pipeline and `:require_authenticated_user` LiveView session. No new route or router scope is required, because it changes controls inside those existing authenticated destinations.
- Phase 2 intentionally proves browser microphone ownership before any server participates. Phase 3 introduces signaling; Phase 6 introduces authoritative Voice runtime ownership.
