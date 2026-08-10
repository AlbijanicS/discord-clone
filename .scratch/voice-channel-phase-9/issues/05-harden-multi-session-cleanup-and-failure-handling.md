# 05 — Harden Multi-Session Cleanup and Failure Handling

**What to build:** Make every multi-Voice-Session lifecycle path remove the
affected Audio Routes and stale slot assignments without disturbing healthy
Sessions. Leave, negotiation races, track ending, peer failures, crashes, and
replacement Sessions must converge on safe room state.

**Blocked by:** 04 — Complete Four- and Five-Voice-Session Routing

**Status:** ready-for-agent

- [ ] Leaving during negotiation removes the Voice Session immediately and
      ignores late offer, ICE, and RTP work.
- [ ] Ordinary leave withdraws all routes involving the exact Voice Session
      before its Session and PeerConnection terminate.
- [ ] An ended accepted source track withdraws that source's routes to every
      destination while unrelated source routes continue.
- [ ] Mute and temporary `:disconnected` behavior retain eligible routes, while
      terminal peer states remove them.
- [ ] A Session crash or signaling-channel death removes only its routes and
      leaves healthy Voice Sessions usable.
- [ ] A replacement Voice Session cannot receive late work addressed to the
      old Voice Session ID or slot assignment.
- [ ] Durable access removal and Voice Channel deletion converge on the same
      exact route and Session cleanup behavior.
- [ ] A Forwarder failure preserves the existing isolated room-tree reset and
      requires clients to rejoin rather than resurrecting stale route state.
- [ ] Cleanup is idempotent and all stale route, slot, and PeerConnection
      delivery attempts are observable only through safe aggregate diagnostics.
