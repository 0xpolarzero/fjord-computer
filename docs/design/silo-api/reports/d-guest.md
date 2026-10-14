# D-guest: guest, files, terminal and editor methods

Silo branch: `engine/d-guest` (worktree `/Users/polarzero/silo-work/d-guest`), from `main@bd7c7c27` (the dispatch keystone). It continues the uncommitted diff of the previous agent (the `guest.exec.get` `deviceId` amendment, `guest.account`, `files.list`, `terminal.command`, `editor.includeNotice`); that diff was reviewed, kept where it was sound and replaced where it was partial (for example it returned an empty replay for `guest.exec.get` and built the terminal argv inline).

## Commits

| Hash | Subject |
| --- | --- |
| `03a99e52` | `feat(api): address guest.exec.get by owner device` (the queued amendment; schema regenerated) |
| `7aea377e` | `feat(engine): add guest access for Linux and macOS computers` (`silo_engine::guest`, ID-keyed aliases in `editor.rs`, targeted event delivery, `GuestExec` cancel route, macOS bridge) |
| `1575e3e4` | `feat(silod): serve the guest, files, terminal and editor methods` (all handlers, `guest.files.watch` activation, unit and socket tests; also a few engine test fixtures and the pure macOS command-line builder with its test) |
| `a9c0f179` | `fix(engine): treat newlines in guest file paths as data` (plus the changeset `guest-access-methods.md`) |
| `2ea62d10` | `fix(engine): end guest runs cancelled before the guest recorded them` (a cancel or timeout right after start used to miss the guest process group; the control helper now waits for it, cancellation retries until the host process is gone, and the account check is cached for 5 s) |

Nothing was pushed. No VM or app was started.

## What was built

Every method the domain owns is implemented on the engine socket for Linux computers. For macOS computers, the methods that only need the guest SSH that exists on `main` work; the rest answer `unsupported_remote_operation` with "(pending parity-2)" (list below).

| Method | Linux | macOS |
| --- | --- | --- |
| `guest.account` | uid and home read in the guest; user from `working_account::inspect_user` | works (SSH) |
| `guest.exec` | bounded; stdout cap (default 256 KiB, per-request up to 768 KiB, `output_too_large`), stderr spooled to a private temp file and never capped, `timed_out`, `not_running`, byte-exact stdin/stdout, `exitCode` or `signal`, `as: account|root` | works (SSH, `sudo -n` for root) |
| `guest.exec.start` | an engine-owned job (`job:<n>`): stdin (initial and open), `guest.exec.output` events with one increasing `seq` across stdout and stderr, `guest.exec.exited`, saved outcome `{exitCode, signal?}`, bounded replay ring (at most `retainOutputBytes` and 1,024 chunks), cancel through `operations.cancel` (TERM, 3 s grace, KILL, confirmed gone in the guest) | works |
| `guest.exec.input` | `not_running` / `stdin_closed`, 8 MiB pending-input bound (`busy`) | works |
| `guest.exec.get` | live from the session, or from the saved outcome (empty output) after the session is gone; `deviceId` accepted | works |
| `guest.files.read` | ranged, metadata from the open file (`size`, `mtimeMs`, `inode`, `mode`); at most 960 KiB per response, larger ranges are refused | works |
| `guest.files.write` | `mode`, `createParents` (0700), atomic (staged at 0600 next to the target, then given `mode`, then committed), `replace: always` / `never` / `ifSha256`; explicit `expectedSha256: null` means "must not exist" (`changed`); `never` and null commit with a hard link, so create-only is race-free | works |
| `guest.files.list` | unpaged, links not followed, `size` and `mtimeMs`; an oversized result is refused, never truncated | works |
| `guest.files.remove` | files and links only, missing counts as removed, directories refused (`not_a_file`), request order, a failure stops the run | works |
| `guest.files.watch` | the caller's own event subscription (id returned as `subscriptionId`, ended by `events.unsubscribe` or disconnect); `guest.files.changed` reaches that subscription only | works |
| `guest.prepare` | the existing owner-side logic (`remote_access`), behind the computer gate | pending parity-2 |
| `guest.sshAlias.ensure/remove` | keyed by `computerId`: alias `silo[-dev]-<computerId>`, `<runtime home>/ssh/<id>.conf` and `<id>.known_hosts`; `installInclude`, `includeInstalled`, `include_not_writable`, `/workspace` path checks, guest folder check, BatchMode probe; remove deletes only its own files and the shared Include only when no `*.conf` is left | pending parity-2 |
| `files.list` | the existing Files-page listing | pending parity-2 |
| `files.upload` / `files.download` | the existing transfer jobs (`transfer:<transferId>`); the response waits until the job exists | pending parity-2 |
| `terminal.command` | returns the argv (`/usr/bin/env MSB_… msb exec <name> --user silo … --workdir /workspace --tty`) | pending parity-2 |
| `editor.command` | prepares the alias and returns the editor argv from the device's editor setting | pending parity-2 |
| `editor.includeNotice` | host-level, platform independent | n/a |
| `guest.ssh` | not served (see deviations) | not served |

Mechanisms:

- **Linux:** `msb exec <name> --no-start --user … --env USER/LOGNAME=…` with `--stream` when stdin is used and `--no-tty --no-stdin` otherwise. The runtime's process stdin protection (`--no-stdin` on every non-TTY exec) is untouched; the API builder is a separate spawn that never carries the startup secrets document.
- **macOS:** the system `ssh` with the computer's key through `guest_access` (new `ssh_invocation`, additive), one command line with every word single-quoted. `macos_computers::guest_ssh(app_data, id)` finds the computer in the live registry, or its stored record when the registry is not loaded.
- **In the guest (Perl, in both platforms):** `helpers/exec.pl` is a supervisor that gives each run its own process group, records it in `/tmp/silo-exec-<token>.pid` and reports a signal death as 128+N with the signal name saved; `helpers/control.pl` ends a group (TERM, grace, KILL) and reads the signal name; `helpers/files.pl` reads, stages and commits, lists, removes and watches. Perl is in the Linux guest image (`perl` in the image lock) and ships with every macOS.
- **Errors:** `GuestError { code, message }` maps onto the existing `ErrorCode` values (`not_running`, `account_not_migrated`, `timed_out`, `output_too_large`, `cancelled`, `stdin_closed`, `not_found`, `permission_denied`, `not_a_file`, `exists`, `changed`, `open_ssh_missing`, `include_not_writable`). No new code was needed.

Shared-code changes (all additive): `silo-api` (`GuestExecGetParams.deviceId` and its schema), `jobs/registry.rs` (`CancelRoute::GuestExec`), `events/mod.rs` (`EventBus::has_subscription` and `publish_to_subscription`), `silod/dispatcher.rs` (activates the `guest.files.watch` subscription with its response, like `events.subscribe`), `editor.rs` (ID-keyed alias functions; `prepare_configuration` split so the name-keyed UI flow is unchanged), `lib.rs` (`pub mod guest`), `macos_computers.rs` and `macos_computers/guest_access.rs` (one `ssh_invocation`, one new module).

## Tests

Run from `app/SiloUI` with `CARGO_TARGET_DIR=/Users/polarzero/silo-work/d-guest/target CARGO_BUILD_JOBS=3`.

- Engine guest suite (`cargo test --locked -p silo-engine --lib -- guest::`): 38 tests passing, covering validation, argv as data, invalid UTF-8 stdin and stdout, signal reporting, the stdout cap (exact cap succeeds, cap+1 fails), a deadline ending the whole guest tree, root and account runs, atomic writes and modes, a four-way create-only race with one winner, null-hash create-only, compare-and-replace, ranged reads, links not followed, directory refusal, exec jobs (ordered input, interleaved sequences, replay eviction, cancel ending the tree, saved outcome after the session is gone), watches (reports changes, not existing content, ends when not wanted or stopped), ID-keyed aliases and their scoped, idempotent removal, the macOS command line quoting and the pending-parity answers. The fake runtime is a shell script standing in for `msb` that runs the command after `--` on this Mac, so the real Perl helpers and the real process plumbing run.
- `silo-engine` event bus: one test for targeted delivery.
- silod handler tests (`cargo test --locked -p silod --lib methods::guest`): 12 tests, one or more per handler, including device refusal for every per-computer method.
- Socket-level integration test (`silod/tests/guest.rs`): one session over a real `engine.sock` drives files (create-only with an explicit null, conflict, ranged read), bounded exec with raw bytes, an exec job with streamed output, exit and finished events and replay, a file watch that delivers on its own subscription, and stable error codes.
- Full gate: see "Gate".

## Gate

`cargo test --locked --workspace --no-fail-fast` from `app/SiloUI` on the final commit (`2ea62d10`):

| Crate | Result |
| --- | --- |
| `silo-api` | 28 passed |
| `silo-engine` | 2,365 passed, 30 ignored, **2 failed** (not this track, see below) |
| `silo-ui` | 71 passed |
| `silod` (lib) | 53 passed (12 are the new guest handler tests) |
| `silod` `tests/guest.rs` (new) | 1 passed |
| `silod` `tests/handshake.rs` | 1 passed |

The two failures are outside the guest domain:

- `backup_controller::tests::install_schedules_pending_import_recovery_outside_tokio_runtime` **fails identically on the base commit `bd7c7c27`** (checked in a throwaway worktree of that commit, then removed). It asserts `!controller.busy` after recovery and is unrelated to guest code.
- `dependencies::tests::version_probe_accepts_the_output_limit_and_rejects_overflow_on_either_stream` timed out under the machine's load (load average 30 to 40 from the parallel tracks) and **passes when run alone**.

`cargo +1.94.0 fmt --all --check` is **not clean on this branch, and was not clean on `main`**: the remaining diffs are all in other domains' files and were left alone to avoid conflicts (`backup_controller.rs`, `jobs/registry.rs` (three hunks, formatting only), `macos_computers.rs` (one test hunk), `silod/src/methods/{checkpoints,computers,mod,services}.rs`). Every file this track created or changed is formatted. The coordinator can run `cargo +1.94.0 fmt --all` once at integration. (Run from `src-tauri/` or with `+1.94.0`: `src-tauri/rust-toolchain.toml` pins 1.94.0 and a plain `cargo fmt` from `app/SiloUI` uses a newer stable.)

Cargo tests leave an untracked `src-tauri/engine/engine/` registry fixture (as the keystone report noted); it was removed after the last run.

## Deviations from the spec and choices

1. **File bytes go through the exec channel, not SFTP.** Every payload is bounded by the 4 MiB frame, and atomic commit, create-only and compare-and-replace need a guest-side helper anyway (SFTP alone cannot do them, as p3-a §2.4 notes). One helper over one channel gives Linux and macOS identical semantics and needs no SSH key setup for Linux file access. `msb ssh serve` SFTP remains in use by the existing Files-page transfers.
2. **Conditional writes:** `never` and null use `link(2)` and are race-free against any writer. `ifSha256(hash)` is serialized per path in the engine, compares inside the guest, re-checks the file identity (dev, inode, size, mtime) right before `rename`, and so is exact for engine writers; a non-engine writer can still slip in between that last check and the rename (microseconds). This is the residual p3-a §2.7 warned about.
3. **Watch is a guest-side listing comparison every 200 ms, not inotify or FSEvents.** It costs one long-lived command per watch and needs no native API on either platform. Latency is up to about 200 ms (B-20's sub-millisecond inotify figures are not met). The first look happens about 200 ms after the response, so a client must re-read the folder after subscribing (it must anyway). Events carry the watched folder, coalesced per look.
4. **`guest.exec.get.sinceSeq` is "the last sequence already seen"**: chunks with `seq > sinceSeq` are returned. After the in-memory session is gone (engine restart or retention), a finished job answers with empty output and `firstRetainedSeq = sinceSeq + 1` (0 when omitted).
5. **`signal` is reported only when the supervisor recorded it.** A program that itself exits with 129..192 and records nothing reports that exit code.
6. **Limits chosen (B-32 candidates, unmeasured on a live guest):** bounded timeout 1 ms to 180 s, stdout cap default 256 KiB and at most 768 KiB, `retainOutputBytes` at most 960 KiB so a full replay always fits one frame, reads at most 960 KiB, output chunks at most 64 KiB, a watch at most 32 folders.
7. **`files.upload` takes `paths` only.** `selection` tokens belong to native pickers and are refused. `origin: viewer` runs as the transfer owner `desktop-shell-<connectionId>`, which the existing transfer code confines to Downloads; that the connection belongs to the caller is the viewers track's check, not done here. `files.download` writes `destination`, or `~/Downloads/<name>` when omitted.
8. **`guest.ssh` is not served.** It is a raw duplex stream after a framed reply, and the socket layer has no stream upgrade yet (parity-2 and Connections add `silod --guest-ssh` and the relay). It answers `unsupported_remote_operation` on both platforms.
9. **Every per-computer method refuses a `deviceId` other than this device** with `unsupported_remote_operation` (routing to other devices is Connections' job). Alias files are always written on the engine that handles the request, which is what the controller-side routing exception needs.
10. **Name-keyed UI flows are untouched.** Tauri's `open-editor`, the transfer transports and the private transports still write name-keyed entries (`silo-<hash>-<name>`); only `guest.sshAlias.*` and `editor.command` write ID-keyed ones. Converting the UI flows belongs to the Tauri client track.

## Pending parity-2 (macOS)

On branch `engine/p3-macos-parity-2` (not merged) live `macos_computers/ssh_alias.rs`, `ssh_stream.rs`, `ports.rs`, macOS arms in `transfer.rs`, and `silod` socket/dispatcher changes. These answer "pending parity-2" today:

- `guest.sshAlias.ensure/remove` (`guest/ssh_alias.rs`, function `linux()`),
- `guest.prepare` (`guest/commands.rs::prepare`),
- `terminal.command` and `editor.command` (`guest/commands.rs`),
- `files.list`, `files.upload`, `files.download` (`silod/src/methods/guest.rs::linux_computer`),
- `guest.ssh` (all platforms).

Merge notes: parity-2 edits `silod/src/dispatcher.rs` (+122 lines) where this branch has one small hunk (the activation of the `guest.files.watch` subscription); the two should merge by hunk.

## Not verified live (no VM was started)

- `msb exec --stream`: that stdin round-trips, that standard error stays separate from standard output, and that the host exit status equals the guest's. The fake runtime proves the host side only.
- The guest-side process-group kill under the real `agentd` (it runs exec children with `setsid`; the supervisor handles an existing group leader) and under macOS `sshd`.
- The macOS path end to end (SSH quoting is unit-tested; no macOS guest was reachable). `PATH` there is the non-interactive SSH `PATH`, so callers should pass absolute program paths (they get `home` from `guest.account`) or set `PATH` in `env`.
- Perl in the shipped guest image at the pinned revision (it is in the image lock).
- Latency of the 200 ms watch and `guest.exec` round trips (each Linux call also runs `msb inspect`).

## Next tracks

- **Phase 4 (Fjord):** `guest.files.write` mode, create-only and compare-and-replace behave as 70 §2.1 asks. Subscribe to `guest.exec.output`, `guest.exec.exited` and `operations.job.finished` before `guest.exec.start`. Read back with `guest.exec.get` after a missed event. A job still running when the engine restarts reads as `lost` and its guest process keeps running (its supervisor token is not persisted; B-37 stays open).
- **Connections:** route `deviceId` to the owner; alias `ensure` for a remote computer must write controller-local files and call the owner's `guest.prepare` only to authorize the key.
- **Tauri client track:** move the name-keyed editor flows to `guest.sshAlias.ensure` and `editor.command`.
