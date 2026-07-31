# 02 — Play the echoed remote track in the Voice Owner Tab

**What to build:** A Workspace Member who joins the Voice Channel receives the server echo as remote browser audio and hears it automatically when browser policy permits. The browser-wide Voice Owner Tab controller owns one remote audio element, so playback survives normal LiveView rendering changes and is released with the rest of the Voice attempt. If autoplay is blocked, the user can enable audio without reconnecting.

**Blocked by:** 01 — Negotiate and route one Opus RTP echo stream.

**Status:** ready-for-agent

- [ ] The remote WebRTC track attaches to a controller-owned audio element and starts playback automatically after the user’s Join Voice action when the browser permits it.
- [ ] A blocked playback attempt produces an accessible Enable audio fallback that retries playback without creating another Voice Channel connection or another offer/answer exchange.
- [ ] Explicit leave, takeover, terminal browser connection failure, and teardown detach remote playback and close/release browser media resources exactly once.
- [ ] Browser tests use fake peer/media seams to verify track attachment, automatic playback, policy-blocked fallback, and cleanup without depending on a physical microphone.
