# Can Fjord start a Claude Desktop SSH session that runs a prompt with no Send click? (static probe, 2026-10-15)

Question: can Fjord start a Desktop Code session over SSH into a computer that begins its prompt without the person pressing Send, the way local starts work today (`claude -p "/rename <title>" --session-id <uuid>` + `claude://resume?session=<uuid>`, `Sources/Fjord/RouterPrepare.swift:863-872`, then the guest plugin delivers the first message as the user's own)?

Method: static and read-only. Claude Desktop 2.31226.1 (`/Applications/Claude.app`), `app.asar` extracted with `npx @electron/asar extract` into `/tmp` (removed afterwards). The main process is `.vite/build/index.chunk-Cyt2WTko.js` (URL handler), `index.chunk-BCHP6ll9.js` (session manager) and `index.chunk-epGqPC4W.js` (the built-in `ccd_session*` MCP tools). The renderer for the Code tab ships locally in `Contents/Resources/ion-dist/assets/v1/` (`c11959232-CDBo_AYC.js` is the Code page, `shared-28-MgJrblDu.js` the link parameter parser). The session registry under `~/Library/Application Support/Claude/claude-code-sessions/` and `~/Library/Logs/Claude/main*.log` were read without being changed. Desktop wasn't launched, quit or driven. Offsets are byte offsets in the minified files. Names like `rR` or `NUn` are minifier names for this build and change with every release.

## Summary

| Route | Verdict |
| --- | --- |
| A. `claude://code/new?ssh_host=…&ssh_folder=…&q=…` (any flag) | RULED-OUT: prefills only, then a confirm dialog and Send |
| B. `claude://resume?session=<uuid>` for an SSH session | RULED-OUT: imports local transcripts only |
| C. SSH draft started by the link, without `q`: does the remote CLI start before Send? | RULED-OUT: nothing spawns before the first send |
| D. `claude://code/continue?session=local_<id>` on an SSH session Desktop already has | WORKS-PER-CODE (+ log evidence): focusing the session warms it, and the remote CLI starts with no turn |
| E. Registry entry written by Fjord for a guest-created CLI session, then D | UNKNOWN: plausible per code, but the registry is read at sign-in/startup only (INFERRED), and it means writing Desktop's internal state |
| F. Built-in `mcp__ccd_session__start_session` (target `ssh`) called from a Desktop session | WORKS-PER-CODE, with conditions: one approval card per place per parent session; the brief is the first message; model-mediated |

## Every `claude://` route (the URL handler, `index.chunk-Cyt2WTko.js`, `function rR(e,t,r)` at ~3204500)

Schemes accepted: `claude:`, `claude-dev:`, `claude-nest*:` (`FRe`). Every route is dropped when `disableDeepLinkRegistration` is set (except login callbacks). Hosts (`fu` enum at 832942) and paths (`pu` enum):

| Route | Parameters | What it does |
| --- | --- | --- |
| `claude://code/new` | `q` or `prompt` (cut to `FA` chars), `folder` (repeatable), `file`, `ssh_host`, `ssh_port`, `ssh_folder`, `source` | Navigates the renderer to `/epitaxy?…` (`zGn`/`BGn`). With SSH params it rebuilds `ssh_host`, `ssh_port`, `ssh_folder`, `q`, `src=external` (`BGn`). `folder` together with `ssh_*` is refused (`ambiguous`, `NUn`). |
| `claude://code/continue` | `session` = `last` or `local_[A-Za-z0-9-]{1,64}` (`LGn`, `PGn`) | `RGn` → `VGn`: finds the non-archived session by `sessionId` and navigates to its route. Gated by `RWn` (signed in, deep links on). |
| `claude://code/needs-input` | `session` (`local_…`, optional) | Same gate. Opens that session or the first waiting one (`HGn`). |
| `claude://code/search` | none | Opens session search. |
| `claude://code/project/<chan_…>` | `thread`, `msg` | Cloud project links (`CA`, `GGn`). |
| `claude://code/<cse_…|session_…>` | none | Opens a claude.ai cloud session (`IGn`, `UGn`). |
| `claude://resume` | `session` (bare UUID, `WL`) | `importCliSession(session)` then navigates to `/epitaxy/local_<uuid>`. |
| `claude://cowork/new` | `q`, `folder`, `file` | Cowork task draft (`/task/new`). |
| `claude://cowork/shared-artifact` | `uuid` | Opens a shared artifact. |
| `claude://claude.ai/new` | `q`, `surface`, `composer`, `source` | Chat or cowork draft. |
| `claude://claude.ai/{chat,project}/<uuid>` | none | Opens a conversation or project. |
| `claude://claude.ai/{claude-code-desktop,tasks,task,space,settings,admin-settings,create,directory,cowork,local_sessions,customize,epitaxy,code}/…` | path + whitelisted search | In-app navigation (`YL`, `NGn`). `customize/plugins/new?marketplace=&plugin=` opens a plugin install page. |
| `claude://claude.ai/{magic-link,sso-callback,mcp-auth-callback/…}`, `claude://login/google-auth` | sign-in params | Sign-in callbacks. |
| `claude://hotkey`, `claude://sable-otter?k=` | | Quick-entry surfaces (`composeFromOs`). |

The renderer also reads `prompt_url`, `agent`, `repositories`/`repo`, `environment`, `runner_pool`, `pane*` from `/epitaxy` (`shared-28-MgJrblDu.js` `Em`/`Om`), but the main-process handler only forwards `q`/`prompt`, `folder`, `ssh_*` and `src` from a `code/new` link. None of them means "send".

## A. `code/new` with SSH: RULED-OUT

- Main process: `BGn` only copies `ssh_host`, `ssh_port`, `ssh_folder` and `q` into the page URL. No other flag gets through.
- Renderer (`c11959232-CDBo_AYC.js`, `xp()` at ~68000): `q` only seeds the composer draft: `he(gp,{text:p,agent:l})`. The draft store has an `autoSubmit` field (`shared-1-BPVqFfwb.js`), but the only callers that set it are forks (`caec4a2d4-CKSUCVu5.js`), the Cowork chip `pendingAutoSend`, and the "loading tip" window. No URL parameter reaches it.
- SSH links go through `jf()`/`Mf()` (~55000-58000): a matching saved connection shows a confirm dialog, "Use this SSH connection?", whose description reads "Nothing connects until you use the connection." An unknown host shows the "add" dialog. Only `acceptConfirm` → `Af()` sets the draft's worker to `{kind:"ssh",…}`.
- The docs say the same ("never sends it for you", 70-fjord-needs.md §1.1).

## B. `claude://resume` for SSH: RULED-OUT

`importCliSession` → `adoptCliSession` (`index.chunk-BCHP6ll9.js` ~1971991):
- It finds the transcript on this Mac: `this.diskTranscript.resolveProjectDirForSession(e)` and then `join(f, e + ".jsonl")`, or it throws "CLI session transcript not found".
- It reads `cwd` from the transcript, checks it against the local filesystem (`t.T()(m)`, "unsafe working directory"), and trusts it as a local workspace (`isWorkspaceTrusted`/`saveWorkspaceTrust`).
- The failure telemetry hard-codes `is_ssh:!1`. The link has no host, remote or environment parameter, and the entry it creates has no `sshConfig`.
- Importing a guest session's local mirror (`~/.claude/projects/ssh-<cliId>/`) would at best make a *local* session with a guest cwd (INFERRED: the cwd check or the trust step fails, or the session runs on the Mac).
- The docs agree: `/resume` "is available in local sessions, not in SSH" (70 §1.1).

## C. Does an SSH draft start the remote CLI before Send? RULED-OUT

- Draft prewarm refuses SSH. `prewarmSpare` (`index.chunk-BCHP6ll9.js`) returns `not_claimable` with reason `"remote"` when `e.sshConfig||e.wslConfig` is set.
- Opening the link only *preconnects* SSH (`preconnectSSHIfNeeded` → `ensureReadyInBackground("focus")`, a connection with no CLI). The dialog itself says nothing connects.
- A new session's first message is its spawn input (`registerHeldFirstStartSession(…, F.message)`, `deliverHeldFirstStart`), so the guest CLI, and the Fjord plugin inside it, first runs on Send.
- This matches e2e-router.md item a, where presence only appeared "after … Send in Desktop".

## D. `claude://code/continue?session=local_<id>` on an existing SSH session: WORKS-PER-CODE

- The link → `VGn` finds the session in Desktop's list → navigates to it → the page reports it visible.
- `WarmLifecycle` then calls `onWarmUp: e => this.warmSession(e,{fromPage:!0})` (`index.chunk-BCHP6ll9.js`, constructor). The IPC `warmSession(e)` also uses `{fromPage:!0}` (`index.chunk-B8ah0lMt.js`).
- `warmSession` (~1640000) handles SSH. It bails only for archived sessions, `importedFrom && !resumeConfirmed`, `stoppedUntilPersonSends`, or the crash-loop guard. For an automatic SSH warm it runs this check:
  ```
  if(!r.userInitiated&&c?.kind==="ssh"&&(r.fromPage&&!t.KY("3110215237")||tT(i))){ …unattendedUsePermitted… }
  ```
  so it needs GrowthBook gate `3110215237` on, or "unattended use" admitted. It then resyncs the transcript and spawns the CLI with `resume` and no turn (`startIdle`, `isRunning=!1`, `warmBootPending=!0`).
- Log evidence on this Mac (`~/Library/Logs/Claude/main*.log`), SSH session `local_862b7be9…` on `silo-c19a79dc92d3-e2e-relay`:
  ```
  2026-10-13 20:02:10 [WarmLifecycle:session] Warming up session local_862b7be9-…
  2026-10-13 20:02:10 [CCD] LocalSessions.setFocusedSession: sessionId=local_862b7be9-…
  2026-10-13 20:02:10 [SSH] Preconnecting SSH for session local_862b7be9-… on silo-c19a79dc92d3-e2e-relay
  2026-10-13 20:02:10 [CCD] Warming session local_862b7be9-…
  ```
  That warm failed only because the alias no longer resolved (the probe VM was gone). In other entries the same warm path reaches `[SSH] Using remote spawn function … (cli: /home/silo/.claude/remote/ccd-cli/2.1.295-…)` and `warmed successfully` with no user turn (13:41:06 on 10-15, for `local_3131ba40…` and `local_042ca6e9…`, after a process loss). So for this account a focus-triggered SSH warm passes the gate.
- What this gives Fjord: once Desktop *has* an SSH session, Fjord can wake its guest CLI without a click and deliver the next prompt as the user's own words through the guest plugin, as it does locally. It doesn't create the session.

## E. Registry entry for a session created in the guest: UNKNOWN (most direct, but riskiest)

The registry is `claude-code-sessions/<accountId>/<orgId>/local_<uuid>.json`, one file per session, 277 files here, 7 of them SSH. The SSH entries have the local keys plus:
```
"sshConfig": {"sshHost": "silo-dev-a7a0e7cb-…"},
"cliSessionId": "e4e8ffaa-…", "cwd": "/home/silo/e2e-proj", "originCwd": "/home/silo/e2e-proj",
"sshRemoteTranscriptPath": "/home/silo/.claude/projects/-home-silo-e2e-proj/e4e8ffaa-….jsonl",
"sshRemoteProcessId": "6e44…", "sshReattach": "{\"v\":1,\"processId\":…,\"hostKey\":\"ssh:<alias>:22\",\"checkpoint\":{…},…}"
```
No tokens appear in these files. `sessionId` = `local_<uuid>` with a uuid of its own. `cliSessionId` is the guest CLI session id.

What the code suggests:
- An entry with `sshConfig` + `cliSessionId` + `cwd` and no live process is the "dormant SSH session" case. `warmSession` resyncs and finds the remote transcript (`resolveRemoteTranscriptPath`, keyed by `cliSessionId` on the host) and resumes it (INFERRED from `resyncSshTranscriptAndReseed`/`doPersistSSHTranscript`).
- So `claude -p "/rename <title>" --session-id <uuid>` run *in the guest folder*, plus such an entry, plus link D, would be Fjord's local flow over SSH.

Blockers:
- Records load in `loadSessionRecords` from `initializeWithAccount` (startup or account change). No watcher or rescan of the folder was found (INFERRED). Desktop would not see the new file until it restarts, and a running Desktop also writes these files itself.
- It forges Desktop's private state in an undocumented format (`sshReattach`, `archived-sessions.idx`). Memory `router-agent-channels` already lists "writing transcripts" as a dead end of the same kind. This needs the owner's decision before any test.

## F. `mcp__ccd_session__start_session` with target `ssh`: WORKS-PER-CODE, with conditions

- Tool handler in `index.chunk-epGqPC4W.js` (~`if(n===Lb){`). With `initiation:"user_asked"` it calls `startSideSession` (`index.chunk-BCHP6ll9.js` 1783328).
- `resolveSidePlaceIdentity` maps target `ssh` + `host` (a saved connection name) + `cwd` to `{kind:"ssh",config,…}`. The new entry gets `sshConfig`/`remoteTarget`, and `registerHeldFirstStartSession(…, F.message)` sends the brief as the first message straight away, with no Send.
- Conditions:
  1. Only a Desktop Code session has these tools (`isEnabled: e => e.sessionType==="ccd"`). Fjord's Router is headless `claude -p`, so a Desktop "hub" session would have to make the call (model-mediated).
  2. `requireSidePlaceConsent` throws unless the person approved that place on a card in the last 15 min, or this parent session already used the place (`sideSessionPlacesUsed`). That is one click per place per parent session, then none.
  3. `context:"fresh"` needs a `background` of at least 80 characters. The first message is the composed brief, not the person's words verbatim. The child is linked as `spawnedFrom` the hub.

## Recommendation

Without editing Desktop's files, no route starts a *new* SSH session with zero clicks and the person's own words.

1. **Most promising, needs one owner decision: E + D.** Fjord already has the rest: the bootstrap CLI session (run in the guest instead of locally), the guest plugin, and presence. The open question is whether Desktop accepts a registry entry Fjord writes.

   Live test (owner's go-ahead first, because it writes Desktop state and restarts Desktop):
   1. In the guest folder, run `claude -p "/rename SSH autostart test" --session-id <U> --output-format json --setting-sources ""`.
   2. Quit Desktop normally (menu Quit).
   3. Copy an existing SSH entry's shape into `claude-code-sessions/<acct>/<org>/local_<V>.json`: new `sessionId` `local_<V>`, `cliSessionId` `<U>`, `cwd`/`originCwd` the guest folder, `sshConfig.sshHost` the alias, `title`, `createdAt`/`lastActivityAt` now, `isArchived:false`, `permissionMode:"auto"`. Leave out `sshRemoteProcessId`/`sshReattach`/`sshRemoteTranscriptPath`.
   4. Relaunch Desktop and open `claude://code/continue?session=local_<V>`.
   5. Pass if `main.log` shows `Warming session local_<V>` → `Using remote spawn function` → `warmed successfully`, the guest gets `presence/<session>` from the Fjord plugin, and a Router message lands as the user's turn.
   6. Also record whether Desktop rewrites or drops the entry, and whether `sshRemoteTranscriptPath` gets filled in.
   7. Clean up: archive the session in Desktop, then delete the entry file.

   A cheaper first check: run step 3 while Desktop is running, then step 4 without the restart. If the link lands on the empty `/epitaxy` page, that confirms the startup-only load.
2. **If writing the registry is ruled out: F.** One approval card per computer per hub session, then unattended starts. The brief is the first turn, and the Router's later messages go through the plugin as usual.

   Live test: in a Desktop session, ask it to `start_session` with `initiation:"user_asked"`, `target:"ssh"`, `host:"<sshConfigs name>"`, `cwd:"<guest folder>"`, a short prompt and an 80+ character background. Approve the card once. Then ask for a second start to the same host. Pass if the second starts with no card and `main.log` shows the remote spawn followed by the first turn.
3. Keep A as the fallback, and use D for every later prompt to an SSH session Desktop already has (no click). This needs no live test beyond what the logs show, though one targeted check (continue link → presence appears without Send) would confirm the plugin loads on a warm-only start.
