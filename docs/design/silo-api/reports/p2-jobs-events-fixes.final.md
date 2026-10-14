Merged `main` first as `cf35f080`, preserving the main-window audience mapping and per-engine settings scope. Fixed all 15 numbered findings, with reverted-red and restored-green regression evidence recorded in [p2-jobs-events-fixes.md](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/p2-jobs-events-fixes.md).

All requested gates passed: workspace Cargo tests, Rust formatting, npm typecheck, lint, and Vitest (2,764 tests). Lint reported six warnings. The Silo branch is clean at `71974e42`; nothing was pushed. The report is written but uncommitted in Lookout, whose `main` has other active changes.

The report also records the unnumbered contract gaps left for follow-up. No app or live computers were exercised.