**12 findings required code changes.** Finding 9 was based on the retired `macos.action` result; canonical spec §30 requires `computers.forceStop` to return `null`. I kept that contract and added a regression test.

The schema was regenerated, and the whole-crate scan also corrected explicit-null behavior for log, storage, and desktop fields.

- `cargo test`: 26 passed; doc tests passed
- `cargo clippy --all-targets -- -D warnings`: passed
- `cargo fmt --check`: passed

Commit: `7a0591f9` (`fix(api): align wire types with native contracts`).

The fixes report is at [p1-api-fixes.md](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/p1-api-fixes.md). It notes that the engine must normalize the historical storage `legacy` trigger at launch before returning canonical storage state. The report is uncommitted; the Lookout repository has unrelated existing changes.