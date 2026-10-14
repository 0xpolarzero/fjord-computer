**E3-macos is complete.** The worktree is clean at `9054b3be`; the owned engine modules have no Tauri API references outside `src/commands/`. The remaining origin strings in `macos_display_gateway.rs` are allow-list data.

Three module-group commits are on `engine/e3-macos`:

- `958757ab` — move macOS remote viewer commands to the adapter
- `e5228812` — extract macOS computer capabilities
- `9054b3be` — extract macOS remote dispatch

Verification passed: filtered tests for each group, the full locked Cargo suite (2,289 passed, 30 ignored), and `cargo +1.94.0 fmt --check`.

The report records remaining command-layer Tauri references and cross-track needs for E1 runtime adapters, E4 remote bridge callers, and the display-host integration seam: [e3-macos.md](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/e3-macos.md).