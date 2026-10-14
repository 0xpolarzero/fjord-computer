# P2 Swift client

## Built

- Checked in the `silo-api` JSON Schema snapshot from Silo commit `7a0591f9e9934f0e39fc430b24770363185ca1d5`, schema SHA-256 `58952de063cac013365277515775d7ef20c7800187a44198a60c89f9f28740eb`, and the manifest recording its source and tooling.
- Added a reproducible quicktype-core `26.0.0` generator. Its Swift renderer preserves schema integer formats and lossless open JSON values; the generator emits Codable model types plus typed wrappers for the schema's 146 methods and validates method metadata before output. Regenerate with `scripts/generate-engine-client.sh --write`; check drift with `scripts/generate-engine-client.sh --check`.
- Replaced the Computers wire records in `EngineClient.swift` with generated schema types, keeping the `EngineClient` protocol and `MockEngineClient`. Local view/action and progress types remain app projections; the socket decodes generated progress and result records before projecting them. `ComputersChangedPayload` uses generated platform snapshots and only includes the platform that changed.
- Added `SocketEngineClient` and a persistent Darwin Unix-domain transport. It implements 4-byte big-endian framing with a 4 MiB limit, UUID request IDs, out-of-order response correlation, the protocol-range handshake, event subscription/unsubscription, per-subscription sequence tracking, gap/reconnect resync notifications, job progress/finish delivery, job lookup, cancellation, and acknowledgement.
- Added an in-process framed fake server, schema-derived JSON fixtures, and tests for generated Codable decoding, handshake range, request IDs, out-of-order replies, job events/lookup/acknowledgement, and a sequence gap.
- Kept `MockEngineClient` as the default. `--socket-client` selects the socket implementation outside demo/test launches. Its production-channel default is `$HOME/.silo/engine.sock`; use `$HOME/.silo-dev/engine.sock` or `FJORD_SILO_SOCKET_PATH` for another channel/path.

## Commits

- `dec12a9a` `feat: generate Silo Swift API client`
- `8adc0265` `fix: normalize generated restore types`
- `38b5ddff` `refactor: use generated Silo Computers models`
- `dacfc17f` `feat: add Silo Unix socket client`
- `9e49d2a8` `fix: align generated method type names`
- `46d69283` `fix: compile generated Silo client adapters`
- The report is committed separately after verification.

## Verification

- `scripts/generate-engine-client.sh --check`: passed; checked-in Swift matches the pinned schema and generator.
- `swift build`: passed on the clean committed snapshot at `46d69283`.
- `scripts/test.sh`: passed on that snapshot, 1,608 tests across 161 suites. This includes both `SiloAPIClientTests` and the existing `ComputersTests` suite.
- A preliminary build of the shared working tree failed while the other track had uncommitted Router/Guest edits. It also found generated acronym names and adapter initializer issues; commits `9e49d2a8` and `46d69283` fix those P2 errors. The shared-tree output also reported errors in uncommitted Router/Guest files owned by the concurrent track. Final verification used a temporary archive of committed `main` and left those files untouched.

## Deviations and limits

- The request points to p4.md §5 for the generated Swift client. In the checked-in design, §5 is bundling and §6 is the generated Swift client; implementation follows §6 and the client portions of §3.
- The schema exposes a protocol range but does not settle the shipped numeric version. The client defaults provisionally to `1...1`; the initializer allows tests or a later protocol decision to inject another range.
- `silod` is not available, so the transport is verified against the local fake server only. The socket path assumes the production `.silo` channel unless overridden; it does not infer the channel from Fjord's bundle identifier.
- The generated method catalog covers all 146 schema methods; this `EngineClient` adapter implements the Computers and operations methods needed by this track, not the entire catalog.
- The API keeps local UI projections for queue entries, job outcomes, and progress presentation. Socket frames are decoded with generated wire types first; these projections preserve the current Computers UI and mock contract.

## Handoff

- `silod` should serve `engine.sock` under `channel.state_dir(home)` and use the schema's request/response/event shapes: echoed string `id`, `{id,result}` or `{id,error:{code,message}}`, and sequenced `{event,subscription,deviceId,seq,payload}` event envelopes. Keep the 4-byte big-endian length and 4 MiB cap.
- Confirm the protocol version before shipping the socket path; update `SocketEngineClient.defaultProtocolRange` after the owner settles the range. The fake server currently negotiates protocol 1.
- Keep mock launches deterministic. A real engine integration should validate the path, peer-euid policy, event resync, and durable job acknowledgement against `silod` once that executable exists.
