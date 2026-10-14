# followups-a: non-blocking review findings for d-computers and d-access

Silo worktree `~/silo-work/followups-a`, branch `engine/followups-a`, cut from `a7873d04`. Merged into `main` by fast-forward; final `main` commit `680a5251`. Never pushed.

All 18 findings are fixed, each with a deterministic regression test (barriers, channels, injected faults, an in-process owner stub; no sleeps or wall-clock timeouts in the new tests; where a test has to wait for another thread it yields a counted number of times and fails with a message instead of timing out).

## Commits by finding

### d-access (`reports/d-access.review.md`)

| # | Finding | Commit |
| --- | --- | --- |
| 1, 2 | P1 removal without remote revocation; success followed by cleanup failure strands removal | `27fa9ee9` `fix(engine): revoke a removed device's key from the owner whatever happened to the private key` (with changeset `7f66b8eb`) |
| 3 | concurrent GitHub sign-ins mix identities | `036ca509` `fix(silod): admit one GitHub sign-in at a time and bind its job, generation and listener` |
| 4, 9 | mirror acknowledges an outcome that failed to persist; mirror-thread start failure leaks route and job | `784c9c80` `fix(silod): store the owner's sign-in outcome before acknowledging it and unwind a failed mirror start` |
| 5 | `push.start` can return a nonexistent job | `8a03d684` `fix(silod): push.start names the job the host accepted and refuses unprepared starts` (+ `dafd69a0` test serialisation) |
| 6 | blocking work on async workers | connect half in `036ca509`, removal half in `27fa9ee9` (see below) |
| 7 | remote network changes published with the controller's identity | `5f3636b2` `fix(silod): publish network.changed only for this device's own network state` |
| 8 | owner job dispatch loses canonical error codes | `de4627e2` `fix(engine): keep canonical error codes across the owner's job dispatch` (+ `de4122e6`, see merge notes) |

Fixes 1 and 2 are one design and one commit, and so are 4 and 9 (same function).

### d-computers (`reports/d-computers.review.md`)

| # | Finding | Commit |
| --- | --- | --- |
| 1 | setup stages bypass the requester | `580af946` `fix(engine): publish setup stages, warnings and failures as the requester's job progress` |
| 2 | early setup failures broadcast to every client | `4e8d8460` `fix(silod): keep an early setup failure with the client that asked` |
| 3 | job results and events omit the Linux row `kind` | `40b4b8f0` `fix(engine): encode Linux state once so job results and events carry the row kind` |
| 4 | socket disconnect leaves display gateways alive | `e2071e32` `fix(silod): end a client's macOS display gateways when its socket closes` |
| 5 | macOS create breaks the job acceptance boundary | `ff309702` `fix(silod): macOS create answers at once and refuses before any job exists` |
| 6 | resource-edit refusal loses `setup_incomplete` | `30b1c713` `fix(engine): classify the resource-edit setup refusal as setup_incomplete` |
| 7 | `forceStop` creates an unreturned job | `4de5981b` `fix(engine): force stop is a command without a durable job` |
| 8 | storage compatibility shim at read time | `dc94a859` `fix(engine): convert legacy reclaim history at launch and validate storage results` |
| 9 | macOS resource jobs in the `setup:` namespace | `fefeb94e` `fix(silod): macOS resource jobs are job:<n>, not setup: jobs` |

## What each fix does and how it is tested

### d-access 1 and 2: device removal (P1)

- `Config` in `desktop-remote/config.json` now keeps, per saved device, the public keys this Mac offered it (`controllerKeys`), and the removals in progress (`removals`: device, saved address, keys, phase `revoke_pending` / `owner_confirmed` / `local_cleanup_pending`, as in p3-a). Public material only. Keys are recorded at connect time and when an owner answers a request made with the current key.
- `remote::remove_device` records the intent before the first owner effect, revokes every recorded key plus the current one (the key that authenticates this Mac goes last), records `owner_confirmed`, and only then forgets the device locally. No lock spans an owner call. A missing private key no longer skips the owner: recorded keys are still revoked, and if the owner cannot confirm, the removal stays pending and the device stays saved.
- A lost acknowledgement is not treated as confirmation. After `owner_confirmed`, a retry or the next launch (`resume_device_removals`, started from `remote::start`) finishes the local cleanup without contacting the owner, so the revoked key is not needed.
- Connecting a device whose removal is pending is refused; two removals of one device do not interleave (`busy`).
- The Tauri `remove_device` command gets the same behaviour (it returns `BridgeError.message`).
- Tests (engine, `remote::removal_tests`, 11): deleted private key still revokes the recorded key; unconfirmed revocation keeps device and intent; rotated key (old first, current last); no key means no owner call; lost reply then authentication failure stays unconfirmed; cleanup failure then "restart" resumes without the owner (revoker counter stays at 1); retry after confirmation never contacts the owner; resume leaves pending-owner removals alone; connect refused during removal; concurrent removal is `busy`; document stores public keys only and loads without the new fields. silod: `removing_a_device_after_its_private_key_was_deleted_still_needs_the_owner` goes through the real handler.

### d-access 3: concurrent GitHub sign-ins

`CONNECT_SLOT` (Idle / Admitting / Active{job, generation}) is taken atomically; a second sign-in is refused as `busy` (05: one flow at a time) instead of overwriting the active identity. The slot is released when the flow ends, before its outcome is published. The cancel route of a job only cancels the shared flow while that job still owns the slot, and `callback_listener_for` only serves the active job. Tests: second request refused as `busy`; a non-owner job cannot move the shared cancellation generation, the owner can; a thread that cannot start frees the slot.

### d-access 4 and 9: mirror

`mirror_owner_connect` acknowledges the owner's outcome only after `publish_finished` returned `Ok` (durable). The mirror start is split out as `follow_owner_connect` and, when the thread cannot start, closes the callback route, cancels the owner job and finishes the local job with the error. Tests: a sqlite trigger on the registry makes the write fail, the owner is not asked to acknowledge, the registry heals afterwards; with working storage the owner is asked; failed `silod-github-mirror` spawn leaves no route, one `operations.cancel` to the owner and a finished local job.

### d-access 5: `push.start`

The reply of the host is canonical: the returned job is `push:<operationId from the reply>`, so a start coalesced onto a running push returns that push. A start whose job does not exist (invalid target, unreadable journal) is refused with the reason; for a remote owner the job is checked with `operations.job.get`. Tests: invalid branch, unreadable journal, coalescing with a running push (journal seeded), remote accepted/coalesced and remote refused.

### d-access 6: blocking work

Local connect startup (SQLite allocation, `prepare_connect` credential lock) now runs in `spawn_blocking` (`036ca509`); a test proves it runs off the single runtime thread. The key derivation (`ssh-keygen`) for removal lives inside `remote::remove_device`'s `spawn_blocking`, and the handler has no blocking call left. I could not add a direct thread probe for the removal half (the engine function reads the process home), so that half is covered by construction, not by its own test.

### d-access 7: events

`network.changed` is published only for this device's own state. The owner's state is the reply to the caller; `sshAccess.save` on another device no longer publishes this device's local network read either. Tests use the owner stub: the owner's rows never appear on the engine's event stream, and a local announcement does.

### d-access 8: codes

`LocalAccess::access_dispatch` and a new `remote_access::dispatch_typed` return `BridgeError`: unknown job `get`/`cancel` is `not_found`, acknowledging a running job is `busy`, a second owner sign-in is `busy` (it was `internal`); unknown `get` no longer returns `null`. Cancellation is recognised by the exact `github::CONNECTION_CANCELLED` string, not by a substring. Tests assert exact codes at the adapter and in `remote_access`.

### d-computers 1: setup publisher

`publish_configuration_progress` (stages, warnings, `setup-failed` with its detail) now persists canonical `operations.job.progress` for the audience bound to the request and keeps the legacy event for `main`. Test: three stages incl. a failure with `failureCode`/`diagnostic`, bound to `socket-a`; nothing reaches another client; an unbound request stays with `main`.

### d-computers 2: fallback audience

`fail_engine_job` sends the outcome to the bound requester first and releases the binding after. Test: two connected clients, the bystander's next `operations.job.finished` is a later all-client one.

### d-computers 3: row `kind`

`ApplicationSource::to_canonical_value` is the single encoding for reads, job results and `computers.changed`. Test deserialises the job result and the event into `silo_api` `ApplicationSource`.

### d-computers 4: display gateways

Socket teardown disconnects the client from the bus first and then closes its gateways (`silod/src/socket.rs`). `register_display` checks "client still connected" under the registry lock, so an in-flight `macos.display.session` cannot register a gateway after the disconnect. Tests: a real `engine.sock` with two clients, closing one ends only its gateway (verified to fail without the teardown line); a late registration for a disconnected client is `cancelled`.

### d-computers 5: macOS create

New `macos_computers::create_macos_computer_accepting`: support check, validation and the preparing row happen on the caller's thread; the job is allocated by a callback after the last refusal; the work then queues as "Creating <name>" on its own thread. A refusal is returned at once and leaves no job. Cancelling while queued ends the job as `cancelled` before the installer and keeps the incomplete computer, as before. Tests (engine): acceptance while the device gate is held; cancel while queued (workflow never ran, job cancelled, computer failed/incomplete); installer starts only after the turn; refused request leaves no job, entry or record. silod: the refusal is an error and the registry lists no job.

### d-computers 6: classification

`store::SETUP_UNFINISHED_FOR_RESOURCES` is shared by the producer and `classify_refusal`. The test produces the refusal from `store::change_resources` itself.

### d-computers 7: force stop

`force_stop` takes its queue turn as "Force stopping Mac" with no job, returns after the stop was issued or refused. `force_stop_with(…, issue)` takes the machine call as a closure so the test can run it without a VM. Test: refused (not running), rejected by the machine (state restored) and accepted; no unacknowledged job, no tracked job, no gate entry.

### d-computers 8: storage history

`runtime_migration` gets a `storage-maintenance` conversion (legacy-tagged entries and a last-trim-only record become manual entries). The read-time synthesis in `runtime/storage.rs::load` and the silod shim are removed; read and reclaim results both pass through `silo_api::methods::storage::StorageState` (`canonical_storage`), so an unconverted `legacy` trigger is an error rather than silently relabelled. Tests: converter unit test (idempotent), the full migration fixture, `canonical_storage` for the four triggers and for `legacy`.

### d-computers 9: namespace

The macOS resource edit validates its `requestId` and allocates `job:<n>` through `start_job`. The id is no longer an idempotency key (duplicates are not detected any more). The socket test asserts the `job:` prefix.

## Gate

Final run on the merged tree (after merging `main` at `c86ab49a`, commit `680a5251`): `cargo test --locked --no-fail-fast` from `app/SiloUI`: silo-api 30, silo-engine 2652 passed and 1 failed (`dependencies::tests::version_probe_accepts_the_output_limit_and_rejects_overflow_on_either_stream`, a timing test that fails under the full-suite load; rerun serially once: passes), silo-ui 71, silod lib 216 and all 9 socket-level tests pass. `cargo +1.94.0 fmt --all --check` is clean for the whole tree. The run before the last `main` merge also saw `backup::tests::timeout_also_stops_gracefully_and_ignored_term_is_killed_after_the_grace` time out; it passes serially.

Note: `silod` lib tests `methods::display::tests::cancelling_a_job_that_has_not_been_admitted_*` and `a_remote_job_is_cancellable_*` failed in the full parallel `silod` lib run on the base `a7873d04` too (verified by checking out the base); they passed in later full runs. They are order-sensitive, not caused by this work.

## Deviations and decisions

- **Spec vs code, d-access 8:** unknown `operations.job.get` on the owner is `not_found` (the same as `engine.sock`), not `null`; the mirror and `push.start` handle `not_found` explicitly.
- **d-access 7:** the full relay of an owner's events (`events.subscribe {deviceIds}`) stays with the core events track. This only stops the wrong attribution; other clients of the controller learn of a remote change when they re-read.
- **d-access 1:** a device saved before this change has no recorded keys; its removal revokes the current key if the private key file exists (the old behaviour) and otherwise only forgets it. Nothing in the repository can know what such a device holds.
- **d-computers 5:** `ensure_loaded` (restore settlement) now runs in the synchronous phase. The old comment wanted it behind the gate; every other macOS entry point already loads outside the gate, and the registry must be loaded before the preparing row can be pushed.
- **d-computers 9:** the earlier report's table (`computers.configuration.change` macOS: `setup:<requestId>`) is superseded: it is `job:<n>`. The `requestId` field stays in the API type; it is only checked for shape.
- No VM, app, GitHub contact or real credential store was used. Fixtures use `install_host` plus `secrets::install()`, never `access::install`. No registry sqlite fixtures or `engine/engine/` were committed.
- Test helper note: the access socket tests share one engine home and Connections settings file; tests that edit it now take `KEY_LOCK` and write atomically (`dafd69a0`).

## Merge notes

- `main` moved twice during the work (`17d7e09e`, then `c86ab49a`); both were merged with `git merge --no-ff main`, without conflicts.
- Main's new `guest/commands.rs` calls `remote_access::dispatch` with a `String` error. The typed variant is `dispatch_typed`; `dispatch` keeps the plain-message signature (`de4122e6`).

## For the next tracks

- Remote event relay (`events.subscribe` with `deviceIds`) must stamp the owner's `deviceId` and keep its sequencing; see d-access 7.
- `operations.*` routing by `deviceId` in core will let `mirror_owner_connect` and the `push.start` job check disappear in favour of the owner's own job id.
- The removal intent and recorded keys live in `desktop-remote/config.json`; any future rewrite of that file must keep `controllerKeys` and `removals` (they are part of `Config`, not `extra`).
