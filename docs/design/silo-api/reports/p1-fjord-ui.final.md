Implemented P1-Fjord Computers: the typed client boundary and mock, list and detail pages, checkpoint actions, job progress, tool enablement, and the quit flow.

**Validation:** `swift build` passed; `scripts/test.sh` passed with 1,579 tests across 157 suites. Rendered and inspected all three requested shots.

**Commits:** `280021f8` client and quit model; `b928709f` UI and quit flow; `aade7c45` report.

**Artifacts:** [Implementation report](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/p1-fjord-ui.md)

- [Computers list](/Users/polarzero/code/projects/lookout/.build/shots/window-computers.png)
- [Computer detail](/Users/polarzero/code/projects/lookout/.build/shots/window-computer-detail.png)
- [Quit dialog](/Users/polarzero/code/projects/lookout/.build/shots/window-computers-quit-dialog.png)

The client currently uses the mock; the Silo RPC adapter is the next step. I left the unrelated pre-existing workspace changes untouched.