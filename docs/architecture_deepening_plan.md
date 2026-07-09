# Architecture Deepening Plan

Ordered, executable plan to deepen five shallow spots in the codebase. Produced
from an architecture review + grilling session. Every decision below is
**locked** — do not re-litigate; execute.

Vocabulary is from the `codebase-design` skill (module, interface, deep/shallow,
seam, leverage, locality) and the domain glossary in `CONTEXT.md`.

## Governing principle (applies to all steps)

**Contexts stay the facade.** `DiscordClone.Chat` and `DiscordClone.Workspaces`
remain the *only* modules the web layer calls. Every refactor happens **behind**
the context seam: new modules are internal collaborators the context delegates
to. `chat.ex`/`workspaces.ex` keep thin one-line delegating wrappers for every
public function that exists today.

Consequences:

- The web layer and its LiveView tests are untouched **except** the specific
  call sites named in steps #3 and #4.
- Each step is one small commit that ends with **`mix precommit` green**
  (`compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`).
- If a step can't stay small, split it — but keep the seam stable so partial
  work never breaks the public API.

## Facts established during review (so you don't re-derive them)

- The web layer **never** references the runtime process modules
  (`ChannelServer`, `WorkspaceServer`, the supervisors, the registries). Only
  `Chat` does. Verified by grep over `lib/discord_clone_web/`.
- `apply_message_unread_fanout!` runs **inside** `send_message`'s
  `Repo.transaction` closure (`chat.ex:749` → `761`) and returns
  `read_state_changes`. It is a plain transaction, **not** an `Ecto.Multi`.
  Broadcasting of those changes happens **after** commit
  (`chat.ex:731`, `broadcast_channel_read_state_changes`).
- `backfill_unread_ranges_from_channel_reads/1` is called from **tests only**
  (7 refs in `chat_test.exs`) plus its own helper `backfill_channel_read_state!`.
  No migration/seed/mix task calls it.
- `presence.ex:104` (`member.role == role`, in `online_members_by_role/3`)
  **groups members by role for the sidebar display** — it is not a permission
  check. Leave it alone.

## Build order

1. **#3** — Delete-permission core (small, fixes a real drift bug)
2. **#4** — MemberActions helper (web-only, mechanical)
3. **#1 + #5** — Extract `Chat.Unread` + `Chat.Unread.Spans` (the big one)
4. **#2** — `Chat.Runtime` facade (trickiest; process lifecycle + tests)

---

## Step 1 — #3 Unify the message-delete permission rule

**Problem.** The delete rule (*actor `owner|admin`, author `admin|member`*) is
written twice and can drift: enforcement in `chat.ex:942`
(`authorize_delete_message/2`) and a re-derivation in `show.ex:1514`
(`moderator_can_delete_message?/3` + `author_role_deletable?/2` +
`current_workspace_role/2`). The UI can show a delete button the context then
rejects, or hide one it would allow.

**Design.** One pure core predicate over roles is the single source of truth;
both entry points call it.

1. In `chat.ex`, add a pure private predicate, e.g.:

   ```elixir
   # true iff an actor with actor_role may delete a message authored by author_role
   defp deletable?(actor_role, author_role)
        when actor_role in ["owner", "admin"] and author_role in ["admin", "member"],
        do: true
   defp deletable?(_actor_role, _author_role), do: false
   ```

   (Author-deletes-own stays a separate clause of `authorize_delete_message` —
   `%Message{user_id: id}, id -> :ok` — it is not a moderation decision.)

2. Rewrite `authorize_delete_message/2` (the multi-role clause at `chat.ex:944`)
   to resolve actor + author roles via `actor_target_roles` and then call
   `deletable?/2` instead of inlining the `when role in [...]` guards.

3. Add a public UI-facing predicate that reuses the member map the LiveView
   already holds (no DB round-trip per message):

   ```elixir
   def can_delete_message?(%Scope{user: %User{id: uid}}, %Message{} = message, member_by_user_id) do
     actor_role  = role_of(member_by_user_id, uid)
     author_role = role_of(member_by_user_id, message.user_id)
     message.user_id == uid or deletable?(actor_role, author_role)
   end
   ```

   `role_of/2` is the map lookup currently living in `show.ex`
   (`current_workspace_role/2`).

4. In `show.ex`: delete `moderator_can_delete_message?/3`,
   `author_role_deletable?/2`, `current_workspace_role/2` and their
   `["owner","admin"]` / `["admin","member"]` literals. Replace the call site
   with `Chat.can_delete_message?(current_scope, row.message, member_by_user_id)`.

**Do not touch** `presence.ex:104` (display grouping, not a capability check).

**Acceptance.**
- Enforcement and UI are provably identical — both route through `deletable?/2`.
- Existing delete tests in `chat_test.exs` still pass unchanged.
- No new DB queries introduced in the render path (predicate reads the map).
- `mix precommit` green.

**Deletion test.** The new predicate absorbs three private helpers in `show.ex`
— complexity concentrates in `Chat`, the source of truth.

---

## Step 2 — #4 Collapse the triplicated member-action handlers

**Problem.** The `member_action` / `kick_member` / `ban_member` (`+ unban_member`)
`handle_event` clauses are copy-pasted across three LiveViews:
`channel_live/show.ex:870,943,972`, `workspace_live/audit_log.ex:128,196,227,260`,
`workspace_live/invite_new.ex:193,254,281`. The **dispatch** (action →
`Workspaces.*`) and the **error→flash mapping** are byte-identical; only the
**success data-refresh** differs per surface. `MemberActionsMenu` already
consolidated the *rendering*; this finishes the job for the *handlers*.

**Design.** A plain function helper owning the whole flash contract; each
surface supplies only a refresh callback.

1. Create `lib/discord_clone_web/live/workspace_live/member_actions.ex`
   (module `DiscordCloneWeb.WorkspaceLive.MemberActions`), a plain module (not a
   LiveComponent, not a macro). Public entry points, one per event:

   ```elixir
   def run(socket, %{"action" => action} = params, refresh)   # member_action
   def kick(socket, params, refresh)
   def ban(socket, params, refresh)
   def unban(socket, params, refresh)
   ```

   Each helper owns: `String.to_integer/1` on `user_id`, reading `workspace_id`
   from `socket.assigns` (the surfaces use `selected_workspace.id` /
   `selected_channel...` — normalize on a small accessor the caller passes or a
   documented assign contract), the action whitelist, dispatch to the matching
   `Workspaces.*` function, the `{:error, _}` / `{:error, _, _}` /
   `{:error, :reason_required}` mapping, **and** the success info-flash strings
   ("Member removed from the workspace.", "Member banned…", etc.). `member_action`
   success has no flash today — preserve that.

2. On success, after putting the flash, the helper calls
   `refresh.(socket)` — a `socket -> socket` closure supplied by the surface —
   which re-fetches and assigns that surface's own lists:
   - `audit_log`: `audit_events` + `Presence.refresh_workspace_members(members)`
     (and `banned_members` for `unban`).
   - `invite_new`: `Presence.refresh_workspace_members(members)`.
   - `show`: its existing moderation refresh.

3. Each LiveView's `handle_event` clauses shrink to delegations, e.g.:

   ```elixir
   def handle_event("member_action", params, socket),
     do: MemberActions.run(socket, params, &refresh/1)
   ```

**Watch:** `workspace_id` comes from different assigns per surface
(`selected_workspace` vs `selected_channel.workspace_id`). Resolve this
explicitly — either pass `workspace_id` into the helper or standardize the
assign the helper reads. Do not silently assume one assign name.

**Acceptance.**
- The action whitelist and error contract exist in exactly one file.
- All three surfaces behave identically to before (same flashes, same refreshes).
  Verify via the existing LiveView tests for each surface; add a focused test for
  the helper if none covers the dispatch directly.
- `mix precommit` green.

**Deletion test.** Three near-identical handler sets fold into one; they differ
only by the refresh callback.

---

## Step 3 — #1 + #5 Extract the unread / read-state subsystem

**Problem.** `chat.ex` is 1,544 lines; ~a third is a self-contained unread
subsystem (~15 private helpers + the public read-state API) that collaborates
only with `ChannelReadState`, `ChannelUnreadSpan`, `ChannelRead`. The pure
interval algebra (`merge_unread_spans`, `subtract_unread_spans`,
`sequences_to_spans`) is total and pure but reachable only through a full
transaction, so it has **zero direct tests** and its edge cases run through DB
round-trips (poor locality).

**Design.** Two new modules; `Chat` keeps delegating wrappers.

### 3a. `DiscordClone.Chat.Unread.Spans` (pure)

Move the pure interval algebra verbatim, made public:

- `merge_unread_spans/1` (`chat.ex:1290`) → `Spans.merge/1`
- `subtract_unread_spans/3` (`chat.ex:1307`) → `Spans.subtract/3`
- `sequences_to_spans/1` (`chat.ex:1429`) → `Spans.from_sequences/1`
- `unread_summary_attrs/1` (`chat.ex:1270`) if it is pure — otherwise it stays
  with the persistence module.

**No `Repo`, no schema structs** in this module — spans are `{from, to}` integer
tuples. If any of these currently reference a schema, strip that at the boundary.

Add `test/discord_clone/chat/unread/spans_test.exs` covering:
adjacent-span coalescing at `+1`, splitting one span into two, `range_too_large`,
empty list, single span, fully-overlapping and disjoint inputs, subtract that
clears a span entirely vs. trims an edge.

### 3b. `DiscordClone.Chat.Unread` (deep)

Move the whole vertical — everything touching the three read-state schemas:

- **Queries:** `list_unread_counts/2` (`chat.ex:272`),
  `list_channel_read_summaries/2` (`286`), `jump_to_oldest_unread/2` (`337`).
- **Mutations:** `mark_channel_read/2` (`424`), `add_channel_unread_range/4`
  (`437`), `subtract_visible_read_range/4` (`452`), `clear_channel_unread/2`
  (`467`).
- **Read-state lifecycle:** `initialize_workspace_reads_for_user/2` (`46`),
  `initialize_channel_reads_for_workspace_members/1` (`77`),
  `delete_workspace_reads_for_user/2` (`111`).
- **Send-path fan-out:** `apply_message_unread_fanout!/3` (`1107`) →
  `Chat.Unread.fanout_on_send!/3`, plus `list_channel_recipient_user_ids/2` and
  all the persistence/locking helpers (`mutate_channel_unread_spans/3`,
  `ensure_channel_read_state!`, `lock_channel_read_state!`,
  `list_channel_unread_span_bounds/2`, `replace_channel_unread_spans!/3`,
  `update_read_state_summary!/2`).
- **Read-state PubSub topic:** `subscribe_to_channel_read_state/2` (`477`) and
  the internal `broadcast_channel_read_state_changes/1` (`1495`) +
  `broadcast_channel_read_state_changed/…` (`1503`). `Chat.Unread` owns this
  topic end-to-end.

`Chat.Unread` calls `Chat.Unread.Spans` for all interval math.

### 3c. Wire `Chat` as the facade

- Replace each moved public function in `chat.ex` with a one-line delegation:
  `defdelegate list_unread_counts(scope, workspace_id), to: Chat.Unread` (or an
  explicit wrapper where arg shuffling is needed).
- `send_message` (`chat.ex:715`): inside the transaction call
  `Chat.Unread.fanout_on_send!(channel, user_id, next_seq)`; after commit call
  `Chat.Unread.broadcast_changes(read_state_changes)` (the moved
  `broadcast_channel_read_state_changes`).

### 3d. Delete the backfill

Remove `backfill_unread_ranges_from_channel_reads/1` (`chat.ex:229`),
`backfill_channel_read_state!/1`, `unread_sequences_for_backfill/1`,
`upsert_channel_read/3`, `cursor_after?/3` **iff** they are only reachable from
backfill, and the `describe "backfill_unread_ranges_from_channel_reads/1"` block
in `chat_test.exs:175` (7 assertions). Confirm no non-test caller before
deleting (grep first). The new `spans_test.exs` covers the span logic those
tests exercised indirectly — and covers it better.

> Deleting migration code is only safe because this is a single-developer,
> local-DB learning project with no staging/production to backfill. If that
> changes, keep the backfill.

### 3e. Domain model

Add to `CONTEXT.md`: **Read State** (a member's read position + unread summary
for a channel) and **Unread Span** (a `{from_seq, to_seq}` interval of unread
message sequences). Name the modules after these terms.

**Acceptance.**
- `chat.ex` shrinks by roughly a third; unread public API unchanged from the
  web layer's perspective (LiveView tests untouched and green).
- `Chat.Unread.Spans` has direct unit tests; existing add/subtract integration
  tests in `chat_test.exs` **kept** (now verifying txn/locks/broadcast wiring).
- `mix precommit` green.

**Deletion test.** The cluster only talks to its own three schemas — extracting
it concentrates complexity behind a narrow seam.

---

## Step 4 — #2 Collapse the runtime wrappers behind `Chat.Runtime`

**Problem.** Five runtime modules with three shallow pass-throughs. A single
call is three hops: `Chat.join_workspace_presence` →
`WorkspacePresenceRuntime.join/3` → `WorkspaceSupervisor.start_workspace/1` →
`DynamicSupervisor.start_child` + `WorkspaceServer.join/3`.
`WorkspaceSupervisor.start_workspace/1` (13 lines) and
`ChannelSupervisor.start_channel/1` are the same 4-line
`start_child`-with-`already_started` shape. `Chat` reaches into five runtime
modules directly; the runtime tests couple to `Registry` and `:sys.get_state`.

**Design.** One deep facade; the two GenServers become state-only.

1. Create `DiscordClone.Chat.Runtime`. It **owns all process machinery**:
   - Registry lookups (`WorkspaceRegistry`, `ChannelRegistry`).
   - `DynamicSupervisor.start_child` against `WorkspaceSupervisor` /
     `ChannelSupervisor` (the OTP supervisors stay in the supervision tree in
     `application.ex` — only the wrapper *modules* are deleted).
   - The **ensure-process** pattern (start-or-lookup, `already_started`
     tolerance) in one place.
   - The timeout-expiry scheduling, including the current Chat→Workspaces hop in
     `schedule_existing_workspace_timeout_expiries` (`chat.ex:907`). Move that
     coordination into `Chat.Runtime`; it may call
     `Workspaces.list_active_future_timeouts` from there, but the runtime
     topology stops leaking into `chat.ex`.

2. Demote `WorkspaceServer` and `ChannelServer` to **state-only**: they keep
   `start_link` + their state operations (`join`/`leave`/`online_user_ids`;
   `put_recent_message`/typing/`list_recent_messages`) but no longer expose
   `whereis`/start-or-lookup for callers. Recent-message loading currently in
   `ChannelSupervisor` moves into `Chat.Runtime` (or a private on the server it
   drives) — keep it near the ensure path.

3. Delete `workspace_supervisor.ex`, `channel_supervisor.ex`,
   `workspace_presence_runtime.ex` (the wrapper modules).

4. Point every runtime call in `chat.ex` (`WorkspaceServer`,
   `WorkspacePresenceRuntime`, `ChannelServer`, `ChannelSupervisor`,
   `WorkspacePresence` at `chat.ex:214,215,224,527,535,546,556,561,571,572,653,`
   `665,728,729,912,908,975`) at `Chat.Runtime`. After this step nothing outside
   `Chat.Runtime` references a `Registry` or a `DynamicSupervisor`.

5. **Split `WorkspacePresence`** (`chat/workspace_presence.ex`):
   - Pure event translation (`to_presence_event/1`, `user_joined_event/2`,
     `user_left_event/2`) → new pure module `DiscordClone.Chat.PresenceEvents`.
     The web layer keeps using it — update the alias in `show.ex:6`,
     `audit_log.ex:4`, `invite_new.ex:5` (`alias …Chat.PresenceEvents, as:
     PresenceEvents`). Exposing a pure value-translation module to the web layer
     is fine — it holds no state.
   - PubSub plumbing (`subscribe/1`, `broadcast_user_joined/left`, `topic/1`) →
     absorbed into `Chat.Runtime`.

6. Rework the runtime tests to target the `Chat.Runtime` seam instead of the
   process topology: `test/discord_clone/chat/channel_runtime_test.exs` and
   `test/discord_clone/chat/workspace_presence_runtime_test.exs` should stop
   aliasing `ChannelServer`/`ChannelSupervisor`/`WorkspaceServer`/
   `WorkspaceSupervisor` and stop reaching into `Process.whereis(Registry)` /
   `:sys.get_state`. Drive behavior through `Chat.Runtime` (or `Chat`) and assert
   on observable outcomes (presence lists, delivered messages). Follow AGENTS.md
   test guidance: `start_supervised!`, `Process.monitor` + DOWN assertions, no
   `Process.sleep`.

**Acceptance.**
- Exactly one module references `Registry`/`DynamicSupervisor` for chat runtime:
  `Chat.Runtime`.
- The three wrapper modules are gone; `application.ex` supervision tree
  unchanged (the OTP supervisors and registries still start there).
- Web layer unchanged except the `PresenceEvents` alias target.
- Runtime tests assert through the seam, not the topology.
- `mix precommit` green.

**Deletion test.** Deleting the wrappers pulls the ensure-process pattern into
one place instead of three.

---

## Definition of done (whole plan)

- Four commits (or a few tiny ones per step), each with `mix precommit` green.
- Web layer untouched except: #3's `show.ex` delete-button call site, #4's three
  `handle_event` delegations, #2's `PresenceEvents` alias.
- New modules: `Chat.Unread`, `Chat.Unread.Spans`, `Chat.Runtime`,
  `Chat.PresenceEvents`, `DiscordCloneWeb.WorkspaceLive.MemberActions`.
- Deleted: 3 runtime wrapper modules, the unread backfill + its tests.
- `CONTEXT.md` gains **Read State** and **Unread Span**.
