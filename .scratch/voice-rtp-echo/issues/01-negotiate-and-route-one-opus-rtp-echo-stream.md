# 01 — Negotiate and route one Opus RTP echo stream

**What to build:** An authenticated Workspace Member can establish the existing one-browser Voice Channel connection with exactly one compatible Opus microphone source. The server provisions a server-to-browser echo track during that same initial negotiation and directly returns each expected inbound RTP packet on it. This proves Elixir receives and sends real media packets without decoding, mixing, transcoding, buffering, reordering, recording, or renegotiation.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] A valid one-audio Opus offer produces an initial answer that contains the outbound echo path; incompatible or out-of-scope media is safely rejected without exposing SDP or credentials.
- [ ] Expected inbound audio RTP is forwarded once in arrival order; unknown tracks, extra audio, video, data channels, and other unexpected media are dropped and counted without disrupting the admitted connection.
- [ ] Aggregate server-side diagnostic state records only non-identifying inbound, echoed, and dropped packet counts plus lifecycle categories; it never logs raw RTP, SDP, ICE, credentials, identifiers, User data, or Voice Channel data.
- [ ] Authenticated Voice Channel and focused ExWebRTC tests prove negotiation, forwarding behavior, strict media rejection, and clean server PeerConnection shutdown through observable behavior.
