# remote-all: every per-computer and per-device method works for another device

Silo worktree `~/silo-work/remote-all`, branch `engine/remote-all`, cut from `main@819367b3` (main had not moved). Fast-forwarded into Silo `main` at `3299b4dd`. Never pushed. No VMs started.

## Commits

| Hash | What |
| --- | --- |
| `e4a9a8ea` | `style(engine)`: rustfmt of five files main already had unformatted (so the fmt gate passes) |
| `5dc92c42` | `feat(api)`: `deviceId` on `activity.setup.read`, `computers.creation.skipComputerUseWait`, `preparation.status`, `preparation.retry`, `device.dependencies`; schema regenerated |
| `3299b4dd` | `feat(engine,silod)`: the routing, the owner side, error codes, tests, changeset `manage-every-computer-on-a-connected-mac.md` |

## Finding

The wire types were nearly complete already: 105 of the 146 methods carried `deviceId` (110 now) (`ComputerDeleteParams` has it; the missing field in Fjord's report is a Swift-side gap, `ComputerDeleteRequest` is the nested configuration). Five per-computer or per-device methods had none (above). The real gap was routing: `computers.*` (including `computers.list`, which the brief calls working: it was not), `checkpoints.*`, `exports.*`, `migration.*`, `preparation.chatgpt.*`, `device.facts`, `logs.query`, `storage.*`, `guest.account`, `guest.exec`, `guest.files.*`, `files.list`, `clipboard.read/write`, `macos.setup.retry` and `macos.template.delete` all answered `unsupported_remote_operation`.

## What was built

One mechanism instead of 50 hand-written routes.

1. **Controller (`silod/src/methods/remote.rs`, `route`).** First step of `methods::dispatch` (and of the `notifications.list` arm). If the method is in the owner list and `deviceId` names another engine (absent, `"local"` or this device's id mean this engine), the request is decoded as the canonical `MethodParams`, `deviceId` is dropped, it is sent with `call_owner` (the existing test seam) in the canonical method name, and the reply is decoded as the canonical `MethodResults` and re-serialized from the typed value. A malformed request costs no round trip; a reply in the wrong shape is an `internal` error naming the method.
2. **Owner bridge (`silo_engine::remote::OWNER_METHODS`).** 55 canonical names with their class (queries and `clipboard.read` are reads, the rest are changes: accepted once per `operationId`, journalled, never replayed). They are in the handshake capabilities, in `access()`, and `execute()` sends them to `dispatch_typed` before the legacy `runtime.`/`macos.` prefixes. The legacy `files.list` bridge arm is deleted (`files.list` is now the canonical handler, which also lists macOS computers).
3. **Owner execution (`serve_owner`).** The owner decodes the request again, refuses a `deviceId` other than its own (a request makes one hop, never three devices), and runs its *own* handler through `methods::dispatch` as a local request from the client `owner-bridge`, on the engine's I/O runtime (`install_runtime`, set in `app.rs`). One implementation per method: a controller gets what a local client of the owner gets, including the owner's `jobId` for a job method, followed with `(deviceId, jobId)` through `operations.*` (already routed). `notifications.list` reads the owner's notices directly.
4. **Error codes.** `BridgeError` gained `api_code` (wire field `apiCode`, ignored by older devices): an owner failure keeps its canonical code (`not_running`, `needs_personalizing`, `setup_incomplete`...) instead of collapsing to `internal`. `map_engine_error` reads it; `access::bridge_error` fills it. An unknown or removed device is now `not_found` (was `internal`) in `exchange_with_device`, `probe_device` and `open_bridge_stream`.
5. **Owner-run jobs without a socket client.** A setup job (`computers.create`, `.configuration.change`, `.delete`) announces progress and outcome "to the client that asked"; for a request from another device that is every subscriber (`bind_setup_audience_to_all`, `HandlerContext::for_owner_bridge`), so the controller sees them through its relay of the owner's events, or by polling `operations.job.get`. The `computers.list` event barrier is skipped for the bridge client (it holds no subscription).
6. **`logs.export`** keeps its own route: each request in `requests` may name a device; its pages are read from that owner with `logs.query` (validated against `LogPage`), and one file is written on the exporting engine.

## Device-level settings

`settings.*`, `updates.*`, `engine.*` (shutdown, update, disconnect), `connections.*` (the controller's own device list, key setup, Connections on/off; `keys.revoke` already runs on the owner) and `editor.includeNotice` stay local: 60 says host-level and controller's local engine, and none takes a `deviceId`. `connections.devices.remove` has a `deviceId` that is the subject, not a route. Fjord's Triage reading `settings.read` (automatic checkpoint retention) is therefore This Mac's setting; the owner's retention would need `settings.read` with `deviceId`, which is not in the spec (95 A-14 reads "everything on the host" as computers and their policies; if retention should be remote-managed, add `deviceId?` to `SettingsReadParams`/`SettingsUpdateParams` and put them in the owner list, no other work).

## Not done, with reasons

- **Remote terminal, editor and SSH alias** (`terminal.command`, `editor.command`, `guest.sshAlias.ensure/remove`, `guest.prepare`): they build a launch command or write the *controller's* SSH configuration. A remote alias is a `ProxyCommand` through the owner's `guest.ssh` stream with a per-device key (`editor::prepare_remote_private` and the legacy `guest.prepare` bridge already do this for desktop viewers and published ports). Wiring that into the canonical `GuestSshAliasEnsureResult` (Include line, config path, home/user from the owner's `guest.account`) is a design of its own. They still answer `unsupported_remote_operation`. This is the main remaining gap for Router "Runs on" a remote computer through SSH.
- **`files.upload` / `files.download`**: the paths are on the controller, so a data transport between engines is needed (chunked `guest.files.read/write` would do; the `transfer:` job and its progress events are not relayed).
- **`guest.files.watch`**: `guest.files.changed` is client-scoped and not relayed.
- **`display.show` / `display.close`**: the engine's own VM window; a remote macOS screen is opened by the client from `macos.display.session` (routes already). **`clipboard.transfer`**: the device pasteboard and a viewer connection of this engine's clients.
- Request windows: owner-run changes use the 600 s default of the bridge (`request_timeout`); `computers.create` of a desktop-capable computer and long `guest.exec` calls are jobs or bounded, so they fit, but `checkpoints.*` run inside the owner's job, not the request.
- Not verified over real SSH between two Macs (the tests fake the transport, see below).

## Audit of the 146 methods

"Before" is the state at `819367b3`; "After" is this branch. Owner list = served by `OWNER_METHODS` (55). "Routes" for the already-routed methods means the existing per-method route (`access.rs`, `guest.rs`, `display.rs`, `operations.rs`) was left alone.

| Method | Kind | Before | After |
| --- | --- | --- | --- |
| `activity.setup.read` | query | no `deviceId` field | routes (owner list), `deviceId` added |
| `checkpoints.abandonRestore` | job | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `checkpoints.create` | job | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `checkpoints.delete` | job | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `checkpoints.fork` | job | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `checkpoints.restore` | job | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `checkpoints.usage` | query | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `clipboard.read` | command | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `clipboard.transfer` | command | refuses | refuses by design: the device pasteboard and a viewer connection of this engine's own clients |
| `clipboard.write` | command | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `computerUse.approval` | command | routes | routes (unchanged) |
| `computerUse.setup` | job | routes | routes (unchanged) |
| `computerUse.state` | query | routes | routes (unchanged) |
| `computers.configuration.change` | job | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `computers.configuration.read` | query | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `computers.configuration.retry` | job | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `computers.create` | job | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `computers.creation.skipComputerUseWait` | command | no `deviceId` field | routes (owner list), `deviceId` added |
| `computers.delete` | job | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `computers.dismissError` | command | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `computers.forceStop` | command | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `computers.identities.configure` | job | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `computers.identities.verify` | query | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `computers.launch` | query | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `computers.list` | query | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `computers.restart` | job | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `computers.shell` | query | local by design | local by design: composes a shell view from a client-supplied error string |
| `computers.start` | job | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `computers.stop` | job | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `connections.devices.connect` | command | local by design | local by design: the controller's own device list and Connections (95 A-3) |
| `connections.devices.health` | query | local by design | local by design: the controller's own device list and Connections (95 A-3) |
| `connections.devices.list` | query | local by design | local by design: the controller's own device list and Connections (95 A-3) |
| `connections.devices.remove` | command | local by design | local by design: the controller's own device list and Connections (95 A-3) |
| `connections.keys.revoke` | command | routes | routes (unchanged) |
| `connections.setEnabled` | command | local by design | local by design: the controller's own device list and Connections (95 A-3) |
| `connections.ssh.authorizationCommand` | query | local by design | local by design: the controller's own device list and Connections (95 A-3) |
| `connections.ssh.keySetupCommand` | command | local by design | local by design: the controller's own device list and Connections (95 A-3) |
| `connections.status` | query | local by design | local by design: the controller's own device list and Connections (95 A-3) |
| `desktop.action` | job | routes | routes (unchanged) |
| `desktop.connect` | query | local by design | engine-to-engine; served between engines on the owner bridge already, never a client request |
| `desktop.status` | query | routes | routes (unchanged) |
| `device.dependencies` | query | no `deviceId` field | routes (owner list), `deviceId` added |
| `device.facts` | query | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `display.close` | command | refuses | refuses by design: same |
| `display.native.attach` | stream | local by design | local by design: stream for this engine's own client |
| `display.show` | command | refuses | refuses by design: the engine's own VM window; a remote macOS screen is opened by the client (Screen Sharing) from `macos.display.session` |
| `display.viewer.audio.set` | command | local by design | local by design: a viewer connection belongs to this engine's client (`display.viewer.open` already routes) |
| `display.viewer.close` | command | local by design | local by design: a viewer connection belongs to this engine's client (`display.viewer.open` already routes) |
| `display.viewer.open` | command | routes | routes (unchanged) |
| `display.viewer.screen.reset` | command | local by design | local by design: a viewer connection belongs to this engine's client (`display.viewer.open` already routes) |
| `display.viewer.sound.cancel` | command | local by design | local by design: a viewer connection belongs to this engine's client (`display.viewer.open` already routes) |
| `display.viewer.sound.check` | query | local by design | local by design: a viewer connection belongs to this engine's client (`display.viewer.open` already routes) |
| `editor.command` | command | refuses | refuses by design: builds a launch command for the controller's own machine from its own SSH alias |
| `editor.includeNotice` | query | local by design | local by design: host-level setting or lifecycle of this engine (60: host-level, controller's local engine) |
| `engine.disconnect` | command | local by design | local by design: host-level setting or lifecycle of this engine (60: host-level, controller's local engine) |
| `engine.handshake` | query | local by design | local by design: host-level setting or lifecycle of this engine (60: host-level, controller's local engine) |
| `engine.shutdown` | job | local by design | local by design: host-level setting or lifecycle of this engine (60: host-level, controller's local engine) |
| `engine.state` | query | local by design | local by design: host-level setting or lifecycle of this engine (60: host-level, controller's local engine) |
| `engine.update.abort` | command | local by design | local by design: host-level setting or lifecycle of this engine (60: host-level, controller's local engine) |
| `engine.update.prepare` | job | local by design | local by design: host-level setting or lifecycle of this engine (60: host-level, controller's local engine) |
| `events.subscribe` | subscription | routes | routes through its own `deviceIds` (relay) |
| `events.unsubscribe` | command | local by design | local subscription |
| `exports.acknowledge` | command | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `exports.create` | job | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `exports.destination.set` | command | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `exports.dismiss` | command | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `exports.import` | job | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `exports.inspect` | job | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `exports.state` | query | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `files.download` | job | refuses | refuses by design: destination is a path on the controller; same |
| `files.list` | query | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `files.upload` | job | refuses | refuses by design: takes file paths on the controller; needs a data transport between the engines |
| `github.access.set` | command | routes | routes (unchanged) |
| `github.configuration.retry` | command | routes | routes (unchanged) |
| `github.configuration.save` | command | routes | routes (unchanged) |
| `github.connect` | job | routes | routes (unchanged) |
| `github.connect.callback` | stream | local by design | engine-to-engine; served between engines on the owner bridge already, never a client request |
| `github.connect.reopen` | command | routes | routes (unchanged) |
| `github.disconnect` | command | routes | routes (unchanged) |
| `github.personalToken.remove` | command | routes | routes (unchanged) |
| `github.personalToken.save` | command | routes | routes (unchanged) |
| `github.repositories.manage` | command | routes | routes (unchanged) |
| `github.repositories.refresh` | command | routes | routes (unchanged) |
| `github.state` | query | routes | routes (unchanged) |
| `guest.account` | query | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `guest.exec` | command | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `guest.exec.get` | query | routes | routes (unchanged) |
| `guest.exec.input` | command | routes | routes (unchanged) |
| `guest.exec.start` | job | routes | routes (unchanged) |
| `guest.files.list` | query | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `guest.files.read` | query | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `guest.files.remove` | command | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `guest.files.watch` | subscription | refuses | refuses by design: change events are client-scoped (`guest.files.changed`) and not relayed to controllers |
| `guest.files.write` | command | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `guest.prepare` | command | refuses | refuses by design: authorizes a key in a guest; remote keys go through the owner's legacy `guest.prepare` bridge used by `editor::prepare_remote_*` |
| `guest.ssh` | stream | local by design | engine-to-engine; served between engines on the owner bridge already, never a client request |
| `guest.sshAlias.ensure` | command | refuses | refuses by design: writes the controller's own SSH configuration; a remote alias is a ProxyCommand through the owner's `guest.ssh` stream (not built) |
| `guest.sshAlias.remove` | command | refuses | refuses by design: same |
| `logs.export` | job | refuses a request naming another device | routes: pages read from each owner, one file written here |
| `logs.query` | query | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `macos.display.connect` | query | local by design | engine-to-engine; served between engines on the owner bridge already, never a client request |
| `macos.display.resize` | command | routes | routes (unchanged) |
| `macos.display.session` | command | routes | routes (unchanged) |
| `macos.display.stream` | stream | local by design | engine-to-engine; served between engines on the owner bridge already, never a client request |
| `macos.setup.retry` | job | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `macos.template.delete` | command | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `migration.preUpgradeBackup.acknowledgeNotice` | command | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `migration.preUpgradeBackup.delete` | command | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `migration.preUpgradeBackup.get` | query | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `migration.preUpgradeBackup.measure` | query | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `migration.state` | query | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `network.open` | command | routes | routes (unchanged) |
| `network.publish` | command | routes | routes (unchanged) |
| `network.state` | query | routes | routes (unchanged) |
| `network.unpublish` | command | routes | routes (unchanged) |
| `notifications.list` | query | `deviceId` in type, ignored (local only) | routes (owner list) |
| `operations.cancel` | command | routes | routes (unchanged) |
| `operations.job.acknowledge` | command | routes | routes (unchanged) |
| `operations.job.get` | query | routes | routes (unchanged) |
| `operations.list` | query | routes | routes (unchanged) |
| `preparation.chatgpt.retry` | command | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `preparation.chatgpt.status` | query | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `preparation.retry` | command | no `deviceId` field | routes (owner list), `deviceId` added |
| `preparation.status` | query | no `deviceId` field | routes (owner list), `deviceId` added |
| `push.dismiss` | command | routes | routes (unchanged) |
| `push.repositories` | query | routes | routes (unchanged) |
| `push.start` | job | routes | routes (unchanged) |
| `push.status` | query | routes | routes (unchanged) |
| `secrets.list` | query | routes | routes (unchanged) |
| `secrets.remove` | command | routes | routes (unchanged) |
| `secrets.retry` | command | routes | routes (unchanged) |
| `secrets.save` | command | routes | routes (unchanged) |
| `settings.flush` | command | local by design | local by design: host-level setting or lifecycle of this engine (60: host-level, controller's local engine) |
| `settings.read` | query | local by design | local by design: host-level setting or lifecycle of this engine (60: host-level, controller's local engine) |
| `settings.update` | command | local by design | local by design: host-level setting or lifecycle of this engine (60: host-level, controller's local engine) |
| `sshAccess.connection` | command | routes | routes (unchanged) |
| `sshAccess.save` | command | routes | routes (unchanged) |
| `sshAccess.state` | query | routes | routes (unchanged) |
| `storage.read` | query | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `storage.reclaim` | job | refuses (`unsupported_remote_operation`) | routes (owner list) |
| `terminal.command` | query | refuses | refuses by design: same: an argv for the controller |
| `updates.check` | command | local by design | local by design: host-level setting or lifecycle of this engine (60: host-level, controller's local engine) |
| `updates.download` | job | local by design | local by design: host-level setting or lifecycle of this engine (60: host-level, controller's local engine) |
| `updates.focused` | command | local by design | local by design: host-level setting or lifecycle of this engine (60: host-level, controller's local engine) |
| `updates.setAutomaticChecks` | command | local by design | local by design: host-level setting or lifecycle of this engine (60: host-level, controller's local engine) |
| `updates.state` | query | local by design | local by design: host-level setting or lifecycle of this engine (60: host-level, controller's local engine) |

Totals: 99 route (55 through the owner list, `logs.export`, `events.subscribe`, 42 existing routes left alone), 11 refuse by design, 36 local by design (engine-to-engine, host-level or the controller's own).

## Tests

- `silod` `methods::remote` (16): a request for another device reaches the stubbed owner in the canonical name without `deviceId`; flattened shapes (`computers.create` Linux, `computers.delete`, `checkpoints.restore`); this engine's id and `"local"` are not forwarded; a malformed request is refused before a round trip; a reply in the wrong shape is an error; the owner's `apiCode` survives (`not_running`) as does `not_found`; an unconnected device is named; **two engines in one process**: the stub for the owner device runs `serve_owner` on the fixture engine, so controller route, bridge classification input and the owner's real handlers run end to end (`computers.configuration.read` returns the owner's computers, a start of an unknown computer is `not_found`, `computers.list` reaches the runtime without a barrier, `notifications.list` returns the owner's notices); the owner refuses a third-device `deviceId`, an unlisted method and a malformed request; and the audit guard `every_method_is_remote_by_the_owner_by_its_own_route_refused_or_local_by_design` puts all 146 registry methods in exactly one bucket (owner / own route / refused / local), checks that every routed one has `deviceId` in the generated schema and that no method with a `deviceId` is unclassified. `the_owner_list_agrees_with_the_registry_kinds` keeps the Read/Change class equal to the method kind; `every_owner_method_is_a_method_a_domain_or_the_notice_list_answers` keeps it served by exactly one domain.
- `silod` `methods::computers`: remote `logs.export` reads pages from a stubbed owner and writes one file; the old "domain refuses another device" test no longer lists `logs.export`.
- `silo-engine` `remote`: every owner method is classified as its kind, in the capabilities and not also a legacy method; per-method run-once-per-identity for changes and run-every-time for reads through the real `handle`; `apiCode` round trip through `error_reply`/`from_remote_reply`; `runtime`: a setup request from another device is announced to all and can be rebound.
- Socket tests (`tests/computers.rs`, `guest.rs`, `checkpoints_domain.rs`) now expect `not_found` / "no longer connected" for a device this engine is not connected to (they expected `unsupported_remote_operation`).
- Gate on the branch tip (`3299b4dd`, identical to main): `cargo test --locked -p silo-engine -p silod -p silo-api --no-fail-fast`: silo-api 31, silo-engine 2721 passed (32 ignored), silod 262 plus all socket-level tests, 0 failed. `cargo +1.94.0 fmt --all --check` clean. silo-ui was not built (it uses none of the changed signatures; checked by grep). One run of `methods::guest::an_owner_serves_a_controllers_command...` failed once under load and passed in the next three runs.

## For the next tracks

- Fjord can now send `deviceId` on all the methods marked "routes" and regenerate its client from the schema (five new optional `deviceId` fields). Job methods return the owner's id: follow it with `(deviceId, jobId)` on `operations.*`; setup progress arrives through the events relay (subscribe with `deviceIds`) or poll `operations.job.get`.
- An older owner (without `OWNER_METHODS`) answers `unsupported_remote_operation` for the new names; there is no fallback to the legacy `runtime.*` bridge on purpose.
- Remote SSH alias / terminal / editor and file transfer are the follow-ups above.
