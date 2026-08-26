# Phase 12 AWS Private-Alpha Deployment Contract

Date: 2026-08-26

Status: application and release implementation complete; hosted acceptance
evidence pending.

This document is the authoritative Phase 12 operational contract. Earlier GCP
deployment notes are historical research and do not describe the selected
private-alpha target.

## Fixed topology

- One ARM64 Ubuntu EC2 instance (`t4g.small`) in `eu-north-1`.
- One Elastic IPv4 address and one DuckDNS hostname pointing to it.
- Caddy owns public TCP 80/443 and proxies HTTPS/WSS to Phoenix on
  `127.0.0.1:4000`.
- Phoenix and ExWebRTC run in one systemd-managed release.
- ExWebRTC advertises the EC2 private-to-Elastic IPv4 mapping and binds only UDP
  50000-50031.
- Cloudflare Realtime TURN supplies STUN and short-lived TURN credentials.
- PostgreSQL is local to the host for the private alpha and is never public.

Do not copy a macOS `_build` directory to EC2. Native dependencies must be
compiled on the ARM64 VM (or in an equivalent Linux ARM64 builder).

## Network boundary

| Protocol/port | Source | Purpose |
| --- | --- | --- |
| TCP 22 | Operator's current public IP only | Administration |
| TCP 80 | Public | ACME and HTTPS redirect |
| TCP 443 | Public | HTTPS and secure WebSocket signaling |
| UDP 50000-50031 | Public | ExWebRTC media |

Do not expose TCP 4000, TCP 5432, EPMD 4369, or Erlang distribution ports.
Phoenix binds to IPv4 loopback, and the release sets `RELEASE_DISTRIBUTION=none`.

## Runtime input contract

Store production values only in `/etc/discord-clone.env`, owned by
`root:discord-clone` with mode `0640`. Use unindented `NAME=value` lines. Never
commit, paste into an issue, or retain the file in deployment evidence.

Required inputs:

- `PHX_HOST`, `PORT`, `DATABASE_URL`, `SECRET_KEY_BASE`, and `POOL_SIZE`
- `RELEASE_DISTRIBUTION=none` and `PHX_SERVER=true`
- `VOICE_ICE_MODE=standard` for normal operation
- `VOICE_STUN_URLS` in standard mode only
- `VOICE_INTERNAL_IPV4` and `VOICE_EXTERNAL_IPV4`
- `VOICE_TURN_CREDENTIAL_TTL_SECONDS` from 120 through 172800 seconds
- `CLOUDFLARE_TURN_KEY_ID` and `CLOUDFLARE_TURN_API_TOKEN`

The application rejects missing or malformed production inputs before serving
traffic. TURN-only mode ignores STUN configuration and emits relay-only policy.

## Deployment and account policy

Follow the tracked commands in `README.md` and install the examples under
`deploy/`. Run migrations as the service user before starting the release.
Public registration and magic-link login are intentionally unavailable. Create
confirmed password accounts only with `bin/provision-user`; do not put passwords
in shell history or process arguments.

## Acceptance matrix

Record UTC time, client network class, browser/OS, result, and only the safe
candidate class (`host`, `srflx`, or `relay`). Never record SDP, ICE usernames,
ICE credentials, API tokens, database URLs, cookies, or full IP addresses.

| Scenario | Mode | Required result |
| --- | --- | --- |
| `/healthz` and `/readyz` over HTTPS | standard | Both return success |
| Two authenticated users on separate networks | standard | Two-way audio; direct or relay candidate may win |
| Same users after setting `VOICE_ICE_MODE=turn_only` and restarting | turn_only | Two-way audio; relay candidate wins |
| Restore `VOICE_ICE_MODE=standard` and restart | standard | Readiness and a fresh call succeed |
| Invalid or missing hosted ICE input | either | Startup fails closed without logging secrets |

For each call, verify join, two-way audio, mute/deafen behavior, leave, rejoin,
and cleanup after tab close. Provider credential fetch failures must reject the
new admission without disrupting an already active room.

## Teardown and credential response

At the end of the alpha, stop the service, preserve only explicitly required
database backups, terminate the EC2 instance, delete unneeded EBS volumes,
release the Elastic IPv4 address, remove the DuckDNS record, and revoke the
Cloudflare TURN key. Review AWS and Cloudflare billing afterward.

If any secret has appeared in chat, logs, shell history, screenshots, or a
repository, rotate it before deployment and treat the old value as compromised.
