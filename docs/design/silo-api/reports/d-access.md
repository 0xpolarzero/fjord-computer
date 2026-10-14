# d-access: the access domain handlers

Silo worktree `~/silo-work/d-access`, branch `engine/d-access`, from `engine/p2-dispatch` (`bd7c7c27`).
Two commits, never pushed:

| Commit | What |
| --- | --- |
| `d8152632` `feat(engine): carry GitHub sign-in and owner jobs over Connections` | Engine seams the domain needs (below). |
| `f232e3d7` `feat(silod): implement the access domain methods` | `silod/src/methods/access.rs` (all 36 methods), `app.rs` wiring, `silod/tests/access.rs`, a changeset. |

The previous agent left a large uncommitted diff (a first `access.rs`, plus engine edits). I reviewed it and kept its shape, but rewrote most of it. Reasons: it blocked async workers on SSH calls, it had no owner-side half for remote methods (`LocalAccess::access_dispatch` was never implemented in silod), `github.connect` with a `deviceId` and `github.connect.callback` were stubs, `connections.devices.remove` failed when no Connections key existed, `connections.devices.connect` published a malformed health event, and `network.unpublish` decoded the wrong params type. It had no tests.

## What each domain does

All methods are in `silod/src/methods/access.rs`; `owns()` is unchanged, so the registry-wide routing test still passes.

- **Routing.** A `deviceId` that is absent, or equal to this engine's own device id, runs locally. Any other id goes through the local engine to the owner over the existing Connections SSH bridge (`call_remote_typed`), always in `spawn_blocking`. The controller validates the owner's reply against the canonical `silo-api` type before returning it.
- **github.\*, secrets.\*.** One sync function, `run_local`, implements them against this engine's own state and publishes `github.changed` / `secrets.changed` with canonical payloads. The same function serves a controller's request on the owner (`SilodLocalAccess::access_dispatch`). Computer names are projected to `computerId` (and back for `configuration.save` / `retry` / `secrets.save`). Rows for computers that no longer exist are dropped rather than failing the whole read.
- **allowAnyDestination.** `secrets.save` with `*` in `allowedDomains` and no `allowAnyDestination: true` is refused before anything is stored, resolved or sent to another device (checked in the controller and again on the owner). The field is stripped before the engine request.
- **push.\*.** Local calls go to `host_push` and `host_push_operations`; remote calls use the existing `repository.push.*` bridge methods. `push.start` returns `push:<operationId>` (the owner keeps the job identity). `push.changed` is now published from the engine, with every push job-progress event, as a validated `PushOperation`.
- **network.\*, sshAccess.\*.** Local and remote, by computer id. A remote owner's own computer name is restored in place of the historical `silo-remote:<device>:<id>` string. `sshAccess.save` publishes `network.changed` with a freshly read network state (that event's catalogue payload is `NetworkState`).
- **connections.\*.** Status, enable, list, connect and the two SSH command helpers are thin. `connections.devices.health` is a pure read of recorded state; it opens no SSH connection. `connections.keys.revoke` runs locally or on the owner. `connections.devices.remove` revokes this Mac's key on the owner first (A-36) and only then forgets the device, closes its callback route, tunnels and viewers, and publishes `connections.devices.changed`. An unreachable owner or a failed revoke leaves the device saved. If this Mac never created a Connections key there is nothing to revoke, and removal proceeds.
- **Health.** `Health` now records `connected`, `busy`, `lastSeen` (RFC 3339 UTC) and the last error. Every successful owner reply counts as an observation (`call_remote_typed` marks it), a busy owner sets `busy` without counting a failure, and `connections.devices.changed` carries the complete `{devices}` projection when something visible changed (a `lastSeen`-only refresh is published at most once a minute).

## GitHub sign-in over SSH (A-17)

- **Owner.** `github.connect` is a new bridge Change method. It starts the normal connect job on the owner, waits up to 20 s for the browser link, and replies `{jobId, url}`. `github.connect.callback` is a new bridge Stream method, served before request dispatch like `guest.ssh`. It relays raw bytes only to the loopback listener of the active connect job, whose port is read from the pending authorization link and checked by the new `github::callback_port` (only `http://127.0.0.1:<port>/github/callback` is accepted). Any other job id gets an error.
- **Controller.** `github.connect {deviceId}` reserves the same loopback port locally before it returns, then listens there. For each browser connection it reads one bounded header (8 KiB, 2 s), opens a `github.connect.callback` stream to the owner, sends the header, and returns the owner's own HTTP reply (at most 64 KiB). It never relays anything else. A port collision or a failed stream cancels the owner job and returns an error; no unusable link is published.
- **Link exposure.** A controller shows a loopback authorization link (`github.state`, `github.connect.reopen`) only while its callback route for that device is live. Otherwise `pendingAuthorizationUrl` is `null`, and `reopen` returns an actionable "route unavailable" error. The App-install link has no callback and passes through.
- **Job mirroring.** The controller returns a job of its own and mirrors the owner's job: it polls the owner (`operations.job.get`, every 2 s), finishes its job with the owner's result or error, acknowledges the owner's job, and closes the route. Cancelling the controller job cancels the owner's. Five failed polls in a row end the job with an error and keep the owner's outcome unacknowledged.
- **`engine.sock` and the callback method.** `github.connect.callback` is engine-to-engine only; the local socket has no raw-stream upgrade, so it answers `unsupported_remote_operation` with a message that says so.

## macOS call site

`access.rs` has a `mod macos_proxy` marked `MACOS-PROXY`. The Linux paths in `GitHubRuntimeAccess` and `SecretsRuntimeAccess` check `macos_proxy::contains_name(computer)` first; today it is always `false`. Its stub bodies list the `proxy_*` entry points that `engine/p3-macos-proxy` adds in its Tauri commands (same shape, same eight operations). To wire macOS, replace the stub bodies and make `computer_name` (also marked) resolve macOS computers. I added `PendingRevocation::computer()` and `::name()` accessors in `secrets.rs`, which that branch also needs. It may add the same accessors, so expect a trivial conflict.

## Tests

- 27 unit tests in `access.rs`, covering every handler: param validation (`Invalid params`), routing to an unknown device, local results validated against the canonical types, id projections, the wildcard acknowledgement, push / network / ssh with unknown computers, key revoke, health, removal both ways, job serving, the callback relay (a real loopback pair), header bounds, and link exposure. `github.connect` starts a real owner job, reaches its listener through `callback_listener_for`, gets a 400 for a wrong state, cancels, and reads the outcome. No GitHub contact: the callback is rejected before any exchange.
- 1 socket-level test, `silod/tests/access.rs`: a real `engine.sock` with handshake, subscription, status / list / health, a saved device removed with its `connections.devices.changed` event, canonical reads, wildcard and remote-device errors, `github.connect.callback` refusal, and a `github.connect` job cancelled and acknowledged through `operations.*`.
- Engine tests added: `callback_port`, key revocation (duplicates, unrelated same-blob keys, missing trailing newline, absent file or key, a managed symlink with and without the key, malformed key), health transitions. The METHODS classification test now lists the new methods.
- The fixtures never use `access::install`: its GitHub worker reads the real credential store. Use `install_host` plus `silo_engine::secrets::install()` in tests (`install` = `install_host` + the two workers).
- No app, VM or GitHub contact. Two early test runs used the full `install` and so the worker read the real dev credential store (read only); I removed that.

## Gate

`cargo test --locked --workspace --no-fail-fast` from `app/SiloUI` (`CARGO_BUILD_JOBS=3`): silo-api 27, silo-ui 71, silod lib 68 + the new socket test + handshake, all pass. `silo-engine` lib: 2,330 passed, 2 failed, 30 ignored.
- `backup_controller::tests::install_schedules_pending_import_recovery_outside_tokio_runtime` fails identically on the pristine base (`bd7c7c27`, checked by stashing my work). Not mine.
- `dependencies::tests::version_probe_accepts_the_output_limit_and_rejects_overflow_on_either_stream` timed out under the machine's heavy parallel load and passes alone (and in the earlier full run). `remote::dispatch_tests::owner_directory_lock_and_socket_are_private_to_this_account` flaked once under load and passes alone.

`cargo fmt --all --check` is not clean on the base, for files this track does not own: `backup_controller.rs`, `jobs/registry.rs`, `macos_computers.rs`, `methods/{checkpoints,computers,mod,services}.rs`. Every file I touched is rustfmt-clean (formatted per file, so the rest of the tree is untouched). The coordinator should format the others once at merge.

## Deviations from the spec, and open points

1. **Remote job identity.** The spec keeps `(deviceId, jobId)` of the owner for `operations.get / cancel / acknowledge`. The core `operations.*` arms still ignore `deviceId`, and that is outside this track, so a remote `github.connect` returns a controller-side proxy job that mirrors the owner's. When core routes `operations.*` by `deviceId`, return the owner's `jobId` instead and delete `mirror_owner_connect`. The owner side already exists: bridge methods `operations.job.get`, `operations.cancel` and `operations.job.acknowledge` serve jobs in the owner's registry. A remote-guest track that adds the same bridge names will conflict trivially; keep one.
2. **Removal is not persisted.** The spec's `RemovalIntent` phases (revoke_pending, owner_confirmed, local_cleanup_pending) are not implemented. The sequence is owner revoke, then local removal, in one call, and a retry repeats the idempotent revoke. The gap is a crash between the two steps: the revoked key can no longer authenticate the retry, so the device stays saved. The spec says never to reinstall the key to recover; the user removes the device again after reconnecting by the account-key fallback.
3. **Remote events are not relayed.** A controller does not publish an owner's `github.changed` / `secrets.changed` and so on; `events.subscribe` with `deviceIds` still refuses non-local ids (core). Controllers re-read after a remote change.
4. **No standalone health timer.** Health updates on every successful owner exchange and on `device_snapshot` polls (Fjord's `computers.list` with a `deviceId`); there is no background observer, so an idle device's `connected` is as old as the last exchange. Add the bounded timer when the P2 maintenance budget is chosen.
5. **GitHub registration is unqualified (B-25).** The same-port callback is the spec's hypothesis; synthetic tests prove the relay, not that GitHub accepts a redirect to the controller's loopback port for a screenless owner. That needs the owner's real GitHub round trip.
6. **Spec-vs-code notes.** `pendingAuthorizationUrl` was added to the engine's `github::snapshot`, as a new field (not a `silo-api` change); `silo-api` already had it, so its schema is unchanged and was not regenerated. `secrets.*` results are `Secret[]` as in the registry (the `SecretsSaveResult = Secret` alias in `silo-api` is stale and unused).

## For the next tracks

- `install_host` is the test-safe install; the real `install` and `start_connections` are wired in `app.rs` after the engine context.
- `remote.rs` additions (all additive): METHODS entries `github.connect`, `github.connect.callback` (Stream), `operations.job.get | cancel | acknowledge`, and `connections.keys.revoke`; `GITHUB_CALLBACK_STREAM`; `pub publish_device_health`; `LocalAccess::github_callback_stream`; `computerName` on remote network and ssh rows.
- A changeset was added: `app/SiloUI/.changeset/connections-device-removal-revokes-key.md`.
