Implemented and committed as `89549e40` (`feat: add Triage computer runs`). The commit contains only Triage-owned paths.

The rule editor, checkpoint and guest-run pipeline, B-17 authentication gate, proof recording and retrieval, result card, rollback, mock tests, and light/dark window shots are in place.

**Verification:** `swift build` passed. `scripts/test.sh` ran 1,687 tests; all 14 `ComputerRunTests` passed, but the full suite failed on two other assertions: a Computers test expects a resource label without disk, and a GuestRouter test observed a missing session. That GuestRouter test passed when run alone.

Production execution remains gated because B-17 has not proven OAuth Bearer substitution. The macOS recorder is packaged, but its TCC provisioning path is not qualified.

[Implementation report](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/p4-triage.md) · [Light shot](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/p4-triage-shots/light/window-triage-computer-run-result-light.png) · [Dark shot](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/p4-triage-shots/dark/window-triage-computer-run-result-dark.png)

Next action: update the Computers resource-label expectation, then rerun `scripts/test.sh` serially.