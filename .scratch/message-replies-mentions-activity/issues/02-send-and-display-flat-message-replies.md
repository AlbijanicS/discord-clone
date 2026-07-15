# 02 — Send and Display Flat Message Replies

**What to build:** Let a Workspace Member select one earlier, non-deleted Message in the current Channel, confirm or cancel that target above the composer, send a durable Message Reply, and see a compact direct-parent preview in the normal Channel timeline. A reply may target another reply but never stores or renders a transitive chain, and replying does not implicitly mention the parent author.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] A Message may omit a reply target or reference exactly one earlier Message in the same Channel.
- [ ] Missing, cross-Channel, future-sequence, and already-deleted reply targets are rejected by the public Chat send workflow.
- [ ] Reply references are immutable after insertion and survive Channel runtime loss.
- [ ] A reply may target another reply while retaining only its direct parent.
- [ ] Non-deleted Message rows expose a stable Reply action; deleted Message rows do not.
- [ ] Selecting a target shows its current author label and truncated content above the composer with an accessible cancel control.
- [ ] Cancelling preserves the draft, successful sending clears the target, and ordinary validation failures preserve both draft and valid target.
- [ ] Reply previews are batch-loaded for bounded Message windows and do not introduce one query per Message.
- [ ] Context and authenticated Channel LiveView tests cover the complete behavior using stable element IDs.
- [ ] `mix precommit` passes.
