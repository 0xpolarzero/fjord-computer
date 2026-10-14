# P3 macOS parity, part 2 review fixes

**Status: all 8 findings fixed with deterministic regression tests; Silo `main` fast-forwarded to `53ba4e11`.** The review is [p3-macos-parity-2.review.md](p3-macos-parity-2.review.md). No VM, app, or live guest was started, so the review's disposable archive round trip (Retry setup, cold boot, new access, rejection of old credentials, SecureToken and volume ownership, nonempty Files/SFTP, shutdown teardown) is **still outstanding**. Nothing here qualifies post-rekey boot or login.

## Commits (branch `engine/p3-macos-parity-2`, merged to Silo `main` fast-forward)

```text
53ba4e11 merge(engine): integrate display methods into macOS parity fixes
69cf130b merge(engine): integrate display methods into macOS parity fixes   (clean merge of main)
56194d7c merge(engine): integrate main proxy and formatting into macOS parity fixes
a7562d9b merge(engine): integrate main and fix P3 macOS parity review findings
48269319 fix(macos): queue guest transfers with computer operations         (finding 5, the previous agent's diff)
```

The fixes for findings 1, 2, 3, 4, 6, 7 and 8 live inside merge commit `a7562d9b`, not in separate commits. I merged `main` first because it had rewritten `silod`'s dispatcher and socket, which finding 2 touches, so the fixes were written on top of the merge. I did not split them back out. `main` moved three times during the work (jobs/events dispatch; macOS proxy plus a formatting commit; display methods), hence the later merges.

## Findings

1. **Relay resurrection during repair** (`macos_computers/ports.rs`). Tunnels now live in a registry with a per-computer revision, advanced under the same lock by unpublish, publish, Stop, and removal. A repair records the revision before reading anything, and installs a tunnel only if the revision is unchanged and the guest is still Running in the same Start generation. The check and the insert are one critical section. A repair also closes tunnels absent from the saved enabled set. The repair is split behind a `RepairHost` seam so tests can hold a pass inside `spawn`.
   Tests: unpublish during repair, Stop during repair, restarted generation during repair, orphan tunnel removal, and a happy-path control. Barriers are channels, with no sleeps.
2. **`guest.ssh` contract and revocation** (`silod` dispatcher and socket; `macos_computers/ssh_stream.rs`, `run_marker.rs`, `ports.rs`, `ssh_alias.rs`, `remote.rs`).
   - `guest.ssh` is always an SSH transport to guest port 22. `purpose:"port"` plus `port` only labels the forward, as on Linux, instead of selecting the destination port.
   - Labelled streams register in the existing `PortRegistration` revocation registry (made `pub(crate)`). Unpublish calls `revoke_port_streams`.
   - The macOS tunnel's `ssh -L` now passes `-o ProxyCommand=… --remote-guest <device> <computer> <port>` so the stream carries its label.
   - `silod` relays the stream with a periodic `allowed()` check (50 ms), so revocation closes the stream.
   - Running state and generation: `silod` has no macOS registry today, because the VMs live in the app process. The VM owner therefore publishes `running.json` (pid and Start generation) in the computer folder from `emit()`. It clears the file on any other state and on load. A stream opens only against a live marker whose owner pid is alive. It ends when the marker disappears, the generation changes, or the forward is no longer enabled in `macos-ports.json`, which also gives cross-process unpublish revocation.
   Tests: stream reaches port 22 with and without a label, in-process revocation, saved-forward revocation, refusal of unpublished labels, Stop and restart generation, a dead owner, marker writer sync with the registry, relay end-to-end over `engine.sock` (bytes pass, then revocation closes the client), `relay_while_allowed`, and the one-shot and late-`guest.ssh` socket tests.
3. **Detach before staging cleanup** (`macos_computers.rs`). `discard_import_folder` detaches the disk image before any removal, through an injectable detach. `recover_archive_import` and the failure paths in `import_archive` use it. A failed detach keeps the folder and returns an error, so the caller's journal identity is preserved. Tests use fault injection for staging, a published folder, and a committed record with leftover staging, including that removal follows the detach.
4. **Journaled export captures** (`macos_computers.rs`, `backup_controller.rs`, `backup_controller/recovery.rs`). Capture folders are named `.silo-macos-export-<journal id>-…`. The mixed-export working folder is `.silo-backup-<journal id>-mixed-…` next to the destination. The journal id is persisted before the export starts, so it is the journaled owner. Recovery (`recover_at_paths_with` and `settle_before_migration`) removes both, and only this operation's. Tests simulate termination by keeping the folders past their destructors, and an end-to-end `recover_at_paths` over a hosted controller checks that other operations' folders and a finished export survive.
5. **Transfer queue admission** (`macos_computers.rs`, `transfer.rs`). This is the previous agent's diff: computer-scoped admission held for the whole upload or download session, cancel bound to the transfer token, and generation revalidated after waiting. Merging `main`'s transfer jobs required one shared cancellation token between the job, the global transfer slot, and the queue guard. macOS transfers now start a durable transfer job like Linux ones. Tests cover overlap with Stop, restore and export, revalidation after waiting, and cancel reaching the token.
6. **`lsof` status 1** (`ports.rs`). Status 1 with empty output means no listeners. Status 1 with output, other statuses, and SSH loss stay errors. The test covers the status matrix.
7. **Inspection validates the model and host limits** (`backup_controller.rs`, `macos_computers.rs`, `engine.rs`). After the existing guest-build check, `validate_macos_rows` checks CPUs, memory, and disk against this Mac (`store::validate_request`) for every row. Only then does it extract the bounded hardware-model component and validate it with `VZMacHardwareModel` (damaged or unsupported). Tests cover the check ordering (the cheap checks fail before any archive read), the bound, and the rejection of an unreadable model. **Cost:** the model check is one extra archive pass per macOS row, on top of the verify pass.
8. **Plist cap** (`offline_setup.rs`). Guest-disk plists are read through a 1 MiB bounded reader before decoding, in `read_plist` and in the user-ID scan. Tests cover the exact limit, one byte over, an oversized neighbour in the user-ID scan, and an oversized `silo.plist` refused by the rekey without modification.

Changesets were added for each user-visible group.

## Merge notes

- `silod` guest-stream support was re-applied to `main`'s domain-handler dispatcher and socket. `guest.ssh` is read as the first request after the handshake. A late `guest.ssh` returns the "must be the first request" error.
- `begin_operation` gained a job-less variant for exports, which hold their own export operation.
- Two commits on `main` and on my branch had committed test-created job-registry files under `app/SiloUI/src-tauri/engine/engine/`. I removed them and ignored that folder.
- `setup_steps_complete` now includes the workspace roots step before the proxy bootstrap is staged.
- `cargo fmt --all --check` failed on `main` itself. I formatted the workspace with the pinned `+1.94.0` toolchain, which now passes.

## Verification

- `cargo +1.94.0 fmt --all --check` passed on the final tree.
- `cargo test --locked --workspace --no-fail-fast` (`CARGO_BUILD_JOBS=4`, own target dir) on the final merged tree: `silo-engine` 2,436 passed, 32 ignored, 2 failed. `silo-api` 27, `silo-ui` 71, and `silod` (unit, `handshake`, and `display` tests) all passed.
- The 2 failures and the failures in earlier runs (a different 2–3 each time) are timing flakes under the machine's load average of 18–30 from other tracks: `dependencies::…version_probe_accepts_the_output_limit…`, `backup_controller::…install_schedules_pending_import_recovery_outside_tokio_runtime`, `transfer::…the_client_cannot_write_far_past…`, and two `runtime::…structured_*` tests. Each passed when rerun alone. None touches this track's logic, though `install_schedules_pending…` also failed alone in 2 of 6 runs under that load.
- The `silo-ui` build script needs `src-tauri/binaries/silo-macos-gateway-*` and `silo-network-bootstrap-*` from `main`'s proxy work. They are gitignored, so I used placeholder executables locally. Nothing about them is committed.
- The native test configuration used the synthetic GitHub values from `docs/SiloUI-RELEASES.md`; none are recorded here.

## Notes for the next work

- **Still unqualified:** the live disposable archive round trip listed at the top. That includes post-rekey boot and login, SecureToken and volume ownership, and nonempty Files/SFTP.
- The run marker is published by whichever process owns the VM. When `silod` becomes the owner, its registry is the same process, and the marker keeps working without changes. It could be dropped later in favour of the registry.
- Inspection of very large macOS archives now takes about one extra pass per macOS row. If that is too slow, capture the hardware model during the verify pass instead of re-extracting it.
- Cross-process unpublish revocation polls `macos-ports.json` every 50 ms per open forwarded stream. An event from the port owner would replace the poll.
