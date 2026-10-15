# Starting and continuing Claude Code work inside a computer: the options (2026-10-15)

Question: what is the most consistent and convenient way for Fjord to start and continue Claude Code work for projects that live in a computer (a Linux or macOS VM run by silod, reached over SSH), for the Router and for Triage, with no click from the owner?

Method: read-only. Fjord's code on main, the Silo API spec and probes in this folder, and Claude Desktop 2.31226.1's shipped code (`app.asar` extracted with `@electron/asar` into a fresh temp folder, removed afterwards) plus the strings of Desktop's bundled Claude Code 2.1.295 binary (`~/Library/Application Support/Claude/claude-code/2.1.295/9d6405864fdc/claude.app/Contents/MacOS/claude`). Desktop was not launched, driven or changed; no VM was started. Offsets (`@n`) are byte offsets in the minified chunk files of this build; minifier names (`Wm`, `RN`…) change with every release. Anything not read in code is marked INFERRED.

## 1. Where things stand

**On the Mac, a session starts with no click.** Fjord runs `claude -p "/rename <title>" --session-id <uuid> --output-format json --setting-sources ""` in the folder, opens `claude://resume?session=<uuid>`, waits for Desktop to import and run it, then delivers the first message through its signed plugin as the owner's own words (`Sources/Fjord/RouterPrepare.swift:863-874`, `RouterMCP.swift:1190-1300`). A session Desktop has but doesn't run yet is a held start whose first message waits up to 30 min (`RouterPrepare.swift:560-571`, `:885-897`, `RouterMCP.swift:1390-1404`).

**In a computer today, Router "Runs on" needs one click per new session.** Fjord installs its guest plugin, writes the `sshConfigs` entry and opens `claude://code/new?ssh_host=…&ssh_folder=…&q=…`; the owner confirms the connection (first time) and presses Send (`GuestDesktopStart.swift:47-54`). After that, every message, form and answer flows with no click (`probes/e2e-router.md` items a–d). Fjord matches the Desktop session to the guest by alias, folder, plugin presence and a transcript message containing the prompt (`GuestDesktopStart.swift:96-113`).

**Triage in a computer is implemented as a headless run**, not a Desktop conversation: checkpoint, then a supervisor runs `claude -p` in the guest with `CLAUDE_CODE_OAUTH_TOKEN` through a placeholder (`ComputerRun.swift:331-336`, `:502-590`), and it is gated off: "Claude OAuth Bearer substitution is unproven (B-17)" (`ComputerRun.swift:335`). On the Mac, Triage hands the item to the Router (`InboxActions.swift` `.askRouter`; `RouterDispatcher.swift:1104` treats an action's message as unattended), which starts a Desktop session. The owner expected the computer case to behave the same way, over SSH.

## 2. What Desktop's code allows

Verified in the shipped code (the probe `probes/desktop-ssh-autostart.md` holds the full route table; this section checks its key claims and adds what it missed).

### 2.1 Making a session appear in Desktop

| Route | What the code does | Verdict |
| --- | --- | --- |
| `claude://code/new` with `ssh_*` and `q` | Pre-fills the draft; nothing spawns before Send (`prewarmSpare` refuses remote drafts, `index.chunk-BCHP6ll9.js @1531126`; the first message is the spawn input). Documented: "never sends it for you" (70 §1.1). | 1 click per session (plus the connection confirm the first time) |
| `claude://resume?session=<uuid>` | `adoptCliSession` resolves the transcript on this Mac, rejects a cwd that fails the local safe-directory check (`"the transcript names an unsafe working directory"`, `@1975376`), trusts it as a local workspace and creates the record with `backend:n.Lr()`, the local backend (`@1977828`). No host parameter anywhere. | RULED OUT for SSH |
| `claude://claude.ai/epitaxy/<id>` and `claude://code/continue?session=local_<id>` | Both are in-app navigation to an existing, non-archived session (`VGn @3217809`, `NGn @3216247` in `index.chunk-Cyt2WTko.js`). Fjord already uses the first to open sessions (`Claude.swift:95-98`). | Opens; see 2.2 for what opening does |
| A registry file written by Fjord (`claude-code-sessions/<acct>/<org>/local_<uuid>.json`) | Records are read by `loadSessionRecords` (`index.chunk-BCHP6ll9.js @1318920`) from `doInitialize` (`index.chunk-epGqPC4W.js @483718`). **New finding:** `doInitialize` calls `loadSessions()` again even when the account is unchanged (the branch logs "loadSessions failed during session reload", `@485056`), and `initializeWithAccount()` runs every time a window's web contents attaches (`index.chunk-B8ah0lMt.js @31701`). So a new Desktop window may rescan the folder without a restart. Whether a reload *adds* a record it didn't have is not established from the code (INFERRED either way). No file watcher on the folder was found. | UNKNOWN; forges private state |
| `claude --desktop`, `--deep-link-origin`, `--prefill-b64` (CLI flags) | The CLI's own desktop hand-off and deep-link prefill; `claude --desktop --resume` is documented as local only (70 §1.1). | Not an SSH route |
| Remote session control (`channel:"mobile"` / `sessions_api` in `Wm`, the start entry, `index.chunk-QEr06WaZ.js @398748`, gate "Remote session control is disabled" `@399164`) | Desktop accepts session starts sent through Anthropic's servers by the Claude mobile/web app. Private API, not for Fjord. | Exists, out of reach |

### 2.2 Waking an existing SSH session with no click (route D)

Opening a session's page (either link above) runs `WarmLifecycle.onWarmUp → warmSession(…,{fromPage:true})`. For an SSH session that is not user-initiated the gate is (`index.chunk-BCHP6ll9.js @1642310`):

```
if(!r.userInitiated&&c?.kind==="ssh"&&(r.fromPage&&!t.KY("3110215237")||tT(i))){
  let n=await this.coldHoldDelivery.unattendedUsePermitted(c,…); if(!n){ …"managed settings or the host's policy do not admit unattended use yet"…; return } }
```

`unattendedUsePermitted` ends in `JT` (`@591159`), which returns `true` when the policy verdict is `no_policy`. On this Mac (no managed settings) the logs show focus-triggered SSH warms reaching `warmed successfully` with no turn (probe D). The warm bails only for archived sessions, imports not yet confirmed, `stoppedUntilPersonSends` (set after the remote host stopped responding, `@1888389`, cleared by the person's next send), the crash-loop guard, or a background-connect backoff. It then spawns the guest CLI with `resume` and no turn.

Fjord's guest plugin writes presence on the mod event `session.start` and renews it every 10 s (`ClaudePlugin.swift:627-632`). That a warm-only resume fires `session.start` is INFERRED (the CLI's `SessionStart` hook sources are `startup`, `clear`, `compact`, `resume`); test T1 settles it. Once presence is up, the Router delivers through the guest inbox exactly as in e2e-router item d.

So D is the continuation path: any message to an SSH session Desktop already has, while the owner is away, with no click. It never creates a session.

### 2.3 Desktop's own `start_session` tool (route F), and the no-card cases it has

The `ccd_session` tools are SDK MCP servers served to the CLI over its control protocol (`mcp_message` requests, `index.chunk-D6Q00DJz.js @1130086`), so only the session's model can call them; no external process can (this also rules out a "call the tool from Fjord's plugin" route: the mod API's `tool.call`, `agent.spawn` and `session.start` names are events a mod observes, with `{ deny }`-style replies, not calls; the mod's own abilities are `prompt.submit`, `process.run`, `http.fetch`, `fs`, `clock`… per the CLI's capability list).

What the start does, read from `startSideSession` (`index.chunk-BCHP6ll9.js @1785797-1791470`):

- `v = y.t(place)` is true when `host`, `cwd`, `environment`, `preset` or `target:"ssh"` is given (`index.chunk-CaOEsn1V.js @3144`). Only then is the place resolved and `requireSidePlaceConsent` run (`@989737`): it needs a card answered in the last 15 min, or the place key already in the parent's `sideSessionPlacesUsed`. The key for SSH is `["ssh", endpoint, cwd, preset]` (`M @5158`), i.e. per host **and** folder. `sideSessionPlacesUsed` appears in no record schema (only in `index.chunk-BCHP6ll9.js`), so it lives in memory and resets at Desktop restart (INFERRED).
- **With no place given, there is no card.** `b` stays undefined, the child's spawn config is `{...RN(parent), ...}` and `RN` carries the parent's `sshConfig`/`remoteTarget` (`@773432`); its cwd is the parent's `originCwd||cwd` (`@1791470`). Its first message is delivered as the spawn input (`registerHeldFirstStartSession`), framed as `Background (from the session that started this one):\n…\n\nTask:\n…` for `fresh` with a background, else the prompt alone (`Eb`, `index.chunk-epGqPC4W.js @362931`). Desktop's tool description requires a `background` of at least 80 characters for `fresh`.
- **A fork never shows a card** (`describeSideSessionStartPlace` returns early for `context:"fork"`, `@990755`). `forkSession` supports remote parents through `forkSessionRemote` (`@1833238`, `@1834491`). The child then receives `Task (from the session that started this one):\n<prompt>` with origin `auto-continuation` (`@1760086`).

Conditions: a Desktop session must make the call; its model must decide to; `initiation:"user_asked"` wants the user's words asking for it (which the plugin can deliver as the owner's own); the token cap and the CLI governor apply.

### 2.4 Scheduled tasks (route G, new)

Desktop's scheduled tasks have a `place {remoteTarget, cwd}` that can be an SSH host (`tXi`, `index.chunk-Cyt2WTko.js @5513900`; `bZi` task schema `@5534719` with `fireAt` for one-shot runs), and a scheduled run must start on that host and folder (`Ht`, `index.chunk-BCHP6ll9.js @18568`, "This scheduled task is set to run on a different machine or folder"). Runs need `hostRunsAvailable()` and an unattended credential check (`checkUnattendedCredential`, `@2795185`). The scheduler works from an in-memory map filled at init from `<acct>/<org>/scheduled-tasks.json` (`rQt @2239731`; `checkScheduledTasksInner @5596501` every 60 s `@5606533`), so a file Fjord wrote would also be a forged, init-time-only record; creating tasks properly goes through `create_scheduled_task`, model-mediated with its own approvals. A cousin of F with more machinery and no gain. Not pursued.

### 2.5 A local Desktop session whose tools run in the guest (route H)

The CLI has `CLAUDE_CODE_SHELL_PREFIX`, prepended to every Bash command (`Fre(Sn,qt)` in the strings), so Bash could be wrapped in `ssh <alias> …`. But Read, Edit, Glob, Grep, git anchors, worktrees, hooks, plugins and MCP all run on the Mac, so the guest folder would have to be mounted on the Mac (virtiofs share for a macOS VM, SSHFS/NFS for Linux) with path translation, and the session's secrets and plugin would live on the Mac. The CLI's "remote tools" (`CLAUDE_CODE_REMOTE_TOOLS_FORWARD`/`_SERVE`, "the serving machine") have no CLI flag and read as the bridge's internal mechanism (INFERRED); not usable. H keeps the unattended local start but gives up the isolation "Runs on" exists for. Escape hatch only.

### 2.6 Headless `claude -p` in the guest, handed to Desktop later (route I)

There is no import path for an SSH session (2.1), so "later" means route E. Alone, the headless run needs its own credential (`setup-token` through a proxy, B-17 unproven) and is not a conversation. This is the already-built, gated `ComputerRun`.

## 3. Evaluation

Rows: A `code/new` link (today) · D wake (continuation only) · E forged registry entry + D · F hub session + `start_session` (no card when the child shares the hub's place) · G scheduled task · H local session, guest tools · I headless `claude -p`.

| | A | D | E + D | F (hub) | G | H | I |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Same as the Mac flow (bootstrap, import, plugin delivers the owner's words) | No: owner sends | Yes for follow-ups | **Yes, literally** (bootstrap via `guest.exec`, record instead of `claude://resume`, link, plugin) | Mostly: a model starts the session; first message framed "from the session that started this one" | No | Start yes, work no | No |
| Clicks per new task | 1 (2 the first time) | n/a | 0 | 0 after the hub exists (1 per project, once) | 0 after creation | 0 | 0 |
| Clicks per follow-up | 0 | 0 | 0 | 0 | 0 | 0 | n/a |
| Works while the owner is away (Desktop running, signed in) | No | Yes | Yes | Yes | Yes | Yes | Yes (no Desktop needed) |
| A real Desktop conversation | Yes | Yes | Yes | Yes, `spawnedFrom` the hub | Yes | Yes, but local | No |
| Auth | Desktop's | Desktop's | Desktop's | Desktop's | Desktop's | Desktop's | `setup-token` + proxy (B-17 open) |
| Robustness to Desktop updates | Documented link | Undocumented link, but Desktop's own session links use the same path | Private file format, init-time load, Desktop rewrites the folder: breaks silently | Built-in tool with a model-facing contract; consent rules may move; the undocumented link for wakes | Private format or model-mediated | CLI env var (undocumented), mounts | CLI docs |
| Effort in Fjord | Done | Small: open the link before a delivery when the guest process is gone | Small: guest bootstrap (spec §2 e), record writer, D | Moderate: hub lifecycle per project, start message, child matching by `spawnedFrom`, D | Large | Large | Done, gated |
| Main risk | Owner must be there | Only continues | Desktop ignores, rewrites or deletes the record; a safety-classifier flavour of "forged state" (memory `router-agent-channels`: writing transcripts was a dead end) | Model in the control path: may paraphrase, refuse, hit the cap; the child's first turn is the brief, not the owner's words | Approvals, scheduler semantics | Isolation lost, path translation | Not a conversation; auth unproven |

Notes:
- D is part of every design: the guest CLI must be running for the plugin to deliver, and Desktop stops warm idle processes (`teardownWarmIfIdle`, `index.chunk-QEr06WaZ.js @485214`), so a delivery to a quiet session opens its page first. Opening the page moves Desktop's Code tab to that session; Fjord's held-start logic (`finishStart`) already covers "the app has it but doesn't run it".
- F without a hub (a card per host and folder per parent per Desktop run) is what the probe described; the no-card cases above are what make F viable: a hub that already sits in the project folder, or a fork of it.

## 4. Recommendation

**Build one "session maker" seam for computer projects, with D plus the guest plugin as the shared continuation path, and decide the maker with two cheap live tests.** The Router and Triage share it: Triage's `.askRouter` already reaches `startSession` with the unattended flag; `runsOnProject(for:)` picks the computer placement (`RouterMCP.swift:1269`). The headless `ComputerRun` path stops being Triage's computer mode (the owner is the only user; no legacy); keep its checkpoint-before-run step as an optional policy applied before a session start if wanted.

1. **Preferred maker, if test T2 passes: E + D.** It is the Mac flow over SSH: `claude -p "/rename <title>" --session-id <U>` in the guest folder (`guest.exec`, spec §2 e), a `local_<V>.json` record with `sshConfig.sshHost`, `cliSessionId:<U>`, `cwd`/`originCwd`, then `claude://code/continue?session=local_<V>`; the first message goes through the plugin as the owner's own words, verbatim. Zero clicks, no model in the loop, matching by `cliSessionId` instead of prompt text. It needs the owner's decision because it writes Desktop's private state, and it must be built to notice failure (no record adopted within the held-start wait → the card says "Open in Claude" with the A link).
2. **Fallback maker, if E is refused or fails: F with a hub per project folder.** Fjord creates the hub once per (computer, folder) through A (the one Send), remembers its `local_` id, and for every new task delivers, as the owner's words, "Start a session here for this task, verbatim: …" to the hub; the hub's model calls `start_session` with `initiation:"user_asked"`, `context:"fresh"` and no place (no card; child on the same host and folder with the brief as its first turn), or `context:"fork"` (no card, the hub's short transcript carried). Fjord matches the child by `spawnedFrom.sessionId == hub` in Desktop's records and by guest presence, then continues through the plugin. Keep the hub on a cheap model and effort, idle, and re-create it through A when archived. Cost: the first turn reads as a brief from another session, and a model sits in the start path.
3. **A stays as the manual path** for a missing hub or a broken maker, never silently: a card with the link.

Not recommended: G (more machinery than F for the same model-mediated start), H (loses the isolation), I alone (not a conversation; B-17 open).

### Live tests, cheapest first

| # | Settles | Steps | Touches | Owner's OK |
| --- | --- | --- | --- | --- |
| T1 | D wakes an SSH session and the guest plugin comes up with no turn (INFERRED `session.start` on a warm resume) | With the computer running and Desktop open on another session: open `claude://code/continue?session=local_<existing SSH session>`; watch `~/Library/Logs/Claude/main*.log` for `Warming session` → `Using remote spawn function` → `warmed successfully`; check `presence/<cli id>` in the guest; send one Router message to it. Pass: presence within ~10 s of the warm and the message lands as the user's turn. | Desktop navigation only; guest files Fjord already writes. Reversible. | Tell them; no approval needed |
| T2 | E: does Desktop adopt a record it didn't write, and when | In the guest folder run the bootstrap with a new uuid U. With Desktop running, write `local_<V>.json` shaped like an existing SSH record (keep `sessionId`, `cliSessionId`, `cwd`, `originCwd`, `sshConfig`, `title`, `createdAt`, `lastActivityAt`, `isArchived:false`, `permissionMode`; leave out `sshRemote*`/`sshReattach`). (a) Open `claude://code/continue?session=local_<V>` at once. (b) If nothing happens, open a new Desktop window (`initializeWithAccount` runs on window attach) and retry the link. (c) If still nothing, quit Desktop normally, relaunch, retry. Pass: the warm chain in the log, presence in the guest, a Router message delivered. Record whether Desktop rewrote, kept or deleted the file and what it filled in. Clean up: archive the session in Desktop. | Writes one file in Desktop's private folder; one bootstrap session in the guest; possibly a Desktop restart | **Yes**: writes Desktop state |
| T3 | F hub semantics: no card without a place; `fresh` and `fork` children start on the same host and folder with the brief as their first turn; `spawnedFrom` in the child's record | In an existing SSH session in the project folder, send (through the Router, as the owner's words) "Start a session here, context fresh, no host or cwd, for: reply with the word pong" with an 80+ character background; then the same with context fork. Pass: no approval card, the child appears with `sshConfig` and the same `cwd`, its first user row is the brief, `spawnedFrom.sessionId` is the hub, and the guest plugin's presence appears for it. Then send a Router message to the child. | Two new sessions in Desktop (archive afterwards); guest files | Tell them; no approval needed |
| T4 | Only if E passes and is chosen: Desktop restart survival and a second start while the first child runs (governor, token cap) | Repeat T2 (a) for a second record while the first is open; quit and relaunch Desktop; confirm both records survive and continue to wake. | As T2 | **Yes** |

Order: T1 (needed by every design), then T2 (a–c) and T3 in either order; T4 last.

### Open points to carry

- Whether a `fresh` child started from the hub inherits the hub's permission mode or asks (the code applies `wk(parent, p)`; the card's mode logic is skipped without a card). T3 reports it.
- `stoppedUntilPersonSends` after a remote failure blocks automatic warms until the person sends in Desktop; Fjord should surface that state (the held-start card) rather than retry.
- A Desktop update can change the record schema (E) or the tool's consent rules (F). Fjord should check the Desktop version it last verified against and degrade to A with a note, as RouterStatus does for the CLI binary.
