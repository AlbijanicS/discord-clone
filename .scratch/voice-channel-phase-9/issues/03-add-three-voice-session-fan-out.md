# 03 — Add Three-Voice-Session Fan-Out

**What to build:** Extend slot-aware routing from a pair to a three-Voice-
Session room. Every ready Voice Session must send to the other two and receive
from the other two, while a Session that is still negotiating does not block
ready pairs.

**Blocked by:** 02 — Make Audio Routes Slot-Aware

**Status:** ready-for-agent

- [ ] Three eligible Voice Sessions create all six directed Audio Routes.
- [ ] Each source reaches both other destinations and never reaches itself.
- [ ] Each destination uses separate Audio Output Slots for its two sources.
- [ ] Two ready Voice Sessions can exchange audio while the third is still
      negotiating.
- [ ] Routes involving the third Voice Session appear as soon as its source and
      destination readiness is complete, without restarting ready Sessions.
- [ ] A source keeps its assigned destination slot while it remains active.
- [ ] Pure Forwarder tests and a real Session-level proof cover the three-
      Voice-Session matrix and both setup orders.
