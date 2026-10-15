# E2E GUI fixes (from probes/e2e-gui.md)

## 1. Shared state
New `AppIdentity` (Sources/Fjord/AppIdentity.swift). Debug builds, and release builds run with `FJORD_SILO_SOCKET_PATH`, `FJORD_E2E`, `FJORD_SUPPORT_FOLDER` or `--e2e`, use:
- support folder `~/Library/Application Support/Fjord Dev` (state.json, forms, plugin, relay key, router trace, Triage runs); `FJORD_SUPPORT_FOLDER` overrides it. The installed app keeps `Fjord`.
- engine socket `~/.silo-dev/engine.sock` (the dev silod's); `FJORD_SILO_SOCKET_PATH` still wins; the installed app keeps `~/.silo/engine.sock`.
- LaunchAgent plist `org.silo.dev.engine.plist` (does not exist, so a dev build can never register or unregister the installed `org.silo.preview.engine`).
Not changed (remaining collision): Claude Code's user-scope plugin marketplace is named `fjord` on both builds, and `~/.claude/settings.json` hooks/sshConfigs entries are shared; a dev build re-points the marketplace at its own folder. Renaming needs a plugin manifest change; left alone.
Tests: AppIdentityTests.

## 2. Failed start toast
The failed-job path already formatted errors, but two gaps were closed in ComputersModel: (a) a finished event arriving before `perform` learned the job id was presented once with the generic label "Computer operation" and then deduplicated; it is now presented again with the real action once known; (b) the last failure per computer is kept (`computerFailures`) and shown on the computer row and the top of the detail page until the next start/stop/delete succeeds. Could not reproduce the exact "completed" text from code alone (no silod.out evidence of the job event). If the engine sends `outcomeChunked: true` with no `error`, Fjord would still read it as success; that is the remaining suspect and is not handled. Test: ComputerJobReceiptTests.failedStartShowsItsErrorInTheToastAndOnTheComputer.

## 3. Guest form card
Matching required plugin presence (live, key id, inbox capability) joined to the guest registry. Presence never appeared, so no evidence, so the pending start stayed `readyInClaude`, though the hook's held form and the registry entry (`hostSessionId`) already identified the session. Fix (Fjord side): `GuestSessionObserver.read` now also builds evidence for a live registry session (PID alive) whose CLI session has a held form, flagged `formBacked` with no capabilities; the matcher accepts it, and relay still requires the inbox capability, so messages are not sent to such sessions. A missing presence folder no longer aborts the read. The cause of the empty `presence/` (guest plugin modules not running) is not addressed here; another agent is on it. Not driven live. Test: GuestRouterTests.pendingStartMatchesAFormBackedSessionWithoutPluginPresence.

## Verification
`swift build` and `scripts/test.sh`: 1920 tests passed.
