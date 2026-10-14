# Engine extraction integration report

**Date:** 2026-10-14  
**Branch:** `engine/integration`  
**Status:** Complete; integration worktree clean.

## Branch merges

Merged with `git merge --no-ff`, one branch at a time, in the requested order:

1. `engine/e3-macos` — `0eba1c2c`
2. `engine/e5-services` — `15da365e`
3. `engine/e2-checkpoints` — `598a68ce`
4. `engine/e1-runtime` — `3ecf1997`
5. `engine/e4-access` — `e5747348`

## Cross-track fixes

- `a1e5a00e` aligned runtime and checkpoint host adapters, including the RuntimeHost imports and migration-aware path boundary.
- `1f326437` routed Connections through host capabilities and kept the E3 macOS display dispatch on its context seam while integrating E4 remote access.
- `870b4951` aligned service callers with the merged remote, runtime-log, and viewer APIs.
- `de399900` aligned command registration and adapter paths; the two frontend source-contract tests now assert the relocated `commands::remote` and `commands::runtime_storage` handlers.
- `5f82e19d` fixed two `Arc<dyn Fn>` callback coercions and a path borrow/move conflict exposed when compiling the combined ChatGPT adapter.

The E1 runtime, E2 checkpoints, E3 macOS, E4 access, and E5 services changes compile together in the final tree. The migration and backup recovery order remains intact: backup recovery is installed before automatic runtime migration, and migration waits for the backup controller through its command adapter.

## Remaining module extractions

Each requested module has its own extraction commit:

- `c53b3d5c` — checkpoint command adapters
- `50ffca03` — desktop command adapters
- `26682417` — desktop viewer command adapters
- `66b64e34` — backup controller command adapters
- `a623df6b` — runtime migration command adapters
- `6826025e` — ChatGPT app command adapters
- `af716802` — settings command adapters
- `18b45bc4` — updates command adapters

The engine modules own their policy and state transitions. Their Tauri command, app-state, window, event, updater, dialog, and lifecycle glue lives under `src/commands/`.

## Verification

All requested gates passed from `/Users/polarzero/silo-work/integration` with the warm target at `/Users/polarzero/silo-work/integration/target` and `CARGO_BUILD_JOBS=8`:

- `cargo +1.94.0 test --manifest-path app/SiloUI/src-tauri/Cargo.toml --locked` — 2,229 passed, 30 ignored, 0 failed; doc tests passed (0 tests).
- `cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --check` — passed.
- `npm --prefix app/SiloUI run typecheck` — passed under Node 24.21.0.
- `npm --prefix app/SiloUI run lint` — passed under Node 24.21.0 with six warnings: one unused expression in `desktop_viewer_bench.js` and five React Fast Refresh export warnings.
- `npm --prefix app/SiloUI test` — 266 test files and 2,764 tests passed under Node 24.21.0.

The native test build used the release guide's permitted synthetic GitHub App configuration. Verification logs are under the ignored `target/verification/` directory.

## Remaining Tauri coupling outside `src/commands/` and `main.rs`

Scanned from `app/SiloUI/src-tauri/src` with `rg -n 'tauri::|AppHandle|WebviewWindow|Manager|Emitter'`, excluding `commands/**` and `main.rs`. The remaining files are app-shell/native integration modules:

- `app_menu.rs`
- `engine_context.rs`
- `linux_menu.rs`
- `single_instance.rs`
- `status_panel.rs`
- `titlebar.rs`
- `tray.rs`
- `window_material.rs`

The requested extracted engine modules (`backup_controller.rs`, `runtime_migration.rs`, `desktop.rs`, `desktop_viewer.rs`, `chatgpt_app.rs`, `settings.rs`, and `updates.rs`) produced no matches.
