# D computers

Silo branch: `engine/d-computers` (worktree `~/silo-work/d-computers`), off `main@bd7c7c27`.
Seven commits, not pushed. A previous agent left an uncommitted diff; it was reviewed, its engine seams were kept and fixed, and its silod module (which did not compile and wired 5 of 30 methods) was rewritten.

## Commits

| Hash | What |
| --- | --- |
| `33bc18de` | `feat(api)`: the `macosResources` variant of `computers.configuration.change`, schema regenerated, two serde tests |
| `4095dbdd` | `feat(engine)`: lifecycle, setup, retry and configuration changes, and macOS create/start/stop/delete/setup/resource edit, run under dispatcher-allocated job ids; setup audience; identities job; launch status support; refusal classifier |
| `2611afa6` | `feat(engine)`: macOS job failures end with stable codes (`not_running`, `needs_personalizing`, `setup_incomplete`, `screen_sharing_unavailable`, `running_limit`, `not_found`) |
| `dd502490` | `feat(silod)`: the whole domain in `methods/computers.rs`, plus the socket test `tests/computers.rs` |
| `11e16f54` | `feat(engine)`: the health watch hands each unexpected change to its host |
| `8976b5dd` | `feat(silod)`: `computers.unexpectedChange` published from an engine-owned health watch started at launch |
| `d02f9ab1` | `fix(silod)`: bind setup progress to its client only for Linux setup jobs |

## What is implemented

All 30 methods the module owns. Params and results are `silo-api` types (results are validated by deserialising into them where the engine value is reshaped).

| Method | Linux | macOS |
| --- | --- | --- |
| `computers.list` | yes; barrier taken before the read | yes; both kinds in one result, `kind` on every row |
| `computers.shell`, `computers.configuration.read`, `activity.setup.read` | yes | not in the spec (sources unmapped); Linux data only |
| `computers.launch` | selection and `lastPass` | macOS ids are part of the effective selection |
| `computers.start`, `computers.stop` | job `job:<n>` | job `job:<n>`, waits as "Waiting..." and cancellable |
| `computers.restart` | job | `unsupported_remote_operation` (no adapter in the spec) |
| `computers.forceStop` | `unsupported_remote_operation` | command |
| `computers.dismissError` | command; the engine's internal job record is acknowledged at once | `unsupported_remote_operation` |
| `computers.create` | job `setup:<requestId>` | job `job:<n>` plus the new row (absent when the request is refused; the job then ends with the reason) |
| `computers.delete` | job `setup:<requestId>`, needs `expected` | job; queued as "Deleting <name>", cancellable while waiting |
| `computers.configuration.change` | job `setup:<requestId>` | `macosResources` variant: job `setup:<requestId>`, optimistic check on cpus, memory and disk |
| `computers.configuration.retry` | job | n/a (`macos.setup.retry`) |
| `computers.creation.skipComputerUseWait` | yes | n/a |
| `computers.identities.verify` / `.configure` | query / job; the per-computer lanes carry the job id so `operations.cancel` works | refused: identity must name a configured local computer |
| `logs.query`, `logs.export` | yes | setup log; export is a job with its own cancel flag |
| `storage.read`, `storage.reclaim` | read / job in a job-owned gate entry | `unsupported_remote_operation` |
| `macos.setup.retry`, `macos.template.delete`, `macos.display.connect`, `macos.display.resize` | n/a | yes |
| `macos.display.session` | n/a | loopback gateway per (client, device, computer); local owner relays directly, another device through its bridge |
| `macos.display.stream` | n/a | `unsupported_remote_operation`: needs a raw stream transport; silod has none |

Events, all on catalogue topics: `computers.changed` (the engine publishes it for both kinds), `operations.job.progress` (`setup`, `lifecycle`, `macos` sources), `operations.job.finished`, `operations.queue.changed`, `computers.unexpectedChange` (new, from the health watch), retained lifecycle and identity notices (A-27, no OS notification).

Quit dialog (95 A-2): no new method is needed. Fjord reads running rows (id, name, state, both kinds) from `computers.list`, calls `computers.stop` for each selected one, and waits on `operations.job.finished` / `operations.job.get`. The socket test covers the macOS side of that flow (list, stop job, typed refusal).

## Engine changes (shared code, all additive)

- `runtime`: `*_with_host_and_job` variants for lifecycle, configuration change and retry; `bind_setup_audience` / `release_setup_audience` so setup progress and outcome reach the client that started the request instead of the fixed `main` client (a request nobody bound keeps `main`); `configure_computer_identities_with_host_and_job`.
- `runtime::storage::workspace_storage_with_job`.
- `macos_computers`: `*_with_job` entry points; delete and the resource edit now admit through the queue (`admit_macos_removal`, `ChangeResources` under `ComputerConfiguration`), with correct job outcomes; `ExpectedResources.disk_gib`; `classify_refusal` / `job_error_code`; `display_session`, `display_stream`, `resize_display` made public.
- `startup`: `StartupState::last_pass` / `record_pass`, `effective_selection`. `settings::settings_of(context)`.
- `health_watch`: `UnexpectedChange` and a defaulted `HealthWatchServices::unexpected_change`; `install_services` is public.
- silod: `SilodContext::disconnect_events` ends the client's screens; `close_remote_displays` is implemented; `app.rs` starts the health watch; `dispatcher.rs` test now probes `computers.unknown` instead of `computers.list` (it was the example of an unsupported method).
- `silo-api`: only the `macosResources` variant and `MacosResourceConfiguration`; schema regenerated and checked by the existing schema test.

No change to `HandlerContext`, the job registry or the event bus.

## Tests

- silo-api: 29 pass (two new).
- silod: 72 lib tests pass (31 in `computers::tests`, one per handler or handler group, including a registry-wide check that every owned method has a typed handler), plus `tests/computers.rs`: a socket-level test over `engine.sock` with a saved macOS computer on disk (reads, stop job with `not_running`, typed refusals, the `macosResources` job, delete job removing the folder, acknowledgement through `operations.*`).
- silo-engine: new tests for the refusal classifier and job codes, queued macOS delete (job visible in the queue, cancelled while waiting), the bound setup audience, launch selection and last pass, unexpected changes.
- `cargo test --locked --workspace`: everything passes except two engine tests that are timing-dependent and unrelated to this track: `backup_controller::tests::install_schedules_pending_import_recovery_outside_tokio_runtime` (fails about 1 run in 3 in isolation, a busy-flag race) and `dependencies::tests::version_probe_accepts_the_output_limit_and_rejects_overflow_on_either_stream` (timeout under full-suite load; passes alone). Neither file was touched.
- `cargo +1.94.0 fmt --all --check` is clean for every file this track touches. It still reports diffs in five files that were already unformatted at the base and belong to other tracks or the shared dispatcher: `engine/src/backup_controller.rs`, `engine/src/jobs/registry.rs`, `silod/src/methods/checkpoints.rs`, `silod/src/methods/mod.rs`, `silod/src/methods/services.rs`.
- Engine tests leave an untracked registry fixture in `app/SiloUI/src-tauri/engine/engine/`. It was moved out of the worktree (to /tmp) once; it can reappear after an engine test run and must not be committed.

No VM, app or runtime was started. macOS tests rely on the test binary lacking the virtualization entitlement, so nothing can boot.

## Deviations and decisions

- **Other devices:** every device-aware method answers `unsupported_remote_operation` for a `deviceId` that is not this device or `"local"`. The owner-side bridge still serves the legacy `runtime.*` / `macos.*` names, so canonical forwarding belongs to the connections track. `macos.display.session` is the exception: its remote branch uses `macos.display.connect` and `macos.display.stream`, which are already canonical bridge names.
- **Synchronous refusals:** an unknown computer, a wrong kind or a bad request id is an immediate error with a typed code (no job is created). Everything after acceptance, including engine refusals, is the job's `error`. A refused macOS create returns `{jobId}` with no `computer`.
- **macOS gaps the spec leaves open (Q13):** restart, dismiss-error, storage, identities and the macOS setup journal are typed refusals, not invented adapters.
- **Setup audience:** the engine had `Audience::Client("main")` hard-coded for setup progress and outcomes. It is now per request, bound by the handler. Tauri's in-process client is unchanged.
- **`macos.display.session` origins:** the allow-list is still the Tauri app's origins (probe B-21).

## Pending for other tracks

1. **Capabilities list.** `CoreMethodRegistry` still advertises only the nine built-in methods in the handshake. Add the implemented methods once all domains merge.
2. **Launch pass in silod.** `computers.launch` reports the selection and `lastPass`, and `StartupState::record_pass` exists, but silod has no `StartupServices` adapter, so no launch pass runs and `lastPass` stays null until the lifecycle track installs one (macOS ids already flow through `startup::install` and `macos_computers::start_at_launch`).
3. **Other engine timers (95 A-26).** Secret revocation retries, log expiry and port repair are still driven by client reads. Only the health watch was added here.
4. **Stream transport.** `macos.display.stream` (and `guest.ssh`, `display.native.attach`) need raw byte streams on `engine.sock`.
5. **Remote routing** of the computers methods (see above).
6. **Engine-owned VM window.** The computers module's `MacosHost` refuses `show_display`; the display track must supply the real window host and share the macOS registry (it is a process global, so contexts are interchangeable).
