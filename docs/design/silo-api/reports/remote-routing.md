# remote-routing: remote jobs, owner events, device health

Silo worktree `~/silo-work/followups-a`, branch `engine/remote-routing`, cut from `main@680a5251`; `main` moved once (`7662ba22`) and was merged. Fast-forwarded into Silo `main` at `efd2877e`. Never pushed.

## Commits

| Hash | What |
| --- | --- |
| `7f77e999` | `operations.*` route by `deviceId`; `mirror_owner_connect` deleted; remote `github.connect` returns the owner's job id |
| `eef153bb` | engine: device-tagged events, device-aware bus subscriptions, the Stream-class `events.subscribe` owner side (`remote_events.rs`) |
| `4b764795` | silod: controller-side relay (`relay.rs`), `events.subscribe` `deviceIds`, framing with the owner's device id |
| `760896be` | device health timer (`remote::probe_devices`, fourth engine timer) |
| `8a1aa7d9` | `desktop.action` / `computerUse.setup` on another device become the owner's job (new bridge method `desktop.job`) |
| `ea951495` | `guest.exec.start` / `guest.exec.get` on another device become the owner's job |
| `874a7e66` | socket test, changeset `remote-jobs-events-and-health.md` |

## What was built

1. **Core `operations.*` routing.** New `silod/src/methods/operations.rs` owns `operations.list`, `.job.get`, `.job.acknowledge` and `.cancel` (the dispatcher arms are gone). A `deviceId` that is absent or this engine's own reads the local registry; another id is relayed through `call_owner` to the owner's bridge (`operations.job.get | cancel | job.acknowledge`, plus a new read-class `operations.list`). Replies are checked against `JobLookupResult` and `OperationQueue`; the owner's error codes (`not_found`, `busy`) survive. The owner's acknowledge now also calls `guest::forget_finished`, as the local one does.
   - `mirror_owner_connect`, its job allocation, cancel route and the `MIRROR_JOBS` test hook are deleted. A remote `github.connect` returns the owner's `jobId`; the controller keeps the callback route and a small watcher (`watch_owner_connect`) that closes it when the owner's job ends, and acknowledges nothing (the client acknowledges by `(deviceId, jobId)`).
   - `push.start` already returned the owner's `push:<id>`. Remote desktop and computer-use jobs and remote guest exec were proxy jobs or refused; they now return the owner's id too (items below).
2. **Owner events to controllers.** See "Event relay" below.
3. **Device health timer.** `remote::probe_devices(ProbeSchedule)` and a fourth timer thread in `silod/src/timers.rs`.
4. **Remote cancel propagation.** Cancelling `(deviceId, jobId)` now calls the owner's `operations.cancel`, whose registry cancel route reaches the owner's gate (waiting or running), exactly as a local cancel. This works because the remote desktop jobs are now the owner's own jobs (below); the old proxy job could only drop the controller's wait.

### Event relay (A-3, A-4)

- **Bus.** `Event` gained `device_id: Option<String>` (`Event::from_device`). `EventBus::subscribe_devices` takes the engines a subscription wants: `None` is this engine only, a list matches events from exactly those ids (this engine's own id included only if named). The envelope's `deviceId` is the event's origin. `subscribed_devices()` and `raise_gap_for_device()` serve the relay. Relayed events go to the wire bus only, never to in-process listeners.
- **Owner (`engine/src/remote_events.rs`, `remote::serve_event_stream`).** `events.subscribe` is a Stream-class bridge method. The owner subscribes to its own bus for the controller and writes framed messages after the `{"result":{}}` reply: `event` (a full wire envelope), `heartbeat` (every 10 s), `gap` (then ends). It takes a stream-budget permit (192) and one of 16 event-relay slots (`EVENT_RELAY_LIMIT`, a share of the budget, so ports and desktops keep room), and says so plainly when either is full. It ends when the controller leaves, Connections stops being allowed, or a write fails. An event too large for a frame ends the stream with a `gap`.
   - Client-scoped events (`display.viewer.page`, `guest.exec.output`, `guest.exec.exited`, `guest.files.changed`) are not relayed; remote exec output is read with `guest.exec.get`.
- **Controller (`silod/src/relay.rs`).** `events.subscribe {deviceIds}` checks each other id is a saved device (`not_found` otherwise), subscribes with the device filter and ensures one relay per device. A relay thread opens the stream, validates each event against `silo-api::EventEnvelope`, requires the owner's device id, one owner subscription and `seq` = last + 1, and publishes `Event::from_device` on the local bus. It stops when no live subscription lists the device.
- **Gaps and resync.** A skipped sequence number, an owner `gap`, or an event that cannot be trusted ends the sessions that listen to that device (the bus gap signal, the same as a local overflow): the client subscribes again and re-reads. A stream that was lost and then reopens also ends them (events may have been missed). A silent stream (no frame for 35 s, heartbeats every 10 s) counts as lost. Open failures, refusals and losses retry with 1 s doubling to 30 s. Removing a device ends the sessions that listened to it.
- The relay subscribes to all relayable events on the owner, whatever the local subscription selected; the local bus filters. Narrowing to the union of local selectors is a possible optimisation.

### Device health timer

Every 10 s the pass looks at the saved devices (read-only: it never creates Connections settings; devices with a removal pending are skipped) and probes those that are due: never observed, or quiet for 30 s (doubling with each failure, capped at 5 min). Probes are `handshake` over SSH, one at a time, 20 s each, at most 16 per pass, no new probe after 90 s. Results go through the existing `poll_succeeded` / `poll_busy` / `close_after_failed_poll`, which publish `connections.devices.changed`. `poll_failed` now publishes only when something visible changed (it published on every failure before). Opening an event stream counts as an observation. The pass is paused with the other timers during shutdown and storage migration.

## Tests

- `silod`: `operations` (7: routing, params without `deviceId`, canonical-type checks, error codes, unknown device for all four, local fallthrough, owner `operations.list`), `relay` (9, including two engines in one process over a real `UnixStream` pair with the real owner loop and a controller relay), `events.subscribe` through the dispatcher (unknown device refused, own id and empty list allowed, a saved device is relayed and stops with its sessions, using a fake link that never touches SSH), `access` (watcher and unwind of the GitHub route, remote sign-in returns the owner's job), `display` (remote desktop and computer-use jobs are the owner's, owner starts a job, cancel by `(deviceId, jobId)` cancels the work on the owner), `guest` (remote exec start/get, no open stdin, owner serves a real exec job), `timers` (4 passes), socket framing with the owner's device id, `tests/access.rs`.
- `silo-engine`: bus (device filtering, `subscribed_devices`, per-device gap), `remote_events` (9), owner stream budgets and refusals (2), probe scheduling and results (5), METHODS classification updated.
- Transport faking: the existing `stubbed_owner` / `stub_owner` seam for bridge calls (now `pub(crate)` for several modules), and a scripted `OwnerLink` for streams. No SSH process is started by any test; production uses `open_bridge_stream`.
- Gate on the merged tree (`efd2877e` minus the fast-forward): `cargo test --locked -p silo-engine -p silod -p silo-api --no-fail-fast`: silo-api 30, silo-engine 2702 passed (32 ignored), silod 240 plus all socket-level tests, 0 failed. `cargo +1.94.0 fmt --all --check` clean. One timing test (`remote::reply_tests::exchange_deadline_covers_a_full_request_pipe`) failed once under load in a partial run and passed alone and in the full run. silo-ui was not built (this branch changes no silo-ui source; main's silo-ui changes came in by merge).

## Deviations and decisions

- **Remote desktop and computer-use jobs are the owner's jobs through a new bridge method `desktop.job`**, not a changed `desktop.action`. `desktop.action` keeps returning the status synchronously for silo-ui's own remote desktop calls. `desktop.job` returns `{jobId}`; the owner runs the same code path as a local job (`spawn_job`, now a thread instead of `tokio::spawn`, so an owner without a runtime can start one). The old `relay_remote` / `relay_cancellable` proxy and its tests are removed.
- **Remote guest exec routes `start` and `get` only.** `guest.exec.input` takes only a `jobId` (no `deviceId`) in `silo-api`, so a remote job's stdin cannot be addressed; a remote start with `stdinOpen: true` is refused as `unsupported_remote_operation`. Fixing it is an API amendment (add `deviceId` to `GuestExecInputParams`, then route `guest.exec.input`). Remote `guest.exec` (bounded) and `guest.files.*` still refuse remote devices; they are not jobs.
- **Gap on reconnect is hard.** Ending the listening sessions after a lost stream comes back is more disruptive than a health-only signal but is the one signal clients cannot miss; the spec's "re-read after a gap or reconnect" has no softer in-band marker in the event catalogue (adding one is an API change).
- **Retry intervals, probe intervals and the relay limit of 16 are not sourced** (05 §10 OQ12/OQ23); they are chosen in code and documented in the module headers.
- `connections.devices.remove` ends event sessions for the device but does not close the owner stream directly; the relay stops on its next tick when no session lists the device.
- Not done: persisted `RemovalIntent` was already done by followups-a; `desktop.connect` gating and Tauri-as-client are other backlog items.

## For the next tracks

- Fjord's `SocketEngineClient` must treat the `engine.sock` session closing (a gap) as "subscribe again and re-read", also for remote devices; events with another `deviceId` carry that engine's state, and `seq` is the local subscription's.
- Clients follow remote jobs with `deviceId` on `operations.*` and on `guest.exec.get`; ids from different devices can collide textually (`job:7`).
- Live qualification still needed: an event stream over real SSH between two Macs (stream budget under several controllers, the 35 s stall limit over a real link) and `desktop.job` against a real owner.
