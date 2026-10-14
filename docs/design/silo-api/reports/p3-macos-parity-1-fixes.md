# P3 macOS parity fixes

Implemented all seven findings from `p3-macos-parity-1.review.md` on `engine/p3-macos-parity`.

## Changes

1. **Queued creation cancellation:** cancellation now requests abort while preserving the incomplete computer's folder, saved record, and inventory row. Only explicit Delete removes it.
2. **Quit during provisioning:** Quit closes macOS admission and signals active creation, setup, and checkpoint workflows before waiting for the device shutdown gate. Disk detach still waits until workflow ownership is released.
3. **Checkpoint metadata:** checkpoints record developer-tools readiness and fingerprint. Restore and interrupted-restore recovery re-derive these fields from checkpoint metadata; missing fields clear readiness and the fingerprint.
4. **Stale tools Retry:** setup readiness now includes developer-tools freshness. A completed computer with a stale tools fingerprint is exposed as incomplete, can enter setup again, and reaches the existing provisioning decision to repair tools.
5. **Queued launch Start:** startup cancellation is passed through the startup service to macOS Start. Waiting for the computer lane is cancellable, and the launch rechecks startup cancellation and shutdown admission before booting.
6. **Resource save atomicity:** a failed record save restores the previous on-disk bytes. The registry reconciles from the persisted record on failure, so memory and disk agree even if rollback itself cannot be completed.
7. **CLT payload repair:** matching package receipts no longer skip installation when Git, Swift, Clang, the SDK, or the compile/run readiness probe is unhealthy. The installer repairs the locked packages.

The regression tests below were observed failing before their fixes and passing afterward:

| Finding | Regression test |
| --- | --- |
| Queue cancellation | `cancelling_a_queued_creation_keeps_its_folder_record_and_inventory_row` |
| Quit cancellation | `quit_aborts_a_blocked_workflow_before_waiting_for_the_shutdown_gate` |
| Checkpoint restore | `restoring_a_pre_tools_checkpoint_clears_tools_readiness_and_fingerprint` |
| Stale-tools Retry | `stale_developer_tools_make_a_complete_computer_retryable_through_provisioning` |
| Queued launch Start | `a_queued_launch_start_skips_boot_after_startup_cancel_or_quit` |
| Resource save | `failed_resource_save_rolls_back_disk_registry_and_reload_state` |
| CLT payload repair | `matching_clt_receipt_does_not_skip_reinstall_when_payload_is_missing` |

## Commits

- `52ec144d` `fix(engine): preserve queued macOS creation on cancel`
- `09982e78` `fix(engine): abort macOS provisioning before Quit`
- `84e0c96d` `fix(engine): restore developer tools metadata from checkpoints`
- `c0121d1b` `fix(engine): retry setup for stale developer tools`
- `6475cb78` `fix(engine): cancel queued launch starts during shutdown`
- `fc0f286f` `fix(engine): keep resource saves atomic with the registry`
- `8e144826` `fix(engine): repair missing developer tools payloads`

The user-facing behavior changes have patch changesets in `app/SiloUI/.changeset/`.

## Verification

- `cargo +1.94.0 test --manifest-path app/SiloUI/Cargo.toml --workspace --locked` — passed on the final implementation. The run used the synthetic GitHub build inputs permitted for native tests and the requested `CARGO_TARGET_DIR` and `CARGO_BUILD_JOBS=5`.
- `cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --check` — passed.
- `git diff HEAD --check` — passed.
- The CLT repair test and `zsh -n app/SiloUI/src-tauri/guest/macos/silo-developer-tools.zsh` — passed.

An earlier full test attempt encountered a missing generated Tauri permissions cache, which was rebuilt under `target/`. A subsequent full run had one timeout in the unrelated `dependencies::tests::version_probe_accepts_the_output_limit_and_rejects_overflow_on_either_stream` test; that test passed in isolation, and the repeated full workspace run passed. No application bundle or VM was launched, and the tests used fixtures and temporary directories rather than live computer data. The CLT test exercises the installer decision helpers with a simulated payload; it does not verify package installation on a live macOS guest.

## Spec deviations and next-track notes

No implementation deviations from the spec or review fixes. `StartupServices::start_at_launch` and the macOS engine adapter now accept the startup cancellation token, so downstream changes should preserve that argument and the post-queue shutdown check. Checkpoint metadata missing the new tools fields is treated as incomplete by design. The frontend already maps `setupComplete` to the Retry setup action; its field now reflects developer-tools freshness. Live CLT installation, network failure recovery, and VM boot behavior remain outside this fixture-based verification.
