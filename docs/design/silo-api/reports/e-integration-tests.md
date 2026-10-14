# Engine integration regression tests

**Date:** 2026-10-14  
**Branch:** `engine/integration`  
**Commit:** `f9f0d9ea` (`test(engine): cover main-thread lookup and progress audiences`)

## Finding 4: AppKit window lookup

Added a recording `MainThread` runner test at the shared dispatch seam used by the macOS computer engine. The Tauri adapter test runs the current-window lookup closures and the production label/pointer validation helper inside that runner, then compares the lookup thread with the runner thread. The existing closed/replaced-window assertions remain.

**Fail-before:** temporarily changed `context::dispatch_to_main_thread` to call the work closure directly. Both focused tests failed with the runner-state assertion:

- Engine: `display_window_lookup_and_validation_run_on_the_main_thread_runner` failed at `runner.running`.
- Tauri adapter: `current_window_lookup_and_validation_run_on_the_main_thread_runner` failed at `runner_for_current.running`.

The captured failing runs are `target/verification/finding-4-engine-fail-before.log` and `target/verification/finding-4-ui-fail-before.log` in the integration worktree.

**Pass-after:** restored the dispatcher to call `MainThread::run`; both tests passed individually. Logs: `finding-4-engine-pass-after.log` and `finding-4-ui-pass-after.log`.

## Finding 6: main-window progress audiences

Added tests at the production publishers for all five events. Each recorded event must target `Audience::Client(ClientId::new("main"))`:

1. Preparation status.
2. Creation-wait progress.
3. Configuration storage warning.
4. Configuration progress.
5. Configuration recovery progress.

The host adapter routing test still verifies that a client audience uses the client-specific emit path and never the broadcast path.

**Fail-before:** temporarily changed all four publisher functions back to `Audience::All`; the focused `main_client` run failed all four site tests. The configuration publisher test covers both the warning and progress events. The independent shared-helper test remained green. Captured output: `target/verification/finding-6-fail-before.log`.

**Pass-after:** restored main-client publication. The focused engine run passed all five matching tests, and the Tauri host-routing test passed. Captured output: `finding-6-pass-after.log`.

## Finding 9: lock overlap test

Removed the 50 ms negative wait. The second thread now first uses `SETTINGS_CHANGE_LOCK.try_lock()` and signals only after observing `WouldBlock`; the test waits up to five seconds for that positive contention signal, then checks the mutation channel without a timing-based negative wait. If the worker does not reach the lock attempt, the test fails on the positive timeout instead of treating the delay as evidence of serialization.

The focused `overlapping_settings_invokes_cannot_apply_an_obsolete_native_theme` test passed after this change.

## Verification

Commands ran on Apple Silicon macOS with `CARGO_TARGET_DIR=/Users/polarzero/silo-work/integration/target`, `CARGO_BUILD_JOBS=8`, Rust 1.94.0, and the release guide's synthetic GitHub App test configuration.

- `cargo +1.94.0 test --manifest-path app/SiloUI/Cargo.toml --workspace --locked` — passed: API 27; engine 2,240 passed / 30 ignored; Silo UI 69; silod 30; handshake 1. No failures.
- `cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --all --check` — passed.
- `git diff --check` — passed before commit.

The full test output is retained at `target/verification/cargo-workspace-tests.log`; formatting output is at `target/verification/rustfmt-check.log`. Tests used fixtures and synthetic configuration. No app or computer was launched.

The integration changes are committed as `f9f0d9ea`. This report is in the Lookout worktree; its other pre-existing changes were left untouched.
