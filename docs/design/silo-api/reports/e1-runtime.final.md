E1 runtime extraction is complete and committed on `engine/e1-runtime`. The owned business modules have no Tauri references; Tauri remains in the command adapters and `main.rs` setup.

Commits: `88c52700`, `4d35692a`, `0c0e079b`, `5acd5481`, `eccb516e`.

`cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --check` and `git diff --check` passed. The filtered and full locked Cargo test runs could not reach the tests: compilation stops on seven unresolved `AppHandle` references in E2-owned `runtime/checkpoints.rs`. The worktree is clean.

The requested report, including remaining cross-track needs, is at [e1-runtime.md](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/e1-runtime.md).