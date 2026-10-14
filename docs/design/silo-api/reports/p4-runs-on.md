# P4 Router “Runs on” implementation

Implemented the Runs on placement flow and a mock-backed guest Router boundary in Fjord. This is a partial implementation of [P4 §2](../design/p4.md#2-router-runs-on); it is not a production guest integration because the generated `guest.*` client adapter and several guest lifecycle readers are not available in this track.

## Delivered

- Added persisted per-project placement, defaulting existing projects to This Mac, and a Runs on menu in the Router project/folder picker. A guest placement stores its owner/computer identity and explicit guest folder; changing it affects future starts.
- Added a controller-side `~/.claude/settings.json` writer for Fjord-owned `sshConfigs` entries. It preserves unrelated settings and connections, backs up the original file, uses compare-and-replace retries, and has add/remove coverage using a temporary HOME.
- Added a `GuestClient` boundary and `MockGuestClient`. Guest Router setup installs the plugin and a portable Node hook/module into guest paths, edits guest Claude settings with a backup and hash-conditional write, and stores the signing key with mode `0600`. The hook uses guest Node and does not invoke the Fjord binary or a controller path.
- Added guest form, relay inbox, presence/registry, clock, transcript, and code-folder helpers. File watches are established before initial reads/writes where required; answers and relay messages use create-only writes; guest PID checks run through guest exec. The transcript reader uses the guest project tree and ranged reads, never the controller’s `ssh-<id>` mirror.
- Added preparation for `claude://code/new?ssh_host=…&ssh_folder=…&q=…`, pending “Ready in Claude” records, and guest-evidence matching. Fjord records the pending start before opening Desktop and does not send the first prompt itself.
- Adapted Router delivery, abort, forms, session/project grouping, routing, summaries, circles, triage, canvas, and waiting paths to carry session location. Guest routes use the guest client and do not fall back to local peer delivery. Desktop SSH fork remains blocked before mutation because C-2 is unproven.

The external behavior follows the [Claude Desktop SSH-link documentation](https://code.claude.com/docs/en/desktop#open-an-ssh-session-from-a-link). The Linux follow-up confirms the guest `PermissionRequest` hook fires in a Desktop SSH session; it also shows the guest transcript is authoritative because the local `ssh-<id>` copy lagged and remained 1,168 bytes smaller despite a newer mtime ([B-15](../probes/linux.md#b-15-permissionrequest-in-claude-code-desktop-ssh), [B-16](../probes/linux.md#b-16-live-transcript-freshness-and-background-task-output)).

## Commits

- `29b94e45 feat: add persisted Router project placement`
- `0a4fd221 feat: manage owned Claude SSH settings`
- `16712bf3 feat: add mockable guest file client`
- `00ffcdca feat(router): add guest Runs on sessions`
- This report is committed separately as `docs(router): report P4 Runs on implementation boundaries`.

## Verification

- `swift build --disable-sandbox` passed after the final product-source changes.
- The required `scripts/test.sh` invocation stopped before test compilation. SwiftPM failed to sandbox manifest compilation with `sandbox-exec: sandbox_apply: Operation not permitted`; the script’s test-summary check therefore failed. It was invoked once and was not retried.
- An earlier focused `GuestRouterTests` run exposed and led to fixes for a short transcript fixture and test-store persistence. The next focused build failed in concurrently edited Silo client test files (`FakeSiloUnixServer`/`SiloAPIClientTests`), before the guest test suite ran. There is no clean full-suite result for this snapshot.
- Offscreen `--window-shots` produced `window-router-composing.png` and `window-router-working-summaries.png` in `/private/tmp/p4-runs-on-shots`. They verify the Router window shell only; neither shot opens the Runs on menu. No live engine or guest session was started.

## Boundaries and remaining work

- `EngineClient.swift` and generated client files belong to the concurrent Silo client track. This implementation uses a separate `GuestClient` protocol and mock, but no production adapter connects it to generated `guest.*` methods yet. The generated adapter must map account, exec, guest file read/write/list/remove/watch, and alias operations into this boundary.
- The current computer picker sees the local owner inventory only. The present `ComputersModel` shape does not provide enough owner identity for the P4 owner-grouped multi-owner picker; selected placements currently have no remote `deviceId`.
- Guest installation requires Node 18+, Git, and Claude already present. The P4 `provision-runtime.sh`/runtime provisioning flow is not implemented.
- Persisted placements and pending starts are saved, but a fresh app launch does not rehydrate guest clients and reattach all file watches automatically. Guest liveness is not a complete tri-state model when evidence becomes inaccessible.
- Guest transcript reads do not yet maintain the P4 inode/size/mtime cache with replacement/shrink offset reset. Background task directories and guest fd inspection are not implemented; those readers live outside the owned files. The `RouterBrief` transcript consumer also remains local-only.
- The computer-removal flow does not yet reconcile Fjord-owned SSH settings or remove the engine alias. Remote-owner placement, RepoWorld/clone routing, and an end-to-end live guest validation remain unverified.
- The screenshot command did not capture the placement popover, so menu layout still needs a dedicated offscreen shot. The app shot is evidence of the Router shell, not acceptance evidence for the placement UI.

Next action: connect the generated guest client adapter, then run the saved project in a disposable Linux guest and verify form delivery plus guest transcript updates before claiming production readiness.
