# 95 · Decisions (2026-10-13)

These settle the owner decisions listed in [80 §4 (A)](80-coverage-and-consistency.md). Part 1 holds the owner's answers. Part 2 holds the defaults Claude chose for the technical ones; the owner can veto any of them.

## 1. Owner decisions

| ID | Decision |
| --- | --- |
| A-1 | **Fjord is the app people use.** Silo's app is no longer maintained as a product. Silo (the repo) maintains the engine and keeps shipping it in Silo's app, which gets the engine's changes. When both apps are installed on a Mac, only one engine runs. |
| A-2 | **Quit asks when computers are running:** "Quit Fjord? 2 computers are running: dev, linux-1." with **Cancel / Keep running / Stop and quit**. A Fjord update or crash never stops computers. You stop computers from Computers. |
| A-6 | **An engine update saves and resumes running computers:** they are paused to disk and resumed after the update, so runs continue. The engine is updated only when its own version changes. |
| A-8 | **No screen lock.** This keeps Silo's current "no input leases" direction (`docs/SiloUI-DESKTOP-VIEWER-DIRECTION.md:11-14`). |
| A-9 | **Proof recordings are made inside the VM:** ffmpeg on Linux (already in the image), the built-in screen recorder on macOS. They work with no window open. |
| A-14, A-16 | **Another Mac can manage everything on the host,** including GitHub and secrets. Secret values travel over the user's own SSH connection. |
| A-15 | **macOS computers get a host proxy, as on Linux.** Agents only ever see placeholders. Recommended route: reuse MicroSandbox's patched network engine behind a `VZFileHandleNetworkDeviceAttachment` gateway. Its frame rings and poll loop are the public seam (see [92-macos-proxy-research.md](92-macos-proxy-research.md)), and the guest CA is installed through the root finalization step. A probe must qualify the route first (B-27 below). The limit stated in `docs/SiloUI-SECRETS.md:76` still applies: an allowed server receives the real value. |
| A-17 | **GitHub sign-in on a host with no screen goes through the controller's browser.** The loopback callback is carried back to the host over the existing SSH connection. |
| A-18 | **Automatic checkpoints before unattended runs:** the last **3** per computer are kept. Each is labeled clearly as **automatic** ("Before run: <task>, deleted automatically"), unlike manual checkpoints, which are never deleted automatically. A setting changes the count or turns them off. |
| A-19 | **macOS computers get full Linux parity in this API version:** GitHub, secrets, files, ports, terminal and editor, export and import, and start at launch. |
| A-21 | **The engine appears in the Dock and ⌘-Tab only while a VM window is open,** as VMPal does. |
| A-27 | **Only Fjord shows notices.** The engine posts no OS notifications. It keeps the latest notice for each key, so Fjord shows them when it opens. |
| A-36 | **Removing a connected Mac revokes its key on the host.** |

## 2. Technical defaults (Claude; veto any)

| ID | Default |
| --- | --- |
| A-3 | Remote methods go through the controller's local engine. Clients only talk to their local engine. |
| A-4 | Events carry the new state plus a sequence number. Subscriber buffers are bounded; after a gap, or on reconnect, the client re-reads. Remote engines push events through a Stream-class bridge method. |
| A-5 | Local clients are authorized by the same OS user (peer euid), like Silo's socket permissions today. Any such client may change settings. Onboarding drafts stay in the client. The viewer cookie is handed to the client. |
| A-7 | A new local socket keeps the v5 framing and adds request ids for multiplexing. The schema is JSON Schema generated from the Rust types, and the Swift `Codable` client is generated from it. |
| A-10 | Stable snake_case error codes for macOS refusals and the new guest, exec and file errors, added to `ErrorCode` and its fixtures. |
| A-11, A-13 | Records and SSH aliases are keyed by `computerId`; stored name keys are migrated. |
| A-12 | The platform state enums stay as they are, in one `computers.list` with `kind`. macOS gets CPU and memory editing (parity). Disks stay fixed after creation, as on Linux. Host limits go in device facts. |
| A-20 | A remote macOS screen is shown through the existing Screen Sharing stream (today's behaviour). |
| A-22 | The engine returns terminal, editor and browser commands, and clients launch them. The engine needs no Apple Events entitlement. |
| A-23 | On Linux, the engine is a systemd user unit with linger on. A package update stops the engine first (save and resume, as A-6). |
| A-25 | Job outcomes are kept in memory for 1 hour (as remote operation results are today) and lost when the engine restarts. Cancelling an unknown job returns `not_found`. |
| A-26 | The engine runs its upkeep on its own timers, without waiting for a client read: secret revocation retries, log expiry, port repair. |
| A-28 | Each client gets its own viewer connection, so one client closing never ends another's viewer. |
| A-29 | `computers.shell` stays. |
| A-30 | Log exports are cancelled one at a time, by job. |
| A-31 | macOS work joins the operation queue (parity). |
| A-32 | The page relay stays limited to `__silo.invoke` calls. |
| A-33 | The engine enforces the viewer drop's Downloads restriction in `files.upload`. |
| A-34 | The guest desktop port stays hidden. |
| A-35 | Device facts include Remote Login status. |
| A-37 | Bounded `guest.exec` keeps today's error on stdout overflow, with a configurable cap. Long runs (Triage) use the `guest.exec.start` job. |
| A-38 | Fjord ships a hook script and plugin that can run inside the guest, installed through `guest.files.*`. Nothing in the guest depends on Fjord's macOS binary. |
| Secrets wildcard (part of A-16) | The engine requires an explicit `allowAnyDestination` acknowledgement for `*`. |

## Probe added by these decisions

- **B-27:** a disposable macOS VM behind a `VZFileHandleNetworkDeviceAttachment` gateway feeding MicroSandbox's frame engine, using synthetic credentials. Test placeholder substitution, isolation between computers, revocation on an existing connection, and guest CA trust installed with `security add-trusted-cert`.

## 3. Amendments (owner, 2026-10-13, later)

- **No legacy (overrides A-11/A-13 "stored name keys are migrated", and every "wire alias" in 05–70):** the owner is Silo's only user. No backwards compatibility, legacy code paths, old-name aliases or migration paths. The only thing allowed is a migration that runs at launch to reach the new version, using Silo's existing launch-migration logic (`runtime_migration`; see 20 `migration.*`). Silo's Tauri UI lives in the same repo, so it moves to the canonical names, and the v5 wire aliases are dropped.
- **Job results (overrides A-25):** job outcomes are saved to disk by the engine, survive engine restarts, and are dropped once a client has acknowledged showing them. A NEW acknowledge method is needed. Cancelling an unknown job still returns `not_found`.
- **Queue (A-31) confirmed after explanation:** macOS work waits in the operation queue (shown as "Waiting…" with Cancel) rather than being refused.
- **Linux hosts dropped (overrides A-23 and the brief's "Linux hosts run the engine without UI"):** hosts are Macs only. They run both Linux and macOS computers, and Fjord controls them. No Linux engine service, no Debian/AppImage updater path, no headless Linux setup. Probes B-9 and B-26 are closed. Silo's existing Linux packages stop getting engine updates.
- **Keychain with self-signed builds (owner, 2026-10-15):** keep the self-signed "Fjord Dev" signing for now. Without a Team ID, macOS ties each Keychain item to the build that created it, so after each engine update the owner has to allow access again. Make that one deliberate click (an explicit, user-started access repair), never a silent failure.
- **SecureToken after import (owner, 2026-10-15):** accept that an imported macOS computer has no SecureToken. Show it as an informational note, not a setup failure.
- **Triage in a computer (owner, 2026-10-15; replaces the headless design and makes B-17 unneeded for Triage):** a Triage action whose project lives in a computer goes through the Router exactly like a Mac project. The Router starts a real Claude Desktop session over SSH with the existing "Runs on" flow, the `claude://code/new?ssh_host=…&ssh_folder=…&q=<prompt>` link with the prompt pre-filled, and the owner presses Send once. Follow-ups then go through the guest plugin with no click. Reason: Desktop cannot import or start an SSH session without the user pressing Send (docs `triage-in-computers-options.md`, `desktop-*.md`, `probes/e2e-autostart.md`, `probes/e2e-router.md`). No headless `claude -p`, no `claude setup-token` / `CLAUDE_CODE_OAUTH_TOKEN`; sessions are normal Desktop conversations. A-18 still holds: an automatic checkpoint is taken and awaited before the session is prepared (skipped when the count is 0, a failure stops the start and is shown). The Fjord side (ComputerRun records, result view, production gate, proof recordings, the action editor's computer settings) was removed with no migration; a saved "Run in a computer" action is dropped when read.
