# Engine integration review fixes

Branch: `engine/integration`, based on `6e32feab` (includes the silod merge). No commits were pushed.

## Findings and regressions

| Finding | Commit | Fix and focused regression test |
|---|---|---|
| 1. Queued remote checkpoint admission | `a29b4e2b` `fix(engine): preserve remote checkpoint admission conditions` | Restored propagation of the remote start condition through queued checkpoint mutations. `queued_remote_checkpoint_expires_before_gate_admission` verifies an expired request is rejected before gate admission. |
| 2. Startup import/export recovery | `a05fdc31` `fix(engine): schedule startup recovery on host runtime` | Startup recovery is scheduled through the host runtime. `install_schedules_pending_import_recovery_outside_tokio_runtime` installs a pending recovery journal without an entered Tokio runtime. |
| 3. Linux host compile blockers | `be300f4f` `build(ci): drop Linux host builds` | Per [95-decisions.md §3](../95-decisions.md), Linux hosts are discontinued. The repo now states that hosts are macOS-only, and Linux host build, package, and release CI paths were removed. Linux guest computers on Mac hosts remain supported; no Linux guest code was changed. Workflow and release-script checks passed (491 tests passed, 16 skipped; 53 focused tests passed), along with YAML parsing and `git diff --check`. Linux host builds are intentionally not a supported gate. |
| 4. Native window thread/race | `6f000344` `fix(engine): validate native display windows on AppKit thread` | Resolve and validate the current owned native window on AppKit immediately before attachment. `display_attachment_rejects_a_closed_or_replaced_window` covers closed and replaced windows. |
| 5. Checkpoint failure events | `2b934263` `fix(engine): publish checkpoint state after failed operations` | Publish refreshed checkpoint state before returning mutation or refresh errors. `failed_checkpoint_mutation_still_publishes_after_refresh` and `failed_checkpoint_refresh_still_publishes_after_mutation` cover both failure boundaries. |
| 6. Main-window event audiences | `8f5cf192` `fix(engine): restore extracted host behavior` | Progress events target `Audience::Client(ClientId::new("main"))`; the Tauri adapter maps that audience only to the main window. `main_window_progress_uses_the_main_client_audience` and `main_client_events_are_sent_only_to_the_main_window` cover the engine audience and host routing. |
| 7. Independent remote handlers | `875a0ee4` `fix(engine): defer Linux path resolution for independent remote handlers` | Defer migration-gated Linux path resolution until a handler requires it. `linux_path_resolution_does_not_block_macos_or_chatgpt_handlers` uses a failing resolver and verifies the macOS and ChatGPT handlers still dispatch. |
| 8. Settings/startup state lifetime | `3a5ef85f` `fix(engine): scope settings state and restore update guarantees` | Move settings, shutdown, quit-confirmation, and startup state into each engine context. `settings_shutdown_and_startup_state_belong_to_their_engine_instance` verifies independent engine instances own independent state. |
| 9. Native theme ordering | `3a5ef85f` `fix(engine): scope settings state and restore update guarantees` | Serialize a settings mutation through native theme application and event publication. `overlapping_settings_invokes_cannot_apply_an_obsolete_native_theme` exercises overlapping invokes and confirms the final native theme matches the latest revision. |
| 10. Remote approval fallback | `8f5cf192` `fix(engine): restore extracted host behavior` | Keep the typed `Approval::Ask` fallback through settings and worker errors before serialization. `both_remote_approval_failure_fallbacks_serialize_ask` covers both failure paths. |
| 11. Silo version metadata | `8f5cf192` `fix(engine): restore extracted host behavior` | Supply the host Silo version for engine metadata and the ChatGPT download user agent. `the_responder_reply_carries_its_versions` and `chatgpt_download_advertises_the_host_silo_version` verify both outputs. |
| 12. Launcher failure text | `8f5cf192` `fix(engine): restore extracted host behavior` | Preserve the launcher-specific error mapping for worker failures. `launcher_worker_failure_keeps_the_launcher_error` verifies the returned text. |
| 13. Restored assertions at behavior boundaries | `3a5ef85f` `fix(engine): scope settings state and restore update guarantees` | Restore settings event/privacy, failed preference-save, memory-bound, free-space rounding, and unknown-space assertions at the engine or host-adapter boundary. Coverage is in `settings_event_publishes_revision_and_settings_without_onboarding_draft`, `failed_preference_save_preserves_snapshot_and_does_not_publish`, `preferences_large_input_memory_is_bounded`, and `preflight_rejects_insufficient_or_unknown_space_without_touching_installation`. |

Whole-workspace formatting is isolated in `993cef4a` `style(engine): format the full Rust workspace`.

## Verification

- `cargo test --manifest-path app/SiloUI/Cargo.toml --workspace --locked` — passed on the final full run: API 27, engine 2,235 passed / 30 ignored, Silo UI 68, silod 30, handshake 1, and doc tests. The test run used the documented synthetic GitHub App configuration, `CARGO_TARGET_DIR=/Users/polarzero/silo-work/integration/target`, and `CARGO_BUILD_JOBS=8`. No live app or VM was started.
- `cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --all --check` — passed.
- `npm --prefix app/SiloUI run typecheck` — passed.
- `npm --prefix app/SiloUI run lint` — passed with six lint warnings.
- `npm --prefix app/SiloUI test` — passed: 266 files, 2,764 tests.
- A prior full Cargo attempt had one `silod` socket test failure (`engine.sock has a live listener`). The isolated test and subsequent full workspace run passed. The first failure excerpt is retained in ignored `target/verification/cargo-workspace-first-failure.txt`.

## Deviations and handoff

Finding 3 follows the owner decision that hosts are Macs only, which supersedes the earlier Linux-host requirement. Linux guests on Mac hosts remain supported. No Linux host build is claimed or required. The Silo integration working tree is clean, and all implementation changes are committed locally. This report is written in the Lookout repo and remains uncommitted; do not merge without the usual re-review.
