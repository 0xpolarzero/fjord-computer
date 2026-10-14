# D-checkpoints: checkpoints, exports, migration, preparation and device

Silo worktree: `~/silo-work/d-checkpoints`, branch `engine/d-checkpoints`, from `main@bd7c7c27` (the P2 dispatch keystone). Nothing was pushed. No VM or app was started.

This track continued an uncommitted diff another agent left behind. The diff did not compile. I kept its Linux job functions, the macOS policy kind and the `settings.rs` reader, and I rewrote or finished the rest (see "From the earlier diff").

## What was built

All 24 methods of the domain are implemented in `silod/src/methods/checkpoints.rs` and its child modules. Params and results are `silo-api` types. I did not change `silo-api`, so no schema regeneration was needed.

| Prefix | Methods | Notes |
| --- | --- | --- |
| `checkpoints.*` (6) | `create`, `restore`, `fork`, `delete`, `abandonRestore`, `usage` | The five changes are durable `job:` jobs. `usage` is a query. Both platforms. |
| `exports.*` (7) | `state`, `destination.set`, `inspect`, `create`, `import`, `dismiss`, `acknowledge` | Over the existing export controller. Ids are `exports:<operationId>` and `inspect:<requestId>`. |
| `migration.*` (5) | `state`, `preUpgradeBackup.get`, `.measure`, `.delete`, `.acknowledgeNotice` | |
| `preparation.*` (4) | `status`, `retry`, `chatgpt.status`, `chatgpt.retry` | |
| `device.*` (2) | `facts`, `dependencies` | |

### Checkpoints (`engine/src/checkpoints/`)

- `Service` is the two-platform adapter. It finds the owner of a computer by inventory (macOS registry first, then the Linux inventory), never by id format. It accepts each change durably, runs it on a blocking thread, persists the outcome, and publishes `checkpoints.changed` as `{linux: ApplicationSource}` or `{macos: MacosComputersState}`.
- `checkpoints.create` returns `{jobId}`. The job outcome is `{checkpoint: Checkpoint}`, the exact committed record, taken from the capture seam (no `checkpoints[0]` inference).
  - The record has `kind: manual | automatic`. `reason: manual | before-restore` and the macOS capture kind (`memory | disk`) are separate fields.
  - Linux dates are normalized to ISO 8601 in the adapter.
- Linux restore, fork, delete and abandon end with `ApplicationSource`. macOS ends with null. A failed change still refreshes the state and publishes `checkpoints.changed`.
- Linux gate entries are linked to the job (`acquire_for_job`).
  - Create is cancellable. The other four are not: a waiting entry leaves the queue, and a running one answers `NotCancellable`.
  - The cancel route is registered the same way the lifecycle code does it.
- Automatic checkpoints (95 A-18):
  - The setting is `automaticCheckpointRetentionCount`, a `u32` with default 3. `0` is off.
  - The engine reads it each time through `settings::automatic_checkpoint_retention_count_for(context)`.
  - `kind:"automatic"` is refused with `permission_denied` ("Automatic checkpoints are turned off in Silo settings.") twice: before the job is accepted, and again once the queue admits the capture.
  - Retention runs after a successful automatic capture. Capture and retention are two separate gate lanes.
    - The pure planner is `checkpoints/retention.rs`. It sorts by parsed time, newest first, with the id as tie-break.
    - It keeps the newest N and lists the rest oldest-first. Manual and before-restore records are never candidates. `0` selects nothing.
    - Each deletion is admitted separately and re-reads the setting, so turning the setting off stops later deletions.
    - Deletion is the ordinary safe path, never `--force`. A pinned record (dependency, pending Start, unfinished Restore) stays, visible with its `deleteBlocker`.
- macOS `checkpoints.usage`:
  - It returns the measured memory-file `sizeBytes`, and `totalBytes: null` unless there are no checkpoints. It never sums clone sizes.
  - Its blockers come from the same function `delete` uses (`checkpoint_delete_blocker`).
  - It needs no virtualization support (a read of saved records).
- macOS `checkpoints.abandonRestore` (the new adapter, 20 Q2) follows the Linux safety boundary:

| Journal state | Result |
| --- | --- |
| Staging journal | Staged files and journal are discarded. The original files and every recovery checkpoint are kept. |
| Swapping journal | Rolled forward and the pending restore is persisted. The abandon is then refused with "already replaced". |
| Unreadable journal | Every file is kept and the abandon is refused. |
| Settled pending restore | Refused with "already replaced". |
| No journal | "has no unfinished Restore." |

- Error codes: engine messages map to `ErrorCode` in `Failure::from_message`. The codes used are `not_found`, `busy`, `update_in_progress`, `cancelled`, `permission_denied` (automatic capture off) and `internal`. `unsupported_remote_operation` is used for a foreign `deviceId` and for macOS export.

### Exports, migration, preparation, device

- `exports.state` returns the API `BackupState`, now with the remembered `destination`. `exports.changed` carries the same state. The controller is installed on first use.
- `exports.destination.set` canonicalizes and requires a folder. It remembers the folder, publishes `exports.changed`, and returns `{destination}`.
- `exports.create` takes computer ids. The engine resolves them to names on the owner (`begin_export_for_ids`).
- `exports.inspect` returns `inspect:<requestId>`. Repeating the id returns the existing job instead of starting or cancelling anything.
- `exports.dismiss` compares against the raw `expectedOperation` JSON, as received.
- The pre-upgrade backup methods return the API shape with the new `path` field.
  - `migration.preUpgradeBackup.changed` is published from `announce_changed(context)`. It carries the `get` result, `null` once the backup is gone.
  - `delete` and `acknowledgeNotice` publish it too.
- `migration.state` returns the API `MigrationState`. `runtime_migration::publish_state(context, controller)` publishes `migration.changed` (see "Next tracks").
- `preparation.changed` is now also published to `Audience::All`. The legacy main-window event stays.
- `preparation.chatgpt.changed` is published by a status publisher given to the ChatGPT worker.
- `device.facts` returns the API `DeviceFacts`.
  - `deviceCapacity` and `macosHostLimits` are measured the same way as before. `macosHostLimits` is null off Apple silicon.
  - `remoteLogin` is a loopback connect to port 22: accepted is `enabled`, refused is `disabled`, anything else is `unknown`. The spec calls an authoritative probe unsourced (80 C-10), so this is the simplest option and it never enables SSH.
- `device.dependencies` validates the request id and reports each check.

### Launch upgrade of the checkpoint layouts

This follows 95 §3: one conversion at launch, then normal reads accept only the new layout.

- Linux `checkpoints/<id>.json` goes from version 1 to 2. macOS `checkpoint.json` goes from schema 1 to 2.
  - Every record becomes `manual`. Reason, native id, dates, memory fields and journals are kept.
  - There is no `serde(default)` fallback any more.
- `checkpoints::upgrade_layouts(context, migration)` is called at silod start (`app.rs`) and in the Tauri setup (`src/main.rs`, a statement after the migration controller is installed). Both run before anything reads the records and before the macOS sweep.
- It is idempotent. A damaged history is left byte for byte. While the storage migration is pending, the Linux storage (the pre-upgrade backup source) is not touched, and macOS records are converted anyway.
- The macOS sweep spares an unconverted layout-1 record (it used to delete anything unreadable).
- Frontend: the Rust contract fixtures were regenerated. They only gain `"kind": "manual"`. The zod schemas pass an optional `kind` through. `npm test` on the touched areas passes (1866 tests), as does the typecheck.

## Commits (`engine/d-checkpoints`)

| Hash | Message |
| --- | --- |
| `8b259ece` | feat(engine): automatic checkpoints, retention and two-platform checkpoint jobs |
| `b7f47cd7` | feat(engine): canonical export, migration, preparation and device topics |
| `793b4604` | feat(silod): checkpoints, exports, migration, preparation and device handlers |
| `0840ef36` | test(engine): cover the automatic checkpoint count validator |
| `2e50a7b4` | feat(engine): upgrade checkpoint records to the policy-kind layout at launch |

## Tests

Run as `cargo +1.94.0 test --workspace --locked` from `app/SiloUI`, with `CARGO_TARGET_DIR=~/silo-work/d-checkpoints/target`.

| Crate or target | Result |
| --- | --- |
| `silo-engine` lib | 2,355 passed, 30 ignored, 2 failed |
| `silod` lib | 62 passed, 0 failed |
| `silod` socket tests | `checkpoints_domain` 1 passed, `handshake` 1 passed |
| `silo-ui` | 71 passed, 0 failed |
| `silo-api` | 27 passed, 0 failed |

The 2 engine failures are timing flakes that do not come from this track.
- `dependencies::version_probe_accepts_the_output_limit...` times out under load (the machine's load average was 26-68). It passes when rerun.
- `backup_controller::install_schedules_pending_import_recovery_outside_tokio_runtime` is a race: the test checks `busy` right after `pending` clears. I ran a binary built with the base `backup_controller.rs` against mine, 15 runs each. It failed 11/15 on the base file and 13/15 on mine, so my change does not cause it.

`cargo +1.94.0 fmt --all --check` passes for every file this track touched. It still fails on files I did not touch and that are already unformatted at `main@bd7c7c27`: `engine/src/backup_controller.rs` (10 hunks), `engine/src/jobs/registry.rs`, `engine/src/macos_computers.rs` (1), `silod/src/methods/computers.rs`, `silod/src/methods/mod.rs` and `silod/src/methods/services.rs`. I left those as they are so the track does not collide with the other agents editing the same files. The coordinator's merge-time style commit covers them.

New tests:
- **Per handler:** `silod/src/methods/checkpoints/tests.rs` has 21 tests, at least one per handler. They cover another device refused, Linux and macOS job start with a durable outcome, automatic refused at zero and accepted at the default, and the usage shape on both platforms. They also cover exports (destination and event, inspect job, create refusals, import validation, dismiss and acknowledge), the pre-upgrade backup (null without a backup, and read, measure, acknowledge and delete with their topic), migration, preparation, ChatGPT status and publisher, device facts and dependencies.
- **Socket level:** `silod/tests/checkpoints_domain.rs` does the handshake, `exports.destination.set` then `exports.state`, `migration.state`, `device.facts` and `preparation.status`. It starts `exports.inspect` as a job, reads it back with `operations.job.get`, and acknowledges it. It also checks the `not_found` and `unsupported_remote_operation` errors.
- **Engine:**
  - the retention planner;
  - Linux retention with a fake native store: keeps the newest N, never touches manual records, stops when the setting is turned off, keeps a pinned record;
  - the automatic capture record;
  - macOS retention, usage and blockers, and abandon in all five cases;
  - the launch upgrade (Linux, macOS, pending migration, idempotent, damaged history untouched, sweep spares layout 1);
  - owner resolution, the Linux job lifecycle, error mapping, `device_facts`, `preparation.changed` and `migration.changed` publication, and the settings validator.

## Deviations and decisions

1. **No singular bridge names.**
   - 20 §1.3 and P3-checkpoints ask for remote delete, abandon and usage "through the canonical owner dispatcher". I did not add `checkpoint.delete`, `checkpoint.abandonRestore` or `checkpoint.usage` to the legacy bridge table. 95 §3 drops the singular names, and P3-connections renames that table.
   - The six `checkpoints.*` handlers are the owner dispatch for both platforms. They accept `deviceId` only when it is this engine; any other device gets `unsupported_remote_operation`, like the other domain tracks.
2. **Retention has no durable `RetentionIntent`.**
   - Retention runs in the same job right after the verified automatic capture, and the next successful automatic capture applies the current count again. This self-heals after a crash between the capture commit and the cleanup.
   - Not done: retrying blocked cleanup on Restore settlement or Start, and the P2 upkeep timer for deferred retention. The overflow stays visible through `deleteBlocker`.
3. **macOS export is refused.** `exports.create` answers `unsupported_remote_operation` for a macOS computer ("macOS computers cannot be exported yet"). The archive mechanism is the open question 20 Q4, and format 4 carries Linux snapshots. Import and inspect handle format 4 only.
4. **Linux job state.** `mark_running` is called when the worker starts, not when the gate admits the entry. The queue entry still shows waiting until admission.
5. **Settings.**
   - I added the key to the validator as a `u32` (0 up to `u32::MAX`; negative, fractional, string and overflow are rejected). d-services also adds the key to `valid_setting` as `as_u64().is_some()`. Expect a conflict on that line and keep the `u32` bound.
   - The reader is `current_settings_for(context)` and `automatic_checkpoint_retention_count_for(context)`.
6. **Shared files other tracks also edit.** Expect text conflicts, all small:
   - `silod/src/context.rs`: I added `migration_controller()`, `runtime_host()` and `backup_controller()`. d-display builds its own runtime host in `display.rs`; the coordinator can point both at `SilodContext::runtime_host()`.
   - `silod/Cargo.toml`: a `silo-engine` dev-dependency with `test-support`.
   - `engine/src/backup_controller.rs`: `api_state`, `begin_export_for_ids` and the publish path (d-display touches this file).
   - `engine/src/macos_computers.rs`.
   - `engine/src/settings.rs`.
   - `silod/src/app.rs`.
   - `src-tauri/src/main.rs`.
   - `engine/src/lib.rs`: two `pub mod` lines.
7. **Test-only engine API.** `macos_computers::{reset_registry_for_test, seed_test_computer, seed_check_policy}` are `pub` under `cfg(any(test, feature="test-support"))` so the silod tests can seed a macOS computer.

## From the earlier diff

Kept:
- the Linux `*_for_job` functions;
- the macOS `PolicyKind` and the `start_macos_checkpoint_*` job starters;
- the `RuntimeHost` and controllers on `SilodContext`;
- the settings reader.

Changed or finished:
- It did not compile (a missing `mut`, a missing import, an unused `policy_kind`, `Scope`).
- Retention now reads the setting at each deletion, and the planner is a separate pure module.
- The `kind` / `policy_kind` serde defaults became the launch upgrade.
- The macOS usage message now comes from the delete path.
- macOS abandon, the `checkpoints.changed` payload shape and the ChatGPT status publisher were added.

## Next tracks

- **P3-connections:** route `deviceId` for these methods to the owner. The handlers already run on the owner as canonical methods. The 122-minute budget and `operationId` replay rules for `checkpoints.*` still have to move off the singular bridge names.
- **Startup (P3-lifecycle):**
  - `silod` does not yet run the launch work for this domain. It should call `preparation::start_with_paths(runtime_paths)` and the ChatGPT automatic worker (`start_automatic`).
  - It should install the export controller at boot, before computers start. Today it is installed on the first `exports.*` call, so an interrupted export journal is settled then, not at launch.
  - `runtime_migration::publish_state` must be called from the launch migration driver. No driver exists in silod, and the conversion triggers are retired.
  - Not wired in `preparation.chatgpt.retry`: the Tauri ready hook also applies computer use in running Linux computers (a computer-use job). The silod hook only removes unused app versions.
- **Fjord (the automatic checkpoint before an unattended run):**
  1. Read `automaticCheckpointRetentionCount` through `settings.read`. If it is 0, skip the capture.
  2. Call `checkpoints.create {computerId, name: "Before run: <task>, deleted automatically", kind: "automatic"}`. The whole name is limited to 80 printable characters, so truncate the task part.
  3. Wait for `operations.job.finished.result.checkpoint` before `guest.exec.start`.
  4. On failure, or on `permission_denied` (the setting was turned off after the read), do not start the run.
- **Live probes:** B-33 (four automatic captures, off and re-enable, pinned excess, restart), the macOS part of B-34 (queue, errors, abandon) and B-36 (deferred retry) were not run. No VM was started.
