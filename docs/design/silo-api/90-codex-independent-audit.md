## Summary counts

**The spec does not yet provide a complete, consistent contract for implementing Fjord.** Every registered Silo command is mentioned, but several automatic behaviors are omitted, and required Fjord workflows depend on unresolved or conflicting contracts.

| Category | Count |
|---|---:|
| Registered Tauri commands checked for a spec mapping | 159 |
| Registered commands wholly unmentioned | 0 |
| Missing engine behaviors | 3 |
| Partial coverage | 7 |
| Contradictions with Silo code | 1 |
| Design problems | 7 |
| **Confirmed findings** | **18** |
| Unverified qualification groups, excluded from findings | 4 |

Silo was audited at `94d81937904af83faf5839e8b28b24e0e1883c8b`. The audit used feature documents, frontend actions and state contracts, command registration, and backend workers and recovery paths. The spec was reread after the parallel citation checks. No files were modified; no apps, VMs, builds, or tests were started.

**Reference convention:** Silo code paths below are relative to `/Users/polarzero/code/projects/microsandbox-workspaces/app/SiloUI/`. Documentation paths are relative to the Silo repository. Spec references use section numbers and method or behavior names, without spec line numbers.

### Independent capability inventory

Each row groups related capabilities while preserving the actions, settings, and statuses that require coverage. A mapping means the spec addresses the subject; findings below identify incomplete contracts.

| Silo capability, actions, or visible state | Independent evidence | Spec coverage |
|---|---|---|
| Linux inventory, resource configuration, stable identity, lifecycle state, attention/failure state, pending restore and revocation | `src/features/application/model/application-source.ts:162–215`; `docs/SiloUI-CONNECTIONS.md`, “User behavior” | §10 `computers.list`, computer views and state mapping |
| Create, edit, duplicate, delete; configuration progress, retry, partial completion; skip computer-use preparation wait | `src/desktop/production-source.ts:1332–1375,1757–1765`; `docs/SiloUI-PREPARATION.md`, “Behavior” | §10 `computers.create`, `computers.configuration.change`, `.retry`, `computers.delete`, `computers.creation.skipComputerUseWait`; Duplicate as client composition |
| Start, Stop, Restart, confirmations, automatic transient retry, account preparation, failure diagnostics and dismissal | `src/features/application/model/lifecycle-guard.ts:32–53,87–133`; `docs/SiloUI-FAILURE-REPORTING.md` | §10 lifecycle methods, recovery and failure reporting; **P4** |
| Queue, waiting/running status, blocked maintenance, cancellation; setup/lifecycle Activity and safe diagnostic details | `src/features/application/model/application-source.ts:138–159`; `src/desktop/production-source.ts:1855–1859` | §10 `operations.list`, `.cancel`, `activity.setup.read`; **D2** |
| Working account, privileged management boundary, Git/jj identities, migrated-account checks and non-root file ownership | `docs/SiloUI-WORKING-ACCOUNT.md`, “Account record and setup”, “SFTP runtime fix” | §10 lifecycle and identities; §50 guest access; §70 `guest.account`; **P4** |
| Checkpoint create, restore, fork, delete, usage, full/disk state, pending restore, recovery checkpoint and abandon unfinished restore | `src/components/checkpoint-panel.tsx:94–155`; `docs/SiloUI-CHECKPOINTS-PLAN.md`, “Product flows” | §20 `checkpoints.*`, pending restore and restore journal |
| Export computer/checkpoint, inspect/import archive, destination choice, progress, cancel, acknowledge, dismiss and reveal result | `src/desktop/production-source.ts:1913–1919,1947–2010`; `docs/SiloUI-RUNTIME-PACKAGING.md`, “Export profile and archive compatibility” | §20 `exports.*`; dialogs/reveal are client responsibilities |
| Host allocation versus guest usage/capacity, reclamation, maintenance history | `src/pages/workspace-storage-panel.tsx:129–229`; `docs/SiloUI-STORAGE-RECLAMATION.md`, “Storage panel and history” | §10 `storage.read`, `.reclaim`, automatic reclamation |
| Logs search, source/computer/date filters, context, pagination, Follow, timestamps, stopped-computer history, export and cancel | `src/pages/logs-page.tsx:57–68`; `docs/SiloUI-LOGS.md`, “Search and investigation” | §10 `logs.query`, `.export`, `.export.cancel`; **P2–P3** |
| Folder browsing, pagination, refresh, copy path, open selected folder in editor, stopped/unavailable status | `src/features/application/components/folder-actions.tsx:20–33`; `docs/SiloUI-FILES.md`, “Loading and refresh” | §50 `files.list`, `guest.sshAlias.ensure`; **P5** |
| Upload/download, conflict resolution, replace/keep-both, progress, cancellation, partial-file cleanup, native selection and viewer drops | `src/components/use-file-transfers.tsx:45–139`; `docs/SiloUI-FILES.md`, “Upload and download” | §50 `files.upload`, `.download`, `.transfer.cancel`, transfer/drop events |
| Terminal/editor handoff, custom application preference, running-computer checks, SSH pinning, Include notice, selected-folder checks and protected editor profiles | `src-tauri/src/terminal.rs:75–103`; `src-tauri/src/editor.rs:32–104`; `docs/SiloUI-EDITOR-HANDOFF.md`, “Trust the editor gives the computer” | §50 `terminal.command`, `guest.sshAlias.ensure`, `editor.includeNotice`, client launchers; **P5, D3** |
| Repository discovery, branch/head/dirty/ahead/behind state, captured push target, durable push status, unknown outcome and acknowledgment | `src/features/application/model/application-source.ts:50–88`; `src/desktop/production-source.ts:1767–1849` | §50 `push.repositories`, `.start`, `.status`, `.dismiss`; **M3, P6** |
| GitHub OAuth connect/cancel/reopen/disconnect, repository management/refresh, account-wide switch, per-computer policy, identity and retry | `src/desktop/production-source.ts:1868–1888`; `docs/SiloUI-GITHUB-IMPLEMENTATION.md` | §50 `github.*`; §10 identities; **M2, D4** |
| Personal-token save/replace/remove, validation status, explicit authentication-method selection without fallback | `docs/SiloUI-GITHUB-PERSONAL-TOKENS.md`, “Behavior”, “Credential boundaries” | §50 `github.personalToken.*`, configuration policy and worker |
| Secret add/edit/remove/retry, domain and assignment validation, write-only value, active/applying/restart-required state, pending revocation and errors | `src/features/application/model/application-source.ts:202–215`; `docs/SiloUI-SECRETS.md`, “Boundary” | §50 `secrets.*`; lifecycle/restore integration; **P7, D4, D7** |
| Listener discovery, publish/unpublish, explicit/automatic ports, website opening, URL/address copy, reachable/waiting/unknown states and remote tunnels | `src/features/application/model/application-source.ts:98–116`; `docs/SiloUI-NETWORK-PLAN.md` | §50 `network.*`, desired-rule reapplication and background repair |
| Managed SSH enablement, LAN/VPN/interface selection, address/port editing, authorized keys, fingerprint, connection-command copy and key export | `src/pages/ssh-access-panel.tsx:103–153`; `docs/SiloUI-MANAGED-SSH.md`, “Using access” | §50 `sshAccess.state`, `.save`, `.connection`, guest preparation/stream |
| Connections enable/connect/replace/remove, device identity, SSH authorization/key setup, remote inventory and operations, disconnect status | `src/desktop/production-source.ts:1669–1743`; `docs/SiloUI-CONNECTIONS.md`, “User behavior” | §60 `connections.*`; §05 bridge transport; **C1** |
| Linux desktop install/update/start/stop/restart, supported legacy recipes, autostart, readiness/failure and computer-use setup/retry | `src/desktop/linux-desktop-viewer.tsx:38–123,205–225`; `docs/SiloUI-DESKTOP.md`, “Lifecycle” | §40 `desktop.status`, `.action`, `.connect`, computer-use methods |
| Linux viewer open/close, reconnect, fullscreen, resize/device pixels, screen reset, clipboard, file drop, sound check/cancel and audio toggle | `src/desktop/linux-desktop-viewer.tsx:200–231`; `src/desktop/linux-desktop-sound-state.ts:19–93` | §40 `display.viewer.*`, `clipboard.transfer`; client drawing; **D5** |
| LCU installation/update, agent reconciliation, ask/auto approval, default approval, app status/retry and creation wait | `docs/SiloUI-COMPUTER-USE-PLAN.md`, “Integration contract”, “Approval design” | §40 `computerUse.*`; §20 preparation |
| macOS creation/resources, IPSW download/install, setup steps/logs/errors, retry/cancel, templates and template deletion | `src/features/macos-computers/components/macos-computer-row.tsx:82–135`; `docs/SiloUI-MACOS-COMPUTERS.md`, “Behaviour”, “Templates” | §30 creation/setup/templates and snapshots; shared §10 methods |
| macOS Start/Stop/Force Stop/Delete, native screen, automatic Recovery screen, clipboard, disk/memory checkpoints and pending restore | `src/desktop/macos-computers.ts:5–22`; `src/features/macos-computers/components/macos-checkpoint-panel.tsx:20–50` | §10 lifecycle; §20 checkpoints; §30 `macos.action`, `display.show`, `.close`, clipboard |
| Remote macOS display authorization, connection/reconnection, resize and fullscreen | `src/desktop/macos-remote-viewer.tsx:69–210,237–244` | §30 `macos.display.*`, remote display behavior |
| Dependency reports, preparation state/retry, runtime migration retry/continue, pre-upgrade backup measure/delete/acknowledge, onboarding recovery | `src/features/application/pages/system-issue-page.tsx:20–27`; `src/desktop/production-source.ts:1385–1509` | §20 `device.dependencies`, `preparation.*`, `migration.*`; §60 onboarding; **M1, P1** |
| Persisted settings, drafts, revisions, write failure/protection, retry/flush, installed application discovery and custom application selection | `src/features/preferences/model/settings.ts:4–82`; `docs/SiloUI-SETTINGS.md`, “Saved values”, “Shared state and failures” | §60 `settings.*` and field ownership classification; §05 client/engine split |
| Notifications, categories, focus suppression, replacement/withdrawal, click routing; update check/download/install/retry, automatic/focus checks and manual installer | `docs/SiloUI-NOTIFICATIONS.md`, “Policy”; `docs/SiloUI-LINUX-UPDATES.md`, “In-app Debian updates” | §60 notifications and updates; §05 update preparation/abort; **D6** |
| Navigation, menus, command palette, shortcuts, help/About/issues/releases, sidebar/status destinations and window styling | `src/features/application/components/application-commands.ts:41–129`; `docs/SiloUI-NATIVE-MENUS.md` | §60 app-shell classification; drawing/navigation remain client-side |

The settings inventory includes all 23 fields in `src/features/preferences/model/settings.ts:4–61`: `theme`, `launchAtLogin`, `startComputersAtLaunch`, `startupComputerIds`, `computerOrder`, `terminal`, `editor`, `browser`, their three custom paths and three system-default switches, `reduceMotion`, `computerUseAutoApproval`, the notification master/category switches, and the three onboarding/notice-dismissal flags. Legacy notification-field conversion is at `:64–82`. Connections settings and automatic-update preferences are covered separately in §60.

### Independent automatic-behavior inventory

| Engine behavior without a direct user action | Silo evidence | Spec coverage |
|---|---|---|
| Vocabulary conversion before saved-state readers; migration state installation and pending conversion | `src-tauri/src/runtime_migration/vocabulary.rs:1–85,173–183`; `runtime_migration.rs:821–858` | §05 engine startup; §20 migration |
| Export/import journal recovery before generation migration; interrupted-result settlement | `src-tauri/src/backup_controller.rs:308–334` | §20 export/import journal; §05 startup |
| Image-cache repair, configuration recovery, lifecycle-intent recovery and preservation of explicit stops | `src-tauri/src/startup.rs:177–226` | §10 launch, configuration journal and lifecycle intents |
| Update-resume recovery of exactly the journaled computers; launch-selection filtering, deduplication and continuation after failures | `src-tauri/src/startup.rs:18–104,135–149,227–265` | §10 `computers.launch`; §60 updates |
| Lifecycle retry/supersession; bounded health inspections, exit waiters and unexpected-state notices | `src-tauri/src/health_watch.rs:207–273`; `runtime.rs:3111` | §10 lifecycle recovery and health watch |
| Automatic storage trim, stopped-log retention cleanup and deferred checkpoint cleanup | `src-tauri/src/runtime/storage.rs:710–741`; `runtime.rs:2676–2683`; `runtime/checkpoints.rs:2952–3090` | §10 storage/log retention; §20 checkpoint deletion; **D7** |
| SSH listener/interface monitoring and startup editor-transport repair | `src-tauri/src/ssh_access.rs:514–568`; `editor.rs:1141–1219` | §50 SSH monitor and alias repair |
| GitHub account/catalog refresh, token renewal, personal-token validation, policy application and disconnect revocation | `src-tauri/src/github.rs:2830–2975` | §50 GitHub background work |
| Durable issued-token ledger and independent retirement retry | `src-tauri/src/github.rs:1189–1275,2804–2827,2985–3006` | **Missing: M2** |
| Secret startup recovery, legacy-removal migration, live reconciliation and deferred name revocation | `src-tauri/src/secrets.rs:753–779,903–930` | §50 secrets background work; **P7, D7** |
| Saved local-port repair on reads; remote dead-tunnel repair and desired tunnel reopening | `src-tauri/src/network.rs:729–769,827–836`; `remote_network.rs:529–543` | §50 network background repair |
| Shared image/LCU preparation, joining in-flight work, verification, publication and retry | `src-tauri/src/preparation.rs:239–353`; `docs/SiloUI-PREPARATION.md`, “Behavior” | §20 preparation |
| ChatGPT preparation delay, automatic backoff, terminal-failure stop, manual wake, single worker and low priority | `src-tauri/src/chatgpt_app/auto.rs:13–96,138–151` | §20/§40 app preparation; **P1** |
| ChatGPT readiness resynchronizes running guests; old-version/staging/download collection is gated and retried | `src-tauri/src/chatgpt_app.rs:1842–1922,2028–2128,2196–2200` | Readiness hook covered in §40; collection **missing: M1** |
| Computer-use startup reconciliation, approval/pin application and app-ready integration | `src-tauri/src/computer_use.rs:1293–1368` | §40 reconciliation and app status |
| macOS registry loading, partial-checkpoint cleanup, restore-journal recovery and periodic VM-state observation | `src-tauri/src/macos_computers.rs:524–560,2256–2310` | §30 startup/state; §20 restore journal |
| macOS template compatibility/pruning and stale computer-use update cancellation/retry on a later start | `src-tauri/src/macos_computers.rs:612–648`; `macos_computers/guest_computer_use.rs:424–451,522–545` | §30 templates and in-place updates |
| Pre-upgrade backup expiration at startup/hourly; automatic and focus-triggered update checks | `src-tauri/src/pre_upgrade_backup.rs:414–459`; `updates.rs:230–290` | §20 backup expiry; §60 updates |
| Push journal recovery to unknown outcome, LFS-before-ref publication and private publishing-cache recovery | `src-tauri/src/host_push_operations.rs:96–103`; `host_push.rs:960–1014`; `host_push_cache.rs:92–177` | §50 push journal; **M3, P6** |
| Remote change identity/deadline handling, durable non-replay markers, result retention and device-health backoff | `src-tauri/src/remote/operations.rs:1–9,117–157`; `remote.rs:1490–1577` | §05 transport; §60 Connections |
| Shutdown admission barrier, transfer/listener/tunnel draining, logout cleanup and pipe-owned helper lifetime | `src-tauri/src/main.rs:363–374`; `runtime/shutdown.rs:50–129`; `owned_tunnel.rs:1–46` | §05 process lifetime/shutdown; §10/§60 shutdown integration |

## Missing

### M1. ChatGPT app garbage collection and deferred cleanup

**Spec location:** §20 `preparation.chatgpt.status` / `.retry`; §40 `computerUse.app.status` / `.retry`.

Neither contract specifies collection of obsolete published versions and records, stale staging directories, or downloads for other versions. Silo preserves old versions while a Linux computer runs, takes a hidden device gate, never waits for the storage lock while holding that gate, and retries skipped collection every 120 seconds.

**Evidence:** `src-tauri/src/chatgpt_app.rs:1842–1922,2028–2068,2110–2128,2223–2227`; `docs/SiloUI-CHATGPT-APP.md`, “Behavior”.

**Consequence:** Extraction can lose both disk cleanup and the protection against deleting an app version still used by a running guest. Specify this as engine behavior; it does not require a public cleanup method.

### M2. GitHub issued-token retirement ledger

**Spec location:** §50 GitHub “Background work”, `github.disconnect`, and `push.start`.

The spec describes renewal and disconnect revocation but omits the separate `runtime-grants` credential-store ledger. Silo records each successful issuance before another network request, preserves credentials still used by runtime grants or active pushes, and independently retries retirement and failed ledger writes.

**Evidence:** `src-tauri/src/github.rs:1189–1275,2125,2804–2827,2985–3006`.

**Consequence:** Partial issuance failures, replacement, or process death can leave credentials without the durable record needed for eventual revocation.

### M3. Private publishing-cache recovery and eviction

**Spec location:** §50 `push.start`, `.status`, `.dismiss`.

Repository-discovery caching is described, but the separate host publishing cache is absent. Silo imposes a 2 GiB budget, protects repositories with inherited cross-process locks, recreates caches carrying a stale `.active` crash marker, discards failed publication state, and avoids evicting active caches. Cleanup failure after publication must not turn a successful remote ref update into a failed push.

**Evidence:** `src-tauri/src/host_push_cache.rs:17,92–177,202–215,272–289`; `docs/SiloUI-GITHUB-IMPLEMENTATION.md`, “Standard host publishing implementation”.

**Consequence:** A replacement implementation can misreport successful pushes, reuse interrupted state, or remove a cache still used by a surviving Git child.

## Partial

### P1. Automatic ChatGPT preparation is named but not specified

**Spec location:** §20 `preparation.chatgpt.status` / `.retry`; §40 app preparation.

Missing semantics include the ten-second startup delay; retries after 30 seconds, one, two, five, ten and thirty minutes, then hourly; stopping on nonretryable failure; manual Retry waking/resetting the schedule; single-worker coordination; and low execution priority.

**Evidence:** `src-tauri/src/chatgpt_app/auto.rs:13–96,138–151`; `chatgpt_app.rs:2212–2220,2235–2237`; `docs/SiloUI-CHATGPT-APP.md`, “Automatic preparation”.

**Consequence:** Merely preserving status and manual Retry drops Silo’s unattended preparation behavior.

### P2. Log credential filtering is absent from the contract

**Spec location:** §10 `logs.query`, `logs.export`.

Silo maintains PEM-filter state per execution session and stream, filters before search/indexing, and preserves that state when rereading pages. Activity filtering also handles credential assignments, authorization options, URL user information and signatures. The spec’s incidental description of diagnostics as “filtered like Logs” does not define these rules.

**Evidence:** `src-tauri/src/runtime_logs.rs:106–151,367–377,445–456`; `runtime_activity.rs:419–510`; `docs/SiloUI-LOGS.md`, “Search and investigation”.

**Consequence:** Search, context, pagination, Follow or export can expose output that Silo currently removes unless filtering is preserved explicitly.

### P3. Malformed and oversized log degradation is undefined

**Spec location:** §10 `logs.query`, `logs.export`.

`unreadableRecords` is exposed without defining invalid/binary/oversized execution-record placeholders, console truncation, estimated timestamps, or ignoring an unterminated JSON record.

**Evidence:** `src-tauri/src/runtime_logs.rs:243–310,369–372`; `docs/SiloUI-LOGS.md`, “Search and investigation”.

**Consequence:** One damaged record can become a whole-query/export failure instead of remaining inspectable alongside valid history.

### P4. Working-account preparation omits legacy migration rules

**Spec location:** §10 `computers.start`; §70 `guest.account`.

“Prepare the account” does not specify copying legacy root/desktop agent files, preserving conflicts, writing the policy record last for interrupted-work retry, handling UID/GID collisions, or refusing an unknown future policy. These rules also affect restored, forked and imported computers.

**Evidence:** `src-tauri/src/working_account.rs:3–8,15–26,39–65`; `src-tauri/guest/working-account.py:64–65,124–164,224–270`; `docs/SiloUI-WORKING-ACCOUNT-MIGRATION.md`, “At the first start”, “Nothing is deleted”, “Home conflicts and retries”.

**Consequence:** An extraction that only creates `silo` can strand existing files or lose deterministic migration recovery.

### P5. Selected-folder editor handoff lacks a formal parameter

**Spec location:** §50 `guest.sshAlias.ensure`, “Launchers”; §70 `guest.sshAlias.ensure`.

The UI opens a specific guest folder. Silo validates that path, checks that the guest directory exists, and performs a BatchMode SSH probe. §50 assigns these checks to `guest.sshAlias.ensure` with an optional `path` in prose, but its parameter list omits `path`; §70 also omits it.

**Evidence:** `src/features/application/components/folder-actions.tsx:20–25`; `src-tauri/src/editor.rs:46–99`.

**Consequence:** A generated client cannot express the existing folder-opening action or invoke its promised validation.

### P6. Host Push omits LFS publication and recovery ordering

**Spec location:** §50 `push.start`.

The upload-pack and credential description does not specify historical LFS source fetch, LFS upload, one upstream fetch/upload retry, terminal cancellation/credential-expiry handling, and publication of the Git ref only after LFS succeeds.

**Evidence:** `src-tauri/src/host_push.rs:960–1014`; `docs/SiloUI-GITHUB-IMPLEMENTATION.md`, “Standard host publishing implementation”.

**Consequence:** Implementing only Git fetch/push can publish references whose required LFS objects were not uploaded.

### P7. Secret startup recovery is reduced to an install hook

**Spec location:** §50 secrets “Background”; §05 engine startup.

Silo processes legacy removals before slow guest reconciliation, reconciles surviving affected secrets, releases the global operation lock, schedules pending revocations, and emits a state change. Naming `secrets::install` does not state these recovery obligations.

**Evidence:** `src-tauri/src/secrets.rs:903–930`.

**Consequence:** The engine can start with unfinished removals or stale assignments without completing Silo’s existing recovery work.

## Contradictions

### C1. Protocol equality is presented as application-release equality

**Spec claim:** §05 “Capabilities and version negotiation” concludes that exact version matching means both devices must run the same Silo version. §60 update-ownership Open question 9 says updating one device breaks Connections until the other matches.

**Code:** Authorization compares the request’s numeric **protocol version** against `VERSION`, then checks device identity. It does not compare application releases. Application version appears separately in error metadata.

**Evidence:** `src-tauri/src/remote.rs:36,2161–2184,564–577`; `bridge_error.rs:17–24`.

**Correction:** State that different protocol versions are rejected. Different application releases sharing protocol version 5 are not rejected merely because their release versions differ. Any stricter supported-release policy must be identified separately from the implemented check.

## Design problems

### D1. Screen locking and proof recording have no usable contracts

**Requirement:** §00 owner decisions require one GUI driver at a time and recordings of agent use.

§40 “One GUI driver at a time, and recordings as proof” explicitly specifies no NEW methods. §70 “A screen lock and proof recordings” requires acquisition before a run, holder display, release on job completion, and a fetchable finished recording, but provides no corresponding contracts.

Existing Silo offers neither feature: macOS setup capture takes still images, and the Linux viewer proxy transports opaque WebSocket traffic. The old no-arbitration policy is explicitly reversed by the brief.

**Evidence:** §00 owner decisions; §40 named behavior; §70 named requirement; `src-tauri/src/macos_computers/guest_screen.rs:1–8`; `desktop_proxy.rs:380–397`; `docs/SiloUI-DESKTOP-VIEWER-DIRECTION.md:11–14`.

**Blocker:** Fjord cannot implement either required workflow. The spec must define lock state/acquisition/release, which input paths obey it, job/disconnect cleanup, and recording start/finish/fetch ownership. Absence of an existing implementation does not remove an explicit NEW requirement.

### D2. Unified jobs and cancellation conflict with the operations contract

§05 “Long jobs with progress” says every job immediately returns `jobId: string`, and “Cancellation” routes every job through `operations.cancel {jobId}`. §10 instead defines Linux-only gate entries with `id: u64` and `operations.cancel {id}`, including success for unknown IDs. §70 gives guest execution string job IDs, owner-side persistence across client disconnects, replayable output and confirmed process termination.

Current Silo has a process-local gate counter, an independent macOS operation tracker, and separate cancellation paths for transfers and log exports.

**Evidence:** §05 named behaviors; §10 `operations.list` / `.cancel`; §70 `guest.exec.start` / `.get`; `src-tauri/src/runtime/operation_gate.rs:94–125,241–249,1031–1054`; `macos_computers.rs:327–331`; `transfer.rs:1482–1496`; `log_export.rs:73–78`.

**Blocker:** Fjord cannot reliably enumerate, reconnect to, route or cancel all jobs. Define one authoritative job identity/registry and its relationship to owner device, engine lifetime, gate entries, retained results and each existing cancellation adapter.

### D3. Shared methods have incompatible schemas and error vocabularies

Three conflicts prevent generating one Swift client:

- §30 `guest.exec` accepts a shell `command` and `maxStdoutBytes`, returning `status` and string output. §70 accepts `argv`, `cwd`, `env`, `as` and `maxOutputBytes`, returning `exitCode`, byte output and truncation state.
- §50 `guest.sshAlias.ensure` accepts `computer` and `installInclude`, returning `includeLine` and `manualIncludeRequired`. §70 accepts `computerId`, returning `home` and `includeInstalled`.
- §05 retains the existing `ErrorCode` set, while §70 introduces codes such as `notRunning`, `accountNotMigrated`, `permissionDenied`, `exists` and `changed` without integrating them into that set.

**Evidence:** The named methods in §§30, 50 and 70; §05 transport error contract; current execution types at `src-tauri/src/macos_computers/guest_access.rs:36–41,454–483`; Include notice at `editor.rs:1080–1126`; error vocabulary at `bridge_error.rs:4–24,105–122`.

**Blocker:** The same method name cannot have both contracts. Consolidate request/result/error definitions and specify platform adapters and NEW error translations.

### D4. Required macOS and controller credential workflows remain mechanism questions

§00 requires GitHub/secrets in Computers, usually-macOS development, and controllers on other Macs. §50 labels macOS credential assignments NEW but leaves their implementation to mechanism questions Q5/Q6. Remote OAuth callback handling and remote secret-value ownership also remain questions.

Linux credential assignment depends on a MicroSandbox profile/proxy path. macOS uses VZ NAT. Existing GitHub authorization starts a local callback listener.

**Evidence:** §00 owner decisions; §50 “Remote control of GitHub and secrets”, “GitHub and secrets on macOS computers”, Open questions; `src-tauri/src/secrets_runtime.rs:56–58`; `macos_computers/engine.rs:485–486`; `github.rs:2589–2600`; `runtime.rs:13110–13132`.

**Blocker:** Method names alone do not establish a usable credential workflow. Choose and specify the macOS credential mechanism, controller authorization completion, and where secret values are accepted and retained.

### D5. Linux viewer sharing has no client ownership or lifetime rule

§40 makes `display.viewer.open` idempotent per computer and reuses a healthy connection. `display.viewer.close` drops the proxy/tunnel using its connection ID. Shared-versus-separate viewers remain an Open question despite §00 requiring Fjord and Tauri to be clients of the same engine.

Silo currently reserves one viewer per computer and scopes detachment to the calling Tauri window.

**Evidence:** §40 `display.viewer.open` / `.close` and Open question 3; §05 “Two clients at once”; `src-tauri/src/desktop_viewer.rs:126–140,715–729`.

**Blocker:** The spec does not establish whether one client closing a viewer destroys another client’s connection, or how resize, audio and clipboard state are isolated. Define client attachment ownership and release semantics.

### D6. Late clients cannot recover engine notices

§60 `notifications.notice` removes engine-side OS delivery/filtering and acknowledges that startup/editor/update notices can fire without connected clients. Buffering remains Open question 10. §05 `events.subscribe` supplies sequence numbers and rereads after gaps but no notice snapshot or replay contract.

Silo currently emits the notice and independently attempts native notification delivery; health watch generates notices even with the main window hidden.

**Evidence:** §60 `notifications.notice` and Open question 10; §05 event envelope / `events.subscribe`; `src-tauri/src/notifications.rs:124–138`; `health_watch.rs:242–264`; `startup.rs:187–218`.

**Blocker:** An always-on engine can report a failure before Fjord subscribes, leaving Fjord unable to reconstruct the notice. Specify retained notice state or replay, including replacement and clearing semantics.

### D7. Read-triggered maintenance has no unattended convergence contract

Existing maintenance depends on frontend reads:

- `read_application_state` schedules secret revocation and stopped-log cleanup.
- Secret revocation skips busy guests and explicitly retries on a later state refresh.
- Network-state reads schedule saved-port repair.

The independent health watcher calls the lower-level inspection path; it does not run those enriched application-state read side effects. The spec preserves current triggers while replacing polling with events and requiring headless/always-on operation.

**Evidence:** §00 headless/always-on decisions; §05 pushed events; §10 log retention; §50 secrets/network behavior; `src-tauri/src/runtime.rs:2664–2683,3001–3031,13029–13060`; `secrets.rs:753–779`; `network.rs:827–836`; `health_watch.rs:247–251`.

**Blocker:** After a busy-gate skip, no contract guarantees another revocation/repair attempt when clients remain disconnected. Stopped-log cleanup likewise lacks an independent periodic trigger. Specify engine-owned scheduling/convergence or an explicit required read schedule.

## Unverified

These are qualification dependencies, not additional confirmed defects.

| Group | Not established by this audit | Evidence and required qualification |
|---|---|---|
| **U1. Claude Desktop SSH integration** | First-party Desktop behavior, guest plugin/hook loading and ordering, session import, transcript freshness and session-registry identity | §70 Open questions 1 and 5–9. Requires a disposable Desktop-to-guest integration run and inspection of guest/plugin/session artifacts. |
| **U2. Guest SSH suitability** | Linux Claude process survival after a dropped MicroSandbox SSH channel; executable/free guest home; macOS guest SFTP/session limits | §70 Open questions 2–4. Requires disconnect/process checks and guest filesystem/SSH inspection. |
| **U3. Claude credential substitution** | Whether OAuth placeholders pass local validation, all destinations can be allowed, and API exec inherits placeholders/certificate configuration | §70 Open questions 11–13; §50 credential mechanism questions. Requires a disposable authenticated guest run and substitution/environment inspection. |
| **U4. Hosting, packaging and future transports** | LaunchAgent behavior across locked GUI sessions, signing/TCC requirements, update ownership and stable remote-helper paths, headless Linux service packaging, future native Linux frame transport; whether every documented macOS gap must be added now | §05 hosting/packaging Open questions; §60 Open questions 1, 7–9; §40 “Native Linux display (later)”; §20 export facts and §30 “Gaps”. Requires packaging qualification and explicit scope decisions. |

**Next action:** consolidate the job, shared-method, credential, viewer, lock and recording contracts, then add the omitted automatic behaviors as explicit engine requirements before implementation.