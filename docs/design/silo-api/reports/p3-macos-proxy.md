# P3 macOS proxy implementation report

Date: 2026-10-14  
Branch: `engine/p3-macos-proxy`  
Commit: `2c8d7d8c` (`feat(engine): add macOS credential-aware proxy`)

## Outcome

The host gateway, credential policy path, and guest bootstrap artifacts are implemented and committed. This branch is not yet live-qualified or ready to enable for newly provisioned macOS computers: the setup and legacy-migration callers belong to the parallel provisioning track and are not wired here. Ordinary Start fails closed when the persisted guest address or CA is missing.

## Implemented

- Added the macOS gateway helper with a datagram frame path and control channel. The engine supervises a gateway per computer and uses the patched MicroSandbox `SmoltcpNetwork` with `VZFileHandleNetworkDeviceAttachment` for credential-aware egress. The runtime still selects Apple NAT for computers with no assigned secret or GitHub policy.
- Added per-computer IPv4 allocation and route-conflict checks, guest network bootstrap, DNS configuration, and a bounded default `dig` path (`+time=2 +tries=1`). The guest bootstrap installs the route and proxy environment through launchd-managed scripts.
- Added per-computer CA storage and System keychain installation. The guest receipt already records the CA fingerprint and `proxyCATrusted` state. Bootstrap removes an inherited Silo CA by fingerprint before installing the current CA; the deletion command uses the macOS `security` CLI's positional keychain argument and verifies removal.
- Added macOS secret and GitHub policy operations using the existing host-side assignment and identity sources. Policy is scoped to a computer, restricts outbound hosts, injects the guest placeholders, and revokes active gateway connections when credentials or policy are removed or changed.
- Added staging, migration, and strict-read hooks so provisioning can stage the guest while it is reachable over temporary NAT, migrate an existing guest, and validate bootstrap state at ordinary Start.
- Added the `silo-ui` patch release changeset.

## Verification

| Check | Result |
| --- | --- |
| `CARGO_TARGET_DIR=/Users/polarzero/silo-work/p3-macos-proxy/target CARGO_BUILD_JOBS=5 cargo test --manifest-path app/SiloUI/Cargo.toml --workspace --locked` | Exit 0. `silo-api`: 27 passed; `silo-engine`: 2,261 passed, 30 ignored; `silod`: 69 passed; remaining integration and doc-test targets passed. |
| `cargo +1.94.0 fmt --manifest-path app/SiloUI/Cargo.toml --all -- --check` | Passed. |
| `sh app/SiloUI/src-tauri/guest/macos/test-network-bootstrap-config.sh` | Passed, including inherited-CA deletion/retry and invalid-fingerprint fixture cases. |
| macOS gateway unit tests | 17 passed against the patched helper source. |
| `npm --prefix app/SiloUI run runtime:prepare` | Passed; prepared the pinned MicroSandbox runtime and gateway helper. |
| `npm --prefix app/SiloUI run test:release` | 128 passed, 12 skipped. |
| `git diff --cached --check` on source changes | Passed. The unified-diff patch file was excluded because its space-prefixed blank hunk lines are required patch syntax. |

The guest CA deletion test substitutes a fixture `security` executable; it does not alter a host or guest keychain. All tests used local fixtures. No credentials were used.

## Integration blocker and live probe

`stage_guest_bootstrap` and `migrate_legacy_guest_bootstrap` are exported for the concurrent provisioning and launch-migration owners, but neither has a production caller on this branch. That wiring must happen before a new or legacy Mac can pass strict Start. I kept the edits within the requested network, secrets, GitHub, and new-module scope.

I did not clone or start a VM. Without the setup/migration caller, such a run would not exercise the integrated start path or establish the requested end-to-end evidence. Consequently, System keychain installation, resolver behavior inside a running macOS guest, DNS reachability, credential revocation over a live connection, and isolation with two simultaneous macOS computers remain unqualified. The gateway and policy unit tests establish only their fixture-level behavior; they do not substitute for the permitted live probe.

After the provisioning and migration owners wire the hooks, run the probe from `probes/proxy.md` under `probes/00-probe-rules.md`: one Dev-template clone at a time, synthetic credentials only, verify the no-credential NAT case and two-computer isolation, collect DNS and CA-trust evidence, then remove the clone and its temporary credentials.
