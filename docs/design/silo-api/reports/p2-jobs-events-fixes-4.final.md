Implemented both P2 fixes and audited the recovery and failure paths in `backup_controller.rs` and `jobs/registry.rs`.

- `exports.changed` now reports the unavailable failed result while recovery is still pending, matching the state after `busy` is released. Successor handoff behavior remains intact.
- Provisional job outcomes stay replaceable through a storage retry, so startup reconciliation can apply the journal’s authoritative result.
- The regressions were demonstrated red before the fixes and green after. They use pause hooks and channel coordination, with no sleeps. A registry test also covers a simulated SQLite write failure and retry.

**Verification passed:** full locked Cargo workspace tests with the documented synthetic GitHub test configuration, Rust formatting, npm typecheck, lint, and tests (266 files, 2,770 tests). Lint reported six warnings in unrelated files. The independent review returned LGTM.

Commits:

- Silo: `17e6d50b` — `fix(engine): keep pending recovery outcomes replaceable`
- Lookout report: `91aec6ea` — `docs(engine): record P2 jobs-events recovery fixes`

The [fixes report](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/p2-jobs-events-fixes-4.md) records the regression evidence and gate results. The Silo worktree is clean; unrelated pre-existing Lookout changes were left untouched. No push was performed.