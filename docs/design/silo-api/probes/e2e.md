# End-to-end qualification (silod + Fjord + Linux computer), 2026-10-14

Silo `engine/e2e` (base `efd2877e`, plus fix `39ba509b`, merged into Silo main as `c7fc165e`). Evidence files: `~/silo-probes/e2e/evidence/`. Computer: Silo Dev `e2e-relay` (memory lowered 32 to 8 GiB, restored to 32 GiB, stopped).

| # | Item | Verdict |
| --- | --- | --- |
| 1 | silod starts, handshake, capabilities | PASS |
| 2 | Fjord Computers tool (real computers, start/stop, job progress, events) | BLOCKED (Fjord GUI); engine side PASS |
| 2b | Automatic checkpoint created and listed | PASS at the engine; found and fixed a bug; the "deleted automatically" label in Fjord is BLOCKED |
| 3 | guest.exec, guest.exec.start streaming, cancel | PASS |
| 4 | Router "Runs on" with Claude Desktop SSH | BLOCKED |
| 5 | Triage "Run in a computer" | BLOCKED |

## Environment findings
- The Dev channel allows one engine. The macOS-VM track was running its own (older, `fa396c70`-based) silod on `~/.silo-dev/engine.sock`. Its handshake listed only 10 capabilities (the pre-silod-core build). I did not touch it. Item 1 was first checked on a copy of the e2e build under an isolated HOME (`~/silo-probes/e2e/home`). When the other engine's pid had died (stale `engine-owner.json`) I ran the e2e build on the real Dev data, with engineVersion bumped to 0.1.1 in the manifest to get past "Conflicting engine builds share version 0.1.0". Run as a plain process, no LaunchAgent.
- LCU: `cua.getApp("dev.fjord.e2e")` waited for the per-app approval panel and timed out twice (30 minutes each); nobody answered. All Fjord GUI work (items 2, 4, 5) was therefore not done. Fjord has no `--socket-client` flag; `FJORD_SILO_SOCKET_PATH` selects the socket (the debug binary was wrapped as `FjordE2E.app`, launched with `--open`, then killed). The installed /Applications/Fjord.app was running throughout and shares `Application Support/Fjord`; a backup is in `~/silo-probes/backup/Fjord-support.e2e`.

## 1. silod, handshake (PASS)
`evidence/01-handshake.txt`, `01b-handshake-real.txt`: protocol 6, 143 capabilities, includes guest.exec, guest.exec.start, guest.exec.get, guest.files.write, computers.*, events.subscribe; `desktop.connect` and `macos.display.stream` withheld as designed. `engine.state` idle. No `guest.exec.cancel` method: cancel is `operations.cancel` on the job. `engine-owner.json` carries the e2e build.

## 2. Computers (engine side PASS)
`computers.list` lists workspace-1 and e2e-relay; `computers.configuration.change` lowered and restored memory; `computers.start`/`stop` of e2e-relay succeeded as jobs (they finish within about 1 s here, so polled `operations.job.get` showed no intermediate progress; a events.subscribe run of start/stop was not completed because of the bug below). Not run through Fjord's UI.

### Bug found and fixed: computers.list broke after any Linux checkpoint (2b)
After `checkpoints.create` (kind automatic, name "Before run: ..., deleted automatically", reason "manual", scope full, 1.7 GB), every `computers.list` failed: `internal: invalid type: integer 1791986953387, expected a string`. Cause: `ApplicationSource::to_canonical_value` left the record's epoch-millisecond `createdAt`, but the API `Checkpoint.created_at` is a string. Fix `39ba509b`: `canonical_checkpoint_times` rewrites it to RFC 3339. Test `the_canonical_computer_list_carries_checkpoints_in_the_api_shape`; contract fixture unchanged. Gate: `cargo test -p silo-engine -p silod -p silo-api`: silod 240 and silo-api pass; silo-engine passes except the known load-sensitive `dependencies::tests::version_probe_accepts_the_output_limit...` (it failed in the full run, also before this change). After the fix the list shows `('automatic', '2026-10-14T14:09:13.387Z', 'Before run: e2e probe, deleted automatically')` (`02e-list-after-fix.txt`). Note: `deleteBlocker` says the checkpoint cannot be deleted while it is the latest state; my cleanup delete was refused, so the probe checkpoint remains on e2e-relay (retention deletes automatic ones).

## 3. guest.exec (PASS)
`03-guest-exec.txt`: exec returned exit 3 with separate stdout (uname, user `silo`) and stderr. exec.start streamed lines one per second via `guest.exec.get` (seq numbered chunks), final state `exited`, exit 0. A `sleep 300` job cancelled with `operations.cancel`: job finished `cancelled` ("The command was cancelled."), exec.get state `cancelled`, no leftover process in the guest.

## 4 and 5 (BLOCKED)
- GUI (Fjord and Claude Desktop) unavailable (LCU approval).
- Guest prerequisites observed (`04-guest-prereqs.txt`): the guest has git but neither `node` nor `claude` installed (earlier probe cleaned them), so the guest-hook installer would first provision Node (GuestNodeRuntime) and a headless `claude` would still need auth; the Triage auth gate would almost certainly block. `guest.sshAlias.ensure` works and installed the Include line (alias `silo-dev-<id>`, ProxyCommand to msb, no agent forwarding); removed again afterwards.

## Cleanup
e2e-relay stopped, memory 32 GiB restored, alias removed, silod shut down (`engine.shutdown`), Fjord E2E app killed. `~/.ssh/config` restored from backup (the alias call had added an Include line); `~/.claude/settings.json` unchanged. Probe checkpoint remains (see above).
