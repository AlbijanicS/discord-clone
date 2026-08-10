# 04 — Complete Four- and Five-Voice-Session Routing

**What to build:** Complete the capped room matrix for four and five active
Voice Sessions. Preserve fixed slot positions, reuse only released slots, and
keep admission safe when several Users try to join together.

**Blocked by:** 03 — Add Three-Voice-Session Fan-Out

**Status:** ready-for-agent

- [ ] Four eligible Voice Sessions create all 12 directed Audio Routes.
- [ ] Five eligible Voice Sessions create all 20 directed Audio Routes.
- [ ] Every Voice Session hears all other active Voice Sessions and never hears
      itself.
- [ ] A source remains in its current destination slot when another User joins
      or leaves.
- [ ] A released slot becomes silent and the next source receives the first
      available slot without moving existing sources.
- [ ] Four- and five-Session rooms do not require renegotiation when Users join
      or leave.
- [ ] Concurrent admission never exceeds five Voice Sessions; the next join
      receives the normal room-full result and no existing User is displaced.
- [ ] Route-matrix and slot-reuse tests cover all room sizes from one through
      five.
