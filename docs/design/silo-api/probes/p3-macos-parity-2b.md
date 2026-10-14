# P3 macOS parity, part 2b: live probe

Run date: 2026-10-14. Host: macOS 26.5, build 25F71. Silo Dev: 0.11.1. Disposable guest: macOS 26.6.2, build 25G83. The pinned MicroSandbox runtime is 0.7.6; the macOS guest checks below called Silo's Apple Virtualization adapters directly and did not exercise MicroSandbox.

## Verdicts

| Probe | Verdict | Observed result |
| --- | --- | --- |
| Previous run's NAT diagnosis | REFUTED | The claim that the VM received no lease is contradicted by the host DHCP lease record matching its exact MAC. The old failure was “guest SSH did not become ready”; its harness did not log the looked-up address, slot inventory, or SSH probe attempts. The record expired at 07:02:53Z, later than the old run (06:02:42–06:07:44Z). **INFERRED:** using the observed one-hour lease duration, it was issued around 06:02:53Z and was valid throughout the SSH wait. The cause of the SSH readiness timeout is unresolved. |
| Other VM held a slot | PARTLY | The old run recorded no slot inventory, so historical contention cannot be assigned. Before the rerun, the visible Silo Dev computers were stopped and the process check found no running Virtualization VM or probe `silod`; the single disposable Mac VM was the only guest started by this track. |
| DHCP lookup | CONFIRMED for the rerun | Matching the VM's pinned MAC returned `192.168.64.33`; the lease was valid and TCP/22 accepted connections 17 seconds after VM start. This makes a general DHCP lookup defect unlikely, but does not identify the old SSH timeout's cause. |
| Files workspace listing | CONFIRMED for one guest | The adapter listed `/Users/silo/workspace` successfully. It was empty (`entries=0`, `next_page=false`); no transfer or nonempty-directory behavior was tested. |
| Published guest port | CONFIRMED for one guest | `lsof` discovery found a temporary guest listener on 49152. The owner published it through the SSH tunnel on host loopback port 59891; the API state was `reachable`, and a host TCP connection succeeded. A second shutdown-enabled run repeated the checks on host port 60719 before its cleanup assertion failed. |
| Local SSH alias | CONFIRMED for one guest | `ensure_ssh_alias` returned `silo-a7fee0ee-2c69-4d40-a212-58cc0da63ab8` through the exact Dev `silod` helper; the existing Include file was unchanged. The probe exercised the engine adapter and helper, not the UI or a remote-device route. |

The earlier `~/silo-probes/p3-macos-parity-2/evidence/probe.log` remains unchanged. Its exact failure was `fatal=guest SSH did not become ready` at 06:07:44Z. A later read of the DHCP record for MAC `02:69:f2:cf:7e:6e` showed address `192.168.64.32` and expiry 07:02:53Z; the record was inspected at 07:45:47Z, 2,574 seconds after expiry. **INFERRED:** with the observed one-hour lease duration, the lease was issued at about 06:02:53Z, during the old probe's SSH wait. The old probe did get a NAT lease. The available evidence does not distinguish guest sshd readiness, a transient address/route issue after acquisition, or a harness readiness bug. The matching code is `~/silo-probes/p3-macos-parity-2/src/lease_monitor.py` (reads `/var/db/dhcpd_leases`, normalizes and matches the exact MAC, validates IPv4 and expiry, then tests TCP/22); its two parser unit tests pass. The command transcript and raw monitor output for the later lookup were not retained, so its exact flags cannot be reconstructed.

## Method and evidence

The live test source is `app/SiloUI/src-tauri/engine/src/macos_computers.rs`, test `live_probe_files_ports_and_local_ssh_alias`. The test used a disposable Dev computer with UUID `a7fee0ee-2c69-4d40-a212-58cc0da63ab8`, 4 CPUs, 8 GiB RAM, a 64 GiB APFS-cloned disk, and MAC `02:b0:52:be:6f:20`. It started a temporary `nc` listener through the guest alias and restored the prior port configuration on drop. The exact owner helper was `target/verification/Silo Dev.engine.app/Contents/MacOS/silod`.

The runner is `~/silo-probes/p3-macos-parity-2b/src/run_live_probe.sh`. Its cargo invocation was:

```sh
env CARGO_TARGET_DIR=/Users/polarzero/silo-work/p3-macos-parity-2/target \
  CARGO_BUILD_JOBS=5 [synthetic GitHub build settings] \
  SILO_MACOS_LIVE_PROBE_ID=a7fee0ee-2c69-4d40-a212-58cc0da63ab8 \
  SILO_MACOS_LIVE_PROBE_APP_DATA='/Users/polarzero/Library/Application Support/org.silo.dev' \
  SILO_MACOS_LIVE_PROBE_HOME=/Users/polarzero \
  SILO_MACOS_LIVE_PROBE_HELPER='/Users/polarzero/silo-work/p3-macos-parity-2/target/verification/Silo Dev.engine.app/Contents/MacOS/silod' \
  cargo +1.94.0 test --manifest-path app/SiloUI/src-tauri/Cargo.toml \
  -p silo-engine --lib live_probe_files_ports_and_local_ssh_alias \
  -- --ignored --nocapture --test-threads=1
```

The run used explicit synthetic GitHub build settings permitted for native tests; their values are not recorded. The first run completed successfully (5.98 seconds). Its captured output was:

```text
live_files entries=0 next_page=false
live_alias alias=silo-a7fee0ee-2c69-4d40-a212-58cc0da63ab8 include_not_changed=true
live_port guest=49152 host=59891 state=reachable
test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 2339 filtered out; finished in 5.98s
```

The first run's complete console transcript was not retained. The subsequent shutdown-enabled run is retained at `~/silo-probes/p3-macos-parity-2b/evidence/live-macos-probe.log`; its Files, alias, and port assertions passed, then its shutdown SSH command closed the host connection and the older assertion treated that close as a failure. Silo Dev showed the guest Stopped afterward. The shutdown assertion was corrected to accept the guest-initiated SSH close, but that correction was not rerun because the VM was already stopped. The runtime helper log is `~/silo-probes/p3-macos-parity-2b/evidence/silod-runtime.log`.

Before the probe, Silo Dev showed only stopped computers and the host process check found no running Virtualization VM. The run used at most one Mac VM. Afterward the process check found no Virtualization VM and Silo Dev showed the disposable guest Stopped. Host free space was 72 GiB, above the 60 GB floor. The Dev app remains open because it also owns two unrelated stopped Linux test computers. The disposable Mac guest's 64 GiB clone is still registered under Silo Dev pending the required action-time confirmation for permanent deletion; the protected template and production app/data were not touched.

## Spec impact and limits

This gives one-live-guest evidence for the adapters related to p3-b §2.2 (workspace listing), §2.3 (port discovery/publication), and the local alias path in `docs/design/silo-api/50-access-network-files.md` (`guest.sshAlias.ensure`). It confirms a working NAT lease and SSH on one 25G83 guest. It does not qualify a nonempty Files listing, file transfer, controller-side port relay, repeated boots, other guest builds, or installed-app behavior. The `files.list` UI/canonical route was not exercised; that dispatcher is Linux-only in this slice, so this result is adapter evidence rather than end-to-end API parity.
