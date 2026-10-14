**Engine extraction is complete** on `engine/integration`. The worktree is clean, and the requested report is at [e-move.md](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/e-move.md).

The changes are committed in separate module groups, ending with `bea1396f`. Tauri-free services and their tests now live in `silo-engine`; Tauri command adapters and app-shell code remain in the UI crate. The standalone engine build passed, and its dependency tree contains no Tauri package.

Final checks passed: Rust workspace tests (2,315 passed, 30 ignored), formatting, typecheck, lint, and all 2,764 frontend tests. Lint reported six warnings; the standalone engine build reported 30 Rust warnings, detailed in the report.