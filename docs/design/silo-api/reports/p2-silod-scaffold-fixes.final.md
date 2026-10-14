Fixed all four findings on `engine/p2-silod`. Each regression failed before its fix and passes now.

- Startup initializes the global channel from the validated manifest.
- Concurrent cold starts tolerate `AlreadyExists`, validate the directory, and reach ownership arbitration.
- Identity publication syncs its containing directory and propagates sync failures.
- Incompatible handshakes report structured engine/client protocol ranges and app versions in the canonical API and generated schema.

Commits: `9fa42b50`, `347ed299`, `41bc45ac`, `81f51766`.

**Verification:** `silod` passed 30 unit tests and 1 integration test; the full workspace passed, including 2,229 UI tests (30 ignored), 60 engine tests, and 30 `silod` tests. The API crate passed 27 tests. Formatting checks passed for both Rust manifests. Full workspace tests used the documented synthetic GitHub configuration; tests used fixture homes and launched no app or LaunchAgent.

Report: [p2-silod-scaffold-fixes.md](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/p2-silod-scaffold-fixes.md). It remains uncommitted in the Lookout checkout, which has unrelated pre-existing modifications. The Silo worktree is clean.