Fixed findings 1, 2, and 4–13 in nine local commits. Finding 3 follows the owner decision in §3: Linux host support is discontinued, so the docs and host build/package CI were updated. Linux guest support remains unchanged.

The full workspace Cargo tests and `cargo fmt --all --check` passed. Typecheck, lint, and frontend tests passed; lint reported six warnings. A socket test failed once in an earlier full run, then passed in isolation and in the final full run.

The per-finding commit and test record is saved at [e-integration-fixes.md](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/e-integration-fixes.md). The Silo branch is clean; the report remains uncommitted in the Lookout repo. No commits were pushed.