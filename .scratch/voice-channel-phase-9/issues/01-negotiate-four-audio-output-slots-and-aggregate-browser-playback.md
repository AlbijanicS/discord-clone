# 01 — Negotiate Four Audio Output Slots and Aggregate Browser Playback

**What to build:** Make the initial Voice connection reserve four fixed Audio
Output Slots and make the Voice Owner Tab play their separate remote tracks
through one stable aggregate `MediaStream` and one audio element. A browser
that cannot provide all four slots must fail before it leaves a partial Voice
Session behind.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] The browser preflights a microphone connection plus four receive-only
      audio lanes before requesting Voice admission.
- [ ] The server validates that the offer provides all four usable Audio Output
      Slots before committing the Voice Session.
- [ ] The server answer establishes four separate outbound audio tracks for
      the destination Voice Session without requiring later renegotiation.
- [ ] A successful browser connection retains each received
      `MediaStreamTrack` separately and adds the tracks to one stable aggregate
      `MediaStream` owned by the Voice Owner Tab.
- [ ] Releasing one slot does not replace or stop the other remote tracks.
- [ ] An incompatible browser receives a clear retryable compatibility error,
      all attempted browser/server resources are released, and retry requires
      an explicit User action.
- [ ] Existing one-Voice-Session signaling and cleanup behavior remains green.
