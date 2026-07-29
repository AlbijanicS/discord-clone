# 02 — Add correlated fake offer and answer signaling

**What to build:** An admitted browser can submit one bounded fake offer on its own Voice signaling connection and receive a fake answer through the same correlated request/reply interaction that the future server PeerConnection will use.

**Blocked by:** 01 — Establish authenticated Voice topic admission.

**Status:** ready-for-agent

- [ ] A fake offer requires the exact current Signaling Session ID and receives one correlated fake answer reply without broadcasting to other topic subscribers.
- [ ] The fake offer contract uses explicit placeholder values, field-level malformed-input feedback, and the temporary Phase 3 decoded-payload and text-field limits.
- [ ] Missing, stale, mismatched, and cross-topic Signaling Session IDs receive safe generic failures.
- [ ] Browser-adapter and authenticated Channel integration tests prove the correlated reply contract and its validation behavior.
