# Can an outside app start a new Claude Desktop SSH session, with its first message, and no click? Final pass (Fable, 2026-10-15)

Question: Fjord (a macOS app) wants a **new** Claude Code session in Claude Desktop's Code tab that runs over SSH on a VM, whose first message is sent, which the owner never clicks for, and which is a normal conversation the owner can see and continue. Rejected already: patching Desktop, restarting or re-signing-in, a pre-seeded pool of records, a hub that holds a turn open or long-polls, driving the UI, headless `claude -p` that never becomes a conversation, anything that needs Send.

Method: read-only. Claude Desktop 2.31226.1 (`/Applications/Claude.app`) and the staged update **2.37337.1** (`~/Library/Caches/com.anthropic.claudefordesktop.ShipIt/update.i0hjvRn/Claude.app`, `ShipItState.plist` says `launchAfterInstallation:false`), both `app.asar`s extracted with `@electron/asar` into a fresh `/tmp` folder and deleted afterwards; the Code tab renderer in `Contents/Resources/ion-dist/assets/v1/`; the strings of Desktop's bundled CLI 2.1.295 (`claude-code/2.1.295/9d6405864fdc/claude.app/Contents/MacOS/claude`) and of the SSH helper `claude-ssh-remote/c8e2…/claude-ssh-linux-arm64` (a Go binary, `github.com/anthropics/claude-ssh`); the public docs at code.claude.com; the CLI changelog. Desktop's own read-only MCP tools were called twice from this session (`list_scheduled_tasks`: none; `list_start_targets`: "Starting sessions is not enabled here"). Desktop was not launched, quit, driven or changed; no record, setting, SSH config or VM was touched; nothing extracted was run. `@n` are byte offsets in the minified chunks (old build names unless marked `new`). INFERRED marks what was not read in code. Earlier probes (`probes/desktop-ssh-autostart.md`, `desktop-mod-session-start.md`, `desktop-session-reload.md`, `probes/e2e-autostart.md`, `triage-in-computers-options.md`) are taken as read; this pass re-checked their load-bearing claims and corrects two (§0.2).

## 0. Verdict

**ONLY-IF: Desktop's own "scheduled task on an SSH host" feature is on for this account (GrowthBook gate `3485864475`, UI string "Running on SSH hosts isn't available right now." when it is off).** Then there is a clean, documented, zero-click route, with one owner click per (host, folder) *once*, never per task:

- Desktop scheduled tasks ("Routines → Local") are a documented feature whose prompt lives in a documented user file, `~/.claude/scheduled-tasks/<task>/SKILL.md` ("To edit a task's prompt on disk, open `~/.claude/scheduled-tasks/<task-name>/SKILL.md` … Changes take effect on the next run", docs/en/desktop-scheduled-tasks). The file is on the Mac even for a task whose place is an SSH host (§3.3).
- A task carries a **place** `{remoteTarget:{kind:"ssh",…}, cwd}` and a run of it starts a **new Code session on that SSH host, in that folder, with the SKILL.md prompt as its first message, with no person at all** (that is what a scheduled run is: `ccdRemoteSessionStart`, §3.2). The run is a normal session under "Scheduled" in the sidebar, continuable; the only things it can't do until the owner continues it are start side sessions and move to the cloud (§3.5).
- A run is started by `mcp__scheduled-tasks__run_scheduled_task` ("the same as the user clicking Run now … starts as a NEW Claude Code session in the task's working folder with the task's stored prompt"), or by a one-shot `fireAt` set with `update_scheduled_task`. **Neither handler has the person-turn gate that kills `start_session`** (§3.4): `run_scheduled_task` checks only the feature switch and `autonomousSweepAllowed()`, then `runNow(id,{mcpTool:true,personStarted:<card answered>})`, where `personStarted` only changes how the SSH place is probed (`attended`), not whether the run is allowed.
- What Fjord does per task: write the owner's words into the task's `SKILL.md` (its own documented edit path), then have its plugin, from any Desktop Code session it already lives in, call `run_scheduled_task` (or `update_scheduled_task {fireAt: now+10s}`). Zero clicks. The session's follow-ups go through the guest plugin as today (route D, `probes/e2e-autostart.md` T1).
- The one-time click: a task's place is fixed at creation to the creating session's host and folder ("The task runs on the SSH host this session works on, in the folder this session was started in; neither can be chosen here", create tool text in `index.chunk-hKMR2oV6.js @29316`), so Fjord needs one SSH session per (host, folder) once, made with today's `code/new` link and one Send, and creates the task from it. Afterwards that session can be archived; the task keeps the place.

Confidence: **high** that the code paths exist and have no person gate (every handler read end to end, old and new build identical here); **medium** on the two things only a live run settles: that the gate is on for this account, and that a plugin's `$.mcp.call` reaches Desktop's SDK MCP servers (the CLI binary has the call and its refusal strings, `cli-strings @232547-232554`; the reach is INFERRED, as in `desktop-mod-session-start.md` §2.1). If the gate is off: **NO** in this build and in 2.37337.1, and §6 gives the smallest request to Anthropic.

Two caveats the owner must accept: the first user row is the SKILL.md prompt inside Desktop's `<scheduled-task name="…" file="…">` frame (§3.2), not the owner's bare words (the words are verbatim inside it); and the session is titled and filed as a run of that task.

### 0.1 Every other idea in one table

| # | Idea | Verdict |
| --- | --- | --- |
| 1a | Remote Control / mobile / web starting a Desktop SSH session as "the person" | RULED-OUT: Desktop's inbound bridge starts **Cowork** sessions only (`sessionType:"agent"`), from Anthropic's servers; Code sessions have outbound-only Remote Control (§1) |
| 1b | Dispatch (the "personal Claude" Cowork session the phone drives) → `start_code_task` | RULED-OUT for SSH: local host path only, "The user will be prompted to approve each workspace" (§1.3) |
| 1c | `claude remote-control` server on the VM, new sessions started from claude.ai/code | RULED-OUT as clean: new sessions on the server are created by a person at claude.ai/code or the phone; no documented programmatic start; they'd be claude.ai sessions, not Desktop SSH sessions (§1.4) |
| 2a | The SSH daemon announcing a session, or Desktop adopting sessions it finds on the host | RULED-OUT: the helper is a request/response RPC server Desktop drives (spawn, reattach, files, git, plugins); no inbound "new session"; `sshAdoption*` reattaches processes Desktop spawned (§2) |
| 2b | `/desktop` from a CLI on the VM | RULED-OUT: `--desktop` is "Open in the Claude Desktop app instead of the terminal (with --continue or --resume <id>)", local resume only (§4) |
| 3 | A `claude://` route that starts and sends over SSH | RULED-OUT: route table unchanged in 2.37337.1; `code/new` prefills, `resume` is local, `continue`/`needs-input` open existing sessions, `debug-handoff`/`preview` are nest-only (§3.0) |
| 4 | `--desktop`, `--teleport`, `--cloud`/`--remote`, `--attach-serve`, `--prefill` | RULED-OUT: none makes a Desktop SSH session; `--attach-serve` is "spawned by the desktop app; not for interactive use" (§4) |
| 5 | Desktop's local servers, MCP bridge, Chrome native host, IDE locks | RULED-OUT: the only listeners are the OpenSSH askpass pipe, the browser-pane bridge socket, and an OAuth callback HTTP server; none creates sessions; the Chrome native host is Desktop → extension; `~/.claude/ide/*.lock` is the CLI's IDE discovery, nothing Desktop reads to make sessions (§5) |
| 6a | A self-hosted cloud environment on the VM (`claude --environment ccpool_…`) | RULED-OUT for the owner: Team/Enterprise only, off by default, sessions clone a GitHub repo rather than open the VM folder; and they'd be cloud sessions in the Code tab, not SSH sessions (§6a) |
| 6b | Cloud routine with an API trigger (`/fire`), self-hosted | Same plan and repo limits; cloud, not SSH (§6a) |
| 6c | A local session whose tools run in the VM (`CLAUDE_CODE_SHELL_PREFIX`, mounts) | RULED-OUT as before (`triage-in-computers-options.md` §2.5): loses the isolation; unchanged |
| 7 | 2.37337.1 changes any of this | NO: the URL handler, the person gate (`byPerson`, `turnInput`), `loadSessionRecords`'s callers, the scheduled-task tools and the host-runs gate are the same code; only minifier names and a few unrelated strings differ (§7) |
| G | Desktop scheduled task with an SSH place, run by its own tools | **VIABLE** under the gate (§3) |

### 0.2 Corrections to earlier passes

- `triage-in-computers-options.md` §2.4 wrote route G off as "a cousin of F with more machinery and no gain" and assumed "creating tasks properly goes through `create_scheduled_task`, model-mediated with its own approvals". The second half is wrong in the way that matters: creation is model-free when a plugin calls the tool, and *running* a task has no person gate at all, unlike `start_session`. The task file is a documented user file, not forged state.
- `desktop-mod-session-start.md` §6: "Desktop has no mod hooks of its own around session start" stands, but §2.2's gate (`cH`: `turnInput.open && person`) is specific to `startSideSession`. It is **not** applied to `run_scheduled_task`, `update_scheduled_task` or the scheduler's own dispatch (§3.4).

## 1. Remote Control, mobile, web: which identities Desktop accepts as "person"

### 1.1 The inbound bridge is Cowork's

`hwa()` (`index.chunk-Cyt2WTko.js @6345805`) builds the "[sessions-bridge]" with `sessionManager: await GS()` (the Cowork manager) and `onRemoteSessionStart: e => Pv.getDispatcher(t)?.dispatchOnRemoteSessionStart(e)` (`@6350143`). The bridge's inbound work (`handleInboundControlResponse` region, `@5801151`) builds

```
{orchestrationRequestId:n.workId, message:d, channel:"sessions_api", sessionType:yJt, …, sessionStart:{sessionId:u, model:n.workSecret.claude_code_args?.model, …}}
```

with `yJt="agent"` (`@2214998` region: `dC="agent",yJt="agent",bJt="dispatch_child",xJt="scheduled"`). The work schema (`index.chunk-DcP6Ha83.js @1287221`) is `{version, session_ingress_token, api_base_url, claude_code_args, mcp_config, auto_mode_environment, worktree}`: no host, no SSH, no cwd. The Cowork manager refuses `channel==="mobile"` unless gate `2216414644` is on ("Remote session control is disabled", `index.chunk-QEr06WaZ.js @399164`). Desktop enrols itself as a trusted device (`POST /api/auth/trusted_devices`, `@6346671`). So the only inbound session start Desktop accepts comes from Anthropic's control plane for Cowork, with `channel:"sessions_api"`/`"mobile"`, and it is not a person-at-the-composer turn for the Code manager either.

### 1.2 Code sessions: outbound only

The Code manager's Remote Control is `[outbound-ccr]` (`@6347047` region, `initOutboundOnlyCCRClient`): it publishes an existing session to claude.ai/code ("View and control this session from claude.ai/code", `index.chunk-BCHP6ll9.js @489873`). The CCR transport skips the read stream when `outboundOnly` (`index.chunk-DcP6Ha83.js`: `!e.outboundOnly&&!g&&u.connect()`). Messages that do arrive through a bridge are machine turns for the person gate (`noteCliInput`: `byPerson:!n?.machineSent&&t.seeded_summon!==!0&&JS(t.origin)`, `@1612039`; identical in `new/index.chunk-BolytlRP.js @1717380`). No channel or identity other than Desktop's own composer (origin `human`, enqueued by Desktop) counts as the person.

### 1.3 Dispatch → `start_code_task`

The Cowork "Dispatch" session ("You can also control this conversation from your phone … Dispatch tab", `@2214998` region) has `mcp__dispatch__start_code_task`: "Start a NEW Claude Code session on the host machine, outside the Cowork VM … appears in the desktop Code tab", parameters `cwd` ("Absolute host path … The user will be prompted to approve each workspace before the session starts"), `prompt` ("The user's message, VERBATIM"), `title`, `model` (`index.chunk-Cq2pev6h.js @2633`). Local only, and an approval per workspace. RULED-OUT.

### 1.4 `claude remote-control` server on the VM

Documented (docs/en/remote-control): server mode "stays running … waiting for remote connections", `--spawn` "How the server creates sessions", `--capacity <N>`; the changelog has "[Remote Control] Fixed the first message of a new Remote Control session started from claude.ai/code" (2.1.292). So claude.ai/code can start new sessions on an always-on machine. But the starter is a person at claude.ai/code or the phone; no API or CLI command creates one; the result is a claude.ai/code session (Desktop's Code tab opens such `session_…` ids as "ccr" conversations, `index.chunk-Cyt2WTko.js @898900`, renderer `c11959232 … backend:"ccr",source:"code_page"`), not a Desktop SSH session, and "Pro, Max, Team, and Enterprise". RULED-OUT as a clean no-click maker; noted as the first-party "new session on my VM from my phone" path.

## 2. The SSH session lifecycle: daemon protocol, adoption

- Desktop starts the helper on the host with `["--serve","--socket",ie]` plus `--token-file` (`index.chunk-BIZ57Fl8.js @309850`), after `--stop`. Tokens per host live in `ssh-remote-server-state.json` (`tokens`, `hostFacts.cliRelPath: .claude/remote/ccd-cli/2.1.295-…`).
- The helper's packages: `internal/handlers/{files,git,gitshadow*,launcher,plugins,pluginlocks,process,server}`, `internal/process/{manager,pty,registry,seal,trampoline}`, `internal/rpc/handler`, `internal/daemon`. Its method vocabulary: `spawn`, `reattach`, `kill`, `signal`, `resize`, `stat`, `list`, `ping`, `hello`, `processes`, `status`, `token`. It is a server Desktop calls; nothing in Desktop handles an unsolicited "a session appeared" from it (every `sshAdoption*` site in `index.chunk-BCHP6ll9.js` keys on `sshRemoteProcessId===handle.processId`, a process Desktop spawned; `desktop-session-reload.md` §4). INFERRED on the Go side (strings only): no "announce" or "import" handler exists. RULED-OUT.
- Session records: still loaded only by `loadSessionRecords` ← `loadSessions` ← `doInitialize` ← `initializeWithAccount` (`new/index.chunk-BolytlRP.js`: `loadSessionRecords` 2 hits, same shape). Unchanged in 2.37337.1.

## 3. The viable route: a Desktop scheduled task whose place is the SSH host

### 3.0 The `claude://` routes, re-checked in both builds

Host enum `fu` (`@832944`): `hotkey, login, claude.ai, preview, cowork, code, debug-handoff, sable-otter`; path enum `pu`: `magic-link, new, sso-callback, mcp-auth-callback, chat, project, settings, admin-settings, customize, directory, create, tasks, task, space, claude-code-desktop, code, epitaxy, design, resume, cowork, local_sessions`. `preview` and `debug-handoff` answer "only available in nest builds" (`@3207977`). The `code` routes are `/new`, `/continue`, `/needs-input`, `/search`, `/project/<chan_>`, `/<cse_|session_>` (the same functions build the Spotlight and tray menus, `@3195525`). The new build has the identical table (`new/index.chunk-BWk6pVUt.js @3221563`). No route sends.

### 3.1 The data model

A scheduled task record (`index.chunk-Cyt2WTko.js`, `create(...)`): `{scheduledTaskId, displayName, filePath, cronExpression, fireAt, enabled, cwd, place, permissionMode, model, useWorktree, sourceBranch, …}`; `place = {remoteTarget:{kind:"ssh",…}, cwd}` (`moveSshHost`, `@5554223`: `e.place=f4({remoteTarget:{kind:"ssh",...t},cwd:…})`). Records live in `claude-code-sessions/<acct>/<org>/scheduled-tasks.json` (here: `{"scheduledTasks":[],…}`); the prompt lives in `<taskFilesDir>/<id>/SKILL.md` with `taskFilesDir = join(claudeConfigDir(), "scheduled-tasks")` (`function Bqi(){return join(jj(),"scheduled-tasks")}`). The Code manager's scheduler is `T4=new pQi({logPrefix:"[CCDScheduledTasks]", …, runsOffDevice:e=>e.place!==void 0, hostRunsEnabled:FGi, buildSessionStartEvent:(e,t,n,r,i)=>jGi(e,t,i)})` (`@5626251`), `FGi(){return Mi("CLAUDE_E2E_HUMBLE_SKY")||Ly("3485864475")}` (`@5447678`; new build `r1i` with the same id).

### 3.2 What a run is

`jGi` (`@5447115`):

```
function jGi(e,t,n){let r={sessionId:t,model:e.model,useWorktree:e.useWorktree,sourceBranch:…,permissionMode:e.permissionMode};
return e.place&&n?{ccdRemoteSessionStart:{...r,remoteTarget:n,cwd:e.place.cwd}}:e.cwd?{ccdSessionStart:{...r,cwd:e.cwd}}:null}
```

The renderer's runner (`ion-dist/assets/v1/c8d44c418-D-8Q-G0S.js @4108-4928`) receives `session_started` with `ccdRemoteSessionStart`, logs "CCD scheduled task dispatch received: taskId=…, cwd=…", skips the folder-trust check for SSH (`n?{trusted:!0}:await f?.checkTrust?.(t.cwd)`), reads the task file **at dispatch time** (`getScheduledTaskFileContent(r.id)` → main `getFileContent` → `readTaskFile`, `@5581500`), asks the host's default permission mode when the task has none (`n?.kind==="ssh"&&!t.permissionMode?await V(n,t.cwd)`), and calls

```
f?.start?.({...z(),...b(n),cwd:t.cwd,message:n?H(r.id,l):O(r.id,r.filePath,l),sessionId:t.sessionId,model:t.model,useWorktree:…,permissionMode:m,…,scheduledTaskId:r.id,scheduledTaskManualStart:e.manualStart===!0||void 0,title:w(r)})
```

i.e. `LocalSessions.start` with the SSH target (`b(n)`) and the message as the spawn input: the first turn runs with no person. The message frame (`shared-2-DtKYxnkM.js @119251`):

```
`<scheduled-task name="${e}" file="${t}">\n${kt}\n\n${n}\n</scheduled-task>`
```

with `n` the SKILL.md body after its frontmatter (`ex` strips `---…---`), `kt` a fixed preamble (imported, not resolved; its text is in `shared-1`), and for SSH the `file` is `~/.claude/scheduled-tasks/<id>/SKILL.md` with `＠` substituted for `@` and a note "(Each ＠ above is a normal at sign, changed so no file is attached automatically…)" (`caf74d8e3-DSoIRYCb.js`). The docs: "When a trigger fires, the session receives the routine's saved prompt as its assigned task … rather than treating it as untrusted content" (docs/en/routines, for cloud routines; the Desktop frame is the local equivalent, INFERRED same intent).

### 3.3 Where the file is, and who may write it

For a task with a place, the create path is `pJi(…, "host-task")` → `iJi(c,t,u)` (`@5469701`), which `mkdir`s and `openFile(`${t}/SKILL.md`, O_WRONLY|O_CREAT|O_EXCL)` **inside the Mac's tasks folder handle `c` (`Wqi(a)`)**; updates go through `oJi` ("Updated the file of ${t}, a task on a host", written through the same local handle). The MCP list tool confirms it from the other side: to an SSH session it says local tasks' "prompt files are there and cannot be read from this session", and includes `prompt` for "an entry that runs on this session's own host … if the task was created on an SSH host" (`hKMR2oV6 @29316`). So the file Fjord edits is `~/.claude/scheduled-tasks/<id>/SKILL.md` on the Mac, the path the docs name as the user's edit point. There is no hash seal on it: `stashDispatchPromptHash` returns early `if(e.place||!Ly("1836754949"))` (`@5617368`), and the sha256 in that area is for `watching.js` scripts, a watcher feature that is `watchersEnabled:()=>!1` for the Cowork config and absent from the Code config (`runWatcherGate` returns `{proceed:!0}` without it).

### 3.4 Starting a run, and the absence of the person gate

`run_scheduled_task` handler (`hKMR2oV6 @24957` and the 3 000 bytes before it):

1. task lookup; if the task has a place: `placeVerdictFor`/`askPlace` → on `NotAvailable` it answers "Running tasks on SSH hosts isn't available in this app right now…";
2. refuses if a run `isRunning`, if `hasPendingDispatch`, or if one was started in the last `H` ms;
3. `if(!v()||!r.autonomousSweepAllowed())return F("Running routines from a session is turned off.")` (`autonomousSweepAllowed(){return this.runsAllowed()}`, `@5545439` region);
4. `T=await r.runNow(p.id,{mcpTool:!0,personStarted:f.personAnswered})`.

`runNow` (`@5579144`): `refusal()`, `isReadyToDispatchBounded()` (skipped for off-device tasks), `placeVerdictFor(e,{attended:t?.personStarted===!0})`, then `buildSessionStartEvent` and `emit("scheduled_task_event",{type:"session_started",…})`. `attended` only reaches the place checker (`uU`/`mU`, `index.chunk-BCHP6ll9.js @1138835/@1142847`), which, for a host that isn't connected, runs `ensureReadyInBackground("scheduled_task")` (a background dial that needs no person unless the failure `needsPerson`, e.g. an interactive sign-in), checks `policyAllows` (`Hb`, managed settings), `folderTrusted`, `savedConnections` (the host must be one of Desktop's `sshConfigs`; Fjord writes that entry today, `probes/e2e-router.md` a). Nothing reads `turnInput`, `promptAuthors` or `cH`. The same holds for the scheduler's own dispatch of a due `fireAt`/cron task (`emitSessionStarted`, `@5589593`: `askPlace(e.id,e.place,!1)`), which is the attended-false path by design. `update_scheduled_task` (`hKMR2oV6 @13070`) validates `fireAt` ("must be in the future"), sets `enabled`, and has no person gate either; its `changeAllowedOnCard` is the permission-card bookkeeping, not a refusal.

Preconditions read in code: the scheduler initialised for the account; `hostRunsReady()` = `hostRunsAvailable()` (`askChecker(usable) && hostRunsEnabled()`, the `3485864475` gate) `&& _rendererStartsHostRuns` (the Code page has declared `setHostRunsSupported` once, `shared-21-CGGmSsMS.js @403527`, so Desktop must have shown the Code tab since launch); `checkUnattendedCredential` (fine for a claude.ai login); `codeRoutinesDeniedBy` policy; the CLI governor not "critical". Two flag-gated throttles (`1648655587` per-task/global active-session limits, default 0 = none).

### 3.5 What the run session is

A `local_<uuid>` Code session with `scheduledTaskId` (`iP`: `"scheduled_task"` start reason unless `scheduledTaskManualStart`), listed under "Scheduled", warmable by the `continue` link like any other, continuable: `LM` sets `scheduledRunContinued=!0` on the owner's first message (`@…LM(e,t,n)` region), after which it is an ordinary session. While not continued it is "unattended" for `isUnattendedSession` (`scheduledTaskId||dispatchParentId||…`): `start_session` and `move_to_cloud` refuse ("Moving to the cloud needs the user at the keyboard; this session runs unattended (scheduled or remotely dispatched)"), the docs add that scheduled sessions "can't send or receive messages between your desktop sessions through the desktop app's session surface". Tool permissions: the task's permission mode, plus the tool approvals saved for that task (`addApprovedPermissions`, `desktop_ccd_scheduled_tasks_permission_auto_approved`); with Fjord's `auto` mode and the guest plugin this matches today's sessions. Remote Control auto-enables for scheduled runs (`yM`) unless the user toggled it; the Fjord plugin loads as in any guest CLI (T1).

### 3.6 Creating the task: the one click per (host, folder)

`create_scheduled_task` (`hKMR2oV6 @10392-11054`): `A=d()` is the calling session's place; `if(f.sessionOnSshHost?.()&&!A?.place) return "Nothing was created: this session's SSH host or folder is not known…"`; the record gets `cwd:A?.cwd, place:A?.place`. The main-process `createScheduledTask(t)` (`@6038256`) accepts `t.place` and is the Routines page's "New routine → Local" IPC, where the owner can pick an SSH folder (renderer strings: "SSH configuration doesn't save host keys for {host}. Set UserKnownHostsFile to ~/.ssh/known_hosts, then run the routine."). So the place is set either by a session already on that host and folder (one `code/new` link + Send, then the plugin or the model calls `create_scheduled_task`; the model path shows "an approval prompt … depending on the user's permission settings") or by the owner in the Routines form. Fjord cannot set it from a local session or from outside. Also `Rt`/`Lt` (`index.chunk-BCHP6ll9.js`, "different machine or folder" region): creation from an SSH session is auto-denied with `ssh_create_scheduled_task` when host runs are unavailable or the host isn't a saved connection ("Nothing was created: the task would run on the SSH host this session works on, and the app starts it there through one of its saved SSH connections…").

One task per (host, folder) is enough: the prompt is rewritten per use, and `runNow` refuses while a run of the same task is in progress, so a second task per project (or `update_scheduled_task {fireAt}` which the scheduler honours after the current run) covers overlap. A `fireAt` task auto-disables after firing; re-arm with `update_scheduled_task {fireAt}` ("Re-arms and auto-enables the task").

Risk to carry: `newLocalTasksOff()` → "Scheduled tasks can no longer be created on this computer … New scheduled tasks run in the cloud" (`@11054`) exists behind an account flag (`coworkNewLocalScheduledTasksOff` for Cowork; the Code manager has its own `newLocalTasksOff` config). Anthropic is moving tasks to cloud routines; this route should degrade to A with a note, as RouterStatus does for the CLI.

## 4. CLI hand-off features

From the 2.1.295 strings: `--desktop` "Open in the Claude Desktop app instead of the terminal (with --continue or --resume <id> to pick the session)" (`@129355`), refused with `--cloud` etc.; `--teleport [session]` "Resume a teleport session" (a cloud session brought to the local terminal, `teleportFromSessionsAPI`); `--cloud [description|session_id|url]` "Create a cloud session with the given description, or attach to an existing one", `--remote` "Deprecated alias for --cloud"; `--environment <environment_id>` "Create a new cloud session that runs on the given self-hosted environment (ccpool_...)"; `--attach-serve <session_id>` "Attach a serve-only helper to a bound cloud session (spawned by the desktop app; not for interactive use)"; `--prefill`/`--prefill-b64` "without submitting it"; `--deep-link-origin`. Desktop spawns `--attach-serve` for cloud sessions bound to an `env_` environment (`index.chunk-B1oFmUyS.js @3780`: `["--attach-serve",e,"--input-format","stream-json","--output-format","stream-json"]`, ids `cse_…`/`env_…`): that is the remote-devices tool host, not a session maker. `/desktop` from a CLI on the VM would open the Mac's Desktop on a *local* resume of a transcript that is on the VM: nothing to resume. No Desktop-side listener a remote CLI can reach other than the helper RPC (§2). RULED-OUT.

## 5. Local servers and IPC

`createServer` sites: the OpenSSH askpass pipe (`index.chunk-BIZ57Fl8.js @59449`, `[OpenSSHAskpass]`), the browser-pane bridge socket (`index.chunk-CXQ0MpL8.js @3392`, `[browser-bridge]`), a one-shot OAuth callback HTTP server (`index.chunk-Cyt2WTko.js @2168922`, `[custom3p-mcp]`). The Chrome native messaging host (`com.anthropic.claude_browser_extension`, `Helpers/chrome-native-host`) is installed by Desktop for the extension to reach Desktop's Claude-in-Chrome bridge; no session-start message was found (INFERRED from the message kinds grep: none). `~/.claude/ide/*.lock` files belong to the CLI's IDE discovery and `--ide`; Desktop lists `ide` only as a profile directory entry to copy (`@…{rel:"ide",kind:"dir"}`). The `LocalSessions` IPC has no import/reload (`desktop-session-reload.md` §1). RULED-OUT.

## 6. Environments

### 6a. Self-hosted environments / cloud routines

Documented (docs/en/self-hosted-environments): "public beta on Team and Enterprise plans and are off by default"; sessions "clone the repository the developer chose" ("A runner … clones the repository into its working directory"); started "from claude.ai, the mobile and desktop apps, the terminal with `claude --cloud` … and scheduled routines" and `--environment` dispatch. The CLI has the whole runner (`claude self-hosted-runner {setup,doctor,orchestrator,…}`, `/v1/code/runners/self-hosted/…`). Cloud routines (docs/en/routines) add API triggers (`POST …/routines/<id>/fire`, "Pro, Max, Team, and Enterprise") whose `text` "arrives wrapped in a `<routine-fire-payload>` block that labels it as untrusted data". Either would give a zero-click new conversation visible in Desktop's Code tab (cloud `cse_` sessions open there, §1.4), but it runs as a cloud session on a GitHub clone, not as a Desktop SSH session in the VM's folder, and self-hosting needs an org plan the owner doesn't have evidence of. ONLY-IF the owner has a Team/Enterprise org and accepts the repo-clone model; otherwise RULED-OUT. Not recommended.

### 6b. Moving a session's environment

`move_to_cloud` pushes the branch and makes a cloud session; `start_session target:"cloud"` is person-gated like every start. `moveSshHost` (`@5554223`) re-points scheduled tasks when a saved SSH connection is renamed, nothing more. RULED-OUT.

## 7. The staged 2.37337.1

Extracted and compared: 365 vs 350 chunks; the session manager (`index.chunk-BolytlRP.js`) and URL handler (`index.chunk-BWk6pVUt.js`) are the same code with new names. Checked identical: the route enums and handler; `byPerson` in `noteCliInput` and the `turnInput` open/close functions (`@907894`, `@1717380`); the `startSideSession` refusal text; `loadSessionRecords`'s callers; `importCliSession`/`sshAdoption*` counts; the SSH warm gate `3110215237` and `unattendedUsePermitted` (one more call site, in the cold-hold delivery, `@626392`); the scheduled-tasks MCP server (`index.chunk-BgYYQXqQ.js`, same six tools, same `runNow(p.id,{mcpTool:!0,personStarted:f.personAnswered})`), `hostRunsEnabled` (`r1i`, same gate id), and the renderer runner. `channel:"debug"`/`"remote_channel_failed"` strings are new telemetry. Nothing in it opens or closes a route.

## 8. Live tests for the viable route, cheapest first

All read-only against Desktop's process: none quits, restarts, signs out or drives Desktop. Approvals are listed per test.

| # | Settles | Steps | Touches | Never quits Desktop | Owner must approve |
| --- | --- | --- | --- | --- | --- |
| G0 | Is the SSH host-runs gate on for this account | In Desktop, open an existing SSH session (the e2e ones, or a fresh one from link A) and ask it, in the composer, to "list my scheduled tasks" — or read the `create_scheduled_task` description the CLI shows that session. Pass: the description says "The task runs on the SSH host this session works on…" (gate on); fail: "Running tasks on SSH hosts isn't available in this app right now" / the Routines page's "Running on SSH hosts isn't available right now." | Nothing | Yes | Tell them; one message typed by the owner (or Fjord delivers it through the plugin) |
| G1 | A host task starts a new SSH session with the file's prompt and no click | From that SSH session create an ad-hoc task (`create_scheduled_task {taskId:"fjord-<proj>", prompt:"reply with the word pong-g1", description:"Fjord inbox"}`, no schedule). Then, from any Desktop Code session where the Fjord plugin runs, `run_scheduled_task {taskId}` via `$.mcp.call("scheduled-tasks","run_scheduled_task",…)`. Pass: `main.log` shows `[CCDScheduledTasks] runNow: dispatching session for task fjord-<proj>` then the renderer's "CCD scheduled task dispatch received … cwd=/home/silo/…", a new session under Scheduled on the SSH host whose first user row is the `<scheduled-task …>` frame around "pong-g1", the assistant answers, and presence appears in the guest. | One task record and `~/.claude/scheduled-tasks/fjord-<proj>/SKILL.md`; one new session (archive after) | Yes | **Yes**: creates a task; installs/uses the Mac-side plugin call |
| G2 | The documented file edit carries the next prompt | Rewrite the SKILL.md body on the Mac (keep the frontmatter) to "reply with the word pong-g2"; `run_scheduled_task` again after G1's run ended. Pass: the second session's first row carries pong-g2 verbatim (the file is read at dispatch). | The file; one session | Yes | Covered by G1 |
| G3 | `fireAt` instead of a call, and the overlap rule | `update_scheduled_task {fireAt: now+20s}` while G2's run is still open; then wait. Pass: the run starts after the current one (or at once if the active-session limit flags are 0), the task auto-disables, and a second `update_scheduled_task {fireAt}` re-arms it. | The record | Yes | Covered by G1 |
| G4 | The owner can continue the run; the plugin delivers follow-ups | Send one Router message to the run through the guest plugin; then the owner types one message in Desktop. Pass: both arrive as user turns; after the owner's message `start_session` is no longer refused as unattended (optional). | One message | Yes | Tell them |

Order: G0 alone decides between ONLY-IF and NO. G1 is the one that needs a decision (it writes a task; the approvals are Desktop's own). If `$.mcp.call` turns out not to reach SDK servers, G1's second step falls back to asking the model in a local session to call the tool (model-mediated, one sentence); the route still has no click.

## 9. If NO: the smallest change to ask Anthropic for

Ask for `claude://code/new` (and `start_session`) to accept a signed **held-first-start**: `claude://code/new?ssh_host=…&ssh_folder=…&prompt_url=file://…&start=held` where Desktop creates the record (as `startSideSession` does with `registerHeldFirstStartSession(…, message)`) and delivers the first message only after the person's next interaction with *that* session, or after a Desktop-side policy the person set once ("Allow Fjord to start sessions on silo-dev-…"), the same consent shape as `requireSidePlaceConsent`'s 15-minute card and the scheduled task's per-task approvals. Argument: the pieces exist and are already trusted for unattended starts (scheduled tasks start new SSH sessions with a stored prompt and no person; `sideSessionPlacesUsed` grants a place for a parent session; `unattendedUsePermitted` already admits SSH warms), so a per-place standing grant for an external deep link is the same trust boundary with one fewer click, and it keeps the person gate where it matters: the message is the owner's words, stored ahead of time by an app the owner installed, exactly the attestation the routines docs describe ("the trigger attests only that the prompt was stored ahead of time by an authorized session on your account").

## 10. Cleanup

`/tmp/fable-asar.*` (both extractions) and `/tmp/fable-tools` removed at the end of the run. No file in `~/Library/Application Support/Claude`, `~/.claude`, `~/.ssh` was written. Nothing committed.
