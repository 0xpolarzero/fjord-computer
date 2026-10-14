Implemented the Computers workflows against the generated client and mock, including creation, checkpoints, files, access controls, networking, storage, screen viewing, connected Macs, and Computers settings. Added model tests and 10 reviewed window shots in the [P4 Computers report](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/p4-computers.md).

`swift build` passed. The final serialized `scripts/test.sh` run passed **1,687 tests across 163 suites**. Earlier attempts exposed a concurrent Triage test compile error and a stale resource-summary assertion; both were addressed and recorded in the report.

Commits: `648b473a` (implementation) and `b14a5969` (test assertion and report update). I left the concurrent track’s remaining worktree changes unstaged.