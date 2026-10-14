# remote-guest-ssh: terminals, editors, aliases, transfers and watches for another device's computers

Silo worktree `~/silo-work/remote-all`, branch `engine/remote-guest-ssh`, cut from `main@3299b4dd` (main had not moved, no merge needed). Fast-forwarded into `microsandbox-workspaces` main at `e29122f0`. Never pushed. No VMs, no real SSH.

## Commit

| Hash | What |
| --- | --- |
| `e29122f0` | `feat(engine,silod)`: everything below, plus changeset `open-terminals-editors-and-files-on-another-macs-computers.md` (one commit: the pieces share `remote.rs`, `guest.rs` and `editor.rs`) |

## Finding

The brief's premise was partly stale. `--remote-guest`, `run_remote_stream`, the owner's `guest.ssh` bridge stream and the engine.sock raw upgrade (for macOS guests, `dispatcher::open_stream`) already existed. What was missing:

- the owner's bridge `guest.ssh` served **Linux computers only** (`spawn_stream` runs `msb ssh serve`); a macOS computer had no owner side;
- the controller-side canonical wiring (alias in the canonical shape, terminal, editor), and `guest.prepare` was a legacy bridge method whose Linux-only arm was the only implementation;
- transfers and watches were refused.

So no new raw-stream upgrade on engine.sock was needed: a remote alias's ProxyCommand goes `silod --remote-guest <owner> <computer>` -> ssh to the owner's bridge -> `guest.ssh` stream.

## What was built

1. **Remote guest SSH** (`silod/src/methods/guest_remote.rs`, `engine/src/editor.rs`).
   - `guest.sshAlias.ensure` for another device: reads the owner's `guest.account` (user, home; the OS is told by `home == /Users/silo`, which picks `/workspace` or `/Users/silo/workspace`), validates the folder for that OS, writes `silo-remote[-dev]-<deviceId>-<computerId>` below `<state>/desktop-remote/ssh/` with the controller's per-device key (`<deviceId>.key`), the owner's pinned host key and `ProxyCommand '<silod>' '--remote-guest' '<device>' '<computer>'`, installs the `Include` (or reports it with `installInclude:false`), and probes the alias. The owner authorizes the key through `guest.prepare` on the owner, whose error codes (`not_running`...) survive.
   - `guest.sshAlias.remove` deletes that alias's `.conf` and `.known_hosts` (idempotent), removes the `Include` with the last `.conf`; the device key and published-port entries stay.
   - `terminal.command` -> `ssh -F <config> -t <alias>`; `editor.command` -> alias with probe, then the chosen editor's argv (Zed URI or VS Code workspace file, macOS roots for a macOS owner).
   - `guest.prepare` is now a **canonical owner method** (`OWNER_METHODS`, Change class), so a controller can also send it with `deviceId` through the generic route. The Linux authorization body moved to `remote_access::authorize_guest`; the legacy bridge entry and arm are gone (same wire shape, old controllers still work against a new owner).
   - **Owner side `guest.ssh` for macOS** (`remote.rs`: `is_linux_computer`, `open_macos_guest_ssh`, `serve_guest_tcp`): TCP to the guest's port 22 through `macos_computers::open_guest_ssh_stream`, relayed with `relay_tcp`, ended by the guest guard (computer stopped), by unpublishing the port (`revoke_port_streams` and the guard), or by shutdown. Same budget, port registration and `purpose:"port"` semantics as the Linux path.
2. **Remote transfers.** `files.upload` / `files.download` with `deviceId`: `transfer::upload_files_remote` / `prepare_download_remote` create the local `transfer:<id>` job first, then connect (authorizes the key, writes the alias without touching `~/.ssh/config`), then run the existing bounded SFTP transaction (`*_with_transport`) through the alias. Bytes ride the ProxyCommand's `guest.ssh` stream, so progress events, cancel and the job's outcome are the local ones; a connection failure fails the job with the owner's message. Roots: Linux workspace/Downloads, or the macOS workspace/Downloads, by the owner's OS.
3. **Watch relay.** New bridge Stream `guest.files.watch` (`engine/src/remote_watch.rs`, owner loop `serve_watch_stream`): the owner starts the watch through a new `LocalAccess::start_guest_watch` (silod: `guest::start_owner_watch` -> `guest::start_watch`) and writes `{"type":"changed","path"}` frames and 10 s heartbeats; a refusal (no such computer, not running, watch limit) comes back before the reply. The controller's `guest.files.watch` with `deviceId` subscribes the caller exactly like a local watch, opens the stream, and a relay thread publishes each hint to **that subscription** (`publish_to_subscription`); `events.unsubscribe`/disconnect drops the stream (and so the owner's watch); a lost or stalled (35 s) stream closes the subscription, as a stopping computer ends a local watch.

## Deviations

- **Watches use their own stream, not the `events.subscribe` relay.** `guest.files.changed` is subscription-scoped; the events relay is per device with a shared owner subscription and excludes client-scoped events. A dedicated Stream (same framing/heartbeat/stall pattern, same stream budget) keeps the hint on the caller's subscription and the owner's watch life tied to the stream. The events relay still does not carry `guest.files.changed`.
- Transfers go over SFTP through the alias (as local ones do), not over chunked `guest.files.read/write`; no new transfer protocol.
- `editor.command` / `terminal.command` / aliases install the `Include` on the controller (as the local ones do).

## Tests (two-engine seams, no SSH)

- `silod` `methods::guest_remote` (11): alias contents/ProxyCommand/key/pinned host key/Include/probe; macOS owner folder and wrong-OS folder refused before any `guest.prepare`; owner refusal keeps `not_running` and writes no entry; unreachable owner is `not_found`; failed probe keeps the entry; removal idempotent and keeps the key; terminal argv; editor argv for both OSes; transfer transport roots; a remote download whose connection fails fails through its `transfer:` job (and bad requests are refused as locally); watch hints reach the caller's subscription and a lost stream closes it; a refused watch leaves no subscription.
- `silod` `methods::guest` (2 new, plus the old "other devices are refused" test narrowed to the methods that still are local-only): **two real engines in one process**: the owner stub runs `serve_owner` on a fixture engine with the fake `msb`, so `guest.account`/`guest.prepare` run the real owner code and the controller's key lands in the owner's `authorized_keys`; the watch test runs the real owner stream loop (`Watching`/`serve`) over a socket pair into the controller's relay and a real file change arrives as `guest.files.changed`.
- `silo-engine`: `remote_watch` (3 frame/loop tests), `serve_guest_tcp` (echo through a macOS-style TCP guest, guard end, port revocation, invalid params), `is_linux_computer`, `serve_watch_stream` (refusal before reply, hint, controller leaves, permit released), `editor` (remote alias by ids, one key per owner, Include kept until last entry, wrong account/host key refused, argv helpers), `transfer` (connect failure), METHODS/OWNER_METHODS classification updated.
- `silod` `methods::remote` audit guard updated: `editor.command`, `terminal.command`, `guest.sshAlias.*`, `files.upload/download`, `guest.files.watch` are "own routing"; `guest.prepare` is an owner method; only `display.show/close` and `clipboard.transfer` remain refused by design.
- Gate: `cargo test --locked -p silo-engine -p silod -p silo-api --no-fail-fast`: silo-api 31, silo-engine 2730 passed (32 ignored), silod 276 plus socket tests, 0 failed (one run of `other_devices_are_refused...` failed before I updated that stale test; green after). `cargo +1.94.0 fmt --all --check` clean. silo-ui not built (no change to its sources).

## For the next tracks

- Fjord can now send `deviceId` on `guest.sshAlias.ensure/remove`, `guest.prepare`, `terminal.command`, `editor.command`, `files.upload/download` and `guest.files.watch`. The alias name is `silo-remote-<deviceId>-<computerId>` (`silo-dev-remote-` for Dev); `home` in the ensure result is the owner's account home. Router "Runs on" a remote computer can use the alias as `sshHost`.
- An older owner lacks the macOS `guest.ssh` and the `guest.files.watch` stream (the latter answers unsupported); `guest.prepare` works against old and new owners.
- Not verified over real SSH between two Macs: the `--remote-guest` hop, SFTP through it, the macOS TCP relay against a real guest, and the 35 s stall limit are covered only by the seams above. A live qualification is still needed.
- The ProxyCommand is `std::env::current_exe()` of the engine that wrote the alias (silod or Silo.app); it is rewritten by the existing `refresh_configs` when the executable moves.
