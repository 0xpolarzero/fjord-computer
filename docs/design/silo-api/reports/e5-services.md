# E5-services implementation report

**Status: partial.** Worktree: `/Users/polarzero/silo-work/e5-services`, branch `engine/e5-services`, clean at `af0a78e2`. The completed E5 modules have no direct Tauri references outside `src/commands/`. Five owned root modules remain coupled: `desktop.rs`, `desktop_viewer.rs`, `chatgpt_app.rs`, `settings.rs`, and `updates.rs`.

## Done

- `bundled_tools.rs`: package classification and path selection are plain Rust. `commands/bundled_tools.rs` owns Tauri bundle/path lookup; a compatibility re-export remains for E1/E4 callers.
- `dependencies.rs`: probe execution and validation are plain Rust. `commands/dependencies.rs` resolves host paths and runs the blocking probe.
- `preparation.rs`: uses `EngineContext` for paths and progress events. `commands/preparation.rs` owns command and startup adapters; `start` remains a compatibility re-export for E1 startup.
- `computer_use.rs`: state-change events publish through `EngineContext`; lifecycle adapters are in `commands/computer_use.rs`.
- `system_integrations.rs` and its macOS module: IPC wrappers, dialogs, and the macOS notification delegate are in `commands/system_integrations*.rs`.
- `desktop_bridge.rs`: the Tauri `Webview` implementation of `Page` is in `commands/desktop_bridge.rs`.
- `desktop_viewer_bench.rs`: the development benchmark is in `commands/desktop_viewer_bench.rs`; its `start` re-export preserves setup wiring.
- `viewer_clipboard.rs`: transfer policy and reporting are Tauri-free; window command, event delivery, and shortcut worker are in `commands/viewer_clipboard.rs`.
- `viewer_shortcuts.rs`: shortcut classification and policy are Tauri-free; native macOS/GTK hooks are in `commands/viewer_shortcuts.rs`.
- `desktop_viewer_media.rs`: probe/audio policy is Tauri-free; four command wrappers are in `commands/desktop_viewer_media.rs`.
- `notifications.rs`: notice policy and delivery tracking are Tauri-free; delivery, focus checks, and command adapters are in `commands/notifications.rs`. Compatibility re-exports remain for current callers.
- `system_shutdown.rs`: shutdown routing and budgets are Tauri-free; AppKit and logind hooks are under `commands/system_shutdown/`. `exit` and `cancel` compatibility re-exports remain for settings.
- `applications.rs` and its platform modules: selection policy and platform discovery are Tauri-free; settings access, dialogs, window checks, command wrappers, and Linux icon dispatch are in `commands/applications.rs`. Compatibility re-exports preserve current E4 helper signatures. The macOS PNG test now uses the `image` crate rather than Tauri's decoder.
- `clipboard.rs` was already Tauri-free.

No `EngineContext` methods were added. Existing event names, payloads, command names, validation rules, and delivery targets were preserved. Window-targeted events use the documented audience mapping and retain comments identifying the previous window target.

## Commits

- `49dd7e394cd46f59bb109df7a29c01e843ebd9e8` `refactor(engine): isolate bundled tool package detection`
- `ad272ce2735c90ec7e270751ccfd7938bec845c6` `refactor(engine): isolate dependency probes from Tauri`
- `a956b2e087d2641d4b5ad27b52379d4587ce1f2e` `refactor(engine): route preparation through host context`
- `e7dd8f33b5c25cfaab02d0a6a729aceec6c8da5c` `refactor(engine): publish computer use events through context`
- `eb5bdbf823fe164a46da0eb9da4263ef624de2fe` `refactor(engine): isolate system integration commands`
- `c25a8f4b49cabc5f6aab209e583276f5ff6a46ee` `refactor(engine): isolate desktop webview adapter`
- `d30531da79f3babea671543fadaf3535be99c21b` `refactor(engine): move desktop benchmark into host adapter`
- `2185af6e2d808b5db19183576c22e6e34f5032e9` `fix(engine): normalize dependency probe paths`
- `cc162c11b82ec0bd1d03a855873f3c1e6584e0a1` `refactor(engine): isolate viewer clipboard adapter`
- `8a26bcc230cbc98ec8776a712d35a6b2e84136a1` `refactor(engine): isolate viewer shortcut adapters`
- `50f43c4069f799c5533e9a3cc4e3a42d6d78c7a8` `refactor(engine): isolate desktop viewer media commands`
- `6418be04fd785014546bbd640038490c6a58b3d0` `refactor(engine): isolate notification delivery adapters`
- `cb4710569bf8ec231e68aaff9f962ee5e1004efa` `refactor(engine): isolate shutdown host adapters`
- `af0a78e212aae2136ccb249ae41aed0339d4c15c` `refactor(engine): isolate application host adapters`

## Verification

Filtered tests passed after the corresponding module groups:

- `bundled_tools::tests`: 3 passed.
- `dependencies::tests`: 31 passed, including after the Linux path normalization fix.
- `preparation::`: 21 passed.
- `computer_use::tests`: 100 passed, including matching `macos_computers::guest_computer_use` tests.
- `system_integrations::tests`: 5 passed.
- `desktop_bridge::`: 24 passed.
- `commands::desktop_viewer_bench::tests`: 1 passed.
- `viewer_clipboard::tests`: 16 passed.
- `viewer_shortcuts::tests`: 5 passed.
- `desktop_viewer_media::tests`: 17 passed.
- `notifications::tests`: 21 passed.
- `system_shutdown`: 5 passed.
- `applications::`: 43 passed.

Final checks ran with `CARGO_TARGET_DIR=/Users/polarzero/silo-work/e5-services/target`, `CARGO_BUILD_JOBS=4`, and the synthetic GitHub values permitted by `docs/SiloUI-RELEASES.md`:

- `cargo test --manifest-path app/SiloUI/src-tauri/Cargo.toml --locked`: passed; `silo-ui` 2,229 passed and 30 ignored; `silo-engine` 60 passed; doc tests passed.
- `cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --check`: passed.

One earlier full parallel run had two transient failures in unrelated E2/E4 tests: `backup::tests::cancel_asks_the_runtime_to_stop_before_killing_it` and `remote_network::tests::delayed_authentication_waits_for_a_successful_control_reply`. Each passed when rerun alone, and a subsequent full run passed without either failure. The captured failure block is in the ignored `app/SiloUI/src-tauri/target/verification/e5-full-test-failures.txt` file.

The run used fixtures and unit-test helpers. No app, VM, live computer, or real user data was used. Existing warnings remain in unrelated remote, runtime migration, macOS FFI, bundled tools, and the desktop proxy example.

A Linux cross-check was attempted with Rust 1.94.0 after the dependency path change. That toolchain lacks the Linux target in this environment. The stable toolchain has an AArch64 Linux target, but GTK/glib build scripts stop because the cross sysroot is unavailable. This leaves Linux cross-compilation unverified here; the focused dependency tests and current native full suite pass.

## Remaining Tauri references in E5 modules

The audit searched the E5 module globs outside `src/commands/`. Only these five root modules still match `tauri::`, `AppHandle`, `WebviewWindow`, `Manager`, or `Emitter`:

| Module | Remaining references | Reason |
| --- | --- | --- |
| `desktop.rs` | Import at 6; app/event parameters at 361, 670, 740, 832, 963; commands at 882, 941, 950; Tauri window arguments at 884–885 and 943–944; async dispatch at 890 and 911; app argument at 907 and 952–953. | Dispatch still threads `AppHandle` through backend calls and emits events. Move the engine dispatch and event publication to plain inputs plus `EngineContext`; leave window checks and command wrappers in `commands/desktop.rs`. |
| `desktop_viewer.rs` | Tauri imports at 19–21; app parameters at 176, 255, 318, 474, 546, 695; commands at 316, 544, 694; async work at 325, 571, 696; webview/window APIs at 357, 382, 397, 413, 416, 538, 541, 603, 631, 635, 646, 657, 662. | Window creation, cookies, bounds, focus/drag events, page-load events, and viewer lifecycle remain in the domain module. Move these host operations into `commands/desktop_viewer.rs` and retain plain viewer/proxy policy in the root module. |
| `chatgpt_app.rs` | Storage path and Tauri manager at 1928–1929; event emission and app-handle flow at 1982–2274; app-handle owner call at 2252; commands and app arguments at 2317–2336. | Storage paths, status publication, background task scheduling, and commands still share one module. Extract path/context inputs and host scheduling/publication while retaining the download, verification, and garbage-collection policy in the engine module. |
| `settings.rs` | Tauri imports/theme at 11 and 29–32; restart/path/command/event code at 679–832; shutdown, window handshake, and commands at 852–1209; Tauri theme tests at 1247–1272; Tauri test helpers at 1593–1596; restart-code tests at 2233–2237; update flush at 2263. | Persistent settings state and shutdown policy remain coupled to Tauri paths, theme, events, window confirmation, and exit APIs. Split engine state/process control from UI theme/window adapters; move Tauri test helpers with the adapters. |
| `updates.rs` | Tauri imports at 16; bundle types at 141–155 and 261; app state/events/background loop at 163–283; commands and app parameters at 292–870; AppHandle browser launch at 871; Tauri bundle test at 1368. | Update policy and state remain coupled to the updater plugin, bundle detection, settings/shutdown flow, Tauri task scheduling, and command wrappers. Keep the updater plugin in commands and move state/policy behind plain engine inputs and context publication. |

All other audited E5 root modules are Tauri-free outside `src/commands/`. Some compatibility re-exports intentionally route legacy callers through command adapters until their owning tracks migrate.

## Cross-track needs

- **E1-runtime path APIs:** provide path-based or `EngineContext` entry points for `runtime_paths`, `update_recovery::running_names`, and `bundled_runtime_library`; current adapters still call AppHandle-based APIs. E1 should call `preparation::start_with_paths` from `startup.rs` and replace startup error dialogs with notice events or client presentation.
- **E1/E4/E2 notification callers:** `startup.rs`, `runtime.rs`, `editor.rs`, `remote.rs`, and `backup_controller.rs` still use AppHandle-shaped compatibility exports for `notify`, `notify_native`, or `clear_computer`. Migrate those callers to context notice publication/client presentation, then remove the re-exports.
- **E1 startup integration errors:** `system_integrations::show_integration_error` remains a compatibility adapter for startup and settings. Move startup/settings failure display to the agreed notice event or a client-side dialog adapter before removing it.
- **E4 host-push:** `host_push.rs` still calls `bundled_tools::directory(&app)`. When E4 adopts `EngineContext`, use the package/path seam and remove the compatibility export.
- **E4 application callers:** `github.rs`, `network.rs`, `remote.rs`, `remote_network.rs`, `editor.rs`, and `terminal.rs` still call AppHandle-shaped application helpers. `commands/applications.rs` keeps these compiling; E4 should migrate to plain selection values and launch policy when those callers are extracted.
- **Settings and shutdown:** `system_shutdown::{exit,cancel}` compatibility exports are still used by E5 settings. Remove them when settings lifecycle adapters move to `commands/settings.rs`.
