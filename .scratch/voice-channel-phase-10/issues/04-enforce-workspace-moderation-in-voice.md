# 04 — Enforce Workspace Moderation in Voice

**What to build:** Existing Workspace Mute and Workspace Timeout have their promised Voice consequences: muted Users remain connected to listen but cannot transmit, while timed-out Users are removed and cannot rejoin until the timeout ends.

**Blocked by:** 01 — Live Voice Channel Roster.

**Status:** ready-for-agent

- [ ] Applying Workspace Mute stops the target's outgoing audio at the server even if browser metadata claims an unmuted state; the target remains an Audio Destination.
- [ ] The roster shows the same generic effective-muted badge for Local Mute and Workspace Mute, without exposing reasons or moderator identity.
- [ ] Applying Workspace Timeout ends the matching Voice Session, clears its roster state, and rejects further Voice admission until durable expiry restores ordinary eligibility.
- [ ] Public Voice and Workspace moderation tests prove mute, unmute, timeout, expiry, and privacy-safe roster effects through observable behavior.
