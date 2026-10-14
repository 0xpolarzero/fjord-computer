# Fjord: Router "Runs on" for computers on another device, 2026-10-14

## Finding
The Silo client, guest client, installer, observer, watcher, SSH settings and placement were already keyed by `GuestReference(deviceId, computerId)` and pass `deviceId` on every `guest.*`, `operations.*` and `desktop.*` call (reports/remote-routing.md, exec-input-device.md). The only local-only restriction was `RouterMCP.ensureGuestComputerReady`, which refused a remote owner and read the local inventory; the agent-tools gate and the computer name also read the local inventory.

## Built
- `RouterMCP.ensureGuestComputerReady`: a computer with a `deviceId` is read, and started if stopped, on its owner (`ComputersModel.ensureRemoteRunning`: `computers.list`/`computers.start` with the deviceId, job polled and acknowledged with the deviceId, running verified by re-reading the owner's inventory). A computer missing from the owner's inventory fails; it never falls back to a same-id computer here.
- `ComputersModel.placementRow(deviceId:computerId:)`: row lookup in the owner's inventory. Used for the agent-tools gate (kind, name) and the Router ssh-config name.
- The rest of the flow needed no change and is now covered by a test: `guest.sshAlias.ensure` with the deviceId (alias `silo-remote-<device>-<computer>`), the `sshConfigs` entry (`fjord-<device>-<computer>`), hook and plugin install, forms/delivery/presence, transcript reads and the watcher, all through `guest.files`/`guest.exec` with the deviceId; agent tools `desktop.status`/`desktop.action`/`operations.job.get` with the deviceId.
- Placement stays keyed by `(deviceId, computerId)` (`SessionLocation`, `GuestReference.key`).
- Mock engine: `computers.start` for a deviceId flips the second device's inventory; agent tools are keyed per `deviceId/computerId`; request logs `agentToolsStatusRequests`, `agentToolsSetupKeys`, `remoteStartRequests`; the mock guest client hands a remote computer the `silo-remote-` alias.

## Tests
`Tests/FjordTests/RunsOnRemoteTests.swift` (5), on a second device whose computer has the same id as a stopped one on This Mac: a full Router session start (owner started, local twin untouched, agent tools set up on the owner, remote alias and sshConfigs entry, hook/key/exec only on the remote reference, deep link and pending start carry the remote alias and location); placement keyed by device and computer; a running remote computer isn't restarted; a computer gone from its owner fails without falling back; agent-tools status/setup carry the deviceId. `swift build` clean; `scripts/test.sh` once: 1763 tests passed (after waiting for another worktree's swift-test to end).

## Notes
- Not verified live (needs two Macs and a real remote alias/ProxyCommand).
- Triage "Run in a computer" and Computers panels still use local references in places (ComputersPanels.swift:238, ComputersView.swift:207, Store.swift computer-removal hooks); out of scope here.
