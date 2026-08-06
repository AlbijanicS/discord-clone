# 04 — Withdraw routes through canonical Voice Session cleanup

**What to build:** Extend canonical Voice Session removal so every lifecycle
path removes every Audio Route involving that exact Session without disturbing
a healthy or replacement Voice Session.

**Blocked by:** 02 — Route audio between two ready Voice Sessions.

**Status:** ready-for-agent

- [ ] Ordinary leave and removal withdraw a Session's routes before the Session
  is stopped; an unexpected Session crash withdraws them when its monitor
  reports the crash.
- [ ] Channel death, terminal peer state, command timeout, access removal, and
  Voice Channel deletion converge on the same idempotent route withdrawal.
- [ ] RTP queued before or after removal cannot reach a stopped or replacement
  Voice Session.
- [ ] Removing or failing one Voice Session leaves a healthy peer Session and
  its routes intact when the room otherwise remains eligible.
