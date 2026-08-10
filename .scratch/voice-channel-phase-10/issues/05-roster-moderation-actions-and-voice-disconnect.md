# 05 — Roster Moderation Actions and Voice Disconnect

**What to build:** Owners and admins can take their existing permitted Workspace Member actions from Voice Channel Roster rows and can silently Voice Disconnect an eligible target.

**Blocked by:** 04 — Enforce Workspace Moderation in Voice.

**Status:** ready-for-agent

- [ ] Roster rows reuse existing member-action authorization: regular members, self, and owner targets do not receive unauthorized action menus.
- [ ] Voice Disconnect ends only the target's current Voice Session and performs normal server/browser media cleanup without changing Workspace membership or durable moderation state.
- [ ] Voice Disconnect sends no explanatory message, notification, or special retry prompt; after cleanup, the ordinary Join control remains available to an eligible User.
- [ ] LiveView, authorization, and lifecycle tests prove permitted actions and reject unauthorized or stale Voice Disconnect attempts.
