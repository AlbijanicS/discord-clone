# 03 — Harden echo lifecycle and certify the diagnostic

**What to build:** The completed one-peer echo diagnostic behaves predictably during normal voice controls and terminal conditions, then has repeatable evidence that the full browser-to-server-to-browser media path works. It remains a temporary, development-only learning diagnostic rather than a permanent product telemetry surface.

**Blocked by:** 01 — Negotiate and route one Opus RTP echo stream; 02 — Play the echoed remote track in the Voice Owner Tab.

**Status:** ready-for-agent

- [ ] Local browser mute suppresses audible echo and unmute resumes it on the same established connection without renegotiation; it remains explicitly local behavior rather than server-enforced moderation.
- [ ] Silence after connected state does not time out the Voice Channel; an ended microphone track, explicit leave, signaling closure, or terminal PeerConnection failure cleans up browser and server resources idempotently and exposes an appropriate retryable state when applicable.
- [ ] Development/test diagnostics expose only safe aggregate lifecycle, remote-track/playback outcome, and inbound/echoed/dropped packet information; normal Voice Channel UI does not present packet counters.
- [ ] Automated tests cover mute/unmute, valid silence, terminal cleanup, and diagnostic privacy boundaries. A documented localhost headphone run proves connected state, remote-track attachment, audible echo, mute/unmute, clean leave, and clean rejoin.
