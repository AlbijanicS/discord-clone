# Extract a shared MemberActions helper and collapse the triplicated handlers

**Source:** `docs/architecture_deepening_plan.md` — Step #4

## What to build

The member-moderation event handlers (promote/demote/mute/timeout, kick, ban,
unban) are copy-pasted across three LiveView surfaces (the channel view, the
audit log, and the invite screen). The dispatch to the `Workspaces` context and
the error-to-flash mapping are identical across all three; only the post-success
data refresh differs per surface. The rendering of the moderation menu was
already consolidated — this finishes the job for the behavior.

Introduce one plain helper module that owns the whole moderation-action contract:
parameter parsing, the allowed-action whitelist, dispatch to the matching
`Workspaces` function, the error flashes, and the success flashes. Each surface
keeps only a thin `handle_event` that delegates and supplies a callback
describing what that surface re-fetches and re-assigns on success (the channel
view refreshes its moderation state; the audit log refreshes audit events plus
members, and banned members for unban; the invite screen refreshes members).

Resolve the workspace-id source explicitly — the surfaces read it from different
assigns — rather than assuming a single assign name.

## Acceptance criteria

- [ ] One module owns the action whitelist, dispatch, and the full flash
      contract (both error and success messages).
- [ ] Each of the three surfaces delegates its moderation `handle_event` clauses
      to the helper and supplies only a success-refresh callback.
- [ ] Every surface behaves exactly as before: same flashes, same lists
      refreshed after each action.
- [ ] Changing the action whitelist or the error contract requires editing one
      file.
- [ ] Existing LiveView tests for the three surfaces pass unchanged.
- [ ] `mix precommit` is green.

## Blocked by

None - can start immediately.
