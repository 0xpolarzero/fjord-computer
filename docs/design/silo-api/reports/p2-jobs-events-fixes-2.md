# P2 jobs and events fixes, pass 2

Date: 2026-10-14  
Silo worktree: `/Users/polarzero/silo-work/p2-jobs-events`  
Branch: `engine/p2-jobs-events`

## Changes

- Merged current Silo `main` at `fc0f286f` in merge commit `aac4a98c`, preserving the job-owned macOS admission path alongside main's parity changes.
- Export and import completion now use `jobs::publish_finished`, so failed terminal writes are retained for retry and suspend new job admission. The backup view and its job identity are captured under one lock; terminal results no longer take their ID from a successor journal.
- Push startup reconciliation copies a valid durable `PushOperation` back into a stale domain journal. If an immutable terminal outcome conflicts with a fallback projection, the registry outcome remains authoritative, the journal is repaired to `unknown`, and startup continues. Generic restart placeholders remain replaceable.
- Tauri runtime and lifecycle notices use the same native-only notification route as current `main`; deletion clears native notifications. The test that expected retained notice events from these native-only paths was replaced.
- macOS progress and terminal publications share a serialization lock. Progress checks that its job is still active and is not waiting for completion retry before publishing.
- Event backlog reservations count the exact length-prefixed socket frame: the four-byte frame length plus the JSON envelope, including escaped strings and sequence digits. `silod` uses the same envelope builder for frame serialization and size accounting.
- Added the Silo patch changeset at `app/SiloUI/.changeset/p2-jobs-events-recovery.md`.

## Red and green regressions

For engine cases, commands used this form with the named test filter:

```sh
CARGO_TARGET_DIR=/Users/polarzero/silo-work/p2-jobs-events/target CARGO_BUILD_JOBS=6 \
  cargo +1.94.0 test --manifest-path app/SiloUI/Cargo.toml --locked -p silo-engine <test-filter>
```

For Tauri notification cases, the same command used `-p silo-ui`.

| Finding | Regression | Red without the fix | Green with the fix |
| --- | --- | --- | --- |
| Original #5: backup completion persistence | `backup_completion_storage_failure_suspends_admission_until_retry` | Replacing `publish_finished` with `reconcile_finished` made the test fail: admission returned `Ok(Acceptance { created: true, ... })` instead of a storage error, so admission was not suspended. | Passed; the failed write is retained, retry commits the result, and admission resumes. |
| Additional P1 #1: export result under successor ID | `completed_backup_result_stays_bound_to_its_captured_journal_identity` | Reading the ID from the successor journal left `exports:previous-export` in `Waiting` instead of `Finished`. | Passed; only the captured prior identity is finished and the successor remains waiting. |
| Original #11: Tauri native-only delivery | `runtime_notice_uses_native_only_delivery` | Removing native delivery produced `[]` instead of the expected notice. | Passed; the adapter routes to native notification delivery only. |
| Original #11: Tauri notification withdrawal | `runtime_notice_withdrawal_uses_native_notification_clear` | Removing the native clear route produced `[]` instead of both computer IDs. | Passed; both IDs are cleared through the native notification adapter. |
| Additional P1 #2: stale push journal with durable success | `a_stale_pushing_journal_is_repaired_from_the_durable_terminal_job` | Disabling the durable terminal projection made startup fail with `Job push:durable-push-result already has a different terminal outcome.` | Passed; the succeeded result remains in the registry and replaces the stale journal row. |
| Additional P1 #2: stale push journal with durable error | `a_durable_push_error_is_kept_without_blocking_startup` | Propagating `RegistryErrorKind::Conflict` made startup fail with `Job push:durable-push-error already has a different terminal outcome.` | Passed; the durable error stays in the registry, the journal is repaired to `unknown`, and startup returns successfully. |
| P2 #4: progress after terminal finish | `stale_macos_progress_snapshot_is_not_published_after_job_finish` | Bypassing the active-job check published `operations.job.progress` after `operations.job.finished`. | Passed; only the terminal event is published. |
| P3 #5: exact backlog wire bytes | `backlog_byte_limit_counts_the_encoded_wire_envelope_exactly` | Restoring `event.name.len() + payload_bytes + 128` undercounted the framed message: computed `8,388,597` bytes versus the `8,388,608` byte limit. | Passed; an exact-limit frame is admitted and a frame one byte over creates a gap. The events module also passed `encoded_wire_size_tracks_json_escaping_and_sequence_digits` for escaped fields and sequence widths. |

The red runs temporarily reverted the specific route or guard, then restored it before the green run. During full-suite validation, the original crash-before-progress push regression also caught an intermediate attempt that treated generic restart placeholders as immutable. The final reconciliation distinguishes a replaceable placeholder from a conflicting committed outcome; all 14 `host_push_operations::tests::` tests then passed.

## Verification

- `CARGO_TARGET_DIR=... CARGO_BUILD_JOBS=6 cargo +1.94.0 test --manifest-path app/SiloUI/Cargo.toml --workspace --locked` — passed across the full workspace.
- `cargo +1.94.0 fmt --manifest-path app/SiloUI/Cargo.toml --all --check` — passed.
- `npm --prefix app/SiloUI run typecheck` — passed.
- `npm --prefix app/SiloUI run lint` — passed with existing warnings in `viewer-file-drop.tsx`, `computer-use-approval.tsx`, `use-file-transfers.tsx`, and `desktop_viewer_bench.js`.
- `npm --prefix app/SiloUI test` — passed: 266 files, 2,770 tests.
- Focused checks also passed: all 12 `events::tests::` tests and all 14 `host_push_operations::tests::` tests.

The tests used temporary registries, journals, and recording adapters. No Silo app or virtual computer was launched, and no live computer data was used.

## Commits

- `aac4a98c merge(engine): integrate main macOS parity`
- `44cc02c0 fix(engine): retain and bind backup job outcomes`
- `885dffc6 fix(engine): reconcile stale push journals from durable outcomes`
- `3be4f169 fix(tauri): restore native-only runtime notifications`
- `d7c0536e fix(engine): prevent macos progress after job finish`
- `1ffaf646 fix(engine): account complete event frames in backlog limits`
- `67695ea1 docs(silo-ui): note job and notification recovery fixes`

No commits were pushed.

## Spec deviation and handoff

The notification fix follows the explicit request to match current `main`: `TauriRuntimeHost` sends these runtime/lifecycle notifications through native-only delivery. This differs from 60 §4.2 and 95 A-27, which specify retained client notices and no engine OS notifications. The adapter behavior is intentionally aligned with `main` for these paths; other retained-notice sources are unchanged.

The registry now has a typed `Conflict` error for an immutable terminal outcome mismatch; `silod` maps it to the contract's `internal` code, and push recovery handles it without replacing the stored outcome. The event backlog and socket writer share `wire_event_envelope`; `SilodContext` must keep supplying its local device ID to the event bus. No API schema or method names changed.
