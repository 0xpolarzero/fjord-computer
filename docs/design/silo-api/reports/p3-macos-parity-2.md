# P3 macOS parity, part 2

**Status: partial.** The Files, port, SSH alias, and command adapters are implemented and the Rust workspace gate passes. This is not full P3 macOS parity: archive export/import and API dispatch integration remain incomplete, and the live guest probe did not obtain a NAT lease.

## Implemented

- Added bounded macOS workspace listing under `/Users/silo/workspace` using a NUL-delimited, base64-name SSH helper. Paging is capped at 200 entries and 20,000 total; snapshots expire after 120 seconds and bind to computer ID, running generation, caller, and path. The helper refuses non-UTF-8 names and symlink traversal. Setup now creates and records the workspace and Downloads roots; SFTP transfers reuse the existing transaction and cancellation code with `/Users/silo/workspace` and `/Users/silo/Downloads` as roots.
- Added machine-readable `lsof` listener parsing, internal-port filtering, ID-keyed saved mappings, and owned `ssh -N -L` tunnels bound to `127.0.0.1`. Website URLs use the existing `.localhost` naming function. Start, stop, delete, and state reads reconcile or tear down the macOS tunnels.
- Added per-computer SSH config files and aliases keyed by computer UUID, strict known-host pinning, disabled agent and X11 forwarding, and terminal/editor methods that return client argv. Clipboard parity was already present in `guest_clipboard.rs`; this part did not change it.
- Added the `p3-macos-parity-2` patch changeset.

## Remaining blockers

- The generated alias uses `silod --remote-guest <localDeviceId> <computerId>`. The existing `remote::run_remote_stream` only resolves IDs in the saved remote-device list, so it cannot route the local device ID. Alias generation and terminal/editor handoff cannot pass an end-to-end connection until P2 adds local self-routing. I left that transport code unchanged under the instruction to avoid networking changes.
- No macOS archive adapter was added. The selected format is the format-4 `.silo-backup` envelope with `silo-vz-components-v1`. Import requires the exact disposable-disk offline account-rekey prototype specified in [P3-B §2.4](../design/p3-b.md#24-archive-format-and-import-c-4). That prototype and its credential work are outside the permitted live probe and conflict with the instruction to avoid secrets code, so neither import nor export is claimed here.
- These are engine Rust entry points only. The existing canonical `silod`/remote and Tauri command routes were not extended to invoke them in this engine-only slice.
- The one permitted clone booted, but no matching NAT lease appeared and SSH was not ready within five minutes. The harness stopped the VM, then its clone, app, metadata, and source build were removed. The only retained probe artifact is `~/silo-probes/p3-macos-parity-2/evidence/probe.log`. No Files, `lsof`, relay, or alias behavior was verified live.

## Verification

- `cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --check` — passed.
- Full workspace: `CARGO_TARGET_DIR=/Users/polarzero/silo-work/p3-macos-parity-2/target CARGO_BUILD_JOBS=5 cargo +1.94.0 test --manifest-path app/SiloUI/Cargo.toml --workspace --locked` — passed; engine suite 2,279 passed, 30 ignored, no failures. Native tests used the synthetic GitHub configuration permitted by `docs/SiloUI-RELEASES.md`; values are not recorded here.
- Focused macOS adapter tests — 289 passed; Files parser 6 passed; ports parser/config/argv 6 passed; shared SFTP-root test passed; editor argv/workspace test passed.
- The first full run had one timing failure in the unrelated `backup::tests::cancel_asks_the_runtime_to_stop_before_killing_it`; its isolated rerun passed. The final full workspace rerun passed. Full logs remain under the ignored `target/verification/` directory.
- `git diff --check` — passed.

The live result is inconclusive, not a pass. Do not treat this commit as completing A-19 full parity until local alias routing, canonical dispatch, archive work, and a successful disposable-guest probe are complete.
