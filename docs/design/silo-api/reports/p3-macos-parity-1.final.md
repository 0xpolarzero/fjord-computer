Implemented part 1 and committed it on `engine/p3-macos-parity`: `bff33a6ccc7ec9704aa30bb69c9f19e2da066aea` (`feat(engine): add macOS provisioning and resource parity`). The work covers developer-tools provisioning, Screen Recording and Screen Sharing setup, start at launch, queued macOS operations with cancellation, and CPU/memory edits applied on next start. The worktree is clean.

The full Rust workspace tests and formatting check passed: 2,261 engine tests, plus suites of 69 and 30 tests; 30 tests were ignored. Typecheck and all 2,770 frontend tests passed. Lint passed with six warnings in unchanged files.

The disposable VM probe was cleaned up. Its findings and limits are recorded in the reports: the probe marks B-19, B-24, and B-4 **partly validated**; the exact provisioning script’s cold install path and full Screen Sharing interaction were not validated. Durable canonical jobs/events integration remains for the P2 track.

- [Implementation report](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/p3-macos-parity-1.md)
- [Probe report](/Users/polarzero/code/projects/lookout/docs/design/silo-api/probes/p3-macos-parity.md)

Next action: connect these macOS operations to the P2 durable jobs/events interface before claiming API-level A-19 parity.