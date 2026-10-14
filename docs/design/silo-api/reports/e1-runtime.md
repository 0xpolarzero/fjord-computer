# E1-runtime implementation report

**Status: E1-owned modules are extracted and Tauri-free.** The required full Rust test run is blocked by an E2-owned compile error in `runtime/checkpoints.rs`. Work is on branch `engine/e1-runtime` in `/Users/polarzero/silo-work/e1-runtime`.

## Built

- Replaced runtime business logic's direct Tauri dependency with the `RuntimeHost` capability interface and `EngineContext`: the context supplies paths and event publication; the host interface supplies runtime state, notifications, package information, and host operations.
- Moved the runtime command bodies into thin adapters in `src/commands/runtime.rs`; `main.rs` registers the adapters and installs the startup, storage, and creation-input services.
- Extracted runtime log queries and exports, runtime storage maintenance, and computer creation wait inputs into Tauri-free modules with Tauri adapters under `src/commands/`.
- Extracted startup, health-watch, runtime-activity, shutdown, lifecycle recovery, configuration recovery, and update recovery services.
- Kept existing behavior, including window-targeted notifications, startup worker scheduling, identity failure notices, macOS runtime-log fallback, and shutdown behavior.

## Commits

- `88c52700` `refactor(engine): extract runtime log queries and exports`
- `4d35692a` `refactor(engine): extract runtime storage maintenance`
- `0c0e079b` `refactor(engine): extract computer creation wait inputs`
- `5acd5481` `refactor(engine): extract startup and health services`
- `eccb516e` `refactor(engine): extract runtime host and recovery services`

## Verification

Rust commands used `CARGO_TARGET_DIR=/Users/polarzero/silo-work/e1-runtime/target`, `CARGO_BUILD_JOBS=4`, Rust 1.94.0, locked dependencies, and the synthetic GitHub App configuration allowed for local native tests. No app or VM was launched.

- Filtered Cargo tests were attempted for `runtime::`, `runtime::runtime_logs::`, `runtime::storage::`, `creation_inputs::`, `startup::`, `health_watch::`, and `runtime_activity::`. Each stopped during crate compilation before its tests ran because E2's `runtime/checkpoints.rs` cannot resolve `AppHandle`.
- Full `cargo +1.94.0 test --manifest-path app/SiloUI/src-tauri/Cargo.toml --locked`: **blocked before tests ran** by seven unresolved `AppHandle` references in `src/runtime/checkpoints.rs` (lines 779, 1477, 1777, 2184, 2473, 2749, and 2898). That E2 module used to inherit `AppHandle` from the parent runtime module; the E1 extraction removed the parent import as required.
- `cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --check`: passed.
- `git diff --check`: passed.
- Searched E1-owned modules for `tauri::`, `AppHandle`, `WebviewWindow`, and `Emitter`: no matches outside `src/commands/`.

## Remaining Tauri references in E1 modules

No E1-owned business module contains Tauri references. The expected Tauri references remain in `src/commands/` thin wrappers and in `main.rs` command registration and app setup. `src/runtime/checkpoints.rs` is excluded from E1 ownership; its inherited-import compile break is listed below.

## Cross-track needs

- **E2 checkpoints:** add explicit `use tauri::{AppHandle, Emitter};` imports to `src/runtime/checkpoints.rs` while it remains Tauri-backed, or complete its extraction. This is the current full-test blocker. E1 did not edit the E2 module.
- **E3 macOS:** `commands/runtime.rs` currently adapts `macos_computers::{names, log_target, stop_all}` to `RuntimeHost`. Preserve or replace those operations with the equivalent host adapter when extracting the macOS module.
- **E4 identity:** `runtime/remote_ops.rs` still calls `crate::remote::log_identity()` for the local remote-log identity. Provide a stable engine identity capability or retain an adapter for this call during the identity/remote extraction.

No other cross-track blockers were identified.
