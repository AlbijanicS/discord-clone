# 02 — Preserve the Voice Owner Tab across authenticated navigation

**What to build:** A Workspace Member with active local microphone capture can navigate among authenticated destinations without interruption or a second permission prompt. The active Workspace exposes a global-rail microphone badge whose controls make the active Voice Channel, mute state, and Leave Voice action available outside the Workspace sidebar.

**Blocked by:** 01 — Capture, mute, and release microphone from a Voice Channel.

**Status:** ready-for-agent

- [ ] The browser-wide controller remains the local microphone owner while individual LiveViews mount and unmount.
- [ ] A newly rendered authenticated destination reattaches to and renders current controller state without requesting capture again.
- [ ] The active Workspace has a microphone badge in the global destination rail, and its non-modal controls popover exposes the active Voice Channel, state, Mute, and Leave Voice.
- [ ] The active Voice Channel is visually distinguishable whenever its Workspace sidebar is visible.
- [ ] Tests prove state reattachment and the global control surface using existing authenticated LiveView seams.
