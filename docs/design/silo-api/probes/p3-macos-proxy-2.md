# B-27 follow-up: Silo macOS proxy bootstrap

**Verdict: BLOCKED.** The live guest qualification did not reach a booted guest. Silo began one 8 GiB macOS installation from Apple's restore image. Free space reached 59 GB, so I cancelled it at the probe rules' 60 GB floor and removed the Dev-only computer and restore image. No guest-level claim is confirmed by this run.

## Scope and environment

This run follows [95 A-15 and B-27](../95-decisions.md), [95 §3](../95-decisions.md), and the selected route in [p3-b](../design/p3-b.md). The code path now stages the network helper, guest System-keychain CA, DNS/route configuration, and persisted host identity during provisioning. Existing installed computers use the launch-time migration before lifecycle recovery or start-at-launch. Ordinary Start remains fail closed.

- Host: macOS 26.5, build 25F71, arm64.
- Dev app: Silo Dev 0.11.1, built from `/Users/polarzero/silo-work/p3-macos-proxy`.
- MicroSandbox: 0.7.6, source commit `09df3d4b9d832adaede1fb9a198cfc660bfab8cd`, Rust 1.94.0.
- Bundle tested: `/Users/polarzero/silo-work/p3-macos-proxy/target/debug/bundle/macos/Silo Dev.app` (`org.silo.dev`).
- Synthetic-only credentials. A synthetic secret was typed into an unsaved Dev form draft, then discarded; it was not saved or sent to an external host. No external echo request ran.

Before creation, process and open-file scans showed no active macOS guest disk or VM attachment, and Dev had no macOS computer record. Idle `VMPalMachine --mcp-library` helpers were present with no VM files open. One probe computer at a time was used; no second computer was created.

## Attempt and disk stop

The Dev UI was used to create `p3-proxy-a` with 4 CPUs, 8 GiB memory, and a 64 GiB disk. Silo's form stated that it downloads about 20 GB of macOS from Apple and installs it. The install progressed while free space was monitored with `df -g /`:

| Observation | Progress | Free space |
| --- | ---: | ---: |
| Before creation | — | 87 GB |
| Restore image download | 66% | 80 GB |
| Restore image download | 85% | 75 GB |
| Guest install | 63% | 62 GB |
| Guest install, 15 seconds later | 78% on the next UI read | 59 GB |

At 59 GB I cancelled creation through Silo's confirmation dialog. Silo removed the in-progress computer. The completed restore image remained in the Dev cache at 19,772,231,540 bytes; no guest files were open. I removed that task-created restore image and verified the cleanup:

```text
ProductVersion: 26.5
BuildVersion: 25F71
arm64
0.11.1
/dev/disk3s1s1  926  11  90  12%
macos_computer_records=0
restore_image_files=0
silo_dev_process=stopped
vm_or_restore_open_files=none
```

The install timeline is `~/silo-probes/p3-macos-proxy-2/evidence/install-attempt.txt`. The final capture is `~/silo-probes/p3-macos-proxy-2/evidence/final-preflight.txt`; its source is `~/silo-probes/p3-macos-proxy-2/src/preflight.sh`. Test summaries are in `~/silo-probes/p3-macos-proxy-2/evidence/workspace-tests.txt`. The Silo Dev template and production app/data were not modified. The two stopped Linux Dev computers were not started or changed.

## Required live checks

| Check | Verdict | Evidence |
| --- | --- | --- |
| Proxy CA is present and trusted in the guest System keychain | **BLOCKED** | Installation did not finish; no guest keychain check ran. |
| Guest default DNS lookup works, without selecting a DNS server explicitly | **BLOCKED** | No guest shell or resolver check ran. |
| Placeholder substitutes only for an allowed HTTPS host | **BLOCKED** | The synthetic secret was never saved; no echo request ran. |
| Revoking a secret closes an already-open connection | **BLOCKED** | No guest connection was opened. |
| Two-computer isolation, sequentially | **BLOCKED** | Only one incomplete computer was created; no second computer was started. |
| Launch-only migration for an existing macOS computer | **BLOCKED** | Dev had no pre-existing macOS computer; the migration code was not exercised against a guest. |

The implementation's readiness check requires the active route and DNS state, explicit and default `dig`, native resolver checks, and HTTPS through System trust before FileHandle Start succeeds. Those checks were not reached in this run and do not replace the requested live probes.

## Spec impact and next evidence

B-27 remains **PARTLY**. This run adds no evidence for the guest CA, default DNS, allowed-host substitution, live revocation, sequential isolation, or launch migration. The prior B-27 report's DNS gap remains open.

A fresh Apple restore plus guest install consumed the available 27 GB above the 60 GB floor before guest provisioning completed. Resume the live checks only on a host with enough free space to complete restore and guest installation while retaining that floor, or with an approved probe flow that uses the existing template without modifying it.
