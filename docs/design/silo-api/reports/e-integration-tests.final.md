Added the regression tests and committed them as **`f9f0d9ea`** (`test(engine): cover main-thread lookup and progress audiences`). The integration worktree is clean.

Both fail-before checks failed as intended: bypassing the main-thread runner failed the Finding 4 tests, and restoring `Audience::All` failed all four publication-site tests, covering the five progress events. After restoring the fixes, the focused tests passed. I also replaced Finding 9’s 50 ms negative wait with a positive lock-contention handshake.

The full locked workspace tests and Rust formatting check passed. The run reported API 27, engine 2,240 passed / 30 ignored, Silo UI 69, silod 30, and handshake 1. No app or computer was launched.

Wrote the evidence report at [e-integration-tests.md](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/e-integration-tests.md).