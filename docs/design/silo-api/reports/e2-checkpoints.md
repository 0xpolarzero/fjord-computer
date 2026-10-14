# E2-checkpoints implementation report

**Status: partial.** Two complete module groups are Tauri-free and committed on `engine/e2-checkpoints`. The checkpoint commands, backup controller and storage migration still need extraction; this track is not ready for integration.

## Done

- `pre_upgrade_backup.rs` now gets app-data and home paths from `silo_engine::context::current()`, and publishes its change event through `EngineContext`. The five Tauri commands moved to thin wrappers in `src/commands/pre_upgrade_backup.rs`; command names and handler registration are unchanged. Folder reveal remains in the wrapper through Tauri's opener plugin.
- `runtime_migration/vocabulary.rs` now gets app-config, app-data and home paths from the installed engine context. The conversion logic and tests remain unchanged; its startup call no longer takes an `AppHandle`.
- `backup.rs`, `runtime/checkpoints/native.rs`, and the checkpoint and migration test modules had no Tauri references to remove and were not changed.
- No user-visible behavior change or changeset was added.

## Commits

- `dc781258` `refactor(engine): extract pre-upgrade backup commands`
- `6efffb98` `refactor(engine): use host context for vocabulary migration`

## Verification

Native tests used synthetic GitHub App values and `CARGO_TARGET_DIR=/Users/polarzero/silo-work/e2-checkpoints/target`, `CARGO_BUILD_JOBS=4`.

- `cargo test --manifest-path app/SiloUI/src-tauri/Cargo.toml --locked pre_upgrade_backup`: **31 passed**.
- `cargo test --manifest-path app/SiloUI/src-tauri/Cargo.toml --locked vocabulary`: **33 passed**.
- `cargo test --manifest-path app/SiloUI/src-tauri/Cargo.toml --locked`: engine **60 passed**; Silo UI **2,229 passed, 30 ignored, 0 failed**; doc tests passed (0 tests).
- `cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --check`: passed.

The full suite ran on fixtures and unit-test inputs. No app or computer was launched. Existing compiler warnings remain in unrelated code.

## Remaining Tauri references

The remaining owned modules below still contain Tauri types or calls outside `src/commands/`.

- `runtime/checkpoints.rs`: six `#[tauri::command]` declarations at lines 777, 1775, 2182, 2471, 2747 and 2896; corresponding `AppHandle` parameters at 779, 1777, 2184, 2473, 2749 and 2898; `AppForkAssignments` stores an `AppHandle` at 1477; `tauri::async_runtime::spawn_blocking` remains at 2901; event emits remain at 804, 1797, 2208, 2493 and 2768. The command bodies still resolve runtime paths and migration readiness, refresh application state, publish change events, and provide GitHub/secrets and macOS-computer services. Their `AppHandle` name comes from the parent `runtime.rs` imports via `super::*`.
- `backup_controller.rs`: Tauri imports at line 16 (`AppHandle`, `Emitter`, `Manager`, `State`, `WebviewWindow`) and `tauri_plugin_dialog::DialogExt` at 17; command declarations at 452, 506, 546, 573, 631, 708, 781, 1564, 2053, 2116 and 2146; `tauri::async_runtime::spawn_blocking` at 457, 514, 552, 584, 725, 816, 901, 1639, 1727, 2060, 2126 and 2155. `AppHandle` helper parameters remain at 259, 322, 328, 332, 411, 508, 548, 783, 805, 824, 1036, 1287, 1566, 1582, 1615, 1629, 1647, 1736, 1800, 2118, 2148, 5674 and 5689. Tauri state setup/access remains at 308, 333, 5675 and 5690; app path lookup at 261 and 277; event emission at 413; dialogs at 524 and 554; opener at 727. These references serve managed controller state, main-window authorization, path lookup, backup dialogs, archive reveal, runtime-path access, notifications and event delivery.
- `backup_controller/recovery.rs`: `AppHandle` parameters at 874 and 955, `runtime_migration::blocks_operations(&app)` at 894, `tauri::async_runtime::spawn_blocking` at 928, and `runtime::inert_runtime_paths`/`runtime::runtime_paths` calls at 968 and 972. Recovery still uses the app to read migration state and runtime paths.
- `runtime_migration.rs`: Tauri imports at line 14; staged paths at 409; conversion at 655-656; Tauri path lookup at 823; managed controller setup/access at 821, 836, 847-848, 892, 908, 913, 925, 930, 946, 949, 1019-1020 and 1043-1044; command declarations at 965, 992 and 1036, with `AppHandle` command arguments at 966, 993 and 1038; `tauri::async_runtime` at 681, 971, 987, 1023 and 1075; app-bound blocking helper at 984-985; event emission at 961; process restart at 683 and 1077. Migration still stores its controller in Tauri state, resolves staged runtime paths through the Tauri runtime adapter, publishes directly, and restarts the Tauri process.

`pre_upgrade_backup.rs`, `runtime_migration/vocabulary.rs`, `runtime_migration/vocabulary/`, `backup.rs`, `runtime/checkpoints/native.rs`, and the owned test files have no remaining `tauri::`, `AppHandle`, `WebviewWindow`, `Manager`, `Emitter` or `State` references. The new command wrapper's Tauri references are intentional.

## Cross-track needs

- **E1-runtime:** provide a Tauri-free runtime-path builder for normal, inert and staged storage, plus the runner and application-state refresh/enrichment seams. Checkpoints and backup operations need those APIs; storage migration needs staged paths. `runtime.rs` currently owns the AppHandle-bound versions.
- **E3-macos:** expose the macOS-computer name lookup as an engine API or an injected provider. Fork checkpoint currently calls `macos_computers::names(&AppHandle)`.
- **E4-access:** expose GitHub and secrets fork-assignment copy/forget operations without `AppHandle`. Checkpoint fork currently implements these in `AppForkAssignments` using the Tauri-backed GitHub adapter.
- **E5-services:** expose a Tauri-free notice path for backup-operation notifications. `backup_controller::notify_transfer` currently needs `AppHandle` to resolve computer identity and invoke notification delivery.
- **E1-runtime and E5-services:** when `runtime_migration` drops its compatibility signatures, update runtime and startup callers of `ensure_ready`, `ensure_ready_async`, `runtime_storage` and `blocks_operations` to use the engine context. Current call sites are in `runtime.rs` and `startup.rs`.
- **Within E2:** migrate `backup_controller`'s recovery wait into engine-owned state before converting `runtime_migration`; migration waits for backup/import recovery before staged conversion.
