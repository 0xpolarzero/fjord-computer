# P3 macOS parity, part 2b

**Status: implementation and Rust gates pass; live and integration qualification is partial.** This run merged `main`, added local SSH alias self-routing, and implemented Apple Virtualization archive export/import in the format selected by [P3-B §2.4](../design/p3-b.md#24-archive-format-and-import-c-4). The offline import rekey passed against a disposable APFS disk. No post-rekey guest boot/login or live archive round trip was performed.

## Delivered

- Merged `main` with `git merge --no-ff main`: `02dfda4a`. The merge has the worktree's prior parity commit and `main` as its parents.
- Local SSH aliases now route a local device ID through the canonical `engine.sock` guest-SSH one-shot stream. Nonlocal device IDs continue through saved Connections. The generated alias and existing SSH `Include` are preserved.
- Added the format-4 `.silo-backup` Apple Virtualization payload `silo-vz-components-v1`, including whole-computer/checkpoint capture, inspection, export, import, fixed-order component frames, checksums, sparse disk restoration, and strict version/length validation. Imported rows receive a new stopped identity and go through the import personalization path.
- Added offline account rekey on the mounted Data volume. It preserves the managed account and home while changing its password verifier and managed authorized key. Re-key normalizes inherited authentication authority to the verifier written and removes inherited SRP, SecureToken, and LKDC entries. Guest host-key rotation retry now clears stale `known_hosts` before the imported password boot.
- Restored published SSH port tunnels after macOS computer start. Added mixed Linux/macOS format-4 archive rows, extraction free-space preflight, and a 1 MiB bound for opaque hardware-model data.

The new rekey path has only been validated offline. Apple describes SecureToken as a password-wrapped key-encryption key; this disk mutation does not prove login, SecureToken, or volume ownership continuity after boot ([Apple deployment guide](https://support.apple.com/guide/deployment/use-secure-and-bootstrap-tokens-in-deployments/dep24dbdcf9e/1/web/1.0)). The hardware-model bound is defensive: Apple documents `dataRepresentation` as an opaque representation ([VZMacHardwareModel](https://developer.apple.com/documentation/virtualization/vzmacmachardwaremodel)).

## Commits

```text
02dfda4a merge(engine): integrate main parity fixes
3e274f75 fix(engine): route local macOS SSH aliases through engine.sock
edaaf264 feat(macos): add imported account rekey path
0ee45580 feat(engine): add Apple Virtualization archive codec
adfd3ffb fix(macos): restore SSH published port tunnels
2135536c feat(macos): export and import Apple Virtualization computers
c676d6ed fix(macos): accept booted account metadata during import
f0d97984 fix(macos): clear inherited import authentication state
c3808595 feat(backup): support mixed platform archives
2ccefe02 fix(backup): budget macOS archive extraction space
5cde56e0 fix(macos): bound imported hardware model data
ffc8fc41 fix(macos): recover imported host key rotation retries
```

Changesets accompany the user-visible changes, including local alias routing, macOS archive import, mixed archives, and the archive/import safety fixes.

## Verification

- `cargo +1.94.0 test --manifest-path app/SiloUI/Cargo.toml --workspace --locked` with `CARGO_TARGET_DIR=/Users/polarzero/silo-work/p3-macos-parity-2/target` and `CARGO_BUILD_JOBS=5`: **2,451 passed, 32 ignored, 0 failed** across emitted test harness results. Suite results: `silo-api` 27; `silo-engine` 2,319 passed and 32 ignored; `silo-ui` 69; `silod` 33 plus two 1-test child-process runs; `silod` integration 1. The native test run used the synthetic GitHub configuration permitted by `docs/SiloUI-RELEASES.md`; values are not recorded.
- `cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --check`: passed.
- `git diff --check`: passed. Final branch status was clean.
- Focused tests: offline rekey 7 passed/1 ignored; real disposable APFS rekey prototype 1 passed; archive space preflight 1 passed; hardware-model bound 2 passed; imported host-key retry 1 passed. Logs are under `~/silo-probes/p3-macos-parity-2b/evidence/`.

## Probe diagnosis and live result

The earlier conclusion that the VM received no NAT lease is **refuted**. The old `~/silo-probes/p3-macos-parity-2/evidence/probe.log` records VM start at 06:02:42Z and the failure `guest SSH did not become ready` at 06:07:44Z. It records neither the lease address, slot inventory, nor SSH attempts. A later host DHCP record for that VM's exact MAC `02:69:f2:cf:7e:6e` showed `192.168.64.32`, expiring at 07:02:53Z; it was inspected at 07:45:47Z. **Inference:** using the observed one-hour lease duration, the lease was issued at about 06:02:53Z, during the old probe. The prior VM got a lease. Historical VM-slot contention cannot be determined from the old evidence, and the reason SSH readiness timed out remains unresolved.

For the rerun, all visible Silo Dev computers were stopped and no Virtualization VM or probe `silod` process was running. This track started one disposable Mac guest only. The guest used a 64 GiB APFS clone, 4 CPUs, and 8 GiB RAM. Its exact ID was `a7fee0ee-2c69-4d40-a212-58cc0da63ab8`, guest macOS 26.6.2 build 25G83; host macOS was 26.5 build 25F71. The matching lease was `192.168.64.33`; TCP/22 accepted connections 17 seconds after VM start.

The direct engine adapter probe confirmed an empty `/Users/silo/workspace` listing (`entries=0`), the local alias through the Dev helper, and a published guest listener on 49152 reachable at host loopback port 59891. This did not test a nonempty listing or file transfer. It used `target/verification/Silo Dev.engine.app/Contents/MacOS/silod`; **no rebuilt `.app` bundle was launched or inspected**. Silo Dev 0.11.1 was used to inspect/manage the guest. The first probe passed in 5.98 seconds. In a second shutdown-enabled run, Files, alias, and port checks passed, but an old assertion treated the guest's SSH connection close during shutdown as an error. The assertion was corrected and not rerun after the VM stopped.

The full method and evidence are in the [part 2b probe note](../probes/p3-macos-parity-2b.md). The old protected log was not modified. The disposable guest is stopped; Silo Dev remains open because it owns two unrelated stopped Linux test computers. Its clone is still registered and awaits confirmation before permanent deletion.

## Limits and next work

- The adapter probe is not end-to-end `files.list` parity: canonical dispatch for that route remains Linux-only in this slice. The alias probe verifies the local helper route, not the UI or a remote-device route.
- No live archive export/import round trip or imported-guest boot/login was run. The real-disk prototype proved offline account rekey only. SecureToken and volume ownership after the new password remain unqualified.
- Remote controller copying of owner-path archives over an authorized bounded SFTP stream remains the P3-connections transport gate described in §2.4. This work does not advertise archive bytes through JSON frames.
- The shutdown assertion correction needs a new one-VM rerun to qualify shutdown cleanup. A nonempty Files listing, file transfer, repeated boots, other guest builds, and installed-app behavior also remain unqualified.
- Permanent deletion of the stopped disposable guest remains pending action-time confirmation; no app exit or cleanup touched the two unrelated Linux guests.

**Next action:** confirm whether to permanently delete disposable guest `a7fee0ee-2c69-4d40-a212-58cc0da63ab8` and its 64 GiB APFS clone. After cleanup, qualify a post-rekey boot/login on a disposable guest before claiming archive-import parity.
