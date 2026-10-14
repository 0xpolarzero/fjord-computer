Implemented `silo-api` as a standalone crate at [app/SiloUI/api](/Users/polarzero/silo-work/p1-api/app/SiloUI/api). It covers 146 methods, 26 events, 23 error codes, and 29 job completion mappings. The generated schema is checked in at [silo-api.schema.json](/Users/polarzero/silo-work/p1-api/app/SiloUI/api/schema/silo-api.schema.json).

All 13 tests passed, as did clippy with warnings denied and Rust 1.94 formatting. The worktree is clean. Commits:

- `f5cb77b3` `feat(api): add standalone wire contract crate`
- `70abe9f5` `feat(api): add canonical method and event contracts`
- `57a0a6f7` `feat(api): generate checked-in contract schema`

The report is at [p1-api.md](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/p1-api.md). It documents unresolved shapes, including `checkpoints.changed`, clipboard read payload details, and some new macOS job results. `JobFinished.result` remains untagged JSON, with method-specific mappings in the schema.

For workspace integration, add `../api` as a member from `app/SiloUI/src-tauri` and depend on it with `silo-api = { path = "../api" }`. The engine workspace was left untouched.