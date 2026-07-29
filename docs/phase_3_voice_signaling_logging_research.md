# Phase 3 voice-signaling logging — research note

## Scope

This note sets a safe observability boundary for Phase 3's fake Phoenix Channel
signaling. It also preserves the boundary when later phases carry real SDP and
ICE.

## Finding

Use structured, metadata-only application logs for Voice signaling. Log the
operation and outcome, never the client payload or a whole socket/channel
struct.

Good metadata for Phase 3:

- lifecycle: `socket_connected`, `topic_joined`, `topic_left`, `terminated`;
- operation: `offer`, `ice_candidate`, or `heartbeat`;
- outcome: `accepted`, `rejected`, or `failed`;
- a stable validation/error code and the decoded payload byte count; and
- low-cardinality operational context such as the application environment or
  failure class.

Avoid logging:

- fake payload content, Signaling Session IDs, session cookies/tokens, or raw
  user, socket, and channel structs;
- account identifiers, display names, email addresses, IP addresses, or a
  durable Voice Channel ID unless a separately reviewed operational need
  requires a pseudonymous correlation value; and
- later real SDP, ICE candidate objects/strings, `ice-ufrag`, `ice-pwd`, STUN
  or TURN credentials, or full exception/request parameters containing them.

This is intentionally stricter than the Phase 3 fake protocol needs. It makes
the logging call sites safe to retain when real WebRTC values replace the fake
ones.

## Why whole signaling values are unsafe

ICE candidate syntax contains network address, port, transport, candidate type,
and sometimes a related transport address. The WebRTC specification says that
candidate addresses can reveal location and local-network topology and expand
device fingerprinting. ICE credentials are security material: `ice-pwd`
protects STUN connectivity checks, while `ice-ufrag` is used in their username.
Therefore, do not try to redact individual fields from SDP or candidate text;
exclude the complete signaling value from logs.[^ice][^webrtc]

## Phoenix and Elixir implications

Elixir Logger supports per-call structured metadata, which is the appropriate
mechanism for the explicit safe subset above. Whether metadata appears in the
final log line depends on the configured handler/formatter, so production
configuration must include only these reviewed keys.[^logger]

Phoenix has two relevant automatic paths to review before Phase 4. Its default
parameter filter only includes `"password"`; it will not automatically redact
fields named `sdp`, `candidate`, `ice_pwd`, or `signaling_session_id`. Also,
the `[:phoenix, :channel_handled_in]` telemetry event includes the Channel
event and parameters. Any telemetry handler/exporter must project this to the
safe subset before it reaches logs or third-party observability tooling.[^phoenix-logger]

## Development and production

Use the same no-content rule in both environments. Development convenience is
not a sufficient exception: local logs are often copied into tickets, chat, or
test output. For local debugging, add narrowly scoped test assertions and
temporary breakpoints/inspect output that are removed before merge; do not make
payload logging a runtime flag. Production should emit the reviewed structured
metadata at an appropriate sampling/rate limit, especially for high-frequency
heartbeat and candidate events.

## Proposed decision

Adopt metadata-only Voice signaling logging in Phase 3: lifecycle/operation,
outcome, error code, and byte count are permitted; signaling values,
credentials, session identifiers, PII, and raw parameter structures are not.

## Sources

[^logger]: [Elixir Logger official documentation](https://logger.hexdocs.pm/main/Logger.html) — per-call and per-process metadata, and formatter-controlled metadata output.

[^phoenix-logger]: [Phoenix.Logger official documentation](https://phoenix.hexdocs.pm/Phoenix.Logger.html) — default parameter filtering and Channel telemetry metadata.

[^ice]: [RFC 8839: JavaScript Session Establishment Protocol (JSEP)](https://www.rfc-editor.org/rfc/rfc8839.html) — ICE candidate grammar and ICE username/password uses.

[^webrtc]: [W3C WebRTC Recommendation](https://www.w3.org/TR/webrtc/) — candidate address fields and privacy implications of ICE candidates.
