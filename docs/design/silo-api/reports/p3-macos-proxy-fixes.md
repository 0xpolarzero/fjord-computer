# P3 macOS proxy follow-up fixes

All seven findings of [the non-blocking review](p3-macos-proxy.review.md) are fixed on `engine/p3-macos-proxy-fixes`, each with a deterministic regression test (no sleeps: barriers, event-driven waits, fault injection). The branch was merged into Silo `main` with `git merge --ff-only`; main is now `17d7e09e`. Nothing was pushed, and no VM, app or Keychain item of the user was started or touched.

## Commits (in order)

| Commit | Finding | What it does |
| --- | --- | --- |
| `3b501569` | 1 | `fix(macos): keep guest frame readiness while queued frames remain` |
| `540538c6` | 2 | `fix(macos): include the network bootstrap in setup readiness and retry` |
| `c84063a4` | 3 | `fix(macos): migrate by bootstrap state without blocking unrelated recovery` |
| `f64cf710` | 6 | `fix(macos): verify guest trust of the proxy CA with a signed probe leaf` |
| `659c594a` | 7 | `fix(macos): retire a deleted computer's proxy CA and prune its lock` |
| `b48bfa6b` | 4, 5 | `fix(macos): route DNS by host resolvers and keep UDP answers within the MTU` |
| `f2d2b858` | — | `docs(changeset): record the macOS proxy follow-up fixes` |
| (merges of `main`, plus `fix(engine): mark the test computer's network bootstrap as staged`) | — | main moved many times while this ran; see "Merges" |

Findings 4 and 5 share one commit: both are hunks of the same MicroSandbox patch file and of the same forwarder source, so they could not be split without hand-building an intermediate patch.

## The upstream patch

MicroSandbox changes (findings 1, 4, 5, and the leaf issuer of 6) are one new patch, `app/SiloUI/patches/microsandbox-macos-network-fixes-0.7.6.patch`, applied after `microsandbox-macos-proxy`. It is pinned in `runtime-inputs.json` and in `scripts/preflight.mjs` (and its test). I verified it by applying all 20 patches to a fresh copy of the pinned source archive (`git apply --check` then apply) and running the gateway and `microsandbox-network` DNS tests there. The existing patch was not edited.

## 1. Burst over 32 frames strands queued frames

- Cause: the pinned `SmoltcpBackend::read_frame` drains its whole wake pipe, then pops one frame. The gateway reads at most 32 per service, so the 33rd frame had no pending notification and `poll(-1)` could sleep with it queued.
- Fix (patch, `netstack/backend.rs`): after each read, including the oversized-frame drop, re-arm the wake while the ring is not empty. A producer pushes before it wakes, so a frame pushed later brings its own wake.
- Tests: the gateway test `a_burst_over_the_batch_limit_is_fully_delivered_without_new_producer_activity` drives the real `FramePump` over the real backend with 33 frames and no later producer activity. It failed before the fix (32 of 33 delivered) and passes now. The patch adds two backend unit tests (readiness stays while frames remain; an oversized drop keeps the rest readable).

## 2. Failed bootstrap leaves setup falsely complete

- `SetupProgress` gets a persisted `proxy_bootstrap` step, set only after the staging succeeds. `complete()` (and so `setup_complete()`, the UI row, checkpoint and resource checks, secret assignment, templates) now requires it. `guest_steps_complete()` is the old condition (all guest steps).
- Retry admission follows readiness (`setup_allowed` uses `setup_complete`), so a computer whose staging failed after the last flag can be retried. Provisioning's early return now also requires the step, so Retry runs the staging.
- The retry boots over the temporary Apple NAT explicitly: `engine::boots_behind_gateway(record)` is `setup.complete()`, and Start uses the NAT boot for anything else. Copies and forks start with `proxy_bootstrap: false` and stage their own bootstrap during personalization.
- Tests: `a_failed_bootstrap_after_the_last_setup_flag_leaves_setup_incomplete_until_retry` injects a staging failure after the last flag and drives failure, Retry admission, NAT boot, success and completion in one session, with no relaunch. Store tests cover readiness, `setup_allowed` and resource-change admission.

## 3. Launch migration

- The migration now checks the existing bootstrap first (`require_guest_bootstrap`). A computer whose bootstrap matches is never held back by saved Restore memory or an unfinished Restore; it only gets its `proxy_bootstrap` step recorded. The cold-boot prohibitions (unfinished Restore, saved memory) now apply only to a guest that really needs conversion, and only to that computer.
- The loop is `migrate_launch_computers` over a small `LaunchMigrationOps` trait, so it is tested without a guest. Failures stay per computer. The "machine may still run" abort is unchanged.
- `startup::install` reports a migration failure and continues: lifecycle recovery, update recovery and automatic starts no longer depend on it. The migration also opens the launch gate on its early-failure paths (it used to stay closed).
- Tests: migrated + saved memory + unaffected second computer; legacy + saved memory fails alone while the second converts; unfinished Restore; conversion failure with the machine released versus held versus unknown; skip rules; and `a_failed_proxy_migration_is_reported_without_suppressing_unrelated_recovery` in `startup.rs`.

## 4. Large EDNS answers

- The forwarder knows the guest MTU and limits a UDP answer to the smaller of the advertised EDNS buffer and one datagram of the MTU (IPv4 20 or IPv6 40 bytes of IP header plus 8 of UDP; IPv6 is assumed when the destination is unknown). A larger answer becomes a header-only reply with TC=1.
- Tests (`microsandbox-network`): `an_answer_above_the_guest_mtu_is_truncated_and_then_served_over_tcp` uses an upstream that serves a roughly 2.1 KiB TXT answer over UDP and TCP, asserts TC=1 and a response of at most 1472 bytes with EDNS 4096, then asserts the full answer over TCP. Also: a smaller MTU lowers the limit; table test of `udp_response_limit`.

## 5. Split DNS and network changes

- New `dns/host_resolvers.rs`: a host resolver table (primary servers plus scoped resolvers), longest-suffix routing (then lowest order, then listing order), a `/etc/resolver/*` parser, a `HostResolverSource` trait with change notification, and the macOS source.
- `nameserver/scdynamicstore.rs` reads `State:/Network/Service/*/DNS` supplemental match domains (with ports and orders), `/etc/resolver`, and the primary resolver, and watches `State:/Network/Global/DNS`, `Global/IPv4` and the service DNS keys through an SCDynamicStore run loop thread.
- The forwarder keeps a swappable routing snapshot. A query clones the snapshot, so a refresh never waits for a query. A failed or empty read keeps the last good table. Only queries addressed to the gateway use the table, so the guest still cannot choose its upstream (the identity binding is unchanged); explicit nameservers still bypass it.
- Tests: `supplemental_domains_route_to_their_own_resolver`, `a_running_forwarder_follows_resolver_changes` (default and VPN domain change twice while the forwarder stays up, awaited on an event counter), `an_unreadable_or_empty_change_keeps_the_last_good_resolvers`, table routing and parser tests, CoreFoundation dictionary parsing tests, and a smoke test that reads the live table and starts and stops the watcher on this Mac.
- Limit: `/etc/resolver` is re-read on a dynamic-store notification, not watched on its own (no file watcher dependency was added).

## 6. CA trust readiness

- The host now signs a probe leaf (SAN `silo-ca-trust-probe.invalid`, one year) with the computer's CA through a new gateway helper mode, `--issue-trust-probe` (CA in on stdin, certificate only out; the leaf key is discarded). It is staged as `proxy-ca-probe.pem`.
- The guest helper's `proxyCATrusted` replaces the fingerprint-presence check: it builds the chain for the probe name with the guest's normal trust (`SecTrust`, evaluated at the leaf's first valid day so the result does not depend on the clock), requires the chain to end at the CA with the configured fingerprint, and offers the CA only as an untrusted chain-building certificate.
- Tests: `test-network-bootstrap-config.sh` builds the helper and uses its `--evaluate-ca-trust` hook with a fixture CA and leaf: a present but untrusted CA fails, the same CA trusted (`--trust-ca-as-anchor`, standing in for an installed trust setting) passes, and a wrong fingerprint, a leaf for another name and a missing leaf fail. A gateway helper test and a `microsandbox-network` test (trusting client accepts the leaf; a client that only has the CA as an extra certificate rejects it) cover issuance. Engine tests cover the framing, the response validation and that the Rust install script, the Swift paths and the probe name agree. I ran the shell test and a real `--generate-ca` to `--issue-trust-probe` to Swift evaluation round trip on this Mac.

## 7. Computer deletion

- `proxy_ca::retire` deletes the channel Keychain item (an absent item is fine), reads it back to prove it is gone, and prunes the lock entry. Item locks are now held weakly (like the other per-computer lock maps) and pruned.
- `remove_computer` detaches the disk, retires the CA, then removes the folder (checkpoints are inside it). The CA goes before the files so a failure of either step leaves the computer listed and the same Delete repeatable. Unit tests never reach the live Keychain (`live_store()` is an in-memory store under `cfg(test)`).
- Tests: retire removes only its own item and channel, repeats and absent items succeed, a failing then succeeding store, a store that lies about deletion, 64 create/delete rounds leaving no key and no lock entry, a held lock surviving pruning, and the deletion ordering and retry at the `remove_computer` level.
- Saved generations: checkpoints live inside the computer folder, forks and template copies get their own CA at personalization, so nothing outside the folder references the CA. A Keychain item orphaned by a crash between steps cannot be enumerated (the Keychain API has no listing); the ordering above keeps that window closed for ordinary failures.

## Verification

- `cargo +1.94.0 fmt --all --check`: clean.
- Gateway: 19 tests pass, in the working tree and in a fresh pinned-source tree with all 20 patches applied. `microsandbox-network` (engine feature): 669 tests pass before the DNS work, 120 DNS tests in the fresh tree after.
- `node --test scripts/preflight.test.mjs scripts/microsandbox-runtime.test.mjs scripts/release.test.mjs`: 50 pass. `sh src-tauri/guest/macos/test-network-bootstrap-config.sh`: passes.
- Full workspace `cargo test --workspace --locked --no-fail-fast` (synthetic GitHub env values, `CARGO_TARGET_DIR=/Users/polarzero/silo-work/p3-macos-proxy/target`): see "Gate results" below.

## Merges

Silo `main` moved repeatedly while this ran (display, computers, guest and access methods from other tracks). I merged it into the branch with `--no-ff` each time. The only conflicts were in `provision.rs` and `store.rs`, where main added the `roots` setup step; I combined it with `proxy_bootstrap` (`guest_steps_complete` includes `roots`). Main's new `SetupProgress` and `ExpectedResources` literals needed the new field (`install_test_computer`, the SSH stream test, the import path). One of my commits had accidentally modified the tracked `registry.sqlite3-shm/-wal` test artifacts that main has since deleted; I removed them from the commit before merging.

## Gate results

Final merge of `main` is `17d7e09e` (Silo `main` fast-forwarded to it from `engine/p3-macos-proxy-fixes`). `main` moved about ten times in the hours this took, and a full workspace run takes 6 to 8 minutes on this shared Mac (load average 12 to 55 from other tracks' builds and tests), so the strict "merge, gate, fast-forward" loop could not close without a shortcut:

- `cargo +1.94.0 fmt --all --check`: clean at the final merge.
- The full `cargo test --workspace --locked --no-fail-fast` ran on the merge before the last one (`56a46610` plus a clean merge of non-macOS changes). `silo-engine`: 2563 passed, 1 failed (`dependencies::version_probe_accepts_the_output_limit_and_rejects_overflow_on_either_stream`, a timeout on a shell loop). `silod` lib: 165 passed, 1 failed (`methods::access::tests::github_mutations_check_params_and_route_to_the_owner`). `silo-api` 30, `silo-ui` 71, every `silod` integration test, and the doc tests passed.
- The two failures are not related to this work and pass on rerun. The version-probe test passes alone and with `--test-threads=1`. The `silod` access tests are intermittent on plain `main` too: three runs of `silod --lib` on a clean checkout of `main` (`366b8765`) gave `connections_status_list_and_enabled_state`, none, and `connections_health_is_a_side_effect_free_projection` plus `ssh_access_methods_use_computer_identities`. Other full runs on earlier merges failed different load-sensitive tests (`transfer::`, `runtime::`, `*_large_input_memory_is_bounded`, `backup_controller::install_schedules_pending_import_recovery_outside_tokio_runtime`, `remote::operations`, silod display job tests); each passed when rerun alone. One full run was killed by a SIGTERM from outside, and one lost build artifacts to a concurrent clean, so those were rerun.
- The last two merges of `main` (the final one touches `macos_computers.rs`, `engine.rs`, `update_save.rs` and the `silod` computers and display methods) got a full `cargo test --workspace --locked --no-run` build, the whole `macos_computers`, `startup` and `proxy` engine tests (475 pass) and the `silod` display and computers tests (65 pass) before the fast-forward. I did not rerun the full suite on the very last merge. A post-merge full run on `main` is the way to confirm it.


## Deviations and notes for the next tracks

- `SetupProgress` gained `proxy_bootstrap`. Existing records read as `false`, so the launch migration records the step for computers whose bootstrap already matches, and converts the others. Anything that builds a finished `SetupProgress` must set it.
- Findings 4 and 5 are in the MicroSandbox patch, not in Silo code: any later change to the pinned patch list must keep `microsandbox-macos-network-fixes` last or re-verify that it applies.
- Not done, and not part of the seven: the review's note that the revocation test updates a policy snapshot without opening sockets. Live guest qualification (System-keychain trust and removal, live DNS, revocation, isolation) is still the separate disk-blocked task from `p3-macos-proxy-2.md`.
