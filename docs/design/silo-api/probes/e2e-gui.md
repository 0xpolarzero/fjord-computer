# End-to-end GUI qualification (silod + Fjord + Linux computer + Claude Desktop), 2026-10-15

Silo `engine/e2e-gui` (base `086fb8d4`, plus fix `3b08abb6`, fast-forwarded into Silo main in `microsandbox-workspaces`, not pushed). Fjord main with fix `a07701e6`. Evidence: `~/silo-probes/e2e-gui/evidence/` (PNG screenshots, `silod.out`, `cargo-test.log`, config diffs). Computer: Silo Dev `e2e-relay` (memory 32 to 8 GiB, restored to 32 GiB, stopped). macOS 26.5. silod ran as a plain process from `~/silo-probes/e2e-gui/bundle.app`, signed with `Fjord Dev` (hardened runtime). Fjord: debug binary wrapped as `FjordE2E.app` (bundle id `dev.fjord.e2e`, `FJORD_SILO_SOCKET_PATH=~/.silo-dev/engine.sock`, a stub `engine-manifest.json` in its Resources so the launcher accepts the running engine). The LCU approval panel was answered by the owner for FjordE2E and Claude.

| # | Item | Verdict |
| --- | --- | --- |
| 1 | Computers tool: real computers, Start/Stop from the UI, job progress, "deleted automatically" label | PARTLY: list, start, stop, label PASS; job progress not observable (jobs finish in about 1 s) |
| 2 | Agent tools: status panel, Set up, ready | PASS after a fix (guest installer permission bug) |
| 3 | Router "Runs on" | PARTLY: placement, sshConfigs entry, guest hook and plugin install, deep link, Send, guest hook firing PASS; live form card and answering from Fjord FAIL (stops at missing plugin presence) |
| 4 | Triage "Run in a computer" | BLOCKED at the production gate (code reading; UI not driven) |
| 5 | Keychain repair | PASS (banner, Allow access, macOS dialog recorded; not answered) |

## Bugs found and fixed
1. **Fjord spoke protocol 1; silod serves 6** (`a07701e6`). `SocketEngineClient.defaultProtocolRange` was 1...1 and the handshake failed with "Incompatible protocol range" (`silod.out`). Nothing could connect to a real silod. Now 6...6; fake servers and tests updated; filtered tests pass (32).
2. **Agent tools setup always failed with "Permission was denied"** (Silo `3b08abb6`, `guest/agent-tools.py`). The Claude installer script is downloaded into a root-only `mktemp -d` dir and then run as the working account (`runuser -u silo`): `bash: .../claude-install.sh: Permission denied`. Fix: `Path(work).chmod(0o755)` before running it. Found by running the script by hand in the guest as root; after the fix, removed Node and Claude from the guest and ran Set up from Fjord: ready. Gate: `cargo test --locked -p silo-engine -p silod -p silo-api --no-fail-fast`: 3070 passed, 0 failed (`cargo-test.log`). No test added for the python script itself (it only runs in a guest).
3. **Hand-assembled engine bundle**: `msb` signed with hardened runtime and no `disable-library-validation` cannot load `libkrunfw` ("different Team IDs"), so every Linux start failed with "The runtime did not complete the operation" (`sandboxes/e2e-relay/logs/boot-error.json`). Not a product bug (live-final's sign.sh does not cover Linux); the bundle was re-signed with that entitlement. A Linux computer start failure shows only the generic text.

## 1. Computers (PARTLY)
- Real computers listed: `workspace-1` and `e2e-relay` with state, CPU, memory (`01a-computers-list.png`). Settings, Computers toggle, sidebar entry and detail page work.
- Start from the UI: `01d-start-*.png`; after it `Running` (job finished within seconds; polled progress never visible). Stop from the UI: `01e-stop-*.png`, engine confirms `stopped`.
- The automatic checkpoint appears: "Before run: e2e probe, Automatic, Full, deleted automatically, 2026-10-14T14:09:13.387Z", 1.79 GB (`01b-detail-stopped-checkpoint.png`, also in the Overview after the fix of the previous run).
- Not shown: intermediate job progress (start and stop each finish in about 1 s here). A stale unacknowledged job from the previous run showed "The computer did not accept SSH logins in time." and was acknowledged.
- Observation (not investigated): while Start was failing at the engine (item 3 of the bug list), the Fjord toast still read "Computer operation completed" and the Start button did nothing visible; the failed job error was not surfaced. Engine jobs `job:191`, `job:192` finished with errors.

## 2. Agent tools (PASS after fix)
- Panel on a stopped computer: "Start the computer to check". Running: "Agent tools: Missing, Set up" (`02a-setup-1..3.png`).
- First Set up: "Setting up the agent tools failed: The computer operation: Permission was denied" (bug 2). The text names no cause; the engine's failure categorizer maps the guest's "Permission denied" to a storage message.
- After the fix: "Agent tools Ready, Node.js 24.21.0, Claude Code 2.1.287" (`02b-setup-4.png`). The guest `claude` is not signed in by Silo.
- Wording nit: with only Claude missing, the text says "Node.js and Claude Code aren't installed".

## 3. Router "Runs on" (PARTLY)
Test project: `~/silo-probes/e2e-gui/projects/e2e-relay-test` (a git repo in a Code folder added in Settings), guest folder `/home/silo/e2e-proj`.
- Runs on menu lists This Mac and `e2e-relay · Linux · Running · Healthy`; guest folder prompt `03a-runs-on-guest-folder.png`; placed.
- Router message `@e2e-relay-test start a new session and tell it: use the AskUserQuestion tool ...` produced "Ready in Claude" (`03b-ready-in-claude.png`).
- Fjord wrote the `sshConfigs` entry in `~/.claude/settings.json` (`fjord-local-<computerId>`, name "e2e-relay · silo", `sshHost silo-dev-<computerId>`; the file was also re-serialized with keys sorted) and `guest.sshAlias.ensure` added an `Include` line to `~/.ssh/config`. In the guest: `~/.local/share/fjord/router/{fjord-form.sh,form-hook.mjs,plugin/,forms/,presence/,relay/,relay.key}`, `~/.claude/settings.json` with the `PermissionRequest` hook (`AskUserQuestion|ExitPlanMode`), `enabledPlugins fjord@fjord`, the marketplace; `claude plugin list` shows `fjord@fjord` enabled.
- Open in Claude opened the deep link in Claude Desktop: "Use this SSH connection?" (e2e-relay · silo, `/home/silo/e2e-proj`), then (first time) "Trust workspace?"; the prompt was prefilled. Both were accepted for the disposable VM. I pressed Send. The guest session ran and Desktop showed the AskUserQuestion.
- **The guest hook fired**, twice (two sessions): `forms/<session>-<ms>-<pid>.json` with the question; Fjord read it (`guestPendingForms` in its state held the form).
- A card for the first guest session appeared in Fjord's Router ("Color preference question", project e2e-proj, "Needs your OK"), but only after the turn ended (built from Desktop's session metadata), and its text is the later LCU-update question, not the form.
- **Stop**: for the live question there was no Router form card and no way to answer from Fjord. The pending start stayed `readyInClaude` (never `matched`). Cause (INFERRED from code and guest state): matching needs presence files from the Fjord plugin (`register.ts`, `session.start` hook writes `presence/<session>`), and `presence/` stayed empty in both sessions although the plugin is enabled and the registry entry (`~/.claude/sessions/<pid>.json`, with the right `hostSessionId`) exists. Adding `"channelsEnabled": true` to the guest settings (the Mac has it) did not change it. Why the module is not run in the guest's Desktop-launched session is unresolved. Needs a dedicated look (try `claude --debug` in the guest, check whether the CLI version or a flag gates plugin modules).
- Answering from Fjord and checking delivery: NOT DONE (blocked by the above). The Desktop questions were answered with Skip in Desktop.
- Environmental finding: the real `/Applications/Fjord.app` shares `~/Library/Application Support/Fjord/state.json`; it overwrote the test app's state (the Computers toggle and Code folder did not persist across launches; the final state has none of my changes except Router `seen` and a `folderColors` entry for `/home/silo/e2e-proj`).

## 4. Triage "Run in a computer" (BLOCKED, from code, UI not driven)
Not run through the UI: it needs a Triage rule on the owner's real inbox. Stop point from the code: `ComputerRunCoordinator.run` goes to phase `preflight` ("Checking authorization and the selected computer") and then throws `gateClosed(ComputerRunGate.productionBlocker)`, because the production coordinator is built with `authorization: .blocked(...)` (ComputerRun.swift 1308, 1338): "Gated: Claude OAuth Bearer substitution is unproven (B-17)...". Nothing touches the workspace, checkpoint or computer before that. Behind the gate, the next requirements are an active `CLAUDE_CODE_OAUTH_TOKEN` secret assigned to the computer (`secrets.list` currently returns `[]`, and the vault is a denied Keychain item) and GitHub access.

## 5. Keychain repair (PASS)
`engine.credentials.status` showed `deniedCount: 2` (`githubSignIn`, `secretsVault`); Fjord showed the banner on Computers: "After this update, Silo's engine needs your permission to use its saved credentials. Press Allow access. macOS then asks once for each saved item: choose Always Allow in each dialog." (`05a-keychain-banner.png`). Allow access turned into "Waiting for macOS...". macOS then showed (French UI, SecurityAgent): "Silo Engine Dev veut utiliser vos informations confidentielles gardees dans « org.silo.dev.github » de votre trousseau. Pour autoriser ceci, saisissez le mot de passe du trousseau « session »." with a password field and the buttons Toujours autoriser / Refuser / Autoriser (`05b-keychain-dialog-fullscreen.png`, full screen). I did not answer it and did not type anything (a password is needed). The keychain is named "session", the dialog asks for its password even for Autoriser.

## Cleanup
- e2e-relay stopped from the Fjord UI; memory restored to 32 GiB; guest left with Node, Claude, `/home/silo/e2e-proj`, the Fjord hook and plugin, `channelsEnabled` (backup `~/.claude/settings.json.e2e-pre-channels` in the guest).
- `~/.claude/settings.json` and `~/.ssh/config` restored from `~/silo-probes/backup/*.20261015-125033`; the post-run versions are in `evidence/`. Fjord test app stopped. `~/silo-work/e2e-gui/target` deleted.
- **silod (pid 49253) is still running**, stuck behind the open Keychain dialog: `engine.shutdown` returned a job that did not finish, SIGTERM did nothing, and my SIGKILL was refused by the permission classifier. The owner should answer or dismiss the dialog (or kill the process); the socket file is already gone.
- Claude Desktop sessions "Color preference question" and "Cat or dog preference" (project e2e-proj) are left for the owner to archive (archiving needs the owner's explicit yes).
- Stale processes from the previous run (`e2e/FjordE2E.app ... --form-hook`, an old `msb snapshot save x y` script) were not mine and were left.
