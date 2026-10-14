# P2-jobs-events implementation report

**Status:** The job registry, local event stream, notice retention, socket methods, and requested progress adapters are implemented in Silo. The P2-tauri-client conversion and remote event relay remain separate work. This report records the implementation limits and crash-evidence gaps explicitly.

## Commits

- `9a3ad237` `feat(engine): persist jobs and publish sequenced events`
- `e1b2e7b2` `feat(silod): serve job and event API over engine socket`

Both commits are on `engine/p2-jobs-events`, based on `6e32feab`.

## What changed

- Added a `silo-engine` SQLite registry at `<engine data dir>/registry.sqlite3`. It persists waiting/running/finished state, progress, terminal outcomes, notices, accepted order, and allocated IDs. WAL transactions commit outcomes before publishing `operations.job.finished`; acknowledgement removes the outcome and preserves a tombstone. `operations.job.get`, `operations.list`, and `operations.job.acknowledge` expose the durable state.
- Mapped setup request IDs, transfer IDs, push operation IDs, backup journal IDs, inspection request IDs, and gate admissions to stable job IDs. The general allocator uses a persisted counter for `job:<n>`. Gate IDs remain queue-entry IDs and link to their owning job. Startup marks unfinished work interrupted; push and backup journal reconciliation runs before the socket accepts connections.
- Added a bounded local event bus with catalogue selector validation, a monotonic engine sequence, per-subscription sequence numbers, requester audiences, subscribe-response ordering, queue snapshot barriers, unsubscribe barriers, and overflow gap delivery followed by session closure. The socket exposes `events.subscribe` and `events.unsubscribe` using `silo-api` request and event types. `operations.list` returns the queue and retained job IDs.
- Added latest-per-key notice retention and `notifications.list`. The engine retains and publishes notices; it does not call an OS notification API.
- Connected setup, lifecycle, transfer, backup, push, macOS state/checkpoint, and update job progress or completion to the registry while keeping the existing `silo://` events for the current Tauri UI. A transfer cancellation regression test covers cancellation before `Slot::take` adopts the acceptance-time token.
- Added the Silo UI patch changeset `steady-jobs-survive-restarts.md`.

## Storage choice and evidence

SQLite WAL provides transactional commit and local concurrent readers; SQLite documents that WAL requires participating processes to use the same host. SQLite documents `synchronous=FULL` durability and the macOS `fullfsync` option. The implementation uses `rusqlite` 0.40.2 with the bundled SQLite feature, pinned in `Cargo.lock`; it sets and checks WAL mode, uses `synchronous=FULL`, enables `fullfsync` on macOS, enables foreign keys, applies a bounded busy timeout, and restricts the database directory/files. The registry schema is currently `user_version=2`; version 2 adds exact encoded discovery-byte accounting and migrates version 1 rows.

Primary references: [SQLite WAL](https://www.sqlite.org/wal.html), [SQLite synchronous and fullfsync pragmas](https://www.sqlite.org/pragma.html#pragma_synchronous), [rusqlite 0.40.2](https://docs.rs/crate/rusqlite/0.40.2), [rusqlite RustSec advisories](https://rustsec.org/packages/rusqlite.html). The SQLite documentation also cautions that durability cannot overcome failing storage; this implementation does not encrypt same-user data.

## Verification

- `CARGO_TARGET_DIR=/Users/polarzero/silo-work/p2-jobs-events/target CARGO_BUILD_JOBS=6 SILO_GITHUB_APP_SLUG=silo-test SILO_GITHUB_CLIENT_ID=test-client SILO_GITHUB_CLIENT_SECRET=<synthetic> cargo +1.94.0 test --manifest-path app/SiloUI/Cargo.toml --workspace --locked --quiet` — passed: 2,367 tests passed, 30 ignored, 0 failed.
- `cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --check` — passed.
- `git diff --check` — passed.
- Focused transfer cancellation regression test — passed.

The native test run used the synthetic GitHub configuration permitted by the local release guide. No frontend files changed, so npm checks were not run. Tests used repository fixtures and temporary directories; no live computers or packaged app were exercised.

## Deviations and remaining evidence

- The P2 design document describes general IDs as `job:<uuid>` and says gate IDs are never durable job identities. The explicit P2 implementer instruction requested `job:<n>`; the implementation follows that instruction and allocates `<n>` transactionally from persistent registry metadata, not from a process-local counter.
- Registry access uses one `rusqlite::Connection` behind a mutex on the calling worker; it is not a dedicated blocking database-owner task as proposed in `design/p2.md`. Measure commit latency and contention before relying on this under load.
- The simulated-restart test closes and reopens the registry against the same temporary database in-process. It does not kill a child process at each acceptance/effect/outcome/event/ack boundary, inject disk-full or read-only storage, or qualify fsync failure. This does not close the P2 design's B-37 crash-safety gate.
- Durable source-domain IDs are deduplicated and acknowledged IDs remain tombstoned, but the registry does not implement transport `operationId` claims, request-parameter fingerprints, or changed-fingerprint rejection. A retry using the same domain ID attaches to the existing identity without comparing request parameters.
- Generic restart recovery marks running jobs `internal`/interrupted and waiting jobs `cancelled`/not-started. Push and backup have journal reconciliation before serving; other domains do not gain restartable execution from this registry and are not blindly replayed.
- The event bus accepts catalogue topics, but this change wires existing progress sources and selected projections rather than adding every catalogue producer. Operations queue, macOS computer, export, update, and notice events have canonical producers; remaining legacy hint producers need state-backed catalogue projections before clients rely on them. Overflow sends a gap and closes that local session; resync requires a fresh connection/subscription ID and domain reads.
- Explicit remote `deviceIds` for subscriptions are rejected as unsupported; this track does not add the SSH event relay. The P2-tauri-client track still needs to move consumers from `silo://` events to the socket API.
- Some current event audiences remain `Audience::All` until client identity replaces window labels. The concurrent integration review owns the `EngineContext::Audience` mapping seam.

## Next integration work

Before treating the API as release-ready, add child-process crash-point tests and storage-failure tests, implement transport request claims/fingerprints, complete catalogue state projections, and prove remote/local resync across the framed relay. Then convert Tauri and Fjord consumers to the canonical socket methods and verify the signed Dev engine with separate client sessions.
