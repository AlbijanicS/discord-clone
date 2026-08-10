# 01 — Live Voice Channel Roster

**What to build:** Workspace Members can see an admission-ordered Voice Channel Roster beneath every Voice Channel. Each row shows the existing initial-avatar treatment and username. Safe, complete roster snapshots make joins and leaves appear immediately in connected Workspace views without refresh.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] Every Voice Channel in a Workspace renders only its own active Voice Sessions, in admission order, with familiar username-initial identity.
- [ ] Admitting, leaving, terminal cleanup, and replacement of a Voice Session publish a complete safe roster snapshot; connected Workspace views update immediately.
- [ ] Browser-facing roster data excludes PIDs, PeerConnection handles, SDP, ICE, raw RTP, and other runtime internals.
- [ ] Runtime and authenticated Workspace LiveView tests prove the observable roster behavior without asserting private process state.
