# Engine extraction: parallel tracks and conventions

P1-engine's first run moved only `channel`, the operation gate and the image cache (branch `engine/p1-engine`, through commit `238b67d3`). To go faster, the rest of the extraction runs as parallel tracks. Each **removes Tauri from its own modules in place, inside the `silo-ui` crate**. A final integration track then moves the Tauri-free modules into the `silo-engine` crate. Tracks edit disjoint files, so they can run at the same time.

## Tracks (each a worktree off `engine/p1-engine` at `238b67d3`)

| Track | Modules it owns (under `app/SiloUI/src-tauri/src/`) |
| --- | --- |
| E1-runtime | `runtime.rs` and `runtime/*` except `runtime/checkpoints*`, plus `runtime_logs.rs`, `runtime_activity.rs`, `guest_image*`, `startup.rs`, `health_watch.rs`, `storage*`, `log_export.rs`, `working_account*`, `computer_names.rs`, `creation_inputs.rs` |
| E2-checkpoints | `runtime/checkpoints.rs`, `runtime/checkpoints/*`, `backup*.rs`, `backup_controller*`, `pre_upgrade_backup*`, `runtime_migration*`, `vocabulary*` |
| E3-macos | `macos_computers.rs`, `macos_computers/*`, `macos_remote*.rs`, `macos_display_gateway.rs` |
| E4-access | `github*.rs`, `secrets*.rs`, `host_push*.rs`, `remote.rs`, `remote/*`, `remote_access.rs`, `remote_network.rs`, `remote_ssh_access.rs`, `ssh_access.rs`, `ssh_connection.rs`, `owned_tunnel.rs`, `editor.rs`, `terminal.rs`, `files*.rs`, `transfer*.rs`, `network*.rs` |
| E5-services | `desktop*.rs`, `computer_use*`, `chatgpt_app*`, `preparation*`, `notifications*`, `settings*`, `system_integrations*`, `system_shutdown*`, `updates*`, `dependencies*`, `applications*`, `bundled_tools*`, `clipboard*`, and any backend module not listed above. Before editing an unlisted module, check that no other track owns it. |

A track never edits another track's modules. If it needs a change in another track's module (a signature, a context access), it records the need in its report under "Cross-track needs" and works around it with the smallest possible adapter inside its own modules.

## Conventions

1. **Context.** Engine logic gets host capabilities from `silo_engine::context::current()` (an `Option<Arc<dyn EngineContext>>`): paths (`EnginePaths`), identity, `publish(Event, Audience)`, `main_thread()`, `process()`. Thread `&dyn EngineContext` or an `Arc` through functions where that's cleaner than the global. Tests construct a test context. Don't add new methods to `EngineContext` on your own: list what's missing under "Cross-track needs", and meanwhile use a local adapter.
2. **Managed state.** Replace `app.state::<T>()` / `app.manage()` for engine-owned state with engine-owned statics (`OnceLock`/`LazyLock`, initialised at engine start) in the owning module. UI-only state (windows, tray, menus) stays managed by Tauri.
3. **Events.** Replace `app.emit*` with `context.publish(Event::new(name, payload), audience)`, keeping today's event names and payloads; canonical renaming comes later. Window-targeted emits use `Audience::All` with a `// window:<label>` comment, unless a client id is available.
4. **Commands.** Every `#[tauri::command]` in your modules moves to `src/commands/<track-domain>.rs`. Each is a thin wrapper: Tauri arguments, window checks such as `require_main`, then a call to the engine function and a mapped result. Engine functions take plain arguments (paths, ids, values), never `AppHandle`, `Window` or `WebviewWindow`. Keep command names and registration unchanged in `main.rs`; only the paths change. Touching `main.rs` registration lines is allowed: the integration track resolves conflicts.
5. **Client-only.** Dialogs, the opener, windows, the tray, menus, the updater plugin and the theme stay in `silo-ui` (`src/commands/*` or the existing UI modules). Engine functions receive the user's choice (a path, a confirmation) as a parameter.
6. **Async and threads.** Use `tokio`, not `tauri::async_runtime`. VZ and AppKit work goes through `context.main_thread()`. For E3: add an engine-side hook that attaches a VM view to a host-provided `NSWindow` (raw pointer or objc2 type), so the Tauri app and later `silod` can host the VM window.
7. **No behaviour change.** No renames, no new features, existing tests unchanged in meaning; move tests with their code. Run `cargo test` filtered to your modules after each step, and the full `cargo test --locked` plus `cargo +1.94.0 fmt --check` before your final commit.
8. **Done means** none of your modules (outside `src/commands/`) reference `tauri::`, `AppHandle`, `WebviewWindow`, `Manager` or `Emitter` (check with `rg`), all tests pass, and the report lists any remaining exceptions with the reason.
9. **Commits:** conventional (`refactor(engine): …`), one per module group. Never push.
