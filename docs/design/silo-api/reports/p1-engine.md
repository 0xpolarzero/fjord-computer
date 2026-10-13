# P1-engine implementation report

**Status: partial; P1-engine is not ready for P2-silod.** Work is on branch `engine/p1-engine` in `/Users/polarzero/silo-work/p1-engine`. The extraction is behavior-preserving so far, but most backend logic and all Tauri command bodies remain in `silo-ui`.

## Built

- Added a Cargo workspace rooted at `app/SiloUI/src-tauri/Cargo.toml` and a Tauri-free `silo-engine` member at `app/SiloUI/src-tauri/engine`.
- Moved build-channel identity into `silo-engine`; `silo-ui` keeps a re-export for existing call sites.
- Added the `EngineContext` capability interface in the engine crate: app paths, identity/channel, event publication and audience, a main-thread runner, and process exit/restart. Added `TauriEngineContext` in `silo-ui/src/engine_context.rs` and install it during app setup.
- Moved the runtime operation gate and its process-wide `OPERATIONS` instance into `silo-engine`. Replaced the gate's Tauri blocking-task dependency with Tokio; `silo-ui` keeps a re-export shim.
- Moved image-cache inspection and repair into `silo-engine`; `silo-ui` keeps a re-export shim.
- Added `docs/SiloUI-ENGINE.md` describing the crate boundary and the future native-window seam.

The context is currently a foundation, not yet the dependency used by extracted business logic. `RuntimePaths`, process execution, runtime lifecycle, and most event publication still use the existing `silo-ui` implementation and `AppHandle`. The 160 existing `#[tauri::command]` declarations have not yet been converted to thin wrappers.

## Commits

- `40b75315` `refactor(engine): add Tauri-free context foundation`
- `40798272` `refactor(engine): move operation gate into engine crate`
- `18248a26` `refactor(engine): move image cache repair into engine`

## Verification

All commands used `CARGO_TARGET_DIR=/Users/polarzero/silo-work/p1-engine/target` where applicable. Native test/build commands used synthetic GitHub App values permitted by `docs/SiloUI-RELEASES.md`; no local credentials were printed. No app or VM was launched.

- `cargo test --manifest-path app/SiloUI/src-tauri/Cargo.toml -p silo-engine runtime::image_cache --locked`: 13 passed.
- `cargo test --manifest-path app/SiloUI/src-tauri/Cargo.toml -p silo-ui --no-run --locked`: passed.
- Final `cargo test --manifest-path app/SiloUI/src-tauri/Cargo.toml --locked`: **2,229 passed, 30 ignored, 0 failed**; engine doc tests passed (0 tests).
- `cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --check`: passed.
- `npm --prefix app/SiloUI ci` under Node 24 was needed because the preexisting install pointed to a missing global TypeScript path. It completed; npm reported 3 dependency audit findings (2 high, 1 critical).
- `npm --prefix app/SiloUI run typecheck`: passed.
- `npm --prefix app/SiloUI run lint`: passed with existing lint warnings in the desktop-viewer benchmark and React fast-refresh modules.
- `npm --prefix app/SiloUI test`: **266 files and 2,764 tests passed**.
- `npm --prefix app/SiloUI run runtime:prepare`: passed earlier in this worktree to prepare the generated native build inputs.
- `rg -n 'tauri::|AppHandle|tauri' app/SiloUI/src-tauri/engine`: no Tauri APIs or `AppHandle` references in engine code. The remaining matches are test strings naming `tauri.conf.json` and `tauri.dev.conf.json`.

## Remaining work and continuation

The current engine contains only `channel`, `context`, `runtime::operation_gate`, and `runtime::image_cache` (plus operation-gate contract tests). `EngineContext` is not yet wired into those business modules. Continue in the requested order, moving one complete module group per commit and preserving its existing tests:

1. **Paths and runtime foundation:** move runtime path and domain seams out of `src/runtime.rs`. In particular, replace `runtime_paths(AppHandle)` and related `inert_runtime_paths`, `migration_runtime_paths`, and path construction with engine paths supplied through `EngineContext`; move runtime errors and runner boundaries; keep the Tauri process adapter in `silo-ui`. Then extract lifecycle, runtime state, activity, guest-image, and configuration-recovery modules behind those seams. Relevant remaining files include `src/runtime.rs`, `src/runtime_activity.rs`, `src/guest_image.rs`, `src/runtime/configuration_recovery.rs`, `src/runtime/lifecycle_recovery.rs`, `src/runtime/remote_ops.rs`, `src/runtime/secrets_runtime.rs`, `src/runtime/shutdown.rs`, `src/runtime/storage.rs`, `src/runtime/update_recovery.rs`, and `src/runtime_logs.rs`.
2. **Checkpoints:** move the full checkpoint group, including `src/runtime/checkpoints.rs`, `src/runtime/checkpoints/native.rs`, and its retry tests, after the runtime paths, runner, configuration, and recovery seams exist. `src/runtime/crash_acknowledgement.rs` also depends on this runtime layer.
3. **macOS:** extract the backend in `src/macos_computers.rs` and `src/macos_computers/`, plus `src/macos_display_gateway.rs`. Route VZ/AppKit work through `EngineContext::main_thread()`. Keep window policy in `silo-ui`; expose an engine hook that accepts the host's `NSWindow` (or an equivalent native handle) so a later `silod` can host the VM view. The current docs describe this seam, but no VZ implementation has moved yet.
4. **GitHub and secrets:** extract business logic from `src/github.rs`, `src/github_http.rs`, `src/github_personal_token.rs`, `src/github_tokens.rs`, `src/secrets.rs`, and the GitHub/secrets sections still embedded in `src/runtime.rs`. Keep credential and Tauri UI adapters on the client side where required.
5. **Remote:** extract engine behavior from `src/remote.rs`, `src/remote/`, `src/remote_access.rs`, `src/remote_network.rs`, `src/remote_ssh_access.rs`, `src/host_push.rs`, `src/host_push_cache.rs`, `src/host_push_operations.rs`, and `src/host_push_transport.rs`; leave client presentation and connection UI in `silo-ui`.
6. **Remaining backend and command adapters:** continue through backup/recovery, computer creation and configuration, files/transfers, networking, desktop/guest operations, settings, startup, and other non-client logic. Convert the corresponding commands into thin calls into `silo-engine`. Keep dialogs, opener, updater plugin, tray, menus, windows, and theme in `silo-ui` per 05 §2. Review command registration in `src/main.rs` as each group moves.

The checkpoint, macOS, GitHub/secrets, remote, and remaining backend groups above have not been extracted. The build-channel and runtime slices did not rename canonical API names or change behavior. The implementer brief says “Macs only”; this partial track retained existing platform behavior and Linux host code because it did not reach a host-platform migration and the track requires no behavior change. Resolve that scope when completing the host-specific extraction rather than treating this report as Linux parity work.

## Notes for dependent tracks

- P1-api can proceed independently. The engine currently has a preliminary `Event { name, payload }` and `Audience`; it does not yet use the canonical `silo-api` wire types or event catalogue. Do not treat these scaffolding types as the final wire contract.
- P2-silod should wait for the runtime and macOS extraction. The current `EngineContext` implementation is Tauri-backed and the runtime still consumes Tauri directly; it is not yet a usable headless engine boundary.
- P1-fjord-ui can continue against its mock. The native `NSWindow` host hook is documented but not implemented.
