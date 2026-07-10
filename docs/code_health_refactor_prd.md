# PRD: Code-Health Refactor (post-UUID)

Status: ready-for-agent
Author: senior review pass, 2026-07-10
Scope owner: Stefan
Related docs: `CLAUDE.md`, `AGENTS.md`, `CONTEXT.md`, `docs/entity_relationships.md`, `docs/style.md`

## Problem Statement

The Discord clone works well and is well-tested (651 tests passing, clean compile,
formatted), but it has grown faster than its abstractions. As the maintainer, when I
go to change one behavior I frequently have to edit the same shape in several places
and hope I found them all: the moderation-plus-audit flow exists five times, the
message-window/pagination helpers exist twice byte-for-byte, role names are spelled
as bare strings in three modules, and the channel view has become a single
2,297-line LiveView that is hard to reason about and has no LiveView-level test.
None of this is broken, but every one of these is a place where a future change is
slower and riskier than it should be, and two of them hide latent bugs. Today's
`id -> UUID` refactor also left some component `attr` types (and one
`String.to_integer/1` call on forged input) describing integers that are now UUID
strings.

## Solution

A staged, behavior-preserving refactor that makes the codebase compact, idiomatic,
and safe to change, done in an order that keeps the suite green at every step. As the
maintainer, after this work I can change the moderation/audit contract in one place,
trust a single source of truth for Workspace Roles, split the channel LiveView with a
real safety net under it, and rely on normalized error contracts and correct
component metadata. The refactor introduces no new product behavior — the observable
behavior at the `Workspaces`, `Chat`, and `ChannelLive.Show` seams stays identical,
which is exactly what the tests assert.

## User Stories

1. As the maintainer, I want the five moderation transaction functions (mute, unmute,
   timeout, remove-timeout, expire) collapsed behind one shared helper, so that a
   change to how a moderation action writes its audit event or broadcasts is made once.
2. As the maintainer, I want the three "end a moderation" variants (unmute,
   remove-timeout, expire) to share an `end_moderation_with_audit` helper, so that they
   cannot drift apart in their event-type/side-effect handling.
3. As the maintainer, I want the message-window and pagination-meta helpers that are
   duplicated between the Chat context and its Unread submodule extracted into one
   module, so that the pagination contract has a single definition.
4. As the maintainer, I want a single source of truth for Workspace Role names
   (owner/admin/member), so that adding or renaming a role does not mean grepping bare
   strings across the Workspaces and Chat contexts and the membership schema.
5. As the maintainer, I want the message-delete capability rule to live in one place
   and be shared by both contexts, so that `Chat` does not re-implement the
   owner/admin-can-delete-admin/member rule that `Workspaces` already owns.
6. As the maintainer, I want `Chat`'s mute/timeout participation checks to route through
   the Workspaces context instead of querying the moderation table directly with raw
   `"mute"`/`"timeout"` strings, so that the definition of "blocked from participating"
   lives in one context.
7. As the maintainer, I want the member-action availability computed for a whole member
   list in a small, bounded number of queries instead of ~3 queries per Workspace Member,
   so that opening a channel or refreshing after a moderation change does not fan out
   into an N+1.
8. As the maintainer, I want all public context functions to return a small, consistent
   set of error shapes (`{:error, reason}` or `{:error, tag, changeset}`), so that the
   web layer never has to match 5-tuples that leak `Ecto.Multi` internals.
9. As the maintainer, I want the channel LiveView split into cohesive pieces (message-
   window state, scroll anchoring, shared workspace/channel management events), so that
   each concern can be read and changed on its own.
10. As the maintainer, I want a LiveView test for the channel view created before the
    split, so that the split is protected by a real safety net rather than only by
    context tests.
11. As the maintainer, I want the public Chat functions that are only ever called from
    tests either removed or clearly marked as test seams, so that the context's public
    surface reflects what production actually uses.
12. As the maintainer, I want the redundant typing subscription (which subscribes to the
    same PubSub topic as the message subscription and is bypassed by a no-op stub in the
    view) resolved, so that typing has either its own topic or no separate function.
13. As the maintainer, I want component `attr` declarations that still say `:integer`
    updated to reflect UUID string identifiers, so that the component contracts are not
    actively misleading after today's UUID refactor.
14. As a Workspace Member interacting with a context menu, I want coordinate parsing to
    tolerate unexpected input instead of raising, so that a malformed or forged event
    cannot crash my channel view.
15. As the maintainer, I want the repeated "cast UUID or fall back to nil/empty/false"
    wrapper collapsed into one helper, so that the ~10 defensive getter functions read
    the same way.
16. As the maintainer, I want the repeated authorize-if-capable one-liners in Workspaces
    expressed through one small helper, so that the eighteen near-identical guard
    functions stop being copy-paste.
17. As the maintainer, I want the two nearly identical `insert_zero_unread_read_states`
    clauses in Unread merged, so that Read State initialization has one code path.
18. As the maintainer, I want the visible-read-range validation that the LiveView does
    (and the context then re-does) consolidated so validation is not duplicated across
    the web and context layers.
19. As the maintainer, I want a regression test proving a Workspace Role change only ever
    produces an audit `event_type` that the WorkspaceAuditEvent schema allows, so that an
    unexpected transition cannot fail the whole role-change transaction.
20. As the maintainer, I want a test proving a second mute after an ended mute is allowed
    (or explicitly rejected), so that the moderation uniqueness constraint's real behavior
    is pinned down.
21. As the maintainer, I want Credo (strict) added to the dev/test toolchain, so that the
    duplication and complexity this refactor removes cannot silently regrow.
22. As the maintainer, I want the giant home LiveView test file split by feature area, so
    that test failures are easier to locate and the file is navigable.
23. As the maintainer, I want `@spec`s and `@doc`s added to the Workspaces and Chat public
    APIs as they are touched, so that Dialyzer can be added later without noise.
24. As a Workspace Member, I want every one of these changes to be invisible to me —
    messages, presence, typing, moderation, unread counts, invites, and audit logs behave
    exactly as before — so that a "cleanup" release never regresses my experience.
25. As the maintainer, I want each step to leave `mix precommit` green, so that the
    refactor can be shipped in small reviewable slices rather than one big risky merge.

## Implementation Decisions

Work proceeds in the staged order below. Each stage is independently shippable and must
leave the full suite green.

**Stage 1 — Mechanical cleanup (no behavior change).**
- Introduce a `UUIDIdentifier` cast-or-fallback helper and route the ~10 defensive
  getters (in Workspaces, Chat, Unread, Runtime) through it.
- Fix component `attr` types that declare `:integer` for what are now `binary_id`
  identifiers (member-actions menu, shell). Make context-menu coordinate parsing
  defensive instead of calling `String.to_integer/1` on event input.
- Remove the redundant `else` passthrough in `Workspaces.fetch_channel/3`.
- Decide the fate of the test-only Chat functions (subscribe-to-typing, add-unread-range,
  clear-unread, list-recent-messages, list-older-messages): delete if truly unused in
  production, or annotate `@doc false` as deliberate test seams. Resolve the typing-topic
  redundancy (typing currently shares the message topic and the view uses a no-op stub).

**Stage 2 — Test strengthening (before any risky extraction).**
- Add a `ChannelLive.Show` LiveView test (new seam) covering: initial render, sending a
  message, deleting a message, toggling a reaction, the unauthorized-access redirect, and
  moderation-menu visibility for different actor/target Role combinations.
- Add the two latent-bug regression tests (Role-change audit `event_type` allow-list;
  second-mute-after-ended-mute uniqueness behavior).

**Stage 3 — Helper extraction.**
- Extract a `Chat.MessageWindow` module holding the message-window query + meta helpers;
  both `Chat` and `Chat.Unread` call it. No behavior change; verified through the Chat seam.
- Merge the two `insert_zero_unread_read_states` clauses in Unread behind a single
  row-shaping function.
- Introduce `run_moderation_multi/2` and `end_moderation_with_audit/…` in Workspaces and
  reduce the five moderation functions to thin callers.

**Stage 4 — Context/API cleanup.**
- Add a `Workspaces.Roles` module (owner/admin/member + `all/0` + capability predicates);
  replace bare role strings in Workspaces, the membership schema helper, and Chat.
- Route `Chat`'s message-delete rule and mute/timeout participation checks through
  Workspaces capability functions rather than direct schema queries.
- Add a batched `available_member_actions` variant that loads active moderations for all
  target Workspace Members in one query; the channel view uses it in mount and on refresh.
- Normalize all public context error tuples to `{:error, reason}` / `{:error, tag,
  changeset}`; log `Multi` failure internals inside the context instead of returning them.
  Update the member-actions web helper and every affected caller `case`.

**Stage 5 — LiveView simplification.**
- Split `ChannelLive.Show`: peel off message-window state (trim/merge/boundary/meta
  family) and scroll-anchoring helpers into their own modules; extract the shared
  workspace/channel management event handlers into a module reusable by the home/entry
  LiveViews (verify against the existing home LiveView before extracting).
- Consolidate the visible-read-range validation so it is not performed in both the view
  and the context.

**Stage 6 — Runtime/process notes.**
- No behavioral change to the OTP timers. Add a short doc line to `docs/` describing lazy
  timeout expiry (an active future timeout expires on next relevant action if no one is
  online when it elapses). Confirm whether the 50ms disconnect grace is intentional.

**Stage 7 — Static analysis.**
- Add Credo (strict, dev/test only), fix or annotate its findings, run a formatting pass.
- Add `@spec`/`@doc` to touched public APIs; defer adding Dialyzer until error tuples are
  normalized (Stage 4) so it starts clean.

Cross-cutting decisions:
- The domain glossary vocabulary (Workspace, Workspace Member, Workspace Role, Channel,
  Read State, Unread Span, Landing Channel) is used throughout; no glossary terms change.
- No schema/migration changes are required by this refactor. The moderation uniqueness
  constraint and the audit `event_type` allow-list are pinned down by new tests, not
  altered, unless Story 19/20 reveal a real defect — in which case the fix is proposed
  separately.
- Contexts remain the only owners of business logic and data access; the web layer stays
  thin. `Chat -> Workspaces` calls introduced in Stage 4 keep the dependency acyclic.

## Testing Decisions

- Good tests here assert **external behavior at the highest seam**, not internal shape.
  Because this is a behavior-preserving refactor, the existing context tests are the
  primary oracle: if `workspaces_test.exs` and `chat_test.exs` stay green through every
  stage, the extraction is correct. Tests should not reach into private helpers or assert
  on `Ecto.Multi` step names.
- Three seams, all as high as possible, no new low-level seams:
  1. `DiscordClone.Workspaces` public API — existing `test/discord_clone/workspaces_test.exs`.
  2. `DiscordClone.Chat` public API — existing `test/discord_clone/chat_test.exs`
     (the extracted `Chat.MessageWindow` is exercised through this seam, not separately).
  3. `DiscordCloneWeb.ChannelLive.Show` via `Phoenix.LiveViewTest` — a new file; this is
     the one new seam, added in Stage 2 before the Stage 5 split.
- Prior art: the LiveView test style should follow
  `test/discord_clone_web/live/workspace_live/home_test.exs` (stable DOM IDs,
  `element/2`/`has_element?/2`, `render_submit`/`render_change`, no raw-HTML assertions),
  and the invite controller test for the redirect/flash pattern. Runtime tests
  (`channel_runtime_test.exs`, `runtime_test.exs`) are the model for any process-timing
  assertions — `start_supervised!/1`, `Process.monitor/1` + `assert_receive {:DOWN, …}`,
  `:sys.get_state/1`, never `Process.sleep/1`.
- New tests to add: the `ChannelLive.Show` coverage above; the Role-change audit
  allow-list regression; the second-mute uniqueness regression. Both allowed and forbidden
  paths are asserted (moderation menus must be present for permitted actor/target Role
  pairs and absent for forbidden ones, including forged member-action events routed
  through the LiveView event path, not only the context).
- The oversized `home_test.exs` is split by feature area (unread/read-state, moderation,
  invites, channel management) with no assertion changes — purely reorganization.

## Out of Scope

- Any new product feature (uploads, voice-channel simulation, private channels, mentions,
  rate limiting, analytics). This PRD is cleanup only.
- Schema or migration changes, except a fix that a Story 19/20 regression proves necessary
  — which would be split into its own change.
- Adopting Phoenix Presence in place of the hand-rolled presence runtime (a `style.md`
  future direction, deliberately deferred).
- Adding Dialyzer now (deferred to after error-tuple normalization).
- Rewriting the OTP timer logic; it is correct and only gets a documentation note.
- Any change to the UUID identifier scheme itself (that refactor already landed today).

## Further Notes

- Verified state at time of writing: `mix format --check-formatted` passes,
  `mix compile --warnings-as-errors` is clean, `mix test` is 651 tests / 0 failures. The
  `Postgrex … disconnected` line during the run is a crash/kill test tearing down a locked
  connection, not a failure.
- The strongest parts of the codebase — the persist-first `FOR UPDATE` message sequencing,
  the invite-acceptance `Multi`, and the `WorkspaceServer`/`ChannelServer` token-and-ref
  timer discipline — are intentionally on a do-not-touch list until their tests are green
  and should be left structurally as-is.
- Suggested review size: ship Stage 1, then Stage 2, then one stage per PR. Each stage
  ends with `mix precommit`. If any stage cannot keep the suite green without an assertion
  change, stop and treat it as a behavior change, not a refactor.
- Publishing decision: this PRD lives in the repo at `docs/` by the maintainer's choice;
  it was not filed on the GitHub tracker.
