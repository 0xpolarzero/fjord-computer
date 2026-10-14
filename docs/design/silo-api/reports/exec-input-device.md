# exec-input-device: remote stdin for guest commands

## Silo

Worktree `~/silo-work/exec-input`, branch `engine/exec-input-device`, one commit `39b16587` (main was `31f66d2d`, no merge needed). Fast-forwarded into Silo `main`. Never pushed.

- `silo-api`: `GuestExecInputParams` gained an optional `deviceId`; schema regenerated.
- `silod` `guest.exec.input`: another device's id is forwarded to the owner (without `deviceId`) through `call_owner`; absent or own id runs locally via the new `exec_input_owner`.
- Owner side: the bridge serves `guest.exec.input` (`access_dispatch`), listed in `ACCESS_METHODS` and as an `Access::Change` method in `remote.rs` (so it is classified and recorded like `guest.exec.start`).
- The refusal of a remote `stdinOpen: true` start is removed.
- Test: the old "cannot keep stdin open" test is replaced by a two-engine stub test (remote start with `stdinOpen`, then input with `data` and `close`; the owner sees no `deviceId`). The method classification test lists the new Change method.
- Gate: `cargo test --locked -p silo-engine -p silod -p silo-api --no-fail-fast`: silo-api 30, silod 241 plus socket tests, silo-engine all passed after adding the method to the classification test (first run failed only that test). `cargo +1.94.0 fmt --all --check` clean. silo-ui not built.

## Fjord

- Schema snapshot and manifest updated to Silo `39b16587`; client regenerated (`scripts/generate-engine-client.sh --write`). New fields: `deviceId` on `SiloWireGuestExecInputParams` (the `macos.display.resize` `deviceId` was already in the snapshot's generated output, so only the exec input diff appears).
- No call site to change: Fjord never calls `guest.exec.input` (Triage runs start with `stdinOpen: false`, `SiloGuestClient.execStart` already passes the owner `deviceId`) and has no caller of `macos.display.resize`. The mock has no guest exec surface, so nothing to keep in step.
- Added a test that the generated input params carry `deviceId`.
- `swift build` ok; `scripts/test.sh`: 1747 tests in 172 suites passed.
