# E3-macos implementation report

**Status: complete.** The worktree is `/Users/polarzero/silo-work/e3-macos` on `engine/e3-macos`, clean at `9054b3be`. The E3 engine modules are Tauri-free outside `src/commands/`.

## Done

- `macos_computers.rs` and `macos_computers/*`: moved the engine implementation behind `MacosContext`, using `EnginePaths`, `EngineContext::publish`, and `EngineContext::main_thread()`. Paths, events, and VZ/AppKit work no longer depend on Tauri. Added a local `MacosHost` adapter for host display windows; the engine side attaches the VM view through a native window handle.
- `macos_remote_viewer.rs`: moved the Tauri webview and viewer-window lifecycle into `commands/macos_remote_viewer.rs`. Its blocking work uses Tokio.
- `macos_remote.rs`: separated the plain bridge dispatcher and validation from Tauri commands. The owner-side dispatcher accepts `MacosContext`; command and current remote-bridge compatibility adapters live in `commands/macos_remote.rs`.
- `macos_display_gateway.rs` was already Tauri API-free and remains unchanged.
- Command names and handler registration remain stable. No `EngineContext` methods were added.

## Commits

- `958757abf450a56dfba1843d2b5b2a2f4c0cd4ef` `refactor(engine): move macOS remote viewer commands to adapter`
- `e5228812556b10b7a14a18c8698f1b002f2c2651` `refactor(engine): extract macOS computer capabilities`
- `9054b3be70ea399499adb679b660911807ea3eb9` `refactor(engine): extract macOS remote dispatch`

## Verification

Filtered tests passed after each module group:

- `cargo test --manifest-path app/SiloUI/src-tauri/Cargo.toml -p silo-ui --locked macos_remote_viewer::tests`: 5 passed.
- `cargo test --manifest-path app/SiloUI/src-tauri/Cargo.toml -p silo-ui --locked macos_display_gateway::tests`: 8 passed.
- `cargo test --manifest-path app/SiloUI/src-tauri/Cargo.toml -p silo-ui --locked macos_computers`: 253 passed, 3 ignored.
- `cargo test --manifest-path app/SiloUI/src-tauri/Cargo.toml -p silo-ui --locked macos_remote_engine::tests`: 4 passed.

Before the final commit, with `CARGO_TARGET_DIR=/Users/polarzero/silo-work/e3-macos/target`, `CARGO_BUILD_JOBS=4`, and the synthetic GitHub App values permitted by `docs/SiloUI-RELEASES.md`:

- `cargo test --manifest-path app/SiloUI/src-tauri/Cargo.toml --locked`: passed; `silo-ui` 2,229 passed and 30 ignored, `silo-engine` 60 passed, doc tests passed.
- `cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --check`: passed.
- `git diff --check`: passed.

The full Rust run emitted non-failing warnings in remote, runtime-migration, bundled-tools, macOS FFI, and desktop-viewer-probe code. No app, VM, live computer, or real user data was used.

## Remaining Tauri references in E3 modules

Outside `src/commands/`, the owned engine sources have no Tauri API references (`tauri::`, `AppHandle`, `WebviewWindow`, `Manager`, `Emitter`, or Tauri command attributes). `macos_display_gateway.rs` retains `tauri://localhost`, `http://tauri.localhost`, and `https://tauri.localhost` as allowed browser-origin strings; these are protocol data, not Tauri API coupling.

| Module | Remaining references and reason |
| --- | --- |
| `commands/macos_computers.rs` | Tauri command arguments and the native display-window host adapter. It owns webview creation, window focus/close notifications, and passes the native window handle to the Tauri-free engine hook. It also retains the small AppHandle compatibility facade used by E1 runtime and logging call sites. |
| `commands/macos_remote.rs` | Tauri command wrappers check the calling window and call the existing remote client. Its `dispatch`, `open_display_stream`, and `DISPLAY_STREAM` facade preserves the current E4 bridge call sites until that track adopts the context-based engine dispatcher. |
| `commands/macos_remote_viewer.rs` | Client-only viewer window creation, focus and close handling, and remote display session lifecycle. These operations belong to the Tauri client adapter; the engine does not own viewer windows. |
| `main.rs` | Tauri command handler registration, retained as the host integration point. |

## Cross-track needs

- **E1-runtime:** the `commands::macos_computers` compatibility facade preserves `stop_all`, `names`, and `log_target` callers that still pass `AppHandle` from runtime shutdown, recovery, checkpoints, and runtime logs. `TauriMacosHost::linux_computer_names` also uses `runtime::computer_names(&AppHandle)` for the existing unique-name collision check. E1 can remove these seams after exposing path/context-based runtime entry points.
- **E4-remote:** `remote.rs` still calls the root `macos_remote` compatibility facade with `AppHandle` for `dispatch`, `open_display_stream`, and `DISPLAY_STREAM`. The facade now builds `MacosContext` in the command layer. E4 should route bridge handling through the context-based engine functions and remove the alias.
- **Engine integration:** the current `EngineContext` has no native display-window host capability. This track uses a local `MacosHost` adapter and the `attach_display` native-window hook without changing `EngineContext`; the integration track must carry that host seam when moving the engine module.
