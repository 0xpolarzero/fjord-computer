Fixed the two recovery regressions on Silo branch `engine/p2-jobs-events` in commit `17e6d50b` (`fix(engine): keep pending recovery outcomes replaceable`).

- `backup_state` distinguishes the matching recovery worker's real `Running` view from its provisional failed result. While terminal publication still holds `busy`, `exports.changed` reports the state that remains after `finish`: unavailable, with the failed result and retry guidance. A predecessor terminal view still yields to a pending successor journal during handoff.
- Job results published while the matching domain journal remains pending are provisional. The registry keeps the recovery placeholder flag through a storage retry, so startup reconciliation can replace the provisional failure with the journal's authoritative outcome. Ordinary committed job outcomes remain immutable.
- Audited recovery, failure, panic, registration failure, pending cleanup, startup reconciliation, and storage retry paths in `backup_controller.rs` and `jobs/registry.rs`. These fixes cover the shared publication projection and durable registry retry path; no other instance of either pattern remained.
- Both new end-to-end regressions use the terminal publication pause hook and channel coordination, with no sleeps. The registry persistence-retry regression injects a SQLite trigger failure.

Regression evidence:

- Before the projection fix, `pending_recovery_publishes_the_state_that_remains_after_busy_is_released` observed `availability=available` and `operation.kind=running` in the event, while the post-finish state was `availability=unavailable`, `operation.kind=result`, `outcome=failed`. After the fix, the event payload equals the state after `busy` is released.
- Before provisional completion, `a_pending_recovery_result_remains_replaceable_by_startup_reconciliation` failed with `Job exports:<id> already has a different terminal outcome.` After the fix, startup reconciliation replaces the provisional failure with the successful result.
- `provisional_recovery_finish_stays_replaceable_after_a_storage_retry` confirms the replaceable flag survives a failed SQLite write and retry, then permits authoritative reconciliation.

Verification passed:

- Full locked Cargo workspace test suite, using the release guide's synthetic GitHub configuration for native unit tests.
- `cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --check`
- `npm --prefix app/SiloUI run typecheck`
- `npm --prefix app/SiloUI run lint` (passed with six existing warnings in unrelated files)
- `npm --prefix app/SiloUI test` (266 files, 2,770 tests passed)
- `git diff --check`

No spec deviations or wire schema changes. The existing `exports.changed` event now reflects the true pending recovery status at publication time. The Silo commit includes a patch changeset. No push was performed.

The read-only review returned LGTM. The Silo worktree is clean after commit. The Lookout repository had unrelated pre-existing changes; only this report is included in its commit.
