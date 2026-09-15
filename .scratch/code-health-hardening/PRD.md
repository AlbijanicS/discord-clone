# Post-Roadmap Correctness, Scalability, and Operations Hardening

> Scope amendment, 2026-09-11: the user explicitly removed self-service email
> changes and Resend delivery. Stories 61–65 and their implementation/provider
> requirements below are superseded. Use operator-provisioned accounts over
> SSH; production does not require a sending domain or mail API key.


Status: ready-for-agent

This specification synthesizes the completed codebase review, design plan,
grill session, and primary-source research. It describes a hardening program to
protect the completed messaging and Voice experience before video or other major
product work begins.

## Problem Statement

The application now supports a substantial Discord-like collaboration
experience, including Workspace Channels, Direct Conversations, Activity,
moderation, unread state, and successful server-routed Voice. The feature set is
working, but several correctness and scalability risks remain in the paths that
will carry the most production load.

A Workspace Member's Channel Message authorization is decided before the
Message transaction. A concurrent kick, ban, Workspace Mute, Workspace Timeout,
leave, join, or role change can therefore interleave with Message persistence
and its recipient projections. This can produce a Message or unread result that
does not correspond to one coherent Workspace participation state.

Workspace Timeout expiry is durable in PostgreSQL but its wake-up mechanism is
owned by ephemeral workspace-presence runtime. If that runtime is not alive or
restarts, the durable restriction eventually becomes ineffective by wall-clock
comparison, but its active row, automatic audit event, broadcast, and interface
projection may not be reconciled promptly or at all.

Some connected LiveViews load mutable state before subscribing to PubSub. An
event committed between those operations can be absent from both the loaded
snapshot and the process mailbox. Several browser-originated event handlers
also assume valid parameter shapes and can terminate a LiveView when a stale,
missing, or forged parameter arrives.

Voice browser state currently overloads one status value with both connection
lifecycle and Local Mute. A later connection or recovery callback can rebuild
state from an older Channel descriptor and lose current Local Mute or Local
Deafen intent. On the server, RTP diagnostics and Speaking Indicator refreshes
perform work per packet. That is unnecessary for aggregate observability and
will become disproportionately expensive as media traffic grows.

Every Channel Message performs multiple database operations per recipient while
holding the Conversation lock. This preserves atomic unread behavior but makes
Message latency and lock duration grow with Workspace size. At the same time,
the large Chat and Workspaces contexts call each other in both directions, and
the Channel and Direct Conversation LiveViews independently implement much of
the same timeline state machine. These structures increase the chance of policy
drift and make future changes slower.

Production email-change delivery is incomplete: production disables the local
mailbox without selecting a real adapter, the sender is a placeholder, and the
settings interface reports success without checking delivery. The repository
also lacks continuous integration and deterministic browser/WebRTC coverage,
while deployment copies a release destructively into the live application
directory instead of switching immutable artifacts atomically.

The application needs to close these gaps without changing established product
semantics, weakening authorization, disrupting Voice, or combining correctness
fixes with high-risk rewrites.

## Solution

Deliver the hardening work as ordered, independently releasable slices.

First, add a fast continuous-integration baseline. Then make the Workspace row
a short-lived transactional participation gate. Channel Message sends acquire
a shared gate, while membership and user-triggered moderation changes acquire
an exclusive gate. Channel creation and deletion, Invite acceptance, and
Workspace deletion participate in the same gate and global lock order. Each
command re-authorizes against locked, current state before touching dependent
rows. This gives concurrent operations one legal ordering and stabilizes the
membership snapshot used for mentions, Activity Items, and unread fanout.

Move Workspace Timeout expiry to a supervised, database-authoritative
reconciler. It scans at startup and periodically, uses the nearest deadline only
as an optimization, claims bounded due batches safely across nodes, and commits
the timeout transition and automatic audit event exactly once before
broadcasting. PostgreSQL time is authoritative for creation, authorization, due
selection, and expiry; application and browser clocks are presentation-only.

Reorder connected LiveView initialization to authorize, subscribe once, and
then load mutable snapshots. Make handlers idempotent where a snapshot and
queued event overlap, and make every browser-originated event handler total over
malformed maps. Preserve privacy-oriented error normalization.

Represent Voice connection status, Local Mute, and Local Deafen as orthogonal
browser state. Derive track and playback behavior from that state and preserve
it through recovery, retry, and takeover. Keep exact RTP forwarding on the hot
path while moving diagnostic counts to periodic aggregate emissions and
coalescing Speaking Indicator refreshes. Voice owners hand counter snapshots to
a separate supervised diagnostics reporter so synchronous Telemetry handlers
can never pause packet forwarding.

Configure one real Req-backed Swoosh provider and make token cleanup and user
feedback reflect the delivery result. Replace per-recipient unread database
loops with a set-based append operation that stays atomic with Message
persistence. After those correctness-sensitive paths are stable, reorganize
Chat and Workspaces behind unchanged public facades into an acyclic set of deep
modules, and extract one shared Conversation timeline state machine and function
component.

Finally, add deterministic two-User WebRTC browser coverage and change
production deployment to immutable, versioned releases selected through an
atomic symlink with health-checked rollback.

## User Stories

1. As a Workspace Member, I want a Channel Message accepted only when one coherent Workspace participation state permits it, so that moderation cannot be bypassed by transaction timing.
2. As a Workspace Member, I want a Message that begins before a concurrent moderation action to have a deterministic outcome, so that the application never produces an ambiguous partial result.
3. As a Workspace Member, I want a kick that wins the participation race to prevent my pending Message, so that removed Users cannot write after removal.
4. As a Workspace Member, I want a ban that wins the participation race to prevent my pending Message, so that a banned User cannot persist content through a stale interface.
5. As a muted Workspace Member, I want a Workspace Mute that wins the race to prevent new participation, so that durable moderation is authoritative.
6. As a timed-out Workspace Member, I want a Workspace Timeout that wins the race to prevent new participation, so that a stale browser cannot bypass the restriction.
7. As a Workspace Member leaving voluntarily, I want leave and Message send to have one valid ordering, so that membership and authored content do not disagree.
8. As a User joining a Workspace, I want concurrent Messages and my initial Read States to share a coherent membership ordering, so that I neither miss Messages sent after I joined nor inherit Messages sent before I joined.
9. As a Channel Message recipient, I want unread state and Activity Items created only while I am a Workspace Member, so that removal permanently clears Workspace-specific projections.
10. As a Workspace Member, I want User Mentions resolved from the same membership snapshot as the Message, so that a race cannot address a non-member or omit a newly joined member inconsistently.
11. As a regular Workspace Member, I want `@everyone` authorization evaluated from my locked current role, so that a concurrent role change cannot bypass the role rule.
12. As a Workspace owner or admin, I want moderation commands re-authorized inside their transactions, so that losing my role concurrently invalidates stale moderation controls.
13. As a Workspace owner or admin, I want moderation and membership commands to remain responsive while ordinary concurrent Message sends continue, so that correctness does not impose unnecessary exclusive send serialization.
14. As a developer, I want one documented Workspace lock order, so that future participation features do not introduce deadlocks.
15. As a User with a Workspace Timeout, I want participation to become eligible when the durable deadline passes, even if no Workspace page is open, so that an ephemeral process cannot prolong the restriction.
16. As a Workspace owner, I want an expired timeout to become inactive and create one automatic audit event, so that the durable moderation history is accurate.
17. As a Workspace Member viewing an expired timeout, I want the interface to refresh after reconciliation, so that it no longer shows an obsolete restriction.
18. As an operator, I want overdue timeouts reconciled when the application starts, so that a restart repairs missed wake-ups automatically.
19. As an operator, I want timeout reconciliation to survive its own process restart, so that a temporary worker failure does not lose durable work.
20. As an operator running multiple application nodes, I want due timeout work claimed once without making ordinary reads inconsistent, so that scaling does not duplicate audit events.
21. As a Workspace owner removing a timeout while it expires, I want one operation to win cleanly, so that the moderation row and audit history do not diverge.
22. As a developer, I want the timeout table to remain the durable schedule, so that process timers are only wake-up hints.
23. As a User opening a Channel, I want every Message committed during mount to appear, so that load-before-subscribe timing cannot hide it.
24. As a User opening a Channel, I want reaction changes committed during mount to appear exactly once, so that snapshot overlap does not double derived state.
25. As a Workspace Member, I want membership, role, moderation, unread, and Voice roster changes during navigation to converge to current state, so that the interface never remains stale after mount.
26. As a Direct Conversation participant, I want the already-correct subscribe-before-load behavior preserved, so that Channel fixes do not regress Direct Messages.
27. As a User with a slow or reconnecting browser, I want duplicate PubSub and snapshot facts handled idempotently, so that counters and rows do not duplicate.
28. As a User, I want a malformed or stale timeout action to show a safe error or do nothing, so that my LiveView does not crash.
29. As a User, I want malformed identifiers and incomplete form events handled safely, so that browser extensions, stale DOM, or forged input cannot terminate my session.
30. As a User whose sudo mode expires, I want settings and password actions rejected safely, so that assertion failures do not crash the view or controller.
31. As a non-member or non-participant, I want private resources to retain normalized not-found behavior, so that hardening does not disclose their existence.
32. As a Voice Owner Tab User, I want Local Mute preserved while the WebRTC connection changes state, so that recovery cannot unexpectedly transmit audio.
33. As a Voice Owner Tab User, I want Local Deafen preserved through interruption and recovery, so that remote playback does not resume unexpectedly.
34. As a Voice Owner Tab User, I want undeafening to preserve a Local Mute I selected independently, so that listening again never implies transmitting again.
35. As a Voice Owner Tab User, I want microphone track state derived from current Local Mute, so that browser track state cannot drift from the displayed control state.
36. As a Voice Owner Tab User, I want remote playback state derived from Local Deafen, so that a replacement or recovered peer applies my current preference.
37. As a Voice Owner Tab User, I want stale callbacks from retired attempts ignored, so that an old peer cannot overwrite a newer Voice Session's state.
38. As a Voice Owner Tab User, I want takeover, retry, track end, and leave to retain their existing cleanup behavior, so that the state refactor does not leak capture or peers.
39. As a Voice Channel member, I want Speaking Indicators to remain responsive without processing identical state for every RTP packet, so that the roster remains useful under load.
40. As an operator, I want exact RTP receive, forward, route, and drop counts in bounded diagnostic intervals, so that observability remains meaningful without per-packet Telemetry dispatch.
41. As an operator, I want low-volume Voice lifecycle failures reported immediately, so that aggregation does not hide connection transitions.
42. As a Voice user, I want media forwarding unaffected by diagnostic reporting, so that observability cannot degrade audio quality.
43. As a future video user, I want media diagnostics to scale with time windows rather than packet volume, so that adding more packet streams does not multiply synchronous event cost.
44. As a Channel Message recipient, I want exact unread spans preserved, so that non-contiguous visibility and bounded read subtraction continue working.
45. As a Channel Message sender, I want Message latency not to grow through multiple database round trips per recipient, so that active Workspaces remain responsive.
46. As a User, I want a Message and all required Read State changes committed atomically, so that a process crash cannot leave permanent missing unread state.
47. As a User, I want Read State broadcasts sent only after commit, so that the interface never observes an unread projection for a rolled-back Message.
48. As an operator, I want unread database query count bounded as Workspace membership grows, so that capacity planning is predictable.
49. As a developer, I want unread optimization measured against a baseline, so that a complex set-based query is justified by observed improvement.
50. As a developer, I want Chat and Workspaces to stop calling each other's public facades in both directions, so that ownership and change impact are easier to understand.
51. As a developer, I want Workspace-specific Message policy separate from shared Conversation mechanics, so that Channel rules do not leak into Direct Conversations.
52. As a developer, I want Friendship-specific Direct Message policy separate from shared Conversation mechanics, so that Direct Conversation rules remain explicit.
53. As a developer, I want membership lifecycle coordination to call the Conversation-owned interface directly, so that Workspaces no longer needs the broad Chat facade.
54. As a developer, I want existing public context return contracts preserved during extraction, so that web callers can migrate without a flag day.
55. As a developer, I want each extracted module to hide a complete invariant or workflow, so that the refactor creates deep modules rather than pass-through layers.
56. As a developer, I want schema and table names left alone during behavioral hardening, so that architectural organization does not create unnecessary migration risk.
57. As a Channel user, I want pagination, replies, reactions, typing, deletion, and scroll behavior preserved, so that sharing timeline code does not alter the Message experience.
58. As a Direct Conversation participant, I want the same timeline mechanics to remain consistent with Channels while retaining Friendship-specific capabilities, so that shared behavior does not weaken privacy.
59. As a developer, I want one normalized Conversation timeline state machine, so that fixes to de-duplication and window merging apply to both Conversation kinds.
60. As a developer, I want common timeline rendering implemented as a function component, so that policy remains in the owning LiveViews rather than a stateful LiveComponent.
61. As a User changing my email, I want success reported only when the provider accepts delivery, so that the interface does not promise a link that was never sent.
62. As a User whose email cannot be delivered, I want a safe retryable error and no usable orphan change token, so that failed attempts remain understandable and clean.
63. As an operator, I want production to fail closed when required mail configuration is absent, so that a deployment cannot silently use the development mailbox adapter.
64. As an operator, I want the sender address supplied from a verified production identity, so that mail is deliverable and not sent as a placeholder address.
65. As a developer, I want provider HTTP performed outside database transactions, so that slow external delivery does not hold database connections or locks.
66. As a maintainer, I want every proposed change checked automatically on a clean PostgreSQL environment, so that regressions are caught before deployment.
67. As a maintainer, I want compilation warnings, formatting, Credo, JavaScript tests, Elixir tests, and coverage enforced in CI, so that local and remote quality gates agree.
68. As a maintainer, I want deterministic browser tests using two authenticated Users, so that multi-user signaling and Voice behavior have real browser coverage.
69. As a maintainer, I want browser media assertions based on increasing WebRTC packet and byte statistics, so that a connected badge alone cannot falsely certify media flow.
70. As an operator, I want hosted cross-network and TURN-only acceptance retained, so that local fake media is not mistaken for proof of NAT traversal or relay service.
71. As an operator, I want releases staged in immutable version directories, so that copying new files cannot partially overwrite the running application.
72. As an operator, I want the active release selected atomically, so that service restart never sees a half-deployed directory.
73. As an operator, I want readiness checked after restart and the prior release restored on failure, so that deployment has a practical rollback path.
74. As an operator, I want database migrations compatible with both current and prior application releases, so that application rollback does not require unsafe database rollback.
75. As a maintainer, I want every hardening slice independently testable and releasable, so that failures can be isolated and reverted without discarding unrelated improvements.

## Implementation Decisions

- Preserve `DiscordClone.Chat` and `DiscordClone.Workspaces` as the public
  facades used by the web layer. Move behavior behind them incrementally without
  changing existing public result tuples.
- Land a fast CI workflow and supported toolchain pins before behavioral work.
  CI runs PostgreSQL and the repository's complete precommit alias, with the
  coverage gate as a separately visible check.
- Use the durable Workspace row as the participation serialization seam. A
  Channel Message transaction acquires a shared row lock; membership and
  user-triggered moderation transactions acquire an exclusive row lock.
- Require every workflow whose correctness depends on the Workspace membership
  snapshot, or which conflicts with a gated Conversation operation, to use the
  same seam. Channel creation uses the shared gate; Invite acceptance,
  membership creation/removal, Channel deletion, and Workspace deletion use the
  exclusive gate. Audit any other Workspace workflow that locks a Conversation,
  Invite, Membership, Ban, or Moderation row before enabling the gate.
- Invite acceptance first reads only enough unlocked identity to locate the
  Workspace, then locks the Workspace, re-fetches and locks the Invite, and
  revalidates it before creating Membership and Read State projections.
- Workspace deletion locks the Workspace before dependent Conversations.
  Channel deletion and creation follow the same Workspace-first order so they
  cannot invert locks with Message sends or membership transitions.
- For Channel Message and reaction participation, re-authorize the actor's
  Membership, applicable Workspace Mute and unexpired Workspace Timeout,
  Channel identity, and relevant recipients after acquiring the Workspace gate
  and inside the mutation transaction.
- For membership, moderation, and Channel-management commands, re-authorize the
  actor's current Membership and role plus command-specific target and resource
  state. Using the Workspace gate must not introduce participation restrictions
  into management commands that existing product policy authorizes by role.
- Select the complete Channel Message recipient snapshot while the shared
  Workspace gate is held. Use that snapshot consistently for mention
  recognition, Activity Items, and unread fanout.
- Use the global database lock order Workspace, then Invite, Ban, Membership,
  Moderation, Conversation, and Read State relations in that order, with rows
  within each relation locked by durable ID. A workflow may skip relations it
  does not need but may never reverse the remaining order. Bring every current
  exception into compliance before enabling the gate and record the order in
  the governing ADR.
- Keep concurrent sends compatible through shared Workspace locks. Do not use a
  process-global mutex, serializable transaction isolation, advisory locks, or
  sender-only membership locking.
- Discover due Workspace Timeout candidate IDs without retaining row locks. For
  each candidate transaction, lock its Workspace first with the gate-compatible
  lock, then re-fetch and claim the moderation row `FOR UPDATE`, using
  skip-locked behavior at that claim if needed. Do not retain moderation locks
  across Workspaces while acquiring Workspace locks. Since authorization treats
  an elapsed deadline as inactive, delayed audit reconciliation must never
  prolong participation denial.
- Add a supervised Workspaces-owned Timeout Reconciler after the Repo and PubSub
  dependencies and before the web endpoint starts accepting traffic.
- Treat process timers and change notifications as wake-up hints. Scan durable
  timeout rows on startup and at a bounded interval even if no hint arrives.
- Discover a deterministic, bounded batch of due timeout candidate IDs without
  row locks. Process each candidate in its own Workspace-first transaction;
  after locking the Workspace, re-fetch the moderation row with `FOR UPDATE
  SKIP LOCKED` or an equivalent conditional claim. Never retain one candidate's
  locks while moving to another Workspace, and never use skip-locked behavior
  for authorization or ordinary interface reads.
- Use PostgreSQL's transaction/database clock as the sole authorization clock.
  Derive `expires_at` from database time when creating a timeout; compare active
  timeout deadlines to database time in participation queries; and select and
  conditionally expire due rows against database time in SQL. Application and
  browser clocks may render countdowns but may not grant or deny participation.
- In one transaction, condition the expiry transition on timeout type, active
  state, and due deadline, then insert one automatic expiry audit event. Manual
  removal and competing reconcilers converge through the same idempotent locked
  implementation.
- Broadcast timeout changes after commit. Remove durable timeout scheduling from
  ephemeral Workspace presence runtime and remove timeout timers from that
  runtime's state.
- For every connected LiveView, authorize the destination, subscribe exactly
  once to all discoverable parent topics, load topic identities when necessary,
  subscribe to child topics, and only then load mutable snapshots.
- Keep subscriptions behind the connected-socket check. Do not subscribe during
  the disconnected HTTP render, and do not create duplicate subscriptions on
  one process.
- Make snapshot and PubSub overlap harmless. Message and entity collections
  deduplicate by durable identity; derived counts and summaries either apply an
  idempotent fact or reload their authoritative projection.
- Treat every browser event payload as untrusted. Add total fallback clauses,
  use complete integer parsing and existing UUID casting, re-check sudo mode,
  and let context workflows validate preset or enum values.
- Preserve privacy-oriented not-found and unauthorized normalization. Malformed
  or forged identifiers must not reveal whether a private entity exists.
- Model Voice browser state with independent connection status, Local Mute, and
  Local Deafen values. During migration, derive the existing presentation state
  rather than changing visible controls unnecessarily.
- Let connection callbacks update connection lifecycle only. Never reconstruct
  current local control state from a Channel join descriptor captured by an
  older closure.
- Derive microphone track enablement from Local Mute and remote audio muting
  from Local Deafen. Deafen creates effective mute without forgetting an
  independently selected Local Mute.
- Publish current Local Mute and Local Deafen after Voice admission, signaling
  recovery, and any local control change. Continue rejecting stale callbacks by
  request generation and connection identity.
- Keep RTP packet forwarding exact and non-blocking. Remove Telemetry dispatch
  from per-packet receive, forward, route, and drop paths.
- Keep diagnostic delta counters in their owning Voice Session and Forwarder
  processes. On a configurable interval, defaulting to five seconds, atomically
  swap/reset the counters and send the snapshot as an ordinary Erlang message
  to a separate supervised diagnostics reporter. The reporter, never the RTP
  owner, executes bounded aggregate Telemetry. Orderly terminal cleanup hands
  off a final snapshot without waiting for the reporter.
- Put numeric counts in Telemetry measurements and bounded lifecycle categories
  in metadata. Keep low-volume track, ICE, and connection lifecycle events
  immediate.
- Coalesce positive Speaking Indicator activity before it reaches the Voice
  Channel runtime. Refresh often enough to preserve the existing 600-millisecond
  decay behavior, but never once per RTP packet.
- Do not introduce concurrent counter primitives while each counter has one
  GenServer owner. Reconsider only if measurement moves to a shared concurrent
  hot path.
- Configure the production mailer with the fixed Resend adapter and the existing
  Req API client. Require an API key and verified sender at production startup.
- Insert the exact email-change token before delivery, deliver outside a
  database transaction, display success only on the adapter's success result,
  and delete that exact token when delivery fails.
- Log only a bounded internal mail failure and show a generic retryable user
  error. Do not retain the placeholder sender or dynamically turn arbitrary
  environment strings into adapter modules.
- Preserve exact Unread Span and Read State semantics. Unread persistence stays
  in the Message transaction and broadcasts stay after commit.
- Replace per-recipient unread queries with a set-based append fast path. Bulk
  create missing Read States, extend adjacent final spans, insert a new
  single-sequence span where needed, bulk update cached summaries, and return
  changed projections for broadcasting.
- Bound unread database query count independently of recipient count. Measure
  query count in deterministic tests and record Conversation-lock duration as
  before/after benchmark evidence, not a timing-sensitive CI assertion.
- Reorganize internals into an acyclic graph after correctness fixes land.
  Conversations owns shared Message persistence, sequencing, replies,
  reactions, Read State, message-backed Activity, and Conversation runtime.
- Workspace Messaging owns Channel-specific participation, mentions, and
  recipient policy. Direct Messaging owns Friendship-specific authorization and
  recipient policy. Workspace Membership Lifecycle coordinates membership with
  Conversation projections without calling the broad Chat facade.
- Keep schema modules and database table names stable during extraction. Move
  one coherent workflow at a time and delete its old implementation in the same
  slice; do not add shallow internal pass-through modules or parallel engines.
- Amend architectural documentation that currently assigns durable Workspace
  Timeout scheduling to Chat runtime. Record the Workspace gate and global lock
  order in an accepted architectural decision.
- Extract a pure, policy-free Conversation Timeline reducer that consumes
  normalized events and returns new state plus declarative effects for stream
  operations and scrolling. It owns window merging, durable-ID de-duplication,
  row state, reply/reaction transitions, typing transitions, and scroll intent,
  but never owns sockets, subscriptions, PubSub, Ecto calls, or timers. Compose
  or preserve the existing focused window and scroll modules instead of
  absorbing them merely to reduce file count.
- Render shared timeline structure with a function component. Channel and Direct
  Conversation LiveViews retain policy-specific commands, subscriptions, and
  affordances. Do not introduce a stateful LiveComponent.
- Extract timeline behavior incrementally in the order pagination and
  de-duplication, Message mutations, reply/reaction state, typing, then common
  rendering.
- Add Playwright and its Chromium build as pinned, isolated browser-test tooling
  in a separate slower CI job. Use two browser contexts with different
  authenticated Users, microphone permission, and deterministic fake audio.
- Prove browser media movement through increasing standardized outbound and
  inbound RTP packet/byte statistics. Keep hosted separate-network and TURN-only
  manual acceptance because local fake media cannot prove real NAT or relay
  behavior.
- Build production releases for the target Linux ARM64 platform into immutable,
  versioned directories. Never synchronize files into the directory used by the
  running service.
- Point the service through a `current` release symlink. Prepare the replacement
  symlink on the same filesystem and atomically rename it into place only after
  the new release is complete and verified.
- Run backward-compatible migrations with the new release before switching,
  restart, require HTTPS health and readiness success, and atomically restore
  the prior release on failure. Retain at least one known-good version.
- Adopt expand/contract database migrations for all work that must support
  application rollback. Application rollback never implies automatic database
  rollback.
- Implement in this order: CI; Workspace participation; Timeout Reconciler;
  LiveView consistency and malformed input; canonical Voice state; Voice traffic
  aggregation; production mail; set-based unread fanout; context deepening;
  shared Conversation Timeline; browser WebRTC CI; atomic deployment.

## Testing Decisions

- Test observable behavior at the highest existing seam. Context behavior is
  exercised through public Chat and Workspaces workflows; UI behavior is
  exercised through authenticated LiveViews; Voice browser behavior is
  exercised through the browser controller interface; deployment behavior is
  exercised through its operator-facing commands and health outcome.
- Do not make private helper calls, internal state-map layout, Ecto query syntax,
  PIDs, or incidental function call order the primary contract. Database lock
  ordering is asserted only where ordering is itself the concurrency guarantee.
- Add dedicated PostgreSQL concurrency tests using independent sandbox
  connections and deterministic database barriers. Prior art is the existing
  Direct Message concurrency suite that observes a blocked lock without sleeps.
- Prove both legal results for send versus kick, ban, Workspace Mute, Workspace
  Timeout, leave, join/Read State initialization, relevant role change, and
  recipient removal. Assert durable Message, mention, Activity, membership, and
  Read State outcomes after both transactions complete.
- Prove the gate and global lock order for Invite acceptance versus Channel
  creation, Invite acceptance versus Workspace deletion, send versus Channel
  deletion, send versus Workspace deletion, and Channel creation versus
  membership removal. Treat a PostgreSQL deadlock or lock timeout as a test
  failure, and assert the complete durable outcome for either legal ordering.
- Add Workspaces tests for due-timeout batch claiming, idempotent transition,
  automatic audit creation, manual-removal races, replacement races, kick/ban
  races, Workspace deletion, and authorization at the deadline. Exercise
  automatic expiry against timeout removal and replacement with explicit
  deadlock detection. Add supervised reconciler tests for startup scan,
  periodic recovery, worker restart, multiple workers, and batch continuation.
- Assert timeout creation, authorization, due selection, and expiry against a
  controlled PostgreSQL clock boundary rather than application-node wall-clock
  assumptions. UI countdown tests remain presentation-only.
- Use `start_supervised!/1`, process monitors, messages, and `:sys.get_state/1`
  barriers for OTP tests. Do not use `Process.sleep/1` or process-liveness polling.
- Add deterministic LiveView mount-race tests that publish after subscription
  but before snapshot completion. Assert each final Message, reaction, unread
  summary, membership projection, moderation projection, and Voice Channel
  Roster state appears exactly once.
- Extend every affected event-handler test with missing keys, malformed UUIDs,
  partially parsed integers, unknown action names, invalid timeout presets,
  stale sudo mode, and forged private identifiers. Assert the LiveView remains
  alive and returns the normalized user-visible outcome through stable DOM IDs.
- Extend existing browser Voice controller and peer-attempt tests with the full
  connection-status by Local-Mute by Local-Deafen transition matrix. Include
  joining, connected, interrupted, recovered, retry, takeover, stale callback,
  track end, and explicit leave cases.
- Add Voice Session and Forwarder tests that route large RTP bursts and assert
  exact packet results while diagnostic event count remains bounded by intervals
  rather than packets. Attach a deliberately blocking Telemetry handler and
  prove RTP forwarding continues while the diagnostics reporter is blocked.
  Test non-blocking terminal snapshot handoff and low-volume lifecycle immediacy.
- Add Speaking Indicator tests proving immediate activation, bounded refresh,
  continued activity through the decay window, final decay, immediate Session
  cleanup, and no effect on forwarding authorization.
- Add Accounts and settings LiveView tests using the existing test mail adapter
  plus a failing adapter seam. Prove successful delivery retains a usable exact
  token, failed delivery reports failure and removes that token, and production
  configuration rejects absent provider or sender settings.
- Preserve existing unread integration tests and add set-based fanout tests for
  empty, adjacent, and non-adjacent final spans; missing Read States; visibility
  holes; concurrent sends; and recipient membership changes.
- Assert bounded query count for representative small, medium, and large
  recipient sets, with exact spans, cached summaries, atomic rollback, and
  correct concurrent-send and membership-race outcomes. Record before/after lock
  duration benchmarks as engineering evidence without enforcing an
  environment-sensitive timing threshold in CI.
- During context extraction, keep public context contract tests unchanged and
  move implementation-focused coverage to the new owning module only when that
  module exposes a meaningful interface. Apply the deletion test: remove old
  tests that merely duplicate behavior already proven through the deep seam.
- Test the Conversation Timeline reducer directly for difficult state-machine
  edges, including overlapping windows, duplicate events, replacement/deletion,
  unread-divider placement, reaction refresh, reply target deletion, and scroll
  intent. Assert its returned declarative stream/scroll effects without sockets,
  PubSub, Ecto, or timers. Continue to test complete user-visible behavior
  through both Channel and Direct Conversation LiveViews.
- Add fast CI on a clean PostgreSQL service and run the complete precommit alias.
  Run the coverage command as a distinct gate at or above the configured
  threshold; do not raise coverage with tests that assert implementation detail.
- Add a separate Playwright job with two isolated authenticated browser
  contexts. Verify Voice join, two-way increasing RTP statistics, Local Mute,
  Local Deafen, leave, interruption/recovery, and Voice Owner Tab takeover.
- Retain the hosted acceptance matrix for HTTPS health/readiness, separate
  networks, standard ICE, TURN-only relay, cleanup, and restored standard mode.
- Add deployment verification around immutable staging, migration failure,
  atomic selection, successful health/readiness, failed health rollback, and
  preservation of the previous release.
- Every implementation slice begins with focused regression coverage, runs its
  affected tests during development, and ends with the full precommit alias and
  coverage gate green.
- Prior art includes existing Chat sequencing, unread, Activity, runtime, and
  Direct Message concurrency tests; Workspaces moderation and Voice lifecycle
  tests; Channel and Direct Conversation LiveView suites; Voice Session,
  Forwarder, signaling, controller, controls, and peer-attempt suites; runtime
  configuration tests; and deployment-readiness tests.

## Out of Scope

- Video, screen sharing, recording, transcription, or an expanded Voice Channel
  capacity.
- New Workspace moderation types or changes to owner/admin permission policy.
- Group Direct Conversations or changes to Friendship semantics.
- Replacing PostgreSQL, Ecto, Phoenix PubSub, Phoenix LiveView, ExWebRTC, or the
  existing server-routed Voice topology.
- A general background-job system, event sourcing, or a transactional outbox.
- Moving unread persistence after Message commit or replacing exact Unread Spans
  with a single cursor.
- Schema/table renaming, wholesale context replacement, dual Conversation
  engines, or architectural migration performed only for aesthetics.
- A stateful timeline LiveComponent or policy callbacks hidden inside a generic
  UI abstraction.
- New routes, changed authentication policy, duplicate LiveSession names, or
  introduction of a `current_user` assign.
- Dynamic selection of arbitrary mail adapters, email marketing, bounce
  processing, or a generalized notification-delivery system.
- Treating Chromium fake audio as proof of physical microphones, acoustic
  playback, public NAT traversal, or hosted TURN reliability.
- Automatic database rollback during application rollback.
- Unrelated UI redesign, feature work, or coverage-percentage inflation.

## Further Notes

- Canonical vocabulary comes from the project glossary: User, Workspace,
  Workspace Member, Workspace Role, Workspace Mute, Workspace Timeout,
  Conversation, Channel, Direct Conversation, Message, Read State, Unread Span,
  Voice Channel, Voice Session, Voice Owner Tab, Local Mute, Local Deafen, Voice
  Channel Roster, Speaking Indicator, Audio Source, and Audio Destination.
- The accepted shared-Conversation decision remains in force: Channel and Direct
  Conversation timelines share mechanics while retaining separate authorization
  and recipient policy.
- The accepted Direct Message lock order remains unchanged. Direct Message sends
  continue to serialize through the Friend relationship before Conversation and
  Read State; the Workspace gate applies only to Workspace participation.
- Conversation runtime remains policy-free and ephemeral. Every mutation is
  authorized before runtime state is changed, and durable state is recoverable
  from PostgreSQL.
- Voice Channel identity remains durable under Workspaces, while active Voice
  Session, routing, speaking, and browser control state remain runtime concerns
  under their established owners.
- The previous architecture plan's placement of Workspace Timeout timers under
  Chat runtime is superseded. A new accepted architectural decision should
  record database-authoritative timeout reconciliation and the Workspace
  participation gate.
- Resend is the selected technical adapter because the existing Swoosh version
  supports it through the already included Req client with no new HTTP library.
  Production activation still requires the operator to provision a verified
  sender and API key.
- New production migrations must use expand/contract discipline because the
  atomic deployment procedure retains an older application release for rollback.
- This is a program-sized specification. The next workflow should split it into
  independently grabbable tracer-bullet implementation issues in the fixed
  delivery order rather than assign the whole PRD to one implementation turn.
- Each issue should preserve a releasable main branch and should update the
  relevant ADR or operational documentation when its decision becomes active.
