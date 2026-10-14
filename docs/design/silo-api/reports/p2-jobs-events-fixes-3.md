# P2 jobs and events fixes, pass 3

Date: 2026-10-14  
Silo worktree: `/Users/polarzero/silo-work/p2-jobs-events`  
Branch: `engine/p2-jobs-events`

## Changes

- Export and import terminal paths now publish the completed domain view and durable job result before releasing the backup controller’s `busy` slot. Registration failures, worker completion, panic containment, and startup recovery share the publish-then-finish ordering.
- Startup recovery can replace only a tagged restart placeholder in the job registry with the recovered backup or import outcome. Acknowledged jobs and existing non-placeholder terminal outcomes remain immutable; pending outcome retries still use the same persistence path.
- macOS checkpoint completion now holds the job publication lock through terminal publication and removal of both the pending-completion guard and active checkpoint mapping. Fork continuation begins after the lock is released. Failed publication retains retry state.
- Added three Silo patch changesets. No wire types, method names, or schema changed.

The `backup_controller.rs` audit found no other accepted terminal path that releases `busy` before publication. Direct `finish` calls left in admission only handle a failed `recovery::begin`, before a job is accepted and before there is a terminal result to publish. The update guard is unrelated to transfer publication.

## Deterministic red and green evidence

All three regressions use explicit channels and test hooks at the reviewed interleaving. No test uses sleeps. For each red run, I temporarily restored the reviewed ordering/behavior, recorded the failure, restored the fix, and reran the same filter.

| Finding | Regression | Red without the fix | Green with the fix |
| --- | --- | --- | --- |
| P1: successor erases predecessor result | `export_worker_publishes_its_terminal_job_before_admitting_a_successor` and `import_worker_publishes_its_terminal_job_before_admitting_a_successor` | Both real worker tests failed because the successor was admitted while terminal publication was paused. | Both passed. The successor stays blocked until the predecessor’s finished job and operation result are published. |
| P2: restart placeholder hides recovered result | `startup_recovery_publication_replaces_the_restart_placeholder_seen_by_job_get` | With the old registry rule, actual `recovery::resume` logged `Job exports:<id> already has a different terminal outcome`; `job.get` still had no result and the regression failed. | Passed. `job.get` returned the recovered restore outcome after startup recovery. |
| P2: checkpoint progress after finish | `checkpoint_completion_removes_both_progress_guards_under_the_publication_lock` | With the reviewed lock scope, the test observed `operations.job.finished` followed by `operations.job.progress` and failed the event-order assertion. | Passed. Only the terminal event was published, both guards were removed, and the reviewed ordering failed without hanging. |

Focused red/green command filters used this command form:

```sh
CARGO_TARGET_DIR=/Users/polarzero/silo-work/p2-jobs-events/target \
CARGO_BUILD_JOBS=6 cargo +1.94.0 test \
  --manifest-path app/SiloUI/Cargo.toml -p silo-engine --locked <filter> -- --nocapture
```

## Verification

- `CARGO_TARGET_DIR=... CARGO_BUILD_JOBS=6 cargo +1.94.0 test --manifest-path app/SiloUI/Cargo.toml --workspace --locked` — passed (exit 0).
- `cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --check` — passed.
- `npm --prefix app/SiloUI run typecheck` — passed.
- `npm --prefix app/SiloUI run lint` — passed with existing warnings in `computer-use-approval.tsx`, `viewer-file-drop.tsx`, `desktop_viewer_bench.js`, and `use-file-transfers.tsx`.
- `npm --prefix app/SiloUI test` — passed: 266 files, 2,770 tests.
- Independent focused re-reviews of P1, P2, and P3 returned LGTM. P3 review specifically confirmed that the intentionally regressed schedule fails by assertion without hanging.

The Rust and frontend tests used temporary registries, fixtures, and recording contexts. No Silo app, virtual computer, or live computer data was used.

## Commits

- `62319c7d3a155e76bb5efb73f5579cf283dc03d7 fix(engine): preserve backup job outcomes`
- `8a0b9b11350078b36acca682b15eaae7a7786b91 fix(engine): serialize checkpoint completion progress`

No commits were pushed.

## Spec deviations and handoff

No spec deviations. Durable terminal outcomes remain available until acknowledgement, and recovery replaces only the explicit restart placeholder. P2-silod should preserve this placeholder marker and finish startup recovery before serving recovered job results. P2-tauri and Fjord clients need no schema or method-name changes; they will observe the recovered outcomes and will no longer receive checkpoint progress after finish.
