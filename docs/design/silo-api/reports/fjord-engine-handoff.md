# Fjord engine update handoff

Fjord side of design/p2 §3 and decisions A-1, A-6. Replaces the old "update blocked until a safe handoff exists" behavior of `EngineLauncher` (reports/p4-bundle.md).

## What was built

`Sources/Fjord/EngineHandoff.swift` (new):
- `EngineHandoff.run`: the coordinator. Steps, in order:
  1. Take `<engine dir>/installer.lock` (`FlockEngineInstallLock`: `open` 0600 with `O_NOFOLLOW|O_CLOEXEC`, `flock(LOCK_EX|LOCK_NB)`; engine dir is `<socket dir>/engine`, the same path Silo's `engine_update::engine_directory` uses). The lock is released by `defer`, so every exit path drops it.
  2. Handshake again under the lock and compare versions ("under the install lock, compare again", p2 §1.4). If another app already updated the engine, nothing else happens.
  3. `engine.update.prepare`, then poll `operations.job.get` until it finishes. The result is `{resuming:[{id,name}]}`.
  4. `engine.shutdown {reason:"update", stopComputers:false}`, then wait until nothing listens on the engine socket (`SocketEngineProbe`).
  5. Re-register the LaunchAgent: `unregister()` (when enabled or awaiting approval), then `register()`. The bundle path is the same after a Fjord swap, so this points launchd at the new silod and starts it (RunAtLoad).
  6. Handshake until the new version answers (must be at least the bundled one).
  7. Poll `computers.list` until every id in `resuming` is running. Anything still not running is reported by name, not treated as failure (nothing can be undone by then).
- Failure before the old engine leaves (prepare refused or timed out, shutdown rejected, engine never exits): `engine.update.abort` is called, the old engine keeps serving, outcome `.blocked`. If abort itself fails, the message says so (the engine's watchdog aborts 30 s after the lock goes).
- Failure after it leaves (register refused, approval needed, new engine silent, wrong version): outcome `.failed`; the lock is released so whichever engine starts next restores the saved set (Silo: "a new version, or no installer, restores at once"). No abort is possible then.
- `EngineHandoffMarker`: a UserDefaults flag.

`EngineLauncher`:
- A newer bundled engine no longer blocks: the old engine stays connected and serving, and `update` (`EngineUpdateStatus`: none, available, running(phase), blocked, failed, completed) reports it. `.updateBlocked` is kept only for the same-version-different-build case.
- `updateEngine()` runs the handoff in its own unstructured task, one at a time, so leaving the Computers page doesn't cancel it mid-way. `continueUpdateIfAutomatic()` runs it when Fjord's LaunchAgent is already registered (`SMAppService` status `.enabled`).
- Silo.app owns the engine and Fjord's agent is not registered: the same handoff, but only after the user presses "Update engine" in Computers (registering Fjord's agent stays consent-gated, as `enable()` is). Source detection (`proc_pidpath`) is not used for this decision: after a Fjord bundle swap the running silod's path no longer matches the bundle.
- `EngineAgentServicing` gained `unregister() async`.

`Store`: `inspectComputersEngine()` attaches, then runs the automatic update and re-attaches the new client; `updateComputersEngine()` is the button; `resumeEngineHandoffIfPending()` runs at `startServices`. `hasEngineConnection` goes false if the client is gone after a failed handoff (the page falls back to the enable page showing the failure and Retry).

`Updater`: `install()` compares the staged app's `engine-manifest.json` engineVersion with the running app's. If they differ it sets the marker before the swap (and clears it if the swap throws). The new Fjord's first launch sees the marker, connects (never registers on its own) and runs the handoff. Doing it in the new Fjord, not the old one, is deliberate: the new silod only exists after the bundle swap, and the old process quits right after swapping; the old silod keeps running from the replaced inode, so computers are untouched until then.

UI: `EngineUpdateBanner` at the top of the Computers page: progress with the step ("Saving running computers…", "Stopping…", "Switching…", "Starting…", "Resuming computers…"), the blocker with Try again, the Update engine button when consent is needed, and the completion line naming resumed and still-resuming computers. A post-swap failure shows on the enable page.

`UnavailableEngineClient` lost `final` and got an explicit `invoke`, so tests can subclass it.

## Tests

`Tests/FjordTests/EngineHandoffTests.swift` (12): fakes for the flock, the SMAppService wrapper, the probe, the connector and an engine client (subclass of `UnavailableEngineClient`). Covered: exact call order with lock held across it; resumed and missing computers; refused prepare (abort, no shutdown, no register, still connected, lock released); failed shutdown; engine that never exits; lock held elsewhere; engine already updated by another app; register fails after the swap (no abort, lock released); new engine never answers; no auto-start when Fjord's agent is unregistered, then manual start; retry after blocked; the real `flock` (exclusive, released, 0600). `UpdaterTests` (3): marker set only when the staged engine differs; cleared on a failed swap. `EngineLauncherTests`: the old "blocked" test now asserts the old engine keeps serving with `.available`.

Results: `swift build` ok. `scripts/test.sh`: 1746 tests, 1 failure: `GuestRouterTests.guestTurnCompletionAndIdentitySurviveLocalMirrorRefresh` (unrelated, timing; passes alone). No LaunchAgent was registered and the app was not launched.

## Deviations, open points

- Nothing exercised the real SMAppService unregister/register or a real silod; both need a signed Dev run. Open risks: (a) whether `register()` right after `unregister()` restarts a service that exited 0 (should, RunAtLoad; fallback would be `launchctl kickstart gui/<uid>/org.silo.preview.engine`); (b) Silo.app and Fjord both registering the label `org.silo.preview.engine` from different bundles: Fjord surfaces the macOS error as a post-swap failure, but the old engine has already left and the saved set restores when any engine starts; consider asking the user before the shutdown if Fjord's agent isn't registered (currently the Update button is that consent).
- Quitting Fjord mid-handoff drops the lock; the engine's watchdog then aborts a prepared update after 30 s.
- If the engine reports no capability to save a computer, prepare fails and the update shows as blocked with the engine's message; nothing is retried automatically until the next launch or Try again.
- Production timing: 0.5 s polls; job wait up to 8 min, exit 2 min, start 1 min, resume 2 min.
