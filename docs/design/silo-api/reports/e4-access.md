# E4-access implementation report

**Status:** E4-owned engine modules are Tauri-free and committed. Test execution is blocked until the parallel E1, E2, E3, and E5 API changes are integrated.

## Built

- Removed Tauri command macros and `AppHandle` access from the E4 engine modules. Added thin command adapters under `app/SiloUI/src-tauri/src/commands/` and redirected the existing command registrations and startup hooks in `main.rs`.
- Moved GitHub, personal-token, and secrets commands, main-window checks, browser opening, and runtime adapters into `commands/github.rs` and `commands/secrets.rs`. GitHub and secrets engine events now publish through the installed engine context.
- Moved Connections, SSH access, remote network, host push, editor, terminal, file, transfer, and local network Tauri entry points into their command adapters. Engine functions use runtime paths, identifiers, values, and engine-context events.
- Kept the 15-second SSH access safety pass and asynchronous repository-push completion in background workers that do not require a Tauri runtime context.
- Moved the GitHub main-window permission test beside its command adapter. Fixed the GitHub connection guard field, editor context lifetime, and transfer download borrows found by the first compile attempt.

## Commits

- `9be3dce8` `refactor(engine): extract GitHub and secrets adapters`
- `37466a30` `refactor(engine): extract Connections and SSH adapters`
- `9e029e66` `refactor(engine): extract host push adapters`
- `55d02974` `refactor(engine): extract editor and terminal adapters`
- `e510b475` `refactor(engine): extract files network and transfer adapters`
- `1646ced0` `refactor(engine): wire access command adapters`

All commits are on `engine/e4-access`; nothing was pushed.

## Verification

All filtered Cargo test commands used `CARGO_TARGET_DIR=/Users/polarzero/silo-work/e4-access/target` and `CARGO_BUILD_JOBS=4`.

- Filtered `silo-ui` tests for `github`, `secrets`, `remote`, `ssh_access`, `ssh_connection`, `host_push`, `editor`, `files`, `transfer`, and `network`: each stopped during test-binary compilation with exit 101. No tests ran. The final compiler output had 31 API mismatches: caller updates in E1, E2, and E5 modules, plus E4 calls into the not-yet-extracted E1, E3, and E5 APIs.
- Full `cargo test --manifest-path app/SiloUI/src-tauri/Cargo.toml --locked`: exit 101 at the same 31 API mismatch errors; tests did not run. The final output is saved in the ignored file `target/verification/e4-full-cargo-test-final.log`.
- `cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --check`: passed before the final commit.
- `git diff --check`: passed.
- `rg` boundary scan across every E4-owned engine module found no `tauri::`, `AppHandle`, `WebviewWindow`, `Manager`, `Emitter`, window/dialog types, or `#[tauri::command]` references.

No UI code changed, so npm checks were not run. No changeset was added because this is an internal extraction with no intended user-visible behavior change.

## Remaining Tauri references in E4 modules

The engine modules have none. Tauri references remain under `src/commands/`, which the extraction conventions exempt. Those adapters still own command arguments and registration, main-window checks, file dialogs, terminal/editor/browser launch, native notifications, and startup. They also bridge the current E1 runtime-path and E2 checkpoint APIs; see Cross-track needs.

## Cross-track needs

The test blockers must be resolved by the owning tracks; E4 did not edit their modules.

- **E1 runtime:** update `runtime.rs` callsites for `secrets::schedule_revocations()` (line 2669), `host_push_operations::merge(&RuntimePaths, ...)` (2831), `github::snapshot()` (2865, 2882), and the moved terminal/editor opening functions (3265, 3267). Update `runtime_logs.rs:602` for the new `remote::call_remote_typed` signature and `runtime/remote_ops.rs` so `dispatch` accepts E4's runtime-path boundary. E4 command adapters also need E1's Tauri-free, migration-aware runtime-path resolver in place of `runtime::runtime_paths(&AppHandle)`.
- **E2 checkpoints:** update `runtime/checkpoints.rs:1481,1484` for the new `github::fork_assignment` and `forget_fork_assignment` signatures. Replace the current AppHandle-based checkpoint calls used by `commands/remote.rs` with E2's engine API.
- **E3 macOS:** change `macos_remote::open_display_stream` and `macos_remote::dispatch` to accept the path/context boundary used by `remote.rs:2044,2175`.
- **E5 services:** adapt `chatgpt_app.rs:2257,2324`, `desktop.rs:914-922`, `desktop_viewer.rs:259,274,330,417,658`, and `macos_remote_viewer.rs:121,218,289` to E4's new remote, editor, and transfer APIs. `remote_access.rs:38-53` also expects path-based `desktop_viewer::local_connection` and `desktop::dispatch`, plus no-AppHandle `chatgpt_app::local_status` and `retry_now` APIs.

After those signatures land in the shared integration branch, rerun the filtered E4 tests and the full Cargo suite. The current worktree cannot prove test behavior until then.
