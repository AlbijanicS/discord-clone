# Phase 6 OTP room-supervision research

Status: research-note  
Checked: 2026-08-03  
Scope: whether each runtime Voice Channel should be one supervised room tree,
rather than unrelated globally supervised RoomServer, Session, and Forwarder
processes.

## Decision-ready finding

Use a global `Voice.RoomSupervisor` `DynamicSupervisor` to start **one
ordinary, nested supervisor per durable Voice Channel ID**. Each nested room
tree contains the `RoomServer`, its `SessionSupervisor`, and its Forwarder.
Name the `RoomServer` with a unique local Registry key such as
`{:room, voice_channel_id}`; name a Voice Session with a separate unique key
such as `{:session, signaling_session_id}`. Keep canonical membership only in
the RoomServer, not in Registry values.

This is a better fit than unrelated global children: the RoomServer is the
single admission/membership authority and the session children and Forwarder
are valid only in its room. A room failure can therefore invalidate the whole
ephemeral unit without affecting other rooms.

## OTP constraints that shape the choice

- `DynamicSupervisor` starts children on demand but supports only
  `:one_for_one`; it cannot itself express room-wide fate sharing. It is thus
  the correct outer container, while the per-room child must be an ordinary
  `Supervisor`.[^dynamic]
- An ordinary supervisor supports `:one_for_all`: an unsuccessful child exit
  terminates and restarts every sibling. It also supports `:rest_for_one`,
  which restarts the failed child and children started after it.[^supervisor]
  Declare `RoomServer` before `SessionSupervisor` and Forwarder, so its failure
  clears the rest of the room in either strategy.[^shutdown-order]
- Select `:one_for_all` only if a failed Forwarder must invalidate all session
  state for correctness. It is the clearest Phase 6 starting policy if the
  Forwarder is a required routing boundary. If the Forwarder is intentionally
  non-critical until Phase 8, use `:rest_for_one` instead: a Forwarder failure
  then does not churn healthy sessions. This is an application-level tradeoff;
  OTP guarantees the stated restart effects, not which components are coupled.
- A normal leave must not resurrect a Voice Session. The default child restart
  is `:permanent`; `:temporary` never restarts and `:transient` restarts only
  after abnormal exits. Use an intentional session child specification and
  `DynamicSupervisor.terminate_child/2` for leave; do not rely on defaults.[^restart]
- A Registry with `keys: :unique` maps a key to at most one process and removes
  that process's registrations on crash. It can provide the `:via` names above,
  but it is local and can briefly return a PID that has already died. The
  get-or-start API must treat `{:already_started, pid}`, dead-PID calls, and
  `:DOWN` monitoring as normal races; it must not treat the Registry as the
  membership source of truth.[^registry]
- The per-User key is useful as a live index for the currently admitted
  session, but a lookup-then-stop-then-start move is not atomic by itself.
  Serialize cross-room joins in one Voice-owned admission coordinator (or an
  equivalent per-User critical section), which asks the old RoomServer to leave
  before the new RoomServer admits. Phase 6 targets one node: Registry is
  explicitly local, so multi-node voice later needs a separate coordination
  decision.[^registry]

## Concrete topology

```text
Voice.RoomSupervisor (DynamicSupervisor, one_for_one)
└─ Voice.Room (ordinary Supervisor, one_for_all or rest_for_one)
   ├─ Voice.RoomServer       (named by {:room, voice_channel_id})
   ├─ Voice.SessionSupervisor (DynamicSupervisor)
   │  └─ Voice.Session*      (named by {:session, signaling_session_id})
   └─ Voice.Forwarder
```

This keeps the five-session cap and simultaneous-admission serialization inside
one RoomServer mailbox. On every session `:DOWN` or explicit leave, that server
removes its membership and the per-User live index before it declares the
operation complete. After an unrecoverable room-tree restart, clients must
rejoin; no PID, Registry registration, or membership map is durable recovery.

## Sources

[^dynamic]: [Elixir 1.15.8 `DynamicSupervisor`](https://elixir.hexdocs.pm/1.15.8/DynamicSupervisor.html) — on-demand children, outer-supervisor role, supported `:one_for_one` strategy, child limits, and start errors. The project declares `elixir: "~> 1.15"`.

[^supervisor]: [Elixir 1.15.8 `Supervisor`](https://elixir.hexdocs.pm/1.15.8/Supervisor.html) — child specifications and `:one_for_one`, `:one_for_all`, and `:rest_for_one` semantics; see also the [Erlang/OTP Supervisor Behaviour](https://www.erlang.org/doc/system/sup_princ.html).

[^shutdown-order]: [Elixir 1.15.8 `Supervisor`: start and shutdown](https://elixir.hexdocs.pm/1.15.8/Supervisor.html#module-start-and-shutdown) — children start in declaration order and terminate in reverse order.

[^restart]: [Elixir 1.15.8 `Supervisor`: restart values](https://elixir.hexdocs.pm/1.15.8/Supervisor.html#module-restart-values-restart) — `:permanent`, `:transient`, and `:temporary` child restart behavior.

[^registry]: [Elixir 1.15.8 `Registry`](https://elixir.hexdocs.pm/1.15.8/Registry.html) — local Registry scope, unique `:via` registration, crash removal, and delayed-unsubscription/dead-PID caveat.
