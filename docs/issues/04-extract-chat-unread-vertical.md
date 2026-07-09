# Extract the Chat.Unread vertical out of the context

**Source:** `docs/architecture_deepening_plan.md` — Step #1 (+ 3d, 3e)

## What to build

Roughly a third of the `Chat` context is a self-contained Read State / Unread
Span subsystem that collaborates only with the three read-state schemas. Move the
whole vertical into its own deep module: the unread-count and read-summary
queries, the read-position mutations (mark-read, add/subtract unread range,
clear), the read-state lifecycle (initialize and delete a member's reads), the
send-path fan-out that records unread spans for recipients, and the read-state
PubSub topic (subscribe plus broadcast) end-to-end.

The `Chat` context keeps thin delegating wrappers for every public function that
exists today, so the web layer and its tests see no change. Message-send calls
the new module for its in-transaction fan-out and broadcasts the resulting
read-state changes after commit.

Delete the one-time unread backfill helper and its tests — confirm first that
nothing but tests references it. The new pure-algebra unit tests already cover
the span logic those tests exercised indirectly.

Register the domain terms **Read State** and **Unread Span** in the domain
glossary, since the new module is named after them.

## Acceptance criteria

- [ ] The unread/read-state vertical lives in its own module and owns its PubSub
      topic; the `Chat` context exposes the same public functions via thin
      delegations.
- [ ] The message-send path runs the fan-out inside its transaction and
      broadcasts read-state changes after commit — behavior unchanged.
- [ ] The one-time backfill helper and its tests are removed, with no non-test
      caller remaining.
- [ ] The domain glossary defines **Read State** and **Unread Span**.
- [ ] The web layer and its LiveView tests are untouched and green; existing
      unread integration tests pass.
- [ ] `mix precommit` is green.

## Blocked by

- `docs/issues/03-extract-unread-spans-pure-module.md` (the vertical calls the
  pure span algebra).
