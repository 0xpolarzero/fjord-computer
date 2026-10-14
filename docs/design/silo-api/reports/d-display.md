# d-display

Silo worktree `~/silo-work/d-display`, branch `engine/d-display` from Silo `main@bd7c7c27` (the dispatch keystone). No push.

The track continued an agent that stopped partway with a large uncommitted diff. I reviewed that diff, fixed what was wrong, finished the missing pieces and committed it in atomic steps.

## Commits

| Hash | Message |
| --- | --- |
| `9492c141` | `style(silo): format engine and silod sources with rustfmt` |
| `52f7246c` | `feat(engine): hold desktop viewer connections per client` |
| `13e44a4f` | `feat(engine): macOS display close, computer-use approval and explicit clipboard` |
| `62b5bb06` | `feat(engine): link desktop actions to durable jobs` |
| `2df16335` | `feat(silod): serve the display, desktop, computer-use and clipboard methods` |

`9492c141` is formatting only. `HEAD` was not `rustfmt`-clean in `backup_controller.rs`, `jobs/registry.rs` and the `computers`, `checkpoints`, `services` and `mod` domain files, so `cargo fmt --all --check` could not pass without it. The other parallel tracks will hit the same lines. The coordinator can drop this commit and format once at merge.

## What was built

All 18 methods of the domain are dispatched by `silod/src/methods/display.rs`: `desktop.status|connect|action`, `computerUse.state|approval|setup`, `display.show|close`, `display.viewer.open|close|sound.check|sound.cancel|audio.set|screen.reset`, `clipboard.transfer|read|write` and `display.native.attach`. `display.viewer.page` is the catalogue event, delivered with `Audience::Client`.

- **Viewer connections (A-28, B-21).** `engine/src/desktop_viewer_api.rs` is a new registry keyed by connection id. It holds one entry per (client, owner device, computer), each with its own loopback proxy, tunnel, cookie and nonce inbox, so there is one Selkies WebSocket per client. Up to 16 entries, pending ones included. A healthy repeat open returns the same entry. An unhealthy one is replaced. A generation counter makes a late completion of a closed or replaced open discard its resources. Tunnels and proxies are dropped outside the registry lock.
- **Ownership.** Every connection-taking handler checks that the caller holds the connection before it touches any state keyed by the id. Without that check, another client could enlist or cancel a sound probe or create revision state for someone else's connection. This was a bug in the previous diff. Unknown and foreign ids both return `not_found`.
- **Cleanup.** `silod/src/socket.rs` closes a client's connections when its socket ends. The engine also closes them when a computer stops, is removed or restored, when a device is lost or removed (via the `EngineContext::close_remote_displays` hook), and on quit. Teardown runs off the async workers because a tunnel can take 500 ms to stop.
- **`display.viewer.page`.** The `Page::eval` adapter publishes `{connectionId, script}` to the owning client only. The socket test shows it: sound check and screen reset round-trip through the real proxy route.
- **`display.show` and `display.close` on macOS.** An engine-owned `NSWindow` goes through the main-thread runner. The app switches to regular activation while any VM window is open and back to accessory when the last closes (A-21). `display.close` is idempotent and is refused with `busy` while the computer is setting up. Two bugs in the previous diff are fixed: the window delegate was dropped inside its own `windowWillClose:` callback, and `releasedWhenClosed` was left on, which over-releases the window.
- **`computerUse.approval` for macOS (new).**
  - A new `computer_use_desired_approval` field on the record is kept apart from the applied one.
  - `computer_use_stale()` and the updater read the desired mode.
  - Forks inherit the desired mode.
  - A running computer is updated at once through `update_in_background`, which uses the update queue and coalesces a change made mid-update. A stopped computer applies it at its next Start.
  - `computerUse.state` for macOS projects from the record: `approval`, `appliedApproval` and `approvalApply`, with `pending` while stale or while an update runs. The receipt fields stay null.
- **`desktop.action` and `computerUse.setup` as jobs.** `desktop::local_for_job` and `desktop::JobLink` put the gate entry under the job id. The queue shows it and `operations.cancel` reaches it while it waits or runs. The previous diff registered a cancel handler that could never find the entry.
- **macOS `clipboard.read` and `clipboard.write`.** They use explicit payloads over the existing guest clipboard path. Writes now enforce the 1 MiB text and 16 MiB PNG limits and check the PNG signature.
- **`desktop.status` on macOS.** It uses a new light single-computer read. The previous diff used `read_macos_computers`, which starts a background fetch of Apple's latest restore image on every call.
- **Error mapping.** One text-to-code table covers cancelled, already-queued, not-found, OpenSSH-missing, not-running, timed-out and busy.

## Tests

- **Unit, one per handler** (19, `methods::display::tests`): they use `install_test_computer`, a new `test-support` helper that seeds the shared macOS inventory.
- **Engine** (10 new): the viewer registry (per-client claim, ownership, generation, cap, device/computer/client close) and macOS approval, state and display close.
- **Socket-level integration** (`silod/tests/display.rs`): two clients on a real `engine.sock`. It covers:
  - separate proxies and cookies;
  - the sound-check and screen-reset page round trip, answered over HTTP on `/__silo/v1/...`;
  - `not_found` for a foreign close or foreign audio;
  - one client disconnecting closes only its own viewer;
  - close once, then `not_found`.
- **Gate:** `cargo +1.94.0 fmt --all --check` passed. `cargo test --workspace --locked --no-fail-fast` passed on the final tree: 2335 engine tests, 71, 60 and 27 in the other crates, plus both silod integration tests; 0 failed. Logs are in `~/silo-work/d-display/target/verification/d-display-cargo-test-3.log`.
- **Flaky tests, unrelated to this track.** Two earlier full runs each failed on tests of other domains: `backup_controller::install_schedules_pending_import_recovery_outside_tokio_runtime` and two `transfer::` tests. Different tests failed each time and they passed when rerun, so they are timing-flaky under full-suite load. Suite-level flakiness is worth knowing for the merge gate.
- No app or VM was started. The test viewers are a loopback proxy and a `sleep` process. Test builds leave an untracked `engine/engine/registry.sqlite3`; I removed it, as the keystone report also noted.

## Deviations and decisions

- **`desktop.connect` is callable by any local client.** The spec says it is engine-to-engine only and a client never receives guest credentials. `silod` has no remote-peer transport or peer identity yet, so the handler cannot tell a peer engine from a local client. P3-connections should gate it to the peer session. The same-user peer-euid rule (A-5) already bounds the exposure.
- **No macOS adapter for `display.viewer.open`, `desktop.action|connect` or `computerUse.setup`.** The spec marks them NEW and unqualified (B-31, 40 macOS addition). They return `unsupported_remote_operation` with an explicit message. macOS shows its screen through `display.show`; `desktop.status` and `computerUse.*` read and set state. `display.native.attach` is also `unsupported_remote_operation` (spec: "later").
- **Remote macOS `display.show`, `display.close`, `clipboard.*` and `clipboard.write`.** All return `unsupported_remote_operation`: the Screen Sharing gateway (A-20) belongs to P3-macos-parity, and `clipboard.*` has no remote bridge name yet. Remote Linux methods (`desktop.*`, `computerUse.*`, `display.viewer.open`) go through the existing `remote::call_remote` routing, which P3-connections will replace.
- **Guest-side Selkies admission is not part of this track.** The engine opens a separate connection per client, as specified, but the pinned streamer still terminates the previous primary peer (B-21 REFUTED; P3-viewers owns the upstream patch). Do not advertise independent viewers until that qualification passes.
- **macOS `clipboard.transfer` and approval do not join the operation queue.** The approval is a quick record change plus the existing updater. Both stay as they were.
- `Cargo.toml` of `silod`: more `objc2-app-kit` features for the window, and `silo-engine` with `test-support` as a dev-dependency.
- `silo-api` is unchanged, so no schema regeneration was needed.

## For the next tracks

- Other domain modules can use `silo_engine::desktop_viewer_api::close_*` on lifecycle events. `ensure_owned` is the check for anything keyed by a connection id.
- Fjord's viewer client must subscribe to `display.viewer.page` before it calls `sound.check`, `audio.set` or `screen.reset`, and evaluate each script in the guest page's main frame. A client that does not evaluate it gets "The computer did not answer."
- The real AppKit window path (`display.show`, Dock activation) is built and type-checked but not exercised. It needs a live check with a signed build on a running macOS VM, when the owner asks for one.
