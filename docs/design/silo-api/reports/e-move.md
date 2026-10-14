# Engine module move report

**Date:** 2026-10-14  
**Branch:** `engine/integration`  
**Status:** Complete; integration worktree clean.

## Commits

1. `d0be5fad` — merge `main` with `--no-ff`
2. `4e9f8a60` — add `silo-api` to the workspace and `silo-engine` dependency graph
3. `380c9e84` — move runtime into `silo-engine`
4. `ccfabe60` — move checkpoints and backups into `silo-engine`
5. `93929d9a` — move macOS computer services into `silo-engine`
6. `e7d43be5` — move access services into `silo-engine`
7. `bea1396f` — move remaining services and test support into `silo-engine`

Each module group was moved with `git mv` and committed separately. The full Rust, formatting, and frontend gates passed after each extraction group.

## Final crate layout

- `app/SiloUI/api/` — canonical `silo-api` wire contract crate and generated schema.
- `app/SiloUI/src-tauri/engine/` — Tauri-free runtime, backup/checkpoint, computer, access, integration policy, update policy, desktop bridge, and other engine modules. Module tests and engine fixtures moved with their modules.
- `app/SiloUI/src-tauri/src/` — `main.rs` setup, `engine_context.rs`, Tauri command adapters, app-shell/window/dialog modules, and UI-specific tests and benchmarks.

The old `src/` tree has no remaining Tauri-free production engine modules. Source-contract tests, API docs, and the generated API schema now point at the relocated engine sources.

## Remaining UI-side code

Tauri command handlers stay in `src/commands/` because they bind engine calls to `AppHandle`, commands, events, dialogs, updater services, and windows. The `main.rs` setup and `engine_context.rs` also remain UI-side. App shell and native window modules remain in `src/`: `app_menu`, `linux_menu`, `single_instance`, `status_panel`, `titlebar`, `tray`, `viewer_shortcuts`, and `window_material`; command permission tests, GitHub build/permission tests, and the desktop-viewer benchmark remain with that client code.

The system-integration policy moved into the engine; dialog and notification installation wrappers remain in `commands/system_integrations.rs`. The macOS viewer origin allowlist remains in `commands/macos_remote_viewer.rs` because it names webview schemes. The engine gateway accepts the allowed origins as input. The example `desktop-viewer-probe.rs` remains a Tauri harness and points at the moved engine bridge modules.

## Verification

The final full Rust workspace test run used fixture data and the release guide's synthetic GitHub App test configuration:

- `cargo test --manifest-path app/SiloUI/src-tauri/Cargo.toml --workspace --locked --quiet` — API: 26 passed; engine: 2,230 passed, 30 ignored; UI: 59 passed; 0 failures.
- `cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --check` — passed.
- `npm --prefix app/SiloUI run typecheck` — passed.
- `npm --prefix app/SiloUI run lint` — passed with six existing warnings: one unused expression in `desktop_viewer_bench.js` and five React Fast Refresh export warnings.
- `npm --prefix app/SiloUI test -- --reporter=dot` — 266 files and 2,764 tests passed.
- `cargo test --manifest-path app/SiloUI/Cargo.toml -p silo-api --locked --quiet` — 26 passed, including the generated-schema match.
- `cargo build --manifest-path app/SiloUI/Cargo.toml -p silo-engine --locked` — passed as a standalone package build.
- `cargo tree --manifest-path app/SiloUI/Cargo.toml -p silo-engine --edges normal,build,dev` — no Tauri package in the dependency tree.
- `rg -n 'tauri' app/SiloUI/src-tauri/engine/src` — matches are confined to test-only configuration and gateway-origin strings.

The standalone engine build emits 30 Rust compiler warnings, including unused items, public/private interface warnings, deprecation, and a conflicting `CFRelease` declaration. The build succeeds; these warnings remain for follow-up cleanup.
