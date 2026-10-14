**Do not merge `bea1396f` as written.** The extraction changes behavior and breaks supported Linux builds.

Reviewed `7a0591f9` (`main`) → `bea1396f` with `git diff -M`, including the reports and conventions. Later silod changes were excluded. All paths below are relative to `app/SiloUI/src-tauri/`; old references identify the `main` version.

1. **P1: Queued remote checkpoint operations lose their admission condition.**  
   **Old:** `src/runtime/checkpoints.rs:785,1784,2190` uses `operation_gate::spawn_blocking`, which propagates `StartCondition`.  
   **New:** [commands/runtime_checkpoints.rs:53](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/src/commands/runtime_checkpoints.rs:53), lines 74 and 101, use raw Tokio spawning. A queued capture, fork, or restore can consequently start after its deadline, disconnection, or access revocation.  
   **Fix:** restore the condition-propagating helper for checkpoint mutations; regress expiration before gate admission.

2. **P1: Interrupted export/import recovery can panic during startup.**  
   **Old:** `src/backup_controller/recovery.rs:928` uses Tauri’s global executor.  
   **New:** [engine/src/backup_controller/recovery.rs:926](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/engine/src/backup_controller/recovery.rs:926) calls `tokio::task::spawn_blocking` from synchronous app setup through `commands/backup_controller.rs:16`. That thread has no entered Tokio runtime. A nonterminal recovery journal therefore prevents startup.  
   **Fix:** supply an explicit runtime handle or schedule recovery through the host adapter. Test installation with an unfinished journal outside Tokio.

3. **P1: Supported Linux builds have multiple compile blockers.**  
   The macOS verification does not exercise these platform branches.

   | Old | New | Required fix |
   |---|---|---|
   | `src/macos_computers/engine.rs:1460`, platform-gated | [commands/macos_computers.rs:46](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/src/commands/macos_computers.rs:46) calls macOS-only `ns_window()` unconditionally | Gate native display handling and retain the unsupported-platform implementation |
   | `src/dependencies.rs:893`, old bundle-type signature | [commands/dependencies.rs:28](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/src/commands/dependencies.rs:28) passes `Option<BundleType>` where `RuntimePackageKind` is required | Convert through the existing package-kind adapter |
   | `src/dependencies.rs:226`, same-crate construction | `commands/dependencies.rs:39` constructs the now-private [engine field:234](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/engine/src/dependencies.rs:234) | Expose a constructor or the necessary field |
   | `src/applications.rs:209,270`, same-crate helpers | `commands/applications.rs:48,99` calls engine helpers still `pub(crate)` at [applications.rs:233](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/engine/src/applications.rs:233) and 238 | Expose the host-facing functions |
   | `src/runtime.rs:12192`, optional argument | [engine/src/runtime/mod.rs:12211](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/engine/src/runtime/mod.rs:12211) passes `Some(RuntimePackageKind::Deb)` | Pass `RuntimePackageKind::Deb` directly |

4. **P1: Native window lookup moved off the AppKit main thread.**  
   **Old:** `src/macos_computers/engine.rs:1456–1464` resolves `ns_window()` inside `on_main`.  
   **New:** [commands/macos_computers.rs:45](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/src/commands/macos_computers.rs:45) resolves it on the blocking worker before attachment. Tauri’s implementation calls `NSView::window()`. The raw pointer also crosses the scheduling boundary before unsafe dereferencing.  
   **Fix:** resolve and attach the native window together on the main thread, checking its continued existence and ownership there.

5. **P2: Failed checkpoint mutations stop publishing state-change events.**  
   **Old:** `src/runtime/checkpoints.rs:804,1797,2208,2493,2768` emits after computing the mutation/refresh result, including failures.  
   **New:** [commands/runtime_checkpoints.rs:55](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/src/commands/runtime_checkpoints.rs:55), lines 83, 103, 122 and 142, return through `?` before publication. `refreshed_state:39` also skips publication when response refresh fails. Failures can persist recovery state that subscribers now miss. The local caller’s error handler refreshes explicitly, so this does not imply every local view remains stale.  
   **Fix:** compute the result, publish after the same original prerequisites, then return it. Cover mutation and refresh failures.

6. **P2: Main-window progress events are now broadcast.**  
   **Old:** `src/runtime.rs:3586,4181,4183`, `src/runtime/configuration_recovery.rs:632`, and `src/preparation.rs:233` target `"main"`.  
   **New:** [engine/src/runtime/mod.rs:3619](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/engine/src/runtime/mod.rs:3619), lines 4211 and 4218, [configuration_recovery.rs:647](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/engine/src/runtime/configuration_recovery.rs:647), and [preparation.rs:234](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/engine/src/preparation.rs:234) publish to `Audience::All`. Other windows receive computer names, progress and diagnostics previously confined to main.  
   **Fix:** use `Audience::Client(ClientId::new("main"))`. The convention permitting broadcasts contradicts the no-behavior-change requirement.

7. **P2: Linux migration now blocks unrelated remote macOS and ChatGPT operations.**  
   **Old:** `src/remote.rs:2217` dispatches macOS directly; `src/remote_access.rs:43–46` handles ChatGPT status/retry without Linux paths.  
   **New:** [engine/src/remote.rs:2210](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/engine/src/remote.rs:2210) resolves migration-gated Linux paths before dispatching either domain. Pending or failed Linux migration therefore disables these previously independent operations.  
   **Fix:** resolve Linux paths only inside handlers that require them. Regress independent handlers with a failing path resolver.

8. **P2: App-owned settings and startup state became permanent process state.**  
   **Old:** `src/settings.rs:703–706` and `src/startup.rs:153–154` create fresh state per app.  
   **New:** [engine/src/settings.rs:708](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/engine/src/settings.rs:708) and [startup.rs:18](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/engine/src/startup.rs:18) use permanent singletons. Initializing settings for a second instance/path returns the first store; shutdown approval and startup cancellation also survive subsequent installations.  
   **Fix:** own this state per engine instance and pass it through the adapters. Test two independent instances and storage paths.

9. **P2: Concurrent settings invokes can apply an obsolete native theme.**  
   **Old:** `src/settings.rs:768–771` holds the settings mutex through theme application and publication.  
   **New:** [engine/src/settings.rs:773](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/engine/src/settings.rs:773) releases it before [commands/settings.rs:80](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/src/commands/settings.rs:80) awaits and publishes. Concurrent invokes can apply revision 2, then revision 1, leaving native appearance inconsistent with persisted settings. Ordinary frontend writes are serialized; concurrent native invokes are the trigger.  
   **Fix:** serialize mutation and publication, or reject stale revisions under a guard covering both theme application and emission.

10. **P3: Remote computer approval loses its `"ask"` failure fallback.**  
    **Old:** `src/remote.rs:1703–1710` defaults the `Approval` enum before serialization.  
    **New:** [commands/remote.rs:241](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/src/commands/remote.rs:241) defaults a string to `""` on settings or worker failure. The owner rejects it and retains its own approval mode, potentially `auto`. This concerns exceptional failures such as poisoned state, not ordinary unreadable settings files.  
    **Fix:** preserve `Approval::Ask` through both fallbacks, then serialize.

11. **P3: Crate metadata now exposes the engine version instead of Silo’s version.**  
    **Old:** `src/remote.rs:573` and `src/chatgpt_app.rs:768` use the UI crate version.  
    **New:** [engine/src/remote.rs:586](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/engine/src/remote.rs:586) and [chatgpt_app.rs:767](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/engine/src/chatgpt_app.rs:767) expand `CARGO_PKG_VERSION` to `0.1.0`, changing error metadata and the download user agent.  
    **Fix:** obtain the application version from host identity.

12. **P3: Launcher failure errors changed.**  
    **Old:** `src/runtime.rs:3275` returns `"The application launcher failed."` for editor/terminal worker failure.  
    **New:** [commands/runtime.rs:227](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/src/commands/runtime.rs:227) maps every worker failure through `internal_failure("running the computer action")`.  
    **Fix:** retain the launcher-specific error mapping.

13. **P3: Existing tests were weakened.**  
    **Old → new:** settings emission/privacy coverage at `src/settings.rs:1592` became a helper-only assertion at [engine/src/settings.rs:1287](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/engine/src/settings.rs:1287). Update tests also lost failed-save publication assertions (`1141` → `666`), repair-save memory bounds (`1234` → `739`), and unknown-space/rounding cases (`1385` → [857](/Users/polarzero/silo-work/integration/app/SiloUI/src-tauri/engine/src/updates.rs:857)).  
    **Fix:** restore those assertions at the actual engine or host-adapter boundary.

No dropped command registrations were found: **159 names remain**. No lost main-window checks were found in the reviewed adapters; viewer clipboard and drag/drop targets remain client-specific.

This was a read-only source review. I did not run builds, tests or native apps. **Merge is safe only after these fixes, focused regression tests, and macOS/Linux build and workspace-test gates pass. Re-review the fixed commit before merging.**