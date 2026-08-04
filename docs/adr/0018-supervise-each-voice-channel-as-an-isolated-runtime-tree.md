# Supervise each Voice Channel as an isolated runtime tree

The Voice runtime starts one dynamically named room tree per durable Voice
Channel. Each tree contains the RoomServer, Forwarder, and SessionSupervisor,
and uses `:one_for_all` so a failure of the room's canonical membership or
routing boundary replaces the room coherently; individual Voice Sessions remain
children of the SessionSupervisor and fail independently. This prevents stale
room membership while keeping an individual browser connection failure local.

`DiscordCloneWeb.VoiceChannel` remains the authenticated signaling and control
adapter. It authorizes durable access through `Workspaces` and delegates runtime
admission to the stateless `DiscordClone.Voice` API, which locates or starts a
room and delegates membership to its RoomServer. The web adapter neither owns
runtime state nor reconstructs Registry or supervision details.

RoomServer generates an opaque Voice Session ID when it admits a User. That ID
identifies the runtime membership without exposing the owned Session process;
the Phoenix Channel retains separate ownership of the Signaling Session ID used
to correlate signaling messages.

`Voice.AdmissionServer` serializes cross-room admission and owns the minimal
global User index of active Voice Session IDs and room PIDs. RoomServers remain
the canonical owners of their own memberships. This deliberate, bounded
coordination point enforces one active Voice Session per User and makes a move
between rooms ordered without coupling Voice to workspace or friend presence.

RoomServer enforces the five-Voice-Session capacity at admission in Phase 6. A
move first checks the target room; a full room rejects with a normal, safe
capacity result and leaves every existing session, including the mover's old
session, unchanged. The control-plane result may expose aggregate occupancy
such as `3/5`, but never a roster or identifying session data.

Voice Sessions are temporary children: a failed browser connection is removed,
not automatically restarted into unknown WebRTC state. Explicit leave, channel
death, session failure, and later peer failure converge on idempotent removal:
the Session stops, RoomServer removes its canonical membership, AdmissionServer
removes the global User index, and Forwarder removes future routes. RoomServer
monitors Sessions, and Sessions monitor their Phoenix Channel connection.

Forwarder is introduced as a supervised lifecycle boundary only; it performs no
RTP routing in Phase 6. The existing Phase 5 signaling/echo contract remains
unchanged until Phase 7 moves it through Voice.Session. The Phoenix adapter
continues to validate Signaling Session IDs; `joined` also associates it with
the separately generated Voice Session ID. Admission responses are
non-identifying and distinguish normal capacity and stale/terminated-session
failures. A User losing Voice Channel access, or deletion of that channel,
ends the corresponding runtime session through an explicit Workspaces-to-Voice
lifecycle notification.

After the last Voice Session leaves, the room keeps only its empty runtime tree
for a fixed 30-second grace period. A new admission cancels that timer; expiry
stops the room. Departed Sessions and their media resources are always released
immediately and never survive the idle grace period.
