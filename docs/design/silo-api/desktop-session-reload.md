# What makes Claude Desktop (re)load session records from disk, short of a restart? (static probe, 2026-10-15)

Question: Fjord writes `claude-code-sessions/<acct>/<org>/local_<V>.json` (with `sshConfig`, `cliSessionId`, `cwd`) while Desktop runs, then opens `claude://code/continue?session=local_<V>`. Live, the record was ignored (`get_session`: not found), a new Code window plus the link did nothing, and only a restart is known to load it. What else makes Desktop reload the folder, does a reload *add* unknown files, and can an external process cause it with no click?

Method: read-only. Claude Desktop 2.31226.1 (`/Applications/Claude.app`), `app.asar` extracted with `@electron/asar` into a fresh `/tmp` folder and removed afterwards; nothing from it was run. `~/Library/Logs/Claude/main*.log` read, not changed. Desktop was not launched, driven, quit or modified. `@n` are byte offsets in this build's minified chunks; minifier names (`rpa`, `kt`, `Jl`…) change with every release. Anything not read in code is marked INFERRED. Earlier probes (`probes/desktop-ssh-autostart.md`, `triage-in-computers-options.md`, `probes/e2e-autostart.md`, `desktop-mod-session-start.md`) are taken as read; this one corrects one of their claims.

## Summary

- **The only code that reads the records folder is `loadSessionRecords`, called only from `loadSessions`, called only from `doInitialize`, reached only through `initializeWithAccount`.** No file watcher, timer, IPC method, MCP tool, mod API, deep link, focus, wake or network handler calls it. The Reload menu and renderer navigation do not either.
- **A reload does add unknown files** (merge-add): known ids are skipped, new ids are loaded and inserted. So the record format is not the problem; the trigger is.
- **The "window attach re-runs `loadSessions`" reading was wrong for the windows a person can open while Desktop runs.** The per-window hook runs once for the main window at launch and for the "Configure Third-Party Inference…" window; "New Session in New Window" and session pop-outs are `window.open` children of the main view and never run it. The main window is hidden on close, never destroyed, so `activate` (Dock click, `open -a Claude`) never rebuilds it. The log confirms it: zero session-load lines between 2026-10-13 17:34 and 10-15 18:23, including the second-run window test.
- **What remains short of a restart** (all need a person at the UI, or hurt running sessions): sign out and back in (`/logout` navigation then sign-in: same-account re-init, merge-add); an org switch and back (full teardown of every running session: unacceptable); the Third-Party-Inference setup window (a menu item behind a feature flag, or an IPC the renderer's settings page sends).
- **No external, no-click trigger exists in this build.** Route E (a record Fjord writes) is restart-only. Confidence: high for the caller set (every call site was enumerated and the log agrees); high that nothing lazily loads a single record by id.

## 1. Every caller of the session-loading code

The loading code, bottom up (`index.chunk-BCHP6ll9.js` unless noted):

| Function | Offset | Called from |
| --- | --- | --- |
| `loadSessionRecords()` | `@1318920` | only `loadSessions()` `@1317815` |
| `loadSessions()` | `@1317815` | only `doInitialize()` (`index.chunk-epGqPC4W.js @484654` account-transition branch, `@484975` same-account branch) |
| `doInitialize(e)` | `@483724` (epGqPC4W) | only `initializeWithAccount()` `@483284` (epGqPC4W), through the subclass wrapper `@1318129` (BCHP6ll9) |

The other `loadSessions` strings are unrelated: `index.chunk-D6Q00DJz.js @740682/@969940/@1075045` are settings-schema keys; `index.chunk-QEr06WaZ.js @461844` is the Cowork manager's own loader over a different map.

Every caller of `initializeWithAccount` on the Code session manager, and what fires each:

| # | Caller | Offset | Trigger | Reaches the same-account reload? |
| --- | --- | --- | --- | --- |
| 1 | `createLocalSessionsApi` (`kt`), unconditionally: `e.webContents?.once("destroyed",oe),l.initializeWithAccount()` | `index.chunk-B8ah0lMt.js @31665` | Per-window API setup `rpa(webContents, window)` (`index.chunk-Cyt2WTko.js @6129968`, guarded `if(Jfa.has(e))return`), which lazily builds the API: `r=gB(async()=>{…createLocalSessionsApi({webContents:e},n,…)})`, `Lv.for(e).setImplementation(_B(r))`, `ZS(()=>{e.isDestroyed()||r()…})` (`@6132599`). `ZS` is `onClaudeCodeSessionManagerLoaded` (`@2207987`): immediate once the manager exists. `rpa` has three call sites: its definition, the main window `pOa(e,t)` (`@6386953`, once per webContents: `aOa.has(t.webContents)`), and the "Configure Third-Party Inference…" window `Ema` (`@6174052`). | Yes, but only when one of those two windows is created (see §2.3) |
| 2 | `setupAccountChangeListener` (`t.p0`, the `current-account` data provider's change event) | `index.chunk-epGqPC4W.js @482278`, `@482349` | Account details change. Re-init only when `!this.currentAccountId` (first init), or `sawLogoutSinceInit` (a logged-out state was seen since init), or the account uuid changed. A logged-out state is synthesized when the main view navigates to `/logout` or `/logout/all-sessions` (`index.chunk-Cyt2WTko.js @6405104`, "synthesizing logged-out"). The provider is also *reset to null* on every main-frame navigation of the main view (`allowStale:!1`, `@824457`), but a null value returns early (`if(!e)return`) and the renderer's re-publish of the same account changes nothing. | Only after sign-out then sign-in (same account): `doInitialize` same-account branch, then `onSameAccountSignedBackIn` (bridge restore `@1336324`) |
| 3 | `handleOrgChange` (`t.aL`) | `index.chunk-epGqPC4W.js @481664` | The `lastActiveOrg` cookie on the claude.ai domain changing (`cookies.on("changed")`, `@2890679`), or `orgUuidOverride` in config. Different org → `doInitialize` account-transition branch: `teardownSession(e,"account_switch")` for every session (`@1313193`), `sessions.clear()`, `sessionLoadEpoch++`, then load the other org's folder. Switching back loads ours again from disk. | Yes, destructively |
| 4 | `startSession` (`@1547236`), `importCliSession` (`@1973139`), `scanRecoverableCliSessions` (`@1978189`), Cowork `startSession` (`index.chunk-QEr06WaZ.js @400115`) | | `(!this.currentAccountId||!this.currentOrgId)&&await this.initializeWithAccount()`: only when the account is unknown (never while signed in and initialized) | No |
| 5 | `createLocalAgentModeSessionsApi` (`ur`) | `index.chunk-BEu1RvDa.js @47111` | Same per-window setup, for the Cowork manager (`n.initializeWithAccount()`) | Not the Code manager |

Triggers checked and found absent (no path to `initializeWithAccount` or `loadSessions`):

- File watcher on the records folder: every `fs.watch`/`watchFile` in the main chunks watches something else (`[CoworkMemorySync]` dir `index.chunk-QEr06WaZ.js @15677`; a folder tree watcher `index.chunk-B8ah0lMt.js @18089`; config file `index.chunk-Cyt2WTko.js @495111`; Chrome extension dirs `@3855943`; LFS/compaction timers in BCHP6ll9). No `chokidar`.
- Timers: none call it. `sessionLoadEpoch` is only bumped at account switch (`@1313465`) and read as a guard.
- IPC: the full `LocalSessions` method list (`Lv=ro(Ov,"LocalSessions",…)`, `index.chunk-Cyt2WTko.js`) has no reload/rescan method. `getSessionList`, `getAll`, `getSession`, `loadArchivedSessions`, `importAllCliSessions`, `probeImportableCliSessions`, `listCliSessions`, `listResumableCliSessions`, `resumeCliSession`, `reconnectSessionHost`, `forceReconnectSSH`, `restartRemoteSession` all work on the in-memory map or on local CLI transcripts (§4).
- Renderer reload / Reload menu: `requestReloadMainView` → `Uzn()` reloads the main view only; `rpa` is keyed by webContents and does not re-run; `did-navigate` on the window only runs cleanup (`L("webcontents_navigated")`, `index.chunk-B8ah0lMt.js` after `@31665`). The account provider reset on navigation returns early (row 2).
- `claude://` routes: every route is in-app navigation or a draft; `code/continue` → `VGn` (`@3217809`) reads `getAllSessions()` (memory) and falls back to `nR("/epitaxy")` (`@3217158`) on a miss, with no log line. `claude://resume` → `importCliSession` (local transcript only, row 4). No route opens the setup window or switches org.
- Wake from sleep, network change, focus: the `[SkillsPlugin] Window focused — polling now` and `[CCD-SessionRecovery]` probes run on focus/timer but never touch the records folder (§4).
- MCP tools (`ccd_session*`): `get_session`, `set_session_title`, `export_transcript` etc. call `c.getSession(id)` → `getSessionWhenLoaded` (`@1692166`): waits for the initial load, then `this.sessions.get(e)`; a miss returns `Session <id> not found.` (`index.chunk-epGqPC4W.js @203473`, `@210342`). No disk fallback.
- Deferred archived load: `ensureArchivedSessionsLoaded` (`@1329095`) runs the list captured during the last `loadSessionRecords` (`deferredArchivedLoad=M` `@1328920`); it does not `readdir` again.

## 2. Merge semantics

### 2.1 A reload adds unknown files and skips known ones

`loadSessionRecords` lists the folder (`readdir`, filter `local_*.json`, temp-file recovery `vk`/`Pt`), reads the archived-ids hint, then per file (`D(r, phase)`):

```
if(this.sessions.has(w.sessionId)||e!==this.sessionLoadEpoch)return;        // @1322197
… let k=n.Mt(w,m); … k.processGoneReason="app_relaunch" …                    // @1322348
… this.sessions.set(w.sessionId,k),this.contextRecovery.adopt(k) …
```

So on a reload: a session already in memory keeps its live state (its record on disk is not re-read); a file with an unknown `sessionId` is normalized (`Mt`, `index.chunk-epGqPC4W.js`: derives `backend` from `sshConfig`, sets `isArchived:false` by default, `permissionMode`, `cwd`/`originCwd` untouched for SSH) and inserted with `processGoneReason:"app_relaunch"`. Then `sessionRecordsLoaded=true`, `emitInitialized()` (`loadGeneration++`, the renderer's list refresh), `onInitialized` (scheduled-task store re-init, plugin watcher; nothing that tears sessions down). The archived index hint can defer a file whose id is listed as archived (`l?.has(s)`), which a fresh Fjord record is not.

Consequence: route E's record shape is fine; a reload would adopt it. INFERRED from the branch structure: the same-account `loadSessions()` runs with the existing map, so a forged record survives and no running session is disturbed.

### 2.2 Main versus renderer

The map lives in the main process (`LocalSessionManager`). Every window, pop-out and the MCP tools read that one map over IPC (`ro(...)` registers global `ipcMain.handle` channels; `index.chunk-Cyt2WTko.js @528169`). A new window never has a store of its own, so "open a window to make it rescan" only works if that window's creation runs `rpa`.

### 2.3 Was the window-attach path reached in the test? No

- "New Session in New Window" (menu, `@4861786`) only does `jv.getDispatcher(B.webContents)?.dispatchNewWindow()` (`@4861921`): the renderer opens it. The main view's `did-create-window` handler (`@6599779` region) adopts such children as pop-outs (`oo.add(e)`, `tAn`, `xOr`, `gEn`…) and never calls `rpa`. The log for the second run shows exactly that: `2026-10-15 17:03:48 mainView backgroundThrottling disabled (visible popouts: 1, …)`.
- The main window is created once (`HBa` `@6593601`, `pOa` `@6386953`); its close handler hides it: `p.on("close",(e=>{if($k())return;e.preventDefault(); … p.hide()}))` (`@6596979`); `window-all-closed` is a no-op (`@6625523`); `activate` only rebuilds the window when `getAllWindows().length===0||!z||z.isDestroyed()` (`@6626343`), which a hidden window never satisfies. So Dock clicks, `open -a Claude`, and URL opens only `show()` it.
- Log evidence: Desktop (pid 59429) has run since 2026-10-11 07:42:51. `main1.log` + `main.log` cover 2026-10-13 17:34:40 → 2026-10-15 18:23:02 (22 696 lines) and contain **zero** lines matching `Initialization succeeded`, `Loaded N persisted sessions`, `Cannot initialize sessions`, `Org changed from`, `Account logged out, marking`, while other `t.m4.info` lines of the same manager (`[LocalSessionManager] flushed held steers`, `[CCD] Warming session`) are present. Every `doInitialize` run logs one of the first three. So no reload ran in that window, including during the new-window test.

## 3. Triggers outside the UI

| Candidate | Result |
| --- | --- |
| `claude://code/continue`, `claude.ai/epitaxy/<id>`, `code/new`, `resume`, any other route | In-app navigation or draft; none re-inits (§1). A `continue` link for an unknown id lands on `/epitaxy` silently. |
| Opening a URL / `open -a Claude` / AppleScript `activate` or `reopen` | `activate` handler shows the hidden main window; no re-init. Electron apps expose no other AppleScript verbs. |
| Touching a file Desktop watches | No watcher on the records folder (§1). The settings file watcher (`@495111`) feeds config, not sessions. |
| Local IPC / MCP endpoint | Desktop's `ccd_*` tools are in-process SDK MCP servers reachable only from a session's CLI (`mcp_message` control requests); none reloads (§1). The remote session control channel (`channel:"mobile"`, Anthropic's servers) starts sessions but is private API. |
| Mod API (`$.mcp.call`, `$.tool.call` on `ccd_session_mgmt` / `ccd_sidebar` / `ccd_session`) | Reaches only the tools above; all read the in-memory map. `unarchive_session` on an unknown id: `getSession` miss → not found. No tool imports or rescans. |
| Posting through an existing session (send_message, `epitaxy` link) | Same map; no reload. |
| Lazy load by id on a miss (`get_session`, `continue`, `open_session_in`, `getSessionWhenLoaded`) | None. `getSessionWhenLoaded` waits for the *initial* load then returns `undefined` (`index.chunk-epGqPC4W.js` `getSessionWhenLoaded`); the deferred-archived list is from the last scan. |
| Third-Party-Inference setup window (`Ema`, `/setup-desktop-3p`, `@6173520`) | Runs `rpa` → `createLocalSessionsApi` → `initializeWithAccount()` → same-account reload (merge-add). Opened only by a menu item visible under flag `xY()` (`@4401292`) or the renderer IPC `openSetupWindow` (`Qpa`, `@6168118`). No deep link. A person's click, and a window on screen. |
| Sign out → sign in | Same-account re-init (row 2 of §1). Clicks, and the sign-in flow. |
| Org switch → switch back | Full reload, but tears down every running session first (`@1313193`): unacceptable with the coordinator inside Desktop. |

Net: **no trigger an external process can fire without a click** reloads the folder in 2.31226.1.

## 4. Other import or adoption paths for a CLI session

- `importCliSession`/`adoptCliSession` (`@1973139`–`@1978189`): local transcript only (`diskTranscript.resolveProjectDirForSession`), `backend:n.Lr()` (local), `adoptedFromOtherSurface:true`. Not SSH.
- `listCliSessions`, `listResumableCliSessions`, `resumeCliSession` (`@1969470`–`@1969882`, the resume picker): `getCliSessionDiscovery()` → the discovery class in `index.chunk-Dq-vaJtk.js` (`listResumableCliSessions(e){` `@7095`), which has no `ssh`/`remote` strings at all; `resumeCliSession` ends in `importCliSession`. Local only.
- `scanRecoverableCliSessions` / `recoverCliSessions` (`@1978189`…; `[CCD-SessionRecovery]` in the log, probed on focus via `probeImportableCliSessions` → `t.Kf`/`Ogi` with a 5-min cache, `index.chunk-Cyt2WTko.js @4960781`): scans this Mac's `~/.claude/projects` and "sibling profile dirs" for transcripts Desktop lost (`skippedNotLost`, `skippedFiltered` counts). Not remote hosts.
- `sshAdoptionPending/Settling/Blocked/Concluding/Revoke` (BCHP6ll9, 71 refs): reattachment of a remote process **Desktop itself spawned** (`sshRemoteProcessId`, `sshReattach` handle); nothing lists a remote `~/.claude/projects`. Connecting to an SSH host (`testSSHConnection`, `probeSSHConnection`, `reconnectSessionHost`, `forceReconnectSSH`) touches connections and the remote helper, not sessions. No "sessions found on this host" feature exists in this build.

## 5. Recommendation and live test

**Best no-restart, no-click trigger: none.** Route E as "write a record while Desktop runs" is dead in 2.31226.1; the record is adopted only by a `doInitialize` run, and nothing Fjord can do from outside causes one. Confidence: high (complete call graph; two days of log with no load lines through the window test).

Cheapest live test, only if the owner wants to see one of the click paths confirmed (it must never quit or restart Desktop; the coordinator runs inside it):

1. With the record `local_<V>.json` in place (shape as in `probes/e2e-autostart.md` T2), the owner signs out of Desktop and signs back in (same account). Pass: `main.log` shows `[LocalSessionManager] Initialization succeeded — … existingSessions=N` then `Loaded N+1 persisted sessions from …`, `get_session local_<V>` answers, and `claude://code/continue?session=local_<V>` warms it (`Warming session` → `Using remote spawn function`). Running sessions should survive (same-account branch; INFERRED), but sign-out may drop remote-control bridges and the claude.ai web view state. Touches: Desktop's sign-in state; one record file.
2. Alternative with less blast radius, if the "Configure Third-Party Inference…" item is visible in the app menu for this account: open it, close it. Same pass criteria. Touches: one window; nothing else.

Neither is a design Fjord can build on: both need the owner. Decision for the owner: drop E as a maker (keep D for continuation and A as the manual start), or accept that a forged record only takes effect at the next Desktop launch, i.e. a Fjord-written record is a "next time Desktop starts" import, never a live one. The next Desktop version (2.37337.1 was staged on this Mac) may change any of this; re-check `initializeWithAccount`'s call sites before relying on it.

What the owner would need to approve for either test: writing one file into Desktop's private folder again, and (test 1) signing out and in. No Desktop restart, no commit, no install.
