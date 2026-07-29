# 04 — Prove isolated and safe Voice signaling

**What to build:** Two browser tabs can independently use the same durable Voice Channel topic without seeing or affecting each other's fake signaling, while the completed control plane emits only safe diagnostic metadata and passes the project's full quality gate.

**Blocked by:** 02 — Add correlated fake offer and answer signaling; 03 — Add direct fake ICE and heartbeat signaling.

**Status:** ready-for-agent

- [ ] Two admitted connections on the same Voice Channel topic prove that offers, answers, ICE, heartbeat, errors, and Signaling Session IDs remain isolated to their owning connection.
- [ ] Voice signaling diagnostics record only reviewed lifecycle/operation, outcome, error-code, and byte-count metadata; no signaling content, credentials, session identifiers, personal identifiers, raw parameters, or socket structures reach logs or telemetry exporters.
- [ ] Unknown events, authorization failures, and malformed payloads fail safely without leaking topic, User, or credential details.
- [ ] Focused tests and `mix precommit` pass, demonstrating the Phase 3 completion boundary without a PeerConnection, Voice Session, RoomServer, or media transport.
