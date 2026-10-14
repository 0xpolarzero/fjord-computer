# Fjord: owner-aware Triage, Computers references and removal hooks, 2026-10-14

## Finding
Audit against reports/fjord-runs-on-remote.md. Triage "Run in a computer" was already keyed by owner end to end: `RunInComputerSettings.deviceID` is copied into `ComputerRunRecord`; `computers.list/start`, checkpoints, `operations.*`, `desktop.*`, secrets and GitHub reads, `guest.*`, ssh alias, and run/reattach/rollback all take the record's `deviceID`, and reattachment reads the record, never the current rule. Only the missing-computer message was weak. The Computers page, however, lists and manages This Mac's inventory only (its list, jobs, queue and every model method use `deviceId: nil`), so its `GuestReference(deviceId: nil, ...)` calls were correct but implicit.

## Changed
- `GuestReference.thisMac(_:)`: the one named place for a This Mac reference. Used by `ComputerAgentToolsPanel` (ComputersPanels.swift) and `ComputerDetailView` (ComputersView.swift).
- Computer-removal hooks: `ComputersModel.prepareComputerRemoval` / `computerRemovalCompleted` now take an owner-scoped `GuestReference` (built in `delete`), and Store.swift passes it through instead of rebuilding `GuestReference(deviceId: nil, ...)`. Removing a This Mac computer therefore matches Router placements, pending forms and ssh entries of `local/<id>` only, never `<device>/<id>`.
- Triage: a computer missing from its owner now fails with "<name> is no longer in the inventory of device <id>. Choose a computer again." and never falls back to a same-id computer.

## Tests
`Tests/FjordTests/RemoteOwnersTests.swift` (4), with a second device whose computer shares its id with a stopped This Mac computer: a Triage run starts the owner's computer (deviceId on the start, local twin still stopped, no guest calls on the twin); a computer gone from its owner fails with the local twin present and nothing started; reattach uses the recorded owner even when the rule now names This Mac; removing the This Mac computer passes `local/<id>` to both hooks and leaves the remote placement and the remote computer intact. `swift build` clean; `scripts/test.sh` once: 1767 tests passed.

## Not done
- Remote computers have no detail page: the list, `.computerDetail(String)` route, job tracking (`waitForFinish`, queue, `perform`) and the ~40 `ComputersModel` methods (files, network, SSH access, secrets, GitHub, checkpoints) are This Mac only; making the page show another device's computers needs the route and every one of them to carry `deviceId` (several wire params, e.g. `ComputerDeleteRequest`, have none yet). The panels now only take `GuestReference.thisMac`.
- Triage reads `settings.read` (automatic checkpoint retention) without a deviceId: the wire method takes no params, so it is This Mac's setting. Mentioned in the gate error as the owner's; unchanged.
- Triage keeps its own start/poll flow rather than `ComputersModel.ensureRemoteRunning`, since it records the job id and phase transitions as it goes; `placementRow` is already used by the editor's picker (via `placementOptions`).
- Not verified live (two Macs).
