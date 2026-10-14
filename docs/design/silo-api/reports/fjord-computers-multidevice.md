# Fjord: the Computers tool manages every connected device (95 A-14)

## What changed
- **Client** regenerated from Silo main. At `3299b4dd`: `deviceId` on `activity.setup.read`, `computers.creation.skipComputerUseWait`, `preparation.*`, `device.dependencies`. `e29122f0` (remote guest SSH, transfers, watches) leaves the schema unchanged; the manifest names it.
- **List**: the Computers page lists This Mac and every device from `connections.devices.list`, grouped by device (flat list while no device is connected). A device whose computers can't be read shows as an unreachable group with the reason. The `+` menu creates on any device (`createDeviceId`, limits from that device's `device.facts`). The palette lists remote computers too.
- **Routes**: `.computerDetail(GuestReference)`; the token is `computer-detail:<deviceId|local>/<computerId>`. `ComputerDetailView` takes a `GuestReference` and every panel receives it.
- **Actions**: every `ComputersModel` action takes a `GuestReference` (or `deviceId:`) and sends the owner: start/stop/force stop/delete/create, checkpoints and usage, resources, files (list, upload, download), network, SSH access, computer use, logs, storage, exports, GitHub, secrets, setup activity, agent tools, Linux viewer. Per-computer state is keyed by `GuestReference.key`; per-device state (GitHub, secrets, exports, setup activity, operation queues) by owner.
- **Jobs** are tracked by `(deviceId, jobId)`: `ComputerJobKey` is the bare job id for This Mac and `<jobId>@<deviceId>` otherwise. It keys `finishedJobs`, receipts, upload conflicts and acknowledgements, and `operations.get/cancel/acknowledge/list` get the owner. Unacknowledged jobs of each device are recovered on connect and recovery.
- **Events**: `events.subscribe` carries `deviceIds` of the connected devices. It is renewed when the device set changes, after which every owner is re-read. `checkpoints`, `operations.queue`, `job.progress` and `job.finished` events carry their source `deviceId` and update that owner's state. Recovery re-reads all owners.
- **Unavailable for a remote computer, with a short reason shown** (`ComputerRemoteLimit`): Open screen of a macOS computer (`display.show`, by design), opening a published port (`network.open` returns the owner's loopback URL) and Open SSH in Terminal (`sshAccess.connection` returns the owner's loopback command and key). Upload, download, terminal, editor and SSH aliases are enabled, as `remote-guest-ssh.md` made them remote. The Export panel can't browse the owner's folders or archives (paths on the owner); it exports to the owner's folder and says so. `clipboard.transfer` is unused by Fjord. Settings (`settings.*`, startup computers) and the quit prompt stay This Mac's, as host-level by design.

## Mock
`MockEngineClient.addPeer(device, client:)` makes another mock the engine of a device: calls naming it by `deviceId` run on that mock (own inventory, job ids, secrets, GitHub, exports) and its events are relayed with the `deviceId` to subscribers that asked for it. Remote `display.show/close`, `clipboard.transfer` answer `unsupported_remote_operation`. `connectDemoRemoteDevice()` adds "Studio Mac", whose computers reuse the ids of This Mac's `dev` and `linux-1`.

## Tests and shots
- `MultiDeviceComputersTests` (14): groups with same-id computers apart; subscription `deviceIds`; start/stop/delete of one never touch the same-id twin on the other device; the same job id on two devices; acknowledgement goes to the owner; relayed events update only their owner; per-owner state keys; secrets per device; limits; upload/download to the owner; create on a device; checkpoints and resources on the owner; route tokens. Existing tests were updated to the new signatures.
- `swift build` clean; `scripts/test.sh` once: 1905 tests passed.
- Shots re-rendered: `computers-remote` (This Mac and Studio Mac groups), `computer-detail-remote` (same id as This Mac's `dev`), `computer-files-remote`.

## Not done
- No live run against two Macs. The relayed events and `deviceIds` resubscription run only against the mock.
- An event from a device not in the loaded list is treated as This Mac's, as before; a device that just connected is covered by the resubscribe-and-reread step.
- Router/Triage code unchanged (already owner-aware).
