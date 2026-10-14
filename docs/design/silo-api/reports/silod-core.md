# silod core integration

Silo branch `engine/silod-core` (worktree `~/silo-work/silod-core`), off `main@bd3f8984`. Merged fast-forward into `main` at `c86ab49a`. Not pushed. No app, VM or window was started.

## Commits

| Hash | What |
| --- | --- |
| `b5db8ed7` | `feat(silod)`: the handshake capability list is derived from the domain routers |
| `aa79d8ee` | `feat(engine)`: timer-callable log expiry and port repair passes, and a launch migration driver |
| `5814f8f3` | `feat(silod)`: launch pass adapter, boot work, engine timers, `desktop.connect` refusal, VM window host and AppKit delegate |
| merges | `0ec6585e`, `c86ab49a` (main moved twice; re-gated each time) |

The third commit bundles items 2 to 6 because `app.rs`, `display.rs` and `methods/mod.rs` are shared by them; splitting by hunk was not worth the risk.

## What was built

1. **Capabilities.** `methods::serves(method)` is the built-ins plus the `owns` of the six domain routers. `CoreMethodRegistry` filters the catalogue by it. Withheld on purpose: `macos.display.stream` and `display.native.attach` (owned, but always a typed refusal) and `desktop.connect` (item 5). Test: the capability set equals the catalogue minus those three, and spot-checks methods of each domain. `tests/handshake.rs` checks `computers.list`, `exports.state` and `display.show` over the socket.
2. **Launch pass.** `silod/src/startup.rs` has `SilodStartupServices`, the `StartupServices` adapter over `silo_engine::startup::install`: blocking check, update-recovery wait, export journal wait, image cache repair plus preparation worker, configuration recovery, macOS proxy bootstrap migration, lifecycle recovery, start-at-launch for macOS ids first (`macos_computers::start_at_launch`) then Linux (`runtime::start_at_launch`). `record_pass` is called by the engine, so `computers.launch` now reports `lastPass`. Failures become retained notices (A-27); no window means `show_integration_error` only logs.
   - The engine-update recovery in `services::start` now returns an `UpdateRecoveryOutcome` (settles even on a panic). The launch pass waits for it first (keeps the "update recovery before lifecycle recovery" order) and skips the pass when a saved set was resumed, as the Tauri flow did.
3. **Engine timers (A-26).** `silod/src/timers.rs`: one thread per pass, a start delay of 30 s, paused while shutting down or while the storage migration blocks operations, a panicking pass never ends its timer. Passes reuse the read-path functions and their guards: `secrets::schedule_revocations` (one at a time), new `network::repair_published_ports` and `macos_computers::repair_published_ports` (the one-pass flag and the 10 s floor per macOS computer), and new `runtime::expire_stopped_logs` (`plan_log_cleanup` and `clean_expired_logs`: hourly per stopped computer, hidden try-lock, a busy gate postpones to the next pass).
   - **Intervals (not sourced, OQ23):** revocations 60 s, ports 30 s, logs 10 min.
4. **Boot work** (`startup::prepare_stored_data`, `install_exports`, `start_background`, wired in `app.rs`): `vocabulary::run` before anything reads files; `pre_upgrade_backup::install`; `begin_proxy_bootstrap_migration`; exports controller installed inside the entered I/O runtime (a failure is logged and retried by the first caller); ChatGPT folder registration plus the status check and background download (with `computer_use` reconcile and `app_ready`, ported from the Tauri adapter); preparation worker via the launch pass.
   - **Launch migration:** new `runtime_migration::drive_pending` (engine) runs a pending "scanning" conversion once, publishes `migration.changed` on prepare, every step and the end, records a failure or panic as `failed`; silod then exits with the restart code after 250 ms. Engine tests: steps published, failure and panic recorded, settled state untouched.
   - `ready_hook` and `status_publisher` of `preparation.rs` are shared by `preparation.chatgpt.retry` and the boot worker; the retry now also sets up computer use on running computers when the app becomes ready (as Tauri did).
5. **`desktop.connect`** answers `permission_denied` for every request on `engine.sock`, before any lookup, and is not advertised. A peer engine gets guest credentials through the owner-side bridge (`desktop_connection`), which does not pass through the dispatcher.
6. **VM window.** The window table and main-thread runner stay in `display.rs`; `show_native_display` and `close_native_display` are now shared. The computers domain's `MacosHost` previously refused `show_display`, so a setup that needed the screen could not open it. It now delegates to the same functions. `app.rs`: the activation policy lives in `app::activation_policy` (used by the window table; the unused `WindowPolicy` duplicate was removed). New `app_delegate.rs`, installed in `run_appkit` before `application.run()`: no termination after the last window closes, no reopen handling, and `applicationShouldTerminate:` starts `services::session_end` once and replies `NSTerminateLater` (the shutdown stops the loop). Unit-tested: the policy mapping, the once-only termination gate. The AppKit objects themselves need a live run.

## Tests

- Added: 4 (capabilities and handshake), 3 (migration driver), 10 (startup adapter), 5 (timers), 1 (delegate gate), 1 (policy), `desktop.connect` refusal.
- Final gate on the merged tree: `cargo +1.94.0 fmt --all --check` clean; `cargo test --locked -p silo-engine -p silod -p silo-api --no-fail-fast`: silod 199+ unit, all socket tests pass; silo-engine passes except two tests that time out only under heavy machine load (load average 25 to 30 from other tracks) and pass alone: `dependencies::tests::version_probe_accepts_the_output_limit_and_rejects_overflow_on_either_stream` and `runtime::tests::structured_progress_is_drained_on_exit_and_ignores_untrusted_text`. `methods::access::tests::connections_health_is_a_side_effect_free_projection` failed once in a full run and passed on both reruns (access code, not touched).
- No sqlite fixtures committed (the stray `engine/engine/registry.sqlite3*` is ignored).

## Deviations and decisions

- **Quit semantics.** A Dock Quit, logout or shutdown request is treated like SIGTERM: session-end shutdown with no prompt. The engine has no UI to ask.
- **Launch migration job id.** The conversion is driven in the background with `migration.changed`; it does not allocate a `job:` id (05 §3 item 3 mentions one). Add it when Fjord needs job progress for it.
- `show_integration_error` has no window to use; only the retained notice and the log carry it.
- `start_at_launch` returns `Ok(false)` for a macOS computer cancelled before its turn, so the Linux path is then tried and fails with "not found" (existing engine behaviour, unchanged).

## Next tracks

- Not done (other tracks, per the backlog): core `operations.*` routing by `deviceId`, persisted `RemovalIntent`, owner event relay, device health timer (access); Tauri as a silod client; Fjord on `SocketEngineClient`.
- A live check is still needed for: the VM window with the delegate (Dock icon on open, back to accessory on close, Dock Quit routing), the launch pass starting real computers, and the timers over a real idle day.
