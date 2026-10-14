# P2 jobs and events fixes

## Result

Merged Silo `main` into `engine/p2-jobs-events` first, then fixed all 15 numbered findings in [p2-jobs-events.review.md](p2-jobs-events.review.md). The merge commit is `cf35f080` with parents `e1b2e7b2` and `f9f0d9ea`. It retains the main-window `Audience::Client("main")` mapping and per-engine settings state. The runtime progress regression now asserts that both the canonical `operations.job.progress` event and the legacy Tauri event still target the main client.

At merge time `main` pointed to `f9f0d9ea`; it later advanced to `fc0f286f`. No later commits were merged. No production app, live computers, or release artifacts were exercised. Nothing was pushed or released.

## Findings and regression evidence

The red logs record the specified behavior temporarily reverted; the green logs show the restored fix. Main-branch evidence is under `/Users/polarzero/silo-work/p2-jobs-events/target/verification/`. Registry follow-up evidence is under `/Users/polarzero/silo-work/p2-jobs-events-registry/app/SiloUI/src-tauri/target/verification/`.

1. **Upload conflict continuation:** the Replace/Keep-both continuation now uses a fresh transfer id and updates progress, toast, and cancellation ownership. Regression: `asks before replacing and sends the chosen policy`. Red: `finding-01-upload-conflict-reverted.log`; green: `finding-01-upload-conflict-restored-green.log`.

2. **Push crash recovery:** startup tags recovery placeholders and reconciles waiting or running push claims from the journal. An unreadable journal records an `Internal` unknown outcome without preventing `silod` from binding. Regressions: `startup_tags_and_reconciles_a_push_claimed_before_a_crash` and `an_unreadable_push_journal_records_uncertainty_without_blocking_startup`. Red: `finding-02-push-recovery-reverted.log`, `registry-startup-placeholder-reverted.log`, `registry-corrupt-push-journal-reverted.log`; green: `registry-startup-placeholder-restored.log`, `registry-corrupt-push-journal-restored.log`.

3. **macOS lifecycle result:** terminal jobs now use the actual command `Result`; a stopped row snapshot cannot turn a failed Start or Stop into success. Regression: `failed_lifecycle_command_is_not_overridden_by_the_stopped_row_snapshot`. Red: `macos-real-result-red.log`; green: `macos-real-result-restored-green-final.log`.

4. **Accept before effects:** macOS work obtains durable job acceptance before launching effects. First-action recovery is deferred until the creation or lifecycle job is accepted. Regressions: `macos_job_acceptance_failure_prevents_the_effect`, `macos_create_acceptance_precedes_first_restore_recovery`, and `macos_remote_lifecycle_acceptance_precedes_first_restore_recovery`. Red/green pairs: `macos-allocate-before-effect-reverted-red-final.log` / `macos-allocate-before-effect-restored-green-final.log`, `macos-create-acceptance-before-recovery-reverted-red.log` / `macos-create-acceptance-before-recovery-restored-green.log`, and `macos-first-action-recovery-reverted-red.log` / `macos-first-action-recovery-restored-green.log`.

5. **Retain outcomes and suspend admission:** completion results remain in memory when persistence fails; conflicting completion and acknowledgement cannot replace or delete them, and new job admission stays closed until persistence succeeds. `operations.job.get` retries and returns the retained outcome. Regressions: `failed_finish_is_retained_and_closes_admission_until_it_can_be_persisted`, `a_later_conflicting_finish_cannot_replace_a_retained_completion`, `acknowledgement_is_rejected_while_another_outcome_is_pending`, and `operations_job_get_retries_pending_completion_before_reading`. Red/green evidence: `finding-05-persistence-reverted.log`; registry `registry-conflicting-finish-reverted.log` / `registry-conflicting-finish-restored.log`, `registry-ack-suspension-reverted.log` / `registry-ack-suspension-restored.log`, and `registry-get-retry-reverted.log` / `registry-get-retry-restored.log`. The macOS retry integration also failed when temporarily reverted (`integration-fork-retry-reverted-red.log`) and passed when restored (`integration-fork-retry-restored-green.log`).

6. **Atomic export cancel:** journal identity validation and token cancellation now share the same synchronization boundary, so a stale cancel cannot stop a successor export. Regression: `a_stale_export_cancel_cannot_cancel_the_successor_token`. Red: `export-cancel-atomic-reverted-red-final.log`; green: `export-cancel-atomic-restored-green-final.log`.

7. **Subscribe response ordering:** subscription reply reservation, event queueing, and activation now use one ordered boundary; events cannot arrive before their subscribe reply. Regression: `subscribe_reply_queues_before_concurrent_event_fanout_and_activation`. Red: `delivery-7-subscribe-order-concurrency-reverted-red.log`; green: `delivery-7-subscribe-order-concurrency-green.log`.

8. **Notice projection barrier:** notice mutation, same-key publication, snapshot capture, and response enqueue are ordered through one projection boundary. Regression: `notice_snapshot_barrier_and_same_key_publication_share_one_projection`. Red: `delivery-8-notice-barrier-reverted-red.log`; green: `delivery-8-notice-barrier-green.log`.

9. **Outcome size budgets:** job outcomes are stored and retrieved in bounded UTF-8-safe chunks. Completion events mark chunked results, and oversized event enqueue returns a bounded error instead of silently losing the reply. Regressions: `large_outcomes_reassemble_from_utf8_safe_chunks_of_the_stored_json` and `oversized_job_completion_events_reference_the_chunked_durable_outcome`. Red: `finding-09-chunk-budget-reverted.log`, `finding-09-event-marker-reverted-red.log`, `delivery-9-oversized-fallback-reverted-red.log`; green: `finding-09-event-marker-restored-green.log`, `delivery-9-oversized-fallback-green.log`.

10. **macOS cancel semantics:** generic cancellation removes a waiting gate entry, but admitted creation remains non-cancellable through `operations.cancel`; users retain the existing Delete path. Regressions: `generic_cancel_of_admitted_creation_does_not_delete_it` and `a_waiting_macos_job_can_be_cancelled_before_its_effect`. Red: `macos-cancel-semantics-reverted-red-final.log`; green: `macos-cancel-semantics-restored-green-final.log`.

11. **Tauri toast behavior:** canonical notices remain available to API clients without adding or changing the existing Tauri toast delivery. Regression: `engine_notice_retains_api_notice_and_preserves_the_tauri_toast_event`. Red: `tauri-toast-legacy-preservation-reverted-red.log`; green: `tauri-toast-legacy-preservation-restored-green.log`.

12. **Serialized sequence and fanout:** sequence allocation and fanout now share one serialized order, so all subscribers observe events in sequence order. Regression: `engine_sequence_and_fanout_share_one_serial_order`. Red: `delivery-12-sequence-reverted-red.log`; green: `delivery-12-sequence-green.log`.

13. **Shared backlog reservations:** an event keeps its backlog reservation while moving from the engine bus into the socket queue, releasing it only after write or discard. Regression: `socket_event_queue_keeps_the_shared_backlog_reservation`. Red: `delivery-13-socket-reservation-reverted-red.log`; green: `delivery-13-socket-reservation-green.log` and `delivery-13-engine-reservations-green.log`.

14. **NotCancellable code:** typed registry errors preserve the contract mapping to `internal` instead of `busy`. Regression: `not_cancellable_uses_the_contract_internal_error_code`. Red: `finding-14-not-cancellable-reverted.log`; green: `delivery-silod-context-final-green.log`.

15. **Drop finished-job closures:** terminal commit removes the job's cancel handler as well as active-key and gate mappings. Regression: `finishing_a_job_drops_its_cancel_handler_before_acknowledgement`. Red: `finding-15-drop-handler-reverted.log`; green: `delivery-engine-events-final-green.log`.

## Commits

- `cf35f080` merge: main into engine/p2-jobs-events
- `318699d6` fix(engine): retain and retrieve completed job outcomes
- `8b2ada1b` fix(silod): preserve typed job error mapping
- `95725cfc` fix(engine): serialize event projection and retain backlog
- `7eae2385` fix(silod): order replies and bound event frames
- `0708f4f8` fix(engine): bound oversized job completion events
- `30562d4f` fix(engine): track macOS checkpoint operation jobs
- `e567ad39` fix(engine): accept lifecycle jobs before macOS recovery
- `70d946d1` fix(engine): retain pending outcomes across recovery
- `e08743d1` fix(silod): retry retained outcomes from job lookup
- `fa516cc2` style: apply Rust 1.94 formatting
- `5d22e43a` fix(engine): retry retained outcomes before macOS continuation
- `71974e42` fix(engine): document lifecycle and export job behavior

Each Silo user-visible fix has a patch changeset. Large completion events carry the `outcomeChunked` marker; downstream clients must retrieve those outcomes through chunked `operations.job.get`.

## Verification

All final gates passed on the integrated branch. Cargo used Rust 1.94.0, `CARGO_TARGET_DIR=/Users/polarzero/silo-work/p2-jobs-events/target`, six build jobs, and synthetic GitHub App values permitted for native tests by the release guide.

- `cargo +1.94.0 test --manifest-path app/SiloUI/Cargo.toml --workspace --locked --quiet` — passed. The engine suite reported 2,283 passed and 30 ignored; all other workspace test groups passed.
- `cargo +1.94.0 fmt --manifest-path app/SiloUI/Cargo.toml --all --check` — passed after the formatting-only commit.
- `npm --prefix app/SiloUI run typecheck` — passed.
- `npm --prefix app/SiloUI run lint` — passed with six warnings.
- `npm --prefix app/SiloUI test` — 266 files and 2,764 tests passed.
- Focused upload-conflict continuation test — 1 passed.

Final gate logs are in `target/verification/final-workspace-cargo-locked.log`, `final-fmt-check.log`, `final-typecheck.log`, `final-lint.log`, and `final-vitest.log` in the Silo worktree. Focused per-finding logs listed above are ignored verification artifacts and were not committed.

## Spec notes and handoff

- The implementation follows 95 §3: no old-name aliases or compatibility paths were added. Populated registry schema-v2 data is rejected without mutation; any future released-data conversion must run through the existing launch `runtime_migration` path.
- An unreadable push journal produces a durable `Internal` unknown outcome and does not block socket startup. This records uncertainty; it does not claim that the push completed or failed.
- The review's unnumbered contract gaps remain follow-up work: register the log-export and GitHub cancellation adapters; add autonomous launch and migration job adapters; make setup/transfer retries attach to an existing identity; and resolve the fingerprint/transport claim gaps. These were outside the 15 numbered findings.
- Tests used fixtures, temporary directories, and injected SQLite failures. They do not establish live computer health, two-device behavior, or installed-app behavior. No app was launched, no live user data was used, and no push, release, version bump, or tag was made.
