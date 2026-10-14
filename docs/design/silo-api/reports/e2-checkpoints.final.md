**E2-checkpoints is partially complete.** I finished the pre-upgrade backup and vocabulary migration modules. Checkpoints, backup controller, and runtime migration still contain Tauri coupling; the report lists the remaining references and cross-track needs.

Commits:

- `dc781258` `refactor(engine): extract pre-upgrade backup commands`
- `6efffb98` `refactor(engine): use host context for vocabulary migration`

Verification passed: 31 pre-upgrade backup tests, 33 vocabulary tests, the full Rust suite (2,289 passed, 30 ignored), and `cargo +1.94.0 fmt --check`. The Silo worktree is clean.

I wrote the requested [E2-checkpoints report](</Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/e2-checkpoints.md>).