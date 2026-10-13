# P1 Fjord Computers UI

Implemented the first Computers tool slice in two commits:

- `280021f8` `feat: add Computers client and quit state model`
- `b928709f` `feat: add Computers tool UI and quit flow`

## Delivered

- Added a typed `EngineClient` boundary for computer lifecycle/configuration, checkpoint actions, display access, operation progress/finish events, and event subscriptions. `MockEngineClient` supplies macOS and Linux computers, starting and failed states, automatic and manual checkpoints, and an active job.
- Added the Computers list and detail pages with state, lifecycle actions, checkpoint actions, and job progress. Automatic checkpoint names retain the API's `, deleted automatically` suffix; the UI presents that label once.
- Added Computers to first-launch tool selection, navigation, and Settings.
- Routed normal quit through the A-2 choice: Cancel, Keep running, or Stop and quit. The stop choice waits for stop completion before disconnecting. Update and signal termination use the non-interactive termination path.
- Added state-mapping and quit-decision tests.

`checkpointsList` is a client projection over `computers.list`, which embeds checkpoints. The spec does not define a standalone `checkpoints.list` request. This slice uses the mock client; it does not yet include a Silo RPC adapter. The checkout's source directory is `Sources/Fjord` rather than the brief's `Sources/FjordComputer`.

## Validation

- `swift build` passed.
- `scripts/test.sh` passed: 1,579 tests across 157 suites.
- Rendered and inspected the requested UI shots with `--snapshot --window-shots`.

## Window shots

- Computers list: `/Users/polarzero/code/projects/lookout/.build/shots/window-computers.png`
- Computer detail: `/Users/polarzero/code/projects/lookout/.build/shots/window-computer-detail.png`
- Quit dialog: `/Users/polarzero/code/projects/lookout/.build/shots/window-computers-quit-dialog.png`

Next action: implement the Silo-backed `EngineClient` adapter against this typed boundary.
