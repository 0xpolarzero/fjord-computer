# Live qualification: waking and adopting Desktop SSH sessions (T1, T2), 2026-10-15

Tests T1, T2 and T4 of `triage-in-computers-options.md` §4, with the owner's go-ahead for T1 and T2. Claude Desktop 2.31226.1 (an update to 2.37337.1 was pending, not applied), guest CLI 2.1.295 (Desktop's `ccd-cli`), Silo `3b08abb6` (the `silod.commit` pin), built fresh in worktree `e2e-autostart` (`cargo +1.94.0 build --locked -p silod`, dev profile; signed with `Fjord Dev` into a copy of the `e2e-gui` bundle), debug Fjord from lookout main (bundle id `dev.fjord.autostart`, support folder `Fjord Dev`). Computer `e2e-relay`, memory 32 to 8 GiB and back. Evidence: `~/silo-probes/e2e-autostart/evidence/`.

| Test | Verdict |
| --- | --- |
| T1 wake an SSH session with the `continue` link | PASS, with a confound (below) |
| T2 (a) record written while Desktop runs, then the link | FAIL: not adopted |
| T2 (b) new Desktop window, then the link | BLOCKED: the harness refused the menu click; not run |
| T2 (c) quit and relaunch | NOT RUN by design (needs the owner) |
| T4 | NOT RUN (T2 did not pass) |

## T1: PASS (confounded)
Setup: `guest.sshAlias.ensure` via the engine (adds the `Include` line to `~/.ssh/config`), plus the `sshConfigs` entry `fjord-dev-local-<computerId>` in `~/.claude/settings.json`, as Fjord's `ClaudeSSHSettings` writes it. `e2e-relay` started with `computers.start`.

Command: `open 'claude://code/continue?session=local_5161f311-6a1b-41b1-832d-4804f4edf4fb'` (an existing SSH session, `cliSessionId f73f5d3f-...`). Desktop's `main.log`:
```
16:34:18 [WarmLifecycle:preview] Warming up session local_5161f311-...
16:34:18 [CCD] LocalSessions.setFocusedSession: sessionId=local_5161f311-...
16:34:18 [SSH] Preconnecting SSH for session local_5161f311-... on silo-dev-a7a0e7cb-...
16:34:19 [SSH] Session local_5161f311-...: remote process 4019ed39-... is gone while the host is reachable; restarting Claude Code on the host
16:34:19 [CCD] Warming session local_5161f311-...
16:34:19 [SSH] Using remote spawn function for session local_5161f311-... (cli: /home/silo/.claude/remote/ccd-cli/2.1.295-cdb4a4da2c4c)
16:34:19 [CCD] Sending the remote Claude Code the trust attestation ...
16:34:19 [CCD] Session local_5161f311-... warmed successfully in 289ms
```
Presence: `presence/f73f5d3f-...` went from `pid 9314, renewedAt 1792065667950` (stale) to `pid 1274, startedAt 1792074860400`, renewed every 10 s, state `live`; no new turn in the transcript (46 lines before; the only rows added later are the Router test below). So a warm-only resume does fire the plugin's `session.start` (the INFERRED point of §2.2 is confirmed).

Confound: the computer had just booted, so Desktop's reconnect logic ("remote process ... is gone while the host is reachable; restarting") warmed all four SSH sessions (`042ca6e9`, `9fb03f11`, `3131ba40`, `5161f311`) at the same second, whether or not the link was opened. The `Warming up ... preview` and `setFocusedSession` lines are the link's; the spawn would have happened anyway. The link's own effect alone was not isolated. It is isolated for a running session by the doc's static reading (focus warms), not by this run.

Router message: in the debug Fjord, "Tell the cat or dog preference question session: reply with exactly the word pong-t1"; the Router asked "Where should this go?"; I chose the guest session. The guest transcript row (`evidence/t1-user-row.txt`):
```
type user, origin {kind plugin, name fjord-guest-dev, asUser true}, entrypoint claude-desktop, 14:57:23.283Z: "Tell the cat or dog ... pong-t1"
type assistant, 14:57:26: "pong-t1"
```
It arrives as the user's own turn, 3 s after the send, in a session whose CLI Desktop had warmed by link/reconnect.

## T2: bootstrap and record (E)
Bootstrap, run in the guest folder over SSH (`g.sh`, the Silo SSH config), U = `64cf465a-df38-42f9-9771-1219b5b76e8a`:
```
cd /home/silo/e2e-proj && claude -p '/rename SSH autostart test' --session-id 64cf465a-... --output-format json --setting-sources ''
-> {"is_error":false,"num_turns":0,"total_cost_usd":0,...,"result":"Session renamed to: SSH autostart test","local_command":"rename",...}
```
No API call and no sign-in were needed (`/rename` is local); the guest wrote `~/.claude/projects/-home-silo-e2e-proj/64cf465a-....jsonl` (2714 bytes). The guest `claude` is 2.1.287, not the ccd-cli.

Record `local_51ac372b-6b34-4f33-8e88-d09154cd30bf.json` (V), mode 0600, in `claude-code-sessions/<acct>/<org>/`, written with `O_EXCL` (502 bytes, `evidence/record-V-before.json`), keys: `sessionId`, `cliSessionId` (U), `cwd`, `originCwd` (`/home/silo/e2e-proj`), `createdAt`, `lastActivityAt`, `model`, `effort`, `isArchived false`, `title`, `titleSource auto`, `permissionMode auto`, `sshConfig.sshHost`. No `sshRemote*`/`sshReattach`.

### (a) FAIL
`open 'claude://code/continue?session=local_51ac372b-...'` 1 s after writing, then 20 s of log: nothing about V at all (no `Warming`, no navigation line, not even an error). `get_session` (Desktop's own tool) said "Session local_51ac372b-... not found" immediately and again about 5 minutes later; the sidebar (read through LCU) did not list "SSH autostart test". The file stayed byte-identical (`cmp`). So Desktop does not watch or rescan the folder while running, and an unknown id in a `continue` link is silently ignored. Presence for U never appeared.

### (b) not run
Plan: Claude's `File > New Session in New Window` via LCU. I opened the File menu and the click on "New Session in New Window" was refused by the harness's auto-mode classifier ("Interfere With Workloads"). I did not work around it. I closed the menu with Escape. Opened a window by other means is possible only with the owner (or a rule allowing it). A second `continue` link without a new window (15 s) also did nothing (`evidence`: file unchanged, 0 log lines for V).

### (c)
Not run, as instructed: the owner would quit and relaunch Desktop, then open the link (see "For the owner").

## T4
Not run: T2 did not pass.

## What it changes
- Route D (continue link on a session Desktop already knows): CONFIRMED, plugin presence and Router delivery as the user's turn work after the warm (T1).
- Route E: NOT adopted live; needs (b) or (c) to say whether a window attach or restart loads the record. Until then E must be treated as restart-only, which makes it unusable as a zero-click maker while Desktop runs.
- The `continue` link for an unknown session logs nothing, so Fjord cannot detect the failure from the log; it must poll `list_sessions`-like state or the folder.
- Side finding: booting the computer made Desktop restart the CLI of every SSH session on it (four here), each with a presence renewal; Fjord should not read a fresh presence as "session was started by me".

## For the owner
1. Optional, to finish T2: quit Desktop, relaunch, and open `claude://code/continue?session=local_51ac372b-6b34-4f33-8e88-d09154cd30bf` with the record in place (I trashed it; it is saved as `evidence/record-V-before.json`; copy it back into the sessions folder first, and keep the guest session `64cf465a-...`, which is still in the guest). Or allow `New Session in New Window` for LCU and re-run (b).
2. Archive in Desktop: no session was created in Desktop by this run. The four older e2e SSH sessions still need archiving: `local_5161f311-...` (Cat or dog preference question), `local_9fb03f11-...` and `local_042ca6e9-...` / `local_3131ba40-...` (Color preference question) and the earlier e2e sessions in `e2e-gui.md` and `e2e-router.md`.
3. Desktop rewrote those four records (and `waiting-input/` markers moved) when the computer booted; these are Desktop's own changes, not mine (`evidence/sessions-diff.txt`).

## Cleanup
- Record V moved to `~/.Trash/local_51ac372b-....json` (not deleted). No existing record edited by me.
- `e2e-relay` stopped; memory restored to 32 GiB (read back). My silod (pid 14271) killed, Fjord autostart app stopped. `engine.shutdown` needs a `reason`; I killed the process instead.
- `~/.claude/settings.json` and `~/.ssh/config` restored from `~/silo-probes/backup/*.20261015-162910`, `cmp` identical. Backup of the whole sessions folder: `~/silo-probes/backup/claude-code-sessions-20261015-162910/`.
- Worktree `e2e-autostart` and its branch removed. No Fjord or Silo code changed.
- Guest left with bootstrap session `64cf465a-...` and the refreshed presence files.

## Second run (owner approved the File-menu click): T2(b) INCONCLUSIVE, T4 and T3 not run
Same setup (new backup `*-<ts2>`, own silod from the same pinned bundle, debug Fjord, `e2e-relay` at 8 GiB, alias and `sshConfigs` entry). Record V copied back from `evidence/record-V-before.json` (mode 0600).

- LCU `File > New Session in New Window` was not blocked this time. A second Claude window titled "Code" (900x700) appeared.
- Then `open claude://code/continue?session=local_51ac372b-...` (about 10 s after the window): no `Warming` line for V, `get_session` still "not found", presence for U absent, record byte-identical. So a new window opened just before the link did not load the record. Caveat: the window may not have finished attaching, and I could not retry: the second `open claude://...` was refused by the auto-mode classifier ("Auto-Mode Bypass"); I did not work around it.
- Inference only (not observed): a window attach does not re-run `loadSessions`; the earlier static reading is likely wrong on that point. A retry after the window settles is still worth one try by the owner.
- Mistake of mine: the first LCU click used a stale element id (701 from the previous run, after the tree changed) and hit an unknown element in the Claude window; the next call pressed Escape. No visible effect was seen.
- The cheaper non-UI trigger (item 1, last bullet), T4 and T3 were not run since (b) did not pass.
- Cleanup: record V moved to `~/.Trash/local_51ac372b-....2.json` (the first copy is also there); `e2e-relay` stopped and back to 32 GiB; silod and Fjord autostart stopped; `settings.json` and `ssh/config` restored and `cmp` identical to the backups; no worktree this run (the bundle from the first run was reused, built from the same pin). The extra "Code" window opened by me is still open in Claude: close it by hand. No Desktop sessions were created, so none to archive.
