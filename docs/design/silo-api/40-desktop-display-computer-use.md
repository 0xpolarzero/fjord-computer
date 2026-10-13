# 40 · Desktop, display and computer use

Domains: `desktop.*` (the existing Linux desktop service, NEW macOS parity by 95 A-19), `display.viewer.*` (the
Linux viewer of the streamed desktop) and `display.native.*` (the later native Linux
display), `computerUse.*`, and the Linux viewer's part of `clipboard.*`.

Silo snapshot: `/Users/polarzero/code/projects/microsandbox-workspaces`, HEAD `94d81937`
(2026-10-10). In this file, paths starting with `src-tauri/`, `src/`, `docs/`, `patches/`
or `runtime-inputs.json` are relative to `app/SiloUI/` for code and to the repo root for
`docs/`. LCU paths are under `~/.local/share/lcu/current/` (installed release 0.11.2,
`bundle.json` `version`).

## Conventions used here

**Host scope (95 §3, Linux hosts dropped).** All owner engines, controller engines and Fjord clients run on Macs only. “Both” in a method's Platforms means Linux computers and macOS computers on those Mac hosts. Linux guest images, desktop services, MicroSandbox, credential substitution and guest SSH remain in scope. Linux engine packages, Secret Service custody, AppImage launch helpers, Linux application launchers and Linux host webviews are retired source evidence, with no API branch or new engine updates (95 §3).


- **Computer identity.** Tauri commands take `computer`: a local computer name, or the
  remote target `silo-remote:<deviceId>:<computerId>` (`src-tauri/src/remote_access.rs:8-19`;
  `docs/SiloUI-VOCABULARY.md:37`). The bridge takes `computerId`, the UUID in
  `ComputerConfiguration.id` (`src-tauri/src/runtime.rs:304-306`;
  `src-tauri/src/remote_access.rs:26-28`). Below, every method takes
  `computerId: string` and, for a computer owned by another device, `deviceId: string`.
  The local engine routes it to the owner, as the Tauri commands do today
  (`src-tauri/src/desktop.rs:906-935`).
- **Errors.** Tauri commands return plain strings. The bridge returns
  `BridgeError { code, message }`, where `code` is one of `update_in_progress`,
  `unsupported_remote_operation`, `cancelled`, `already_queued`, `busy`, `not_found`,
  `incompatible_version` or `internal` (`src-tauri/src/bridge_error.rs:4-24`; on the wire
  `{error, code, message}`, `src-tauri/src/remote.rs:564-576`). Every `desktop.*` error is
  a plain string and reaches the bridge as `internal` (`src-tauri/src/remote.rs:2218`;
  `src-tauri/src/bridge_error.rs:104-107`). The error strings quoted below are the current
  ones.
- **Change semantics on the bridge.** A `Change` method is "accepted once per request
  identity, never replayed" (`src-tauri/src/remote.rs:226-231`). `desktop.action` and
  `computerUse.approval` are `Change`. `desktop.status` and `desktop.connect` are `Read`
  (`src-tauri/src/remote.rs:244-249`).
- **State-change event.** A successful desktop action and an approval change emit
  `silo://application-state-changed` on the owning device (`src-tauri/src/desktop.rs:824`,
  `:848`). The computer-use reconcile and ChatGPT-app-ready paths emit it too
  (`src-tauri/src/computer_use.rs:1348`, `:1366`). No emit was found when a background
  approval apply finishes (pending → applied). In the API these emits are
  `computers.changed` (05 §4.2 D, event catalogue; 80 §2 N15). Payload: NEW full computer state plus sequence number, justified by 95 A-4
  (95 §2; 05 event catalogue). Subscriber buffers are bounded; after a gap or
  reconnect the client re-reads `computers.list` (95 A-4).
- **Jobs.** Methods of Kind `job` follow the one job contract of 05 §4.2 E (ids,
  `operations.job.progress`, `operations.job.finished`) and 05 §4.2 F (cancellation).
  **NEW durable outcomes (95 §3 Job results, overriding A-25):** terminal outcomes
  are saved to disk, survive engine restarts and are deleted only after a client
  acknowledges displaying them through `operations.job.acknowledge` (05 job contract).
  Persisting outcomes does not promise that interrupted work resumes; B-37 qualifies recovery.
- **macOS queue admission (NEW, justified by 95 A-31 and §3 Queue).** Mutating macOS work
  waits for its operation turn, appears as “Waiting…” with Cancel, and is not refused
  because another operation is running (10 operations queue; 95 §3). Read methods and
  established display/SSH streams keep their sourced query/stream roles. Any operation
  cancellation and durable terminal outcome follow the shared 05 contract.

**No legacy contract (95 §3).** Historical commands, bridge names and guest recipes below are evidence of today's implementation, not supported compatibility routes. Silo's Tauri client moves to canonical API names. The engine accepts no old wire names, old-name aliases, name-key fallbacks or legacy guest paths. Any conversion required to reach this version runs once at launch through `runtime_migration` (20 `migration.*`; 95 §3).

---

## 1. The Linux desktop service (`desktop.*`)

### What it is

- **The guest helper.** The helper is `/usr/local/bin/silo-desktop`. Its operations are
  `status`, `connection`, `start`, `stop`, `restart`, `restart-streamer`, `boot` and
  `autostart true|false` (`src-tauri/guest/desktop-service.py:1357-1406`). The internal
  operations are `prepare-install`, `supervise` and `supervise-selkies`
  (`src-tauri/guest/desktop-service.py:1363-1372`).
- **Root only, and serialized.** Every operation needs root (`:1359-1360`). It holds
  `/run/silo-desktop/operation.lock` (`:1374-1375`).
- **Per-boot reset.** The first call of a new boot resets the session's runtime files
  (`:1376-1384`; `docs/SiloUI-DESKTOP.md:40-48`).
- **The session and the streamer.** The session is Xvfb with Xfce on display `:1`. It
  is streamed by Selkies 2.0.0 on guest port 6901 (`docs/SiloUI-DESKTOP.md:50-88`;
  `src-tauri/guest/desktop-service.py:1186-1191`).
- **Shared input.** Human and agent input share the session. Silo does not arbitrate
  between them (`docs/SiloUI-DESKTOP.md:363-364`; `docs/SiloUI-DESKTOP-VIEWER-DIRECTION.md:11-14`).

### Current built-in desktop and streamer

- **Configuration baseline.** `DesktopConfiguration { startWithComputer: bool (default true), builtIn: bool (default false, omitted when false) }` lives in `ComputerConfiguration.desktop` (`src-tauri/src/desktop.rs:8-21`; `src-tauri/src/runtime.rs:318-319`). Current guest images include the built-in desktop; creation sets `builtIn:true` and `startWithComputer:true` (`src-tauri/src/desktop.rs:28-80`; `docs/SiloUI-DESKTOP.md:185-194`).
- **NEW contract, justified by 95 §3.** This API supports the current built-in Selkies desktop and computer-use recipe. It contains no Kasm fallback, pre-v4 desktop installation, LCU 0.4 setup or old streamer receipt/clipboard branches. Those branches exist in today's source (`src-tauri/src/desktop.rs:259-289, 520-528`; `src-tauri/src/desktop_bridge.rs:495-506`) and are excluded by the amendment.
- **Current recipe.** The bundled lock is recipe 4, Selkies 2.0.0, initial size 1440×900 (`src-tauri/guest/desktop-streamer-lock.json`). The host reads `/var/lib/silo-desktop/streamer.json` with desktop status (`src-tauri/src/desktop.rs:160-206`). Any old-record/receipt conversion is launch-only through 20 `migration.*` (95 §3), not runtime compatibility behavior.
- **Update desktop.** `desktop.action {action:"update-streamer"}` runs the bundled `setup-desktop.sh update-streamer`, requires the session stopped, installs the pinned Selkies and patches, preserves credentials and writes the current recipe (`src-tauri/src/desktop.rs:208-257, 291-299`; `src-tauri/guest/setup-desktop.sh:146-153`; `docs/SiloUI-DESKTOP.md:158-173`).

### Autostart

- **Boot hook in the runtime.** The MicroSandbox runtime Silo builds from
  `runtime-inputs.json` (MicroSandbox 0.7.6) carries
  `patches/microsandbox-create-stopped-0.7.6.patch`. That patch runs
  `/usr/local/bin/silo-desktop boot` on every actual boot of a `silo.managed` sandbox,
  with a 15 s limit, and never fails the boot (patch lines 206-225; listed in
  `runtime-inputs.json` `patches`).
- **What `boot` does.** It starts the session when `config.json` `autoStart` is true,
  which is the default (`src-tauri/guest/desktop-service.py:1404-1406`).
- **Setting autostart.** `startWithComputer` is pushed with `silo-desktop autostart
  true|false` by `configure_with` (`src-tauri/src/desktop.rs:324-358`).
  - `configure_with` runs when a configuration change touches only the desktop
    (`src-tauri/src/runtime.rs:5909-5930`) and at creation (`src-tauri/src/runtime.rs:5672`).
  - The first install checks the runtime capability `--silo-desktop-protocol`
    (`src-tauri/src/desktop.rs:334-343`; flag added by
    `patches/microsandbox-silo-network-0.7.6.patch:53-62`; listed in its test at `:81`).
- **Behaviour** (`docs/SiloUI-DESKTOP.md:21-27`):
  - switching autostart on starts a running computer's desktop;
  - switching it off leaves a running desktop alone;
  - an explicit stop in automatic mode lasts for the current boot.
- **API mapping.** Changing `desktop.startWithComputer` is a computer configuration change. Legacy desktop addition is excluded by 95 §3. It belongs to
  `computers.configuration.change` (10 §3; Tauri `change_computer_configuration`,
  `src-tauri/src/runtime.rs:4322`), because `desktop.startWithComputer` is a field of
  `ComputerConfiguration` (10 §1.2; 80 §2 N3). It is not a `desktop.*` method. This
  section only fixes the field's meaning.

### desktop.status

- **Kind:** query.
- **Platforms:** Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19).
- **Status:** EXTENDED. NEW macOS desktop-state adapter (95 A-19); no macOS Selkies service mechanism is established (B-31). Existing source:
  - Tauri `read_desktop_state`, `src-tauri/src/desktop.rs:941-949`.
  - Bridge `desktop.status`, `src-tauri/src/remote.rs:245`, dispatched in
    `src-tauri/src/remote_access.rs:36-40`.
- **Params:** `computerId`, `deviceId?`.
- **Result:** the projected desktop state. The fields come from `public_status`
  (`src-tauri/src/desktop.rs:498-609`) and the stopped fallback (`:430-439`). The TS
  contract is `linuxDesktopStateSchema` (`src/desktop/linux-desktop-state.ts:56-83`).

  | Field | Values | Source |
  | --- | --- | --- |
  | `installed` | bool | desktop.rs:509-511 |
  | `state` | `running` `starting` `stopped` `failed` `uninstalled`; host adds `computer-stopped` | desktop.rs:500-508, :453-457 |
  | `autoStart` | bool | desktop.rs:512-514 |
  | `version` | helper version string or null; absent in the stopped fallback | desktop.rs:599, guest `version='1'` desktop-service.py:1186 |
  | `user` | POSIX name or null (`silo`); absent in the stopped fallback | desktop.rs:599, :611-623 |
  | `display` | `:N[.M]` or null (`:1`); absent in the stopped fallback | desktop.rs:600, :625-635 |
  | `backend` | `selkies` or null in the NEW current-only contract (95 §3); source also accepts historical Kasm | desktop.rs:520-528 |
  | `sessionState`, `streamState` | `stopped` `starting` `running` `failed` null | desktop.rs:529-545 |
  | `updateRequired` | bool | desktop.rs:546-550 |
  | `updateAvailable` | bool, forced false when `updateRequired` | desktop.rs:551-555, :606 |
  | `streamerVersion` | `N.N.N` or null | desktop.rs:556-562 |
  | `computerUse` | object, built-in computers only, also while stopped (see `computerUse.state`) | desktop.rs:432-437, :488-494; computer_use.rs:1614-1624 |
  | `name` | bridge only: the owner's computer name | remote_access.rs:37-40 |

  - The guest reports `port: 6901` (`src-tauri/guest/desktop-service.py:1187`). The
    projection drops it, and the API continues to hide it (95 A-34), although the TS schema allows
    it (`src/desktop/linux-desktop-state.ts:79`).
  - Credentials and other guest output are never projected
    (`src-tauri/src/desktop.rs:498`).
  - The frontend derives `state` from `sessionState`, except for `uninstalled` and
    `computer-stopped` (`src/desktop/linux-desktop-state.ts:86-97`).
- **Errors:**
  - "The computer changed identity. Refresh before accessing its desktop."
    (`desktop.rs:383-385`, `:397-411`)
  - "This computer no longer exists on this device." (`desktop.rs:382`)
  - "The desktop returned an invalid status." and the field-level messages
    (`desktop.rs:477-478`, `:508-555`)
- **Semantics:**
  - Takes no operation gate, so it stays available during other operations
    (`desktop.rs:745-747`).
  - A running computer costs one guest exec with a 15 s guest limit; the host waits up to
    75 s (`desktop.rs:102-110`, `:143`). That exec also reads the computer-use status and
    the streamer receipt (`desktop.rs:459-475`).
  - A stopped computer, or one pending its first restore, is answered from Silo's own
    record (`desktop.rs:386-390`, `:449-458`).
- **Sources:** `docs/SiloUI-DESKTOP.md:29-38`, `:313-320`.

- **macOS addition:** NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The Linux-specific mechanics above do not establish a macOS implementation. macOS native window and Screen Sharing remain the sourced display routes (30 §5; 95 A-20); mappings for desktop, Selkies-only controls and later native-frame transport need OQ 14 / B-31.

### desktop.action

- **Kind:** job (05 §4.2 E).
  - Today the call is synchronous and returns the state at the end.
  - Guest limits are 1800 s for `update-streamer` and the current setup helper,
    120 s for `restart-streamer` and 60 s otherwise (`desktop.rs:301-312`). For
    the historical `setup-computer-use` source route, 1800 s only sets the queue expectation: its guest runs use the
    computer-use helper's 900 s plus 60 s grace (`computer_use.rs:39-43`, `:875-884`;
    `desktop.rs:799-812`).
  - The operation queue's expected duration is the limit plus 5 min, with a 10 min floor
    (`desktop.rs:314-318`).
  - The remote request window is 2100 s for the long actions and 600 s otherwise
    (`src-tauri/src/remote.rs:991-1010`).
- **Platforms:** Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19).
- **Status:** EXTENDED. NEW durable job outcomes plus macOS desktop-operation adapter and queue admission (95 §3 Job results/Queue; 95 A-19; adapter unqualified B-31). Existing source:
  - Tauri `desktop_action`, `src-tauri/src/desktop.rs:950-959`.
  - Bridge `desktop.action`, `src-tauri/src/remote.rs:246`, dispatched in
    `src-tauri/src/remote_access.rs:42` → `desktop::dispatch`, `desktop.rs:670-693`.
- **Params:** `computerId`, `deviceId?`, `action`, one of the following
  (`desktop.rs:759-770`; TS `DesktopAction`, `src/desktop/linux-desktop-state.ts:84`):

  | `action` | Effect | Source |
  | --- | --- | --- |
  | `start` | Starts the computer if `Created`/`Stopped`, then `silo-desktop start` | desktop.rs:792-795, :320-322; desktop-service.py:1390-1391 |
  | `stop` | Ends the graphical session; terminal jobs survive | desktop-service.py:1392-1393; docs/SiloUI-DESKTOP.md:25-27 |
  | `restart` | stop then start | desktop-service.py:1394-1396 |
  | `restart-streamer` | Restarts Selkies only; session and density kept | desktop-service.py:1397-1398; docs/SiloUI-DESKTOP.md:108-109 |
  | `update-streamer` | Refresh the current desktop recipe; no old-recipe compatibility path (95 §3); refused while the session runs | desktop.rs:294-295; setup-desktop.sh:146-153 |

- **Result:** `{jobId}` (`job:<n>`, 05 §4.2 E); `operations.job.finished.result`: the
  desktop state, as in `desktop.status` (`desktop.rs:826`).
- **Progress/events:**
  - No progress source (05 §4.2 E item 4). The action is followed through its gate entry
    on `operations.queue.changed`: it appears in the operation queue as "Updating
    {computer} desktop" and is cancellable (`desktop.rs:716-731`).
  - On success it emits `silo://application-state-changed` (`desktop.rs:824`), which is
    `computers.changed` in the API (05 §4.2 D).
  - There is no finer progress.
- **Cancel:** `operations.cancel {jobId}` (05 §4.2 F), routed to its gate entry.
- **Errors** (`desktop.rs:758-798`, `:906-940`). Where today's command errors, the job
  ends with `operations.job.finished.error` (05 §4.2 E item 5):
  - "Unsupported desktop action."
  - "Add a Linux desktop in computer settings first."
  - "Computer use is built into computers created with the current guest image. Create a new
    computer to use it."
  - "This computer sets up computer use itself."
  - `terminal::start_first` when the runtime has no such computer
  - "Start the computer before changing its desktop session."
  - Shutdown refusal (`runtime::shutdown::ensure_accepting_operations`)
  - Guest exec failures
  - "Missing desktop action." and "Missing computer identity." (`desktop.rs:673`, `:689`,
    `:718`); "Computer operation ordering failed." (`:803`); the gate errors of
    `gate.computer(...)` (`:719-725`)
  - Tauri side: "This window cannot access that desktop." (`desktop_viewer.rs:172`) and
    "Silo could not finish the Linux desktop action. Reopen the viewer and retry."
    (`desktop.rs:938`)
- **Semantics:**
  - Holds the computer's operation turn (per-computer gate, `desktop.rs:745-756`).
  - The guest scripts are pushed from the host, so an older guest copy never installs or
    repairs (`desktop.rs:208-210`).
  - The historical `setup-computer-use` branch supplies `computerUse.setup`; the new `desktop.action` does not accept it (95 §3). Setup takes the same turn and yields to queued stop/delete or explicit Stop and quit (`computer_use.rs:1654-1657`; 95 A-2).
- **Sources:** `docs/SiloUI-DESKTOP.md:29-38`, `:127-173`, `:321-336`.

- **macOS addition:** NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The Linux-specific mechanics above do not establish a macOS implementation. macOS native window and Screen Sharing remain the sourced display routes (30 §5; 95 A-20); mappings for desktop, Selkies-only controls and later native-frame transport need OQ 14 / B-31.

### desktop.connect (engine-internal)

- **Kind:** query.
- **Platforms:** Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19).
- **Status:** EXTENDED. NEW macOS desktop-connection adapter (95 A-19; no macOS Selkies connection mechanism established, B-31). Existing bridge source:
  - Bridge `desktop.connect`, `src-tauri/src/remote.rs:244` → `desktop_viewer::local_connection`,
    `src-tauri/src/desktop_viewer.rs:175-184` → `desktop::connection_local`,
    `src-tauri/src/desktop.rs:961-1009`.
  - It is marked "Private backend-only connection material. Never register this as a UI
    command." (`desktop.rs:961`).
- **Params:** `computerId`.
- **Result:** `{ port: 6901, username, password }`.
  - The username is 1-64 chars of `[A-Za-z0-9_-]`.
  - The password is 32-128 hex chars.
  - Anything else is rejected (`desktop.rs:994-1008`).
- **Errors:**
  - "The desktop is not running."
  - "Could not read desktop connection credentials."
  - "Invalid desktop connection credentials."
  - The shutdown refusal (`desktop_viewer.rs:182`) and the identity errors of
    `desktop.status` (`desktop.rs:979`, `:993`).
- **Semantics:**
  - Takes no gate. It re-checks the computer's identity after the read
    (`desktop.rs:992-993`).
- **API decision:** engine-to-engine only. A client never receives the guest credentials.
  The client-facing method is `display.viewer.open`, below.

- **macOS addition:** NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The Linux-specific mechanics above do not establish a macOS implementation. macOS native window and Screen Sharing remain the sourced display routes (30 §5; 95 A-20); mappings for desktop, Selkies-only controls and later native-frame transport need OQ 14 / B-31.

---

## 2. The Linux display (`display.viewer.*`, Linux computers)

### How Fjord shows Linux desktops at first

- **The streamed viewer stays.** Fjord first shows a Linux computer with the same
  streamed Selkies viewer that Silo uses today. The 2026-10-09 revision keeps that viewer
  for remote computers and the interim; the native Linux-guest display waits for
  MicroSandbox (`docs/SiloUI-DESKTOP-VIEWER-DIRECTION.md:16-38`). That source
  also listed Linux hosts; the later 95 §3 amendment removes the Linux-host route.
- **What Fjord needs.** Fjord needs a web view that loads the Selkies client from a
  loopback origin. The engine keeps everything else, as `desktop_viewer.rs` does today:
  - the SSH tunnel;
  - the authenticating proxy;
  - the guest credentials;
  - the reserved bridge route;
  - the clipboard and sound orchestration.

### The connection the engine owns today

1. **Credentials.**
   - Local: `local_connection` (`desktop_viewer.rs:175-184`).
   - Remote: bridge `desktop.connect` on the owning device (`desktop_viewer.rs:257-267`).
2. **SSH tunnel to a private Unix socket.**
   - The tunnel is `ssh -N -L <socket>:127.0.0.1:6901`, with `ExitOnForwardFailure`,
     `StreamLocalBindMask=0177` and keepalive 15 s × 3 (`desktop_viewer.rs:189-228`; port
     6901 enforced at `desktop.rs:1005-1008`).
   - The socket lives in a fresh 0700 directory (`:230-240`). Its path must fit `sun_path`
     (103 bytes, `:186-187`). The socket must belong to this uid (`:242-253`).
   - The tunnel has 8 s to get ready (`:290-302`).
   - Local computers use the private transport through the runtime's ProxyCommand
     (`desktop_viewer.rs:276-279`; `src-tauri/src/editor.rs:520-535`, `:810-830`).
   - Remote computers use `editor::prepare_remote_private`. It authorizes a per-device
     key in the guest through the owner (`guest.prepare`) and proxies through the owner's
     `guest.ssh` stream (`src-tauri/src/editor.rs:732-797`, `:847-860`;
     `remote_access.rs:265-279`; `remote.rs:1802-1804`).
   - Requires OpenSSH (`desktop_viewer.rs:256`).
3. **Loopback proxy** (`src-tauri/src/desktop_proxy.rs`):
   - **Listener.** It binds `127.0.0.1:0` (`desktop_proxy.rs:497-505`).
   - **Credentials it makes.** It generates a random `token` (UUID simple) and the cookie
     name `silo_desktop_<port>` (`:506-507`). It holds the guest Basic credential
     (`:508`).
   - **Request filter** (`:73-173`):
     - only `GET`, `POST` and `HEAD` with `HTTP/1.1`;
     - `Host` exactly `127.0.0.1:<port>`;
     - the cookie `silo_desktop_<port>=<token>`;
     - `Origin`, if present, exactly `http://127.0.0.1:<port>`;
     - no `Transfer-Encoding` or `Expect`, and bodies of at most 64 MiB.
   - **Forwarding.** It rewrites `Host` and `Origin` to the guest's and injects
     `Authorization: Basic` (`:159`).
   - **Limits** (`:316-399`, `:259-284`, `:520-523`):
     - WebSocket upgrades are relayed transparently;
     - plain HTTP gets a 120 s deadline;
     - headers are capped at 16 KiB within 5 s;
     - at most 48 concurrent connections.
   - **Reserved route.** `/__silo/v1/<op>` is answered by the proxy and never forwarded
     (`:360-362`, `:400-457`; `src-tauri/src/desktop_bridge.rs:22`, `:315-331`).
4. **The registry** (`desktop_viewer.rs:24-159`):
   - at most one viewer per computer, and 16 viewers overall (`:126-141`);
   - each viewer has a `generation`, so a late connect cannot install itself after a close
     (`:24-119`);
   - a healthy connection only resizes, and an unhealthy one reconnects (`:49-52`, `:67-89`).
   - The engine drops connections when a computer is restored (`runtime/checkpoints.rs:2159`),
     when a device is removed (`remote.rs:460`) or its polls find it disconnected or
     revoked (`:1568`, `:1573`), and at Quit or update (`runtime/shutdown.rs:107`;
     `updates.rs:752`).

**B-21 refutes independent current viewers.** `claim_viewer` returns the existing entry for the same computer; its test asserts one entry for two opens (`desktop_viewer.rs:120-139`, `:1210-1219`; [linux.md §B-21](probes/linux.md#b-21--two-viewer-clients)). The live WKWebView follow-up became Selkies' new primary and terminated the original viewer ([linux.md Follow-up §B-18](probes/linux.md#b-18-live-silo-desktop-proxy-in-wkwebview)). Two independent fixture views do not prove two Silo viewers.

95 A-28 therefore requires NEW engine work: client-scoped connection/registry ownership, separate proxies/tunnels, and guest streamer support that prevents a second client taking over the first. The EXTENDED `display.viewer.open`/`.close` methods below carry that NEW behavior; extraction alone cannot provide it. Independent close/disconnect, simultaneous resize and clipboard behavior remain OPEN during implementation (B-21), without introducing input leases (95 A-8).

### What the Tauri webview does: UI-only, but a non-Tauri frontend must do the same

These are the settings of the guest child webview in `desktop_viewer_attach`
(`desktop_viewer.rs:625-670`). Fjord's WKWebView must reproduce them. They are not
engine methods.

- **Storage.** Nonpersistent storage (`.incognito(true)`).
- **Blocked actions.**
  - New windows are denied.
  - Downloads are refused, so the guest page can never write to the host's Downloads
    (`desktop_viewer.rs:636-637`; G-13 in `docs/SiloUI-REVIEW-REMEDIATION-PLAN.md:557`).
  - Navigation is limited to `about:blank` and the proxy origin.
- **The initialization script.** `GUEST_BRIDGE_SCRIPT` (`desktop_viewer_bridge.js`) is
  injected into all frames (`desktop_viewer.rs:458-462`, `:639`). It:
  - locks the web clipboard and `getUserMedia`/`getDisplayMedia`;
  - seeds Selkies' `localStorage` (`clipboard_seamless=false`);
  - installs `window.__silo` (`docs/SiloUI-DESKTOP.md:603-661`).
- **The cookie.** The cookie is set for domain `127.0.0.1`, path `/`, HttpOnly. The
  webview then navigates to `http://127.0.0.1:<port>/` (`desktop_viewer.rs:661-670`,
  `:538-542`).
- **Placement.** The child webview's position and inset come from window geometry
  (`desktop_viewer.rs:430-456`, `:571-593`).
- **Page reloads.** A page-load listener tells the shell about reloads (`:643-651`).

**Qualified WKWebView seam (B-18).** The fixture passed all-frame script injection, HttpOnly cookie hiding, H.264/Opus WebCodecs, download cancellation and page clipboard rejection. The follow-up loaded live Selkies at HTTP 200 through Silo's actual proxy cookie with its bridge script and the same media/clipboard behavior. The live run did not attempt a download; `download_denied=false` is not a failure result. Fjord's native paste-confirmation flow and live download/all-frame behavior remain OPEN ([linux.md §B-18](probes/linux.md#b-18--wkwebview-security-and-media-checks), [Follow-up §B-18](probes/linux.md#b-18-live-silo-desktop-proxy-in-wkwebview)).

### display.viewer.open

- **Kind:** command.
- **Platforms:** Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19).
- **Status:** EXTENDED. NEW authorized cookie/result handoff, separate connection per client and macOS viewer adapter (95 A-5/A-28/A-19; B-31). Existing connection work comes from two Tauri commands:
  - The connection half of `desktop_viewer_attach` (`desktop_viewer.rs:544-693`: tunnel,
    proxy, registry) moves into the engine.
  - The window half of `open_desktop` (`desktop_viewer.rs:316-429`) is UI-only.
  - The remote identity check of `open_desktop` (`desktop.status` before opening,
    `:328-344`) stays in the engine.
  - The result shape is NEW. It is required because the owner decision makes Fjord, a
    non-Tauri process, draw this screen (00-brief "Fjord becomes the main macOS frontend").
- **Params:** `computerId`, `deviceId?`.
- **Result** (NEW type):
  - `connectionId: string` — the registry entry, which replaces the Tauri window label as
    the key (`desktop_viewer.rs:138`).
  - `url: string` — `http://127.0.0.1:<port>/` (`desktop_viewer.rs:625`, `:538-542`).
  - `cookie: { name, value, domain: "127.0.0.1", path: "/", httpOnly: true }`, which is
    `Proxy.cookie_name` and `Proxy.token` (`desktop_proxy.rs:20-27`, `:506-507`;
    `desktop_viewer.rs:661-666`).
  - `initScript: string` — the text of `desktop_viewer_bridge.js`. The engine serves it
    because the script and the Rust route parser share one contract file
    (`src-tauri/src/desktop_bridge_contract.json`; `docs/SiloUI-DESKTOP.md:637-640`).
  - `name: string` — the display name: the computer name, or "<computer> · <device>" for a
    remote computer (`desktop_viewer.rs:328-345`).
- **Errors:**
  - "Close an unused desktop viewer first." (`desktop_viewer.rs:135-137`)
  - "The desktop is still connecting." (`:77-79`)
  - "Desktop tunnel closed. Check the computer connection." (`:292-293`)
  - "Desktop connection timed out. Reconnect the computer." (`:298-299`)
  - "The desktop connection is not private. Reconnect the desktop." (`:248-249`)
  - "Your home folder's path is too long for a desktop connection." (`:203`)
  - "The desktop is not running." (`desktop.rs:980-982`)
  - Shutdown refusal (`desktop_viewer.rs:326`)
- **Semantics:**
  - Opening never starts the desktop. Starting is a separate explicit operation
    (`docs/SiloUI-DESKTOP-VIEWER-DIRECTION.md:163-164`).
  - It is idempotent per client and computer: that client's healthy connection is
    returned, and an unhealthy one is replaced. Each client receives a separate
    connection, proxy and tunnel; the 16-viewer cap applies to connections
    (NEW, justified by 95 A-28; existing reuse/drop and cap:
    `desktop_viewer.rs:67-140`). Closing or disconnecting one client cleans up only
    its own connection (95 A-28). NEW streamer admission must also prevent Selkies primary-client takeover; current live behavior terminated the first viewer ([linux.md Follow-up §B-18](probes/linux.md#b-18-live-silo-desktop-proxy-in-wkwebview)).
  - Closing the view never stops the desktop (`docs/SiloUI-DESKTOP.md:25`).
  - The cookie value is a bearer secret for the loopback proxy. Today it never leaves the
    Silo process (an HttpOnly cookie set by Rust). Here it crosses the engine API to the
    client authorized by peer euid for the same OS user (NEW, justified by 95 A-5;
    existing bearer cookie: `desktop_viewer.rs:661-666`).
- **Sources:** `docs/SiloUI-DESKTOP.md:436-439`; `docs/SiloUI-DESKTOP-VIEWER-DIRECTION.md:45-81`.

- **macOS addition:** NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The Linux-specific mechanics above do not establish a macOS implementation. macOS native window and Screen Sharing remain the sourced display routes (30 §5; 95 A-20); mappings for desktop, Selkies-only controls and later native-frame transport need OQ 14 / B-31.

### display.viewer.close

- **Kind:** command.
- **Platforms:** Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19).
- **Status:** EXTENDED. NEW caller-owned connection authorization and macOS viewer adapter (95 A-28/A-19; B-31). Existing cleanup: Tauri `desktop_viewer_detach` (`desktop_viewer.rs:715-732`). Closing
  the child webview is UI-only.
- **Params:** `connectionId` — must belong to the authorized calling client (NEW, justified by 95 A-28).
- **Result:** none.
- **Errors:** "Unknown desktop viewer." (`:722`).
- **Semantics:**
  - Bumps the generation and drops the proxy and tunnel (`desktop_viewer.rs:43-48`).
  - Also ends the viewer's sound probe and audio ordering state
    (`desktop_viewer_media.rs:275-283`). Silo does this when the viewer window is destroyed
    (`desktop_viewer.rs:396-399`), not in `desktop_viewer_detach`.

- **macOS addition:** NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The Linux-specific mechanics above do not establish a macOS implementation. macOS native window and Screen Sharing remain the sourced display routes (30 §5; 95 A-20); mappings for desktop, Selkies-only controls and later native-frame transport need OQ 14 / B-31.

### display.viewer.page (the page channel)

- **Kind:** subscription: the event `display.viewer.page` of the 05 event catalogue
  (05 §4.2 D), from engine to client, with no reply. It is delivered to one client
  (`Audience::Client`), not broadcast (05 §4.2 D; 80 §2 N15). The page answers over HTTP
  to the proxy's reserved route.
- **Platforms:** Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19).
- **Status:** EXTENDED: existing viewer page evaluation is reached by Tauri `desktop_viewer_attach` (`src-tauri/src/desktop_viewer.rs:545-567`; `src-tauri/src/desktop_bridge.rs:421-430`) and its `Page` adapter below. NEW client-addressed page events move that evaluation to Fjord while retaining only the `__silo.invoke` relay (95 A-32; 00 brief, Fjord draws the screens). This is a catalogue event, not another request method.
  - Today Rust drives the guest page through the `Page` trait, whose only method is
    `eval(script)` (`src-tauri/src/desktop_bridge.rs:421-430`), implemented by the Tauri
    child webview.
  - With Fjord the page lives in the client's web view. So the engine needs a way to ask
    the client to evaluate a script in that page.
  - Required by the owner decision that Fjord draws the screens. The `Page` seam is the
    exact cut point.
- **Event:** `{ connectionId, script: string }`. `script` is always
  `window.__silo&&window.__silo.invoke(<method>,<args>);`, built with `serde_json`
  (`desktop_bridge.rs:529-535`).
  - `method` is one of `sendFrames`, `sendShortcut`, `requestClipboard`, `capabilities`,
    `setMute`, `setVolume`, `setAudioActive`, `resetScreen` or `resetResolutionToWindow`
    (`src-tauri/src/desktop_viewer_bridge.js:421-434`; `desktop_bridge.rs:582-737`).
- **Semantics:**
  - The client must evaluate the script in the guest page's main frame and do nothing else
    with it.
  - The page posts its answer to `/__silo/v1/{clipboard|capabilities|sent}`. It needs the
    viewer cookie and a single-use nonce that the engine issued (`desktop_bridge.rs:45-98`,
    `:121-216`; `docs/SiloUI-DESKTOP.md:632-649`).
  - The engine waits for the answer: 3 s for acknowledged sends, up to 10 s for other
    waits, plus a 5 s grace (`desktop_bridge.rs:22-29`).
  - So the guest page stays untrusted. Only engine-issued nonces are accepted, and the
    client relays scripts without reading answers.
  - A client that does not evaluate the script makes every call below fail with "The
    computer did not answer." once the wait ends (`desktop_bridge.rs:134-143`). "The desktop
    is not connected." (`:29`) is only the page's own `closed`/`disconnected` answer
    (`:598`, `:663`).

- **macOS addition:** NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The Linux-specific mechanics above do not establish a macOS implementation. macOS native window and Screen Sharing remain the sourced display routes (30 §5; 95 A-20); mappings for desktop, Selkies-only controls and later native-frame transport need OQ 14 / B-31.

### clipboard.transfer (Linux viewer part)

- **Kind:** command.
- **Platforms:** Linux and macOS computers on Mac hosts only (95 §3).
  - On a Linux computer it needs an open viewer connection, because the transfer goes
    through the Selkies page.
  - The macOS variant is Tauri `macos_computer_clipboard`
    (`src-tauri/src/macos_computers.rs:900-912`). It returns the same `Report` type and
    belongs to the macOS section.
- **Status:** EXTENDED. NEW macOS operation queue admission with Waiting/Cancel (95 A-31; 95 §3 Queue); Linux/macOS clipboard behavior already exists. Existing source: Tauri `macos_computer_clipboard` (`src-tauri/src/macos_computers.rs:900-912`) and `desktop_viewer_clipboard` (`desktop_viewer.rs:694-713`) →
  `viewer_clipboard::run_blocking` (`src-tauri/src/viewer_clipboard.rs:232-248`).
- **Params:**
  - `computerId`, `deviceId?`;
  - `connectionId`, required for Linux only (80 §2 N9);
  - `action`: `paste` | `copy` (`viewer_clipboard.rs:29-34`), on both platforms (80 §2
    N9). `paste-into` / `copy-from` is only the internal macOS `Direction`
    (`src-tauri/src/macos_computers/guest_clipboard.rs:107-114`).
- **Result:** `Report { action, status, content, message }`
  (`viewer_clipboard.rs:36-66`).
  - `status` is one of `pasted`, `copied`, `device-empty`, `computer-empty`, `too-large`,
    `not-connected`, `unsupported`, `busy` or `failed`.
  - `content` is `text`, `image` or null.
- **Semantics** (`docs/SiloUI-DESKTOP.md:740-776`):
  - Before any key is sent, the engine asks the page for the server's clipboard policy,
    for up to 4 s. If clipboard policy disables it, it reports `unsupported`; there is no recipe-2 compatibility branch (95 §3).
  - **Paste.** It reads the device clipboard: text up to 1 MiB, otherwise a PNG of up to
    16 MiB and 32 Mpx. It sets the guest clipboard, then sends Ctrl+V.
  - **Copy.** It sends Ctrl+C, waits up to 1 s for a new selection and writes the device
    clipboard. HTML flavours are dropped.
  - Linux source behavior permits one transfer per viewer and reports `busy` for a second (`viewer_clipboard.rs:212-237`). NEW macOS work waits in the operation queue with “Waiting…” and Cancel rather than failing admission due to competing work (95 A-31; 95 §3 Queue).
  - The device clipboard is the engine host's pasteboard (`src-tauri/src/clipboard.rs`;
    `docs/SiloUI-DESKTOP.md:855-921`). On macOS, `silod` runs in the user's GUI login
    session (00-brief), so it can reach that pasteboard.
- **Triggers are UI-only:** Command+C/V, the Edit menu items and the toolbar buttons
  (`src-tauri/src/viewer_shortcuts.rs`; `docs/SiloUI-DESKTOP.md:722-738`).
- **Events:** none. The Tauri event `desktop-clipboard` is UI-only, not an API event: it
  reports a transfer that a shortcut in the Tauri shell started
  (`viewer_clipboard.rs:249-256`). In the API the client starts every transfer itself and
  gets the `Report` as the result (80 §2 N9).

- **macOS addition:** only the NEW behavior named in Status is added; existing macOS setup, record and clipboard primitives are cited above and in 30 §10.

### display.viewer.sound.check

- **Kind:** query (long-polling, up to 60 s).
- **Platforms:** Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19).
- **Status:** EXTENDED. NEW macOS viewer sound-capability adapter (95 A-19; Selkies mechanics do not establish it, B-31). Tauri `desktop_viewer_sound_support`
  (`src-tauri/src/desktop_viewer_media.rs:302-328`).
- **Params:** `connectionId`.
- **Result:** `{ sound: bool }` (`desktop_viewer_media.rs:289-292`).
- **Semantics:**
  - It probes the page's `capabilities` 20 times, 0.5 s apart, until the Selkies transport
    is open (`:20-29`, `:57-96`).
  - When the web engine cannot decode Opus, it calls `set_audio_active(false)` so the guest
    stops encoding audio (`:60-70`).
  - Only one probe runs per viewer. A newer request supersedes an older one with "The
    desktop sound check was cancelled." (`:125-256`).
  - The answer describes the client's web engine (WebCodecs Opus), never the OS version
    (`docs/SiloUI-DESKTOP.md:795-814`).

- **macOS addition:** NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The Linux-specific mechanics above do not establish a macOS implementation. macOS native window and Screen Sharing remain the sourced display routes (30 §5; 95 A-20); mappings for desktop, Selkies-only controls and later native-frame transport need OQ 14 / B-31.

### display.viewer.sound.cancel

- **Kind:** command.
- **Platforms:** Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19).
- **Status:** EXTENDED. NEW macOS viewer probe cancellation adapter (95 A-19; B-31). Tauri `desktop_viewer_sound_cancel` (`desktop_viewer_media.rs:330-336`).
- **Params:** `connectionId`.
- **Result:** none.
- **Semantics:** abandons the probe (`Probes::cancel`, `:170-178`).

- **macOS addition:** NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The Linux-specific mechanics above do not establish a macOS implementation. macOS native window and Screen Sharing remain the sourced display routes (30 §5; 95 A-20); mappings for desktop, Selkies-only controls and later native-frame transport need OQ 14 / B-31.

### display.viewer.audio.set

- **Kind:** command.
- **Platforms:** Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19).
- **Status:** EXTENDED. NEW macOS viewer audio-control adapter (95 A-19; Selkies mechanics do not establish it, B-31). Tauri `desktop_viewer_set_audio` (`desktop_viewer_media.rs:338-356`).
- **Params:**
  - `connectionId`;
  - `muted: bool`;
  - `active: bool` — false while the client's view is hidden or minimized;
  - `revision: u64` — monotonic.
- **Result:** none.
- **Semantics:**
  - Applied under a per-viewer lock. A revision older than the last applied one is skipped
    (`:98-121`).
  - It uses Selkies `setMute` and `pipelineControl` (`desktop_bridge.rs:700-717`).
  - The mute preference is the client's own per-computer setting
    (`docs/SiloUI-DESKTOP.md:815-828`). That is UI-only.

- **macOS addition:** NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The Linux-specific mechanics above do not establish a macOS implementation. macOS native window and Screen Sharing remain the sourced display routes (30 §5; 95 A-20); mappings for desktop, Selkies-only controls and later native-frame transport need OQ 14 / B-31.

### display.viewer.screen.reset

- **Kind:** command.
- **Platforms:** Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19).
- **Status:** EXTENDED. NEW macOS viewer screen-reset adapter (95 A-19; Selkies mechanics do not establish it, B-31). Tauri `desktop_viewer_reset_screen` (`desktop_viewer_media.rs:358-370`).
- **Params:** `connectionId`.
- **Result:** none.
- **Semantics:**
  - Sends `r,1440x900,primary` and `s,96`, acknowledged (`desktop_bridge.rs:719-731`;
    `desktop_viewer_media.rs:16-18`).
  - Arms a one-shot listener so the next window resize returns the screen to the window's
    size (`docs/SiloUI-DESKTOP.md:829-838`).
  - Not offered when the desktop reports `updateRequired` or `updateAvailable`
    (`docs/SiloUI-DESKTOP.md:834-836`).

- **macOS addition:** NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The Linux-specific mechanics above do not establish a macOS implementation. macOS native window and Screen Sharing remain the sourced display routes (30 §5; 95 A-20); mappings for desktop, Selkies-only controls and later native-frame transport need OQ 14 / B-31.

### Resize and device-pixel rendering

- **Resize: no engine method.**
  - The Selkies client watches its own view size. 500 ms after the last change it asks the
    server for that size in device pixels (`docs/SiloUI-DESKTOP.md:840-847`).
  - The client only has to size its web view. Closing the view keeps the size.
- **Device pixels.**
  - This is the guest flag `--use-css-scaling=false|locked`, recipe 4
    (`docs/SiloUI-DESKTOP.md:66`). A Retina view gets 2× pixels and DPI 192, and the
    display-scaling patch turns that into Xfce at 2× (`docs/SiloUI-DESKTOP.md:90-114`).
  - Frame size is capped to H.264 level 5.2 (about 8.8 Mpx) because the macOS WebKit
    decoder refuses larger frames. So a very large view shows a slightly scaled picture
    (`docs/SiloUI-DESKTOP.md:116-125`).
  - A fresh session always starts at 1440×900 and 96 DPI, which computer-use agents
    expect (`docs/SiloUI-DESKTOP.md:71-88`, `:108-114`).
- **Window limits are UI-only.** The minimum window is 672×480 (`desktop_viewer.rs:384-385`).

### File drop to Downloads

- **Today.**
  - A native drag over a viewer window (shell or guest view) emits `silo://viewer-drag`
    with `true` or `false`.
  - On drop it emits `silo://viewer-drop` with an `UploadSelection` token, not the paths
    (`src-tauri/src/transfer.rs:70-71`, `:1279-1305`, `:1216-1245`).
  - The shell then calls `upload_files` with `directory` set to `/home/silo/Downloads`
    (`src/desktop/viewer-file-drop.tsx:54`). A viewer window may only upload there
    (`transfer.rs:1373-1390`, `:156-158`).
- **API mapping.**
  - The upload is `files.upload` (the files section): `directory =
    files.downloadsRoot` = `/home/silo/Downloads`.
  - The token indirection keeps host paths out of the shell webview: it gets a token and
    file names, never paths (`transfer.rs:1279-1281`, `:1216-1219`). It is Tauri
    capability plumbing, so it is UI-only. A native client passes the dropped paths it got
    from its own drag and drop.
  - The restriction "a viewer drop goes to Downloads only" is enforced today by the Tauri
    command on the calling window's label (`transfer.rs:1386-1390`). The engine enforces this in `files.upload` with a viewer origin bound to the
    caller's `connectionId` (NEW, justified by 95 A-33; 50 §files.upload).

---

## 3. Native Linux display (later)

- **Availability:** later. Gated on the following:
  - **microsandbox#1805.** It is open. A maintainer says virtio-gpu "should appear in
    0.8.x", with library bundling undecided. Display output and input are not confirmed
    (https://github.com/superradcompany/microsandbox/issues/1805, read 2026-10-13;
    `docs/research/desktop-native-display-2026-10-09.md:57-60`).
  - **Checkpoints.** MicroSandbox refuses to checkpoint with GPU, sound or input devices
    attached, because they lack quiesce support (`docs/research/desktop-native-display-2026-10-09.md:64-72`).
  - **The direction's own gates.** These are a maintained upstream route, and measured
    latency, CPU and memory against the streamed path
    (`docs/SiloUI-DESKTOP-VIEWER-DIRECTION.md:36-38`).
- **Summary of the sources.**
  - Revision 2026-10-09 of the viewer direction: local computers on macOS move to the
    guest's virtio-gpu scanout in a native view, with virtio-input, host audio and resize.
    Venus GPU comes later. There is no encoder, transport or webview in that path
    (`docs/SiloUI-DESKTOP-VIEWER-DIRECTION.md:16-43`).
  - The streamed viewer stays for remote Linux computers on Mac hosts and the interim; the source
    also lists a Linux-host route now removed by 95 §3
    (`docs/SiloUI-DESKTOP-VIEWER-DIRECTION.md:27-32`). Shared memory does not cross a network
    (`docs/research/desktop-native-display-2026-10-09.md:73-74`).
  - VMPal draws IOSurface frames in Metal. Cua Spaces still streams
    (`docs/research/desktop-native-display-2026-10-09.md:17-37`).
  - MicroSandbox's libkrun has virtio-gpu, a display backend API, virtio-input and
    virtio-snd, but MicroSandbox builds none of them (`:39-43`). Piece-by-piece status is
    at `:45-51`.
- **PR #1482.** It was closed on 2026-09-23 as too large
  (https://github.com/superradcompany/microsandbox/pull/1482).
  - The runtime copies each presented frame into a 2-slot memory-mapped file per scanout.
  - It announces `configure`, `frame` and `disable` as JSON lines on `display.sock` next
    to `agent.sock`. Input comes back on the same socket.
  - The viewer is a separate process, because `Vm::enter()` takes the sandbox's main
    thread.
  - `present_frame` never waits for a viewer: after a 200 ms write timeout the viewer is
    dropped.
  - There is no HiDPI and no clipboard.
  - The wire types are in `crates/runtime/lib/gpu_display/protocol.rs` at head `229c071a`
    (fork `ya-luotao/microsandbox`, branch `gpu-m0`).
- **Owner decision.** The runner's frames are drawn by the frontend (00-brief).

### display.native.attach

- **Kind:** stream. The engine relays the runner's display socket to a local client, as
  the bridge does for other `Stream` methods (`src-tauri/src/remote.rs:226-234`).
- **Platforms:** Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19). The sourced Linux shared-memory route is local to the engine only; macOS transport is unsourced (OQ 14 / B-31).
- **Status:** NEW, later. No native frame/input attachment is implemented in Silo: its runtime omits the display components (`docs/research/desktop-native-display-2026-10-09.md:39-51`), and #1482 is an unshipped protocol source, not a current bridge method. Required by 95 A-19 and the owner decision above, and by the revision
  2026-10-09 direction. The shapes come from PR #1482's `protocol.rs`.
- **Params:** `computerId`.
- **Frame source.** Newline-delimited JSON, tagged by `t`:
  - `hello { sandbox }`.
  - `configure { scanout, width, height, format, path, slots }` — `path` holds `slots`
    back-to-back frames of `width*height*4` bytes in `format`. `SLOTS = 2`.
  - `frame { scanout, slot, seq, rect? }` — `rect` is `[x, y, w, h]` of damage.
  - `disable { scanout }`.
  - Pixels never cross the socket. The client maps `path` read-only (#1482's
    `crates/cli/lib/commands/display.rs:190-191`).
- **Input back.** Evdev-style, tagged by `t`:
  - `key { code, down }` (`KEY_*`);
  - `abs { x, y }` with both axes in `0..=32767`;
  - `btn { code, down }` (`BTN_*`);
  - `rel { code, value }` (`REL_WHEEL` and others).
- **Resize.** No message in #1482. Runtime resize exists only as steamac patch `0012`,
  against upstream libkrun (`docs/research/desktop-native-display-2026-10-09.md:49`;
  #1805 body). See Open questions; no shape is specified here.
- **Audio.** Host CoreAudio playback exists only as steamac `0014`
  (`docs/research/desktop-native-display-2026-10-09.md:50`). The sources give no client
  API shape.

- **macOS addition:** NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The Linux-specific mechanics above do not establish a macOS implementation. macOS native window and Screen Sharing remain the sourced display routes (30 §5; 95 A-20); mappings for desktop, Selkies-only controls and later native-frame transport need OQ 14 / B-31.

---

## 4. Computer use (`computerUse.*`)

### Model

- **Linux built-in computers.**
  - The device's published ChatGPT app folder is mounted read-only at `/opt/silo/chatgpt`.
    The verified LCU archive, when Silo holds it, is mounted read-only at `/opt/silo/lcu`
    (`src-tauri/src/computer_use.rs:32-35`, `:658-713`).
  - After each boot, when the app becomes ready, on an approval change and at app start,
    the host pushes `silo-computer-use.py` and `pinned.json` and runs `apply`
    (`computer_use.rs:1-10`, `:786-813`, `:1127-1368`).
  - The host decides and keeps state. The guest is "a plain executor"
    (`computer_use.rs:7-9`; `src-tauri/guest/silo-computer-use.py:1-31`).
- **Not a security boundary.** Agents in the computer have root, so the approval switch
  configures agents' approval prompts and nothing more (`computer_use.rs:140-142`;
  `docs/SiloUI-COMPUTER-USE-PLAN.md:351-362`).
- **macOS computers.** The ChatGPT macOS app and LCU's darwin build are installed by
  `silo-computer-use.zsh` over SSH, during setup step 4 and by in-place updates
  (`src-tauri/src/macos_computers/guest_computer_use.rs:1-7`; `docs/SiloUI-MACOS-COMPUTERS.md:333-371`).

### Guest helpers

- **Linux** `/usr/local/libexec/silo-computer-use` (`silo-computer-use.py:823-857`):
  - **`status`** prints the receipt projection. It is read in the same guest command as
    the desktop status (`computer_use.rs:800-802`; `desktop.rs:460-463`).
  - **`apply --approval ask|auto [--force] [--boot]`** is idempotent:
    - it installs LCU against the mounted app;
    - it runs `lcu setup --agent all --allow-missing --session direct --yes --approval
      <mode>` as `silo`, adding `--cross-turn on --unattended` from LCU 0.11.0;
    - it runs `lcu status --json` and `lcu doctor` in the session;
    - it reports `apply.outcome` as `applied`, `partial` or `failed` with a `reason`.
    - Sources: `silo-computer-use.py:1-31`; `docs/SiloUI-DESKTOP.md:269-290`;
      `docs/SiloUI-COMPUTER-USE-PLAN.md:478-492`.
  - **`reconcile`** runs `lcu setup --reconcile`. It registers pending agents whose
    binaries now exist. It is skipped while an `apply` holds the lock
    (`silo-computer-use.py:548-565`).
  - **`watch`** is a single instance started by `apply`. It polls the agent install
    directories every 5 s while an agent is pending and runs `reconcile`. A login hook in
    `/etc/profile.d` is the fallback (`docs/SiloUI-DESKTOP.md:291-302`;
    `silo-computer-use.py:487`, `:538`).
- **macOS** `silo-computer-use.zsh`:
  - **Commands:** `apply --approval ask|auto`, `app-present`, `status` and `grant`
    (`src-tauri/guest/macos/silo-computer-use.zsh:9-12`).
  - **`apply` steps:** SIP check, app install, LCU runtime, TCC grants, Screen Sharing, and
    `lcu setup --agent all ... --cross-turn on --unattended`. It also installs a LaunchAgent
    that runs `lcu setup --reconcile` at each login (`:14-28`).

### LCU pins and in-place updates

- **Linux pins.**
  - LCU 0.11.0 for arm64 and amd64 (`src-tauri/guest/lcu-lock.json`).
  - It must equal the ChatGPT app lock's `lcuVersion`, or `pinned()` fails
    (`computer_use.rs:763-784`).
  - Pinned pair: `{ schemaVersion: 1, app: { dir, version, runtime }, lcu: { version,
    archive, url, sha256 } }` (`:775-783`).
- **macOS pins.**
  - LCU 0.11.0 darwin-arm64 (`src-tauri/guest/macos/lcu-lock.json`) and the ChatGPT macOS
    app lock.
  - They are validated by `Pins::parse`: schema 1, versions equal, bundle `com.openai.codex`,
    a 10-char team, and asset hosts checked (`guest_computer_use.rs:251-276`).
- **`runtime-inputs.json`** pins MicroSandbox 0.7.6 and its patches, not LCU. Its
  relevance here is the desktop boot hook (section 1; `runtime-inputs.json:3`, `:64-96`).
- **In-place updates in Linux guests.**
  - Each boot's `apply` reinstalls only when LCU's recorded app path or version differs
    from the pin (`docs/SiloUI-DESKTOP.md:289-290`).
  - At app start, a running computer whose last reported `lcuVersion` is not the pinned
    one gets a boot-style apply (`pin_is_stale` and `reconcile_in`,
    `computer_use.rs:1293-1328`).
  - "Changing the pinned version updates a computer at its next start"
    (`docs/SiloUI-COMPUTER-USE-PLAN.md:189`).
- **In-place updates on macOS, by fingerprint.**
  - `computer_use_version_for(approval)` is the first 8 bytes of a SHA-256 over the app
    lock, the LCU lock, the script and the approval mode (`templates.rs:105-133`).
  - The record stores `computer_use_version` and `computer_use_approval`
    (`macos_computers/store.rs:101-108`). `computer_use_stale()` compares them
    (`store.rs:118-127`).
  - After a Start, a stale complete computer updates on a background thread. Detail
    "Updating Computer Use"; it ends on Stop, Delete, a checkpoint or Quit. The new
    fingerprint is recorded only on success (`guest_computer_use.rs:424-546`;
    `docs/SiloUI-MACOS-COMPUTERS.md:104-130`).

### Supported agents

- **Registered automatically.** `lcu setup --agent all --allow-missing` registers every
  agent LCU supports, including agents installed later (`docs/SiloUI-COMPUTER-USE-PLAN.md:180-186`).
- **Named agents.** The plan names Claude Code, Codex, Pi, OMP and Hermes
  (`docs/SiloUI-COMPUTER-USE-PLAN.md:8-15`, `:70-80`). LCU names the same harnesses
  (`~/.local/share/lcu/current/README.md:34`).
- **What `auto` changes.** It adds only Claude Code `permissions.allow: ["mcp__lcu"]` and
  Codex `default_tools_approval_mode = "approve"`. `ask` removes exactly those
  (`docs/SiloUI-COMPUTER-USE-PLAN.md:236-239`; `docs/SiloUI-DESKTOP.md:307-312`).
- **Reported lists.** Built-in computers report `agents` as free strings from the guest
  (`computer_use.rs:1574-1580`). Historical `lcuAgents` (retired by 95 §3) is filtered to `pi`, `codex` and
  `claude-code` (`desktop.rs:587-593`).

### computerUse.state

- **Status:** EXTENDED. NEW macOS receipt/status projection (95 A-19; 30 §10); Linux computerUse state is already projected by desktop.status. Existing source: Tauri `read_desktop_state` (`src-tauri/src/desktop.rs:941-949`), bridge `desktop.status` (`src-tauri/src/remote.rs:245`), projected `computerUse` (`desktop.rs:430-437,488-494`; `computer_use.rs:1614-1639`).
- **Kind:** query.
- **Platforms:** Linux and macOS computers on Mac hosts only (95 §3). Linux EXISTS; macOS is NEW.
- **Existing Linux behavior:** EXISTS as the `computerUse` object of `desktop.status`
  (`desktop.rs:430-437`, `:488-494` → `computer_use::desktop_state`,
  `computer_use.rs:1614-1639`).
  - Exposing the existing projection separately is extraction; macOS status projection is the NEW behavior. Required by
    `docs/SiloUI-MACOS-COMPUTERS.md:497`: "status in the UI" is listed as not done for
    macOS.
- **Params:** `computerId`, `deviceId?`.
- **Result.** `state_object` (`computer_use.rs:1444-1477`); TS `computerUseSchema`
  (`src/desktop/linux-desktop-state.ts:7-30`).

  | Field | Values |
  | --- | --- |
  | `state` | `unavailable` `preparing` `installing` `ready` `failed` (computer_use.rs:1480-1612) |
  | `reason` | text or null |
  | `cause` | `app-download` only when the host's ChatGPT download failed for good (:1527-1532) |
  | `compatibility` | `tested` `untested` `unknown` (:1401-1407) |
  | `warning` | text or null |
  | `approval` | desired: `ask` `auto` `unknown` (unreadable policy) (:1468) |
  | `appliedApproval` | last mode applied completely, or `unknown` (:1469) |
  | `approvalApply` | `applied` `pending` `failed` `partial` (:1423-1442); TS adds `unknown` |
  | `approvalApplyReason` | text for `failed`/`partial` (:1387-1399, :1453-1458) |
  | `appVersion`, `runtimeVersion`, `lcuVersion` | strings or null |
  | `agents` | string list or null |

  - While the computer is stopped, the last `ready` or `failed` observation is shown from
    `<storage>/computer-use/<id>.observed` (`computer_use.rs:1535-1553`, `:473-478`).
- **macOS (NEW).** The record has only `computer_use_version` and `computer_use_approval`
  (`store.rs:101-108`). The row detail "Updating Computer Use: <step>" is transient
  (`guest_computer_use.rs:50`, `:475-486`, `:505-512`, `:545`).
  - From the record a NEW macOS result can give: `approval`, `appliedApproval` (the
    record's mode while the fingerprint is current), and `approvalApply`: `pending` while
    stale or while an update runs, otherwise `applied`.
  - Any other field needs the guest receipt (`silo-computer-use.zsh` `status`, `:9-12`) and
    stays null until it is read.
  - The receipt fields are the ones 30 §10 lists for its `computerUse.status`:
    `{schemaVersion, state, reason, chatgptVersion, lcuVersion, approval, at}`
    (`src-tauri/guest/macos/silo-computer-use.zsh:82-87`). They are this method's macOS
    fields, read on demand. `computerUse.state` is the one canonical read; 30's
    `computerUse.status` is not a separate method (80 §2 N7).

- **macOS addition:** only the NEW behavior named in Status is added; existing macOS setup, record and clipboard primitives are cited above and in 30 §10.

### computerUse.approval

- **Status:** EXTENDED. NEW macOS desired/applied policy storage, immediate/retry application and queue admission (95 A-19/A-31; 95 §3 Queue). Existing source: Tauri `set_computer_use_approval` (`src-tauri/src/desktop.rs:880-904`) and bridge `computerUse.approval` (`src-tauri/src/remote.rs:249`).
- **Kind:** command. It returns at once; the apply runs in the background.
- **Platforms:** Linux and macOS computers on Mac hosts only (95 §3). Linux EXISTS; macOS is NEW. This is the one canonical setter: the
  existing bridge name, and 30 §10's macOS `computerUse.approval` is its macOS part (80 §2
  N7).
- **Existing Linux behavior:** EXISTS.
  - Tauri `set_computer_use_approval` (`desktop.rs:880-904`).
  - Bridge `computerUse.approval` (`src-tauri/src/remote.rs:249`), dispatched in
    `desktop.rs:675-682`.
  - Routed to the owner with `chatgpt_app::call_owner` (`src-tauri/src/chatgpt_app.rs:2249-2269`).
- **Params:** `computerId`, `deviceId?`, `mode: "ask" | "auto"` (`computer_use.rs:47-71`).
- **Result:** the desktop state (`desktop.rs:852-878`). In the API: `computerUse.state`.
- **Errors:**
  - "Unsupported computer-use approval." (`desktop.rs:838`)
  - "Computer use is built into computers created with the current guest image."
    (`desktop.rs:861-865`)
  - "Silo could not save the computer-use setting." (`computer_use.rs:333`)
  - Shutdown refusal (`desktop.rs:839`)
- **Semantics, Linux. Desired versus applied:**
  - `set_approval` stores the desired mode in `<storage>/computer-use/<id>.json`, under a
    process-wide lock. It never rewrites the last attempt (`computer_use.rs:134-170`,
    `:356-372`).
  - On a running computer it schedules a `Change` apply (`computer_use.rs:1689-1728`):
    - The apply takes the computer's operation turn. It is hidden from the queue UI and
      waits at most 10 min (`:1036`, `:1213-1240`).
    - It re-checks identity and the running instance, and reads the current desired mode
      when its turn comes (`:1242-1250`).
    - It loops until the applied mode equals the desired one (`:1248-1290`).
    - It yields to a queued stop, restart or delete of that computer and to Quit or update
      (`:1041-1113`).
  - A stopped computer applies at its next boot (`docs/SiloUI-DESKTOP.md:303-312`).
  - `approvalApply` is `pending` from scheduling to the end (`computer_use.rs:479-514`).
  - An `unfinished` marker is written before each run, so a crash shows as pending and is
    retried at app start (`:152-158`, `:163-164`, `:387-403`, `:1293-1319`).
  - The download failure `lcu-archive-unavailable` is retried after 1, 5 and 15 min
    (`:516-591`).
  - The remote request window is 2100 s (`remote.rs:1005-1007`).
- **Semantics, macOS (NEW).** Required by `docs/SiloUI-MACOS-COMPUTERS.md:497`: "Not done
  yet: re-applying when the `computerUseAutoApproval` setting changes (a rerun of `apply
  --approval` does it) … status in the UI".
  - Today a macOS computer has no approval command: `set_computer_use_approval` only finds
    Linux metadata (`desktop.rs:371-382`).
  - Its mode is fixed at setup from the initial setting (`macos_computers/provision.rs:182-190`;
    `macos_computers.rs:1208`).
  - An update keeps the recorded mode (`guest_computer_use.rs:493-495`;
    `store.rs:106-107`).
  - NEW type field: a desired mode next to `computer_use_approval`, which is the applied
    one. It is justified by the Linux split between desired and applied
    (`computer_use.rs:143-158`).
  - Today `computer_use_stale()` and `run_update` use the applied `computer_use_approval`
    (`store.rs:121-126`; `guest_computer_use.rs:493-495`). NEW: they read the desired mode
    instead, so a change makes the fingerprint stale. The existing `update_in_background`
    path then applies it (`guest_computer_use.rs:435-546`) at the next Start, its only
    caller today (`macos_computers.rs:1414`). Applying at once on a running computer is a
    NEW call of it.

- **macOS addition:** only the NEW behavior named in Status is added; existing macOS setup, record and clipboard primitives are cited above and in 30 §10.

### computerUse.setup

- **Kind:** job (05 §4.2 E).
- **Platforms:** Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW (95 A-19).
- **Status:** EXTENDED. NEW durable job outcomes and macOS setup adapter/queue admission (95 §3 Job results/Queue; 95 A-19; B-31). Existing source: `desktop.action` with `action: "setup-computer-use"`
  (`desktop.rs:799-812`; `computer_use.rs:1643-1687`), called by the panel's "Try again"
  (`src/desktop/computer-use-bridge.ts:25`; `src/desktop/computer-use-panel.tsx:103`).
- **API decision (NEW, justified by 95 §3).** `computerUse.setup` is the sole canonical setup method. The historical `desktop.action {action:"setup-computer-use"}` route is not accepted by the new API; it is cited only as the existing implementation seam.
- **Params:** `computerId`, `deviceId?`.
- **Result:** `{jobId}` (`job:<n>`, 05 §4.2 E); `operations.job.finished.result`: the
  desktop state, as `desktop.action` returns it.
- **Progress/events:** no progress source; its gate entry on `operations.queue.changed`
  and `computers.changed`, as for `desktop.action`.
- **Cancel:** `operations.cancel {jobId}` (05 §4.2 F), routed to its gate entry.
- **Semantics:**
  - It runs the helper with `--force` inside the computer's operation turn, and cancels a
    scheduled retry (`desktop.rs:799-812`; `computer_use.rs:1654-1660`).
  - It works whether or not the desktop is reachable (`docs/SiloUI-DESKTOP.md:321-327`).

- **macOS addition:** NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The Linux-specific mechanics above do not establish a macOS implementation. macOS native window and Screen Sharing remain the sourced display routes (30 §5; 95 A-20); mappings for desktop, Selkies-only controls and later native-frame transport need OQ 14 / B-31.

### computerUse.defaultApproval (the `computerUseAutoApproval` setting)

- **Kind:** part of `settings.*`. This section only fixes its meaning.
- **Status:** EXISTS.
  - Setting key `computerUseAutoApproval`, a boolean (`src-tauri/src/settings.rs:245-263`),
    default `false` (`src/features/preferences/model/settings.ts:22`, `:54`).
  - UI label: "Allow agents to use the desktop without asking in new computers"
    (`src/features/application/components/connections-settings.tsx:135`).
- **Semantics:**
  - Only `true` means `auto` (`computer_use.rs:191-201`). The value is cached for creation
    and import (`:203-209`, `:225-235`; synced at `settings.rs:507`, `:770`).
  - **New and imported computers** start with it (`computer_use.rs:237-252`;
    `runtime.rs:5680`; `runtime/checkpoints.rs:1019-1020`).
  - **Forks** inherit the source's desired mode (`runtime/checkpoints.rs:1671`;
    `computer_use.rs:429-449`).
  - **Computers created on a connected device** get the controller's setting through
    `computerUse.approval` right after creation (`src-tauri/src/remote.rs:1700-1717`).
  - It is a default for new computers only. Changing it never changes existing computers
    on either platform. On macOS this is the documented gap
    (`docs/SiloUI-MACOS-COMPUTERS.md:497`).

### The ChatGPT for Linux app: `preparation.chatgpt.status` / `preparation.chatgpt.retry`

- **Not defined here.** They are `preparation.chatgpt.status` and
  `preparation.chatgpt.retry`, owned by 20 §4.2.3 and §4.2.4 (80 §2 N5). Their event is
  `preparation.chatgpt.changed` (05 §4.2 D). Historical wire names `chatgpt.status` (Read) and
  `chatgpt.retry` (Change) are removed; both clients call the canonical names (95 §3; source `remote.rs:247-248`). The routing param is `deviceId?`
  (80 §2 N5, N16).
- **Notes for computer use** (facts 20 does not give):
  - `ready` triggers `app_ready`, which applies in running computers
    (`computer_use.rs:1352-1368`; `chatgpt_app.rs:2198`).
  - The TS controller schema allows the remote-only `unknown` state
    (`docs/SiloUI-CHATGPT-APP.md:182-213`; `src/desktop/linux-desktop-state.ts:37-46`).

### Skipping the computer-use wait at creation: `computers.creation.skipComputerUseWait`

- **Not defined here.** It is `computers.creation.skipComputerUseWait`, owned by 10 §3
  (80 §2 N6). Tauri `skip_computer_use_wait` (`src-tauri/src/runtime.rs:3615-3619`).
- **Note for computer use:** after a skip, computer use finishes at first start
  (`docs/SiloUI-DESKTOP.md:241-254`).

### The macOS gap, in one place

- **No approval UI or command.** No command covers macOS computers (`desktop.rs:371-382`).
  "status in the UI" is not done (`docs/SiloUI-MACOS-COMPUTERS.md:497`).
- **No re-apply on change.**
  - The mode is fixed at setup (`provision.rs:182-190`) and kept by updates
    (`guest_computer_use.rs:493-495`).
  - The doc lists "re-applying when the `computerUseAutoApproval` setting changes" as not
    done (`docs/SiloUI-MACOS-COMPUTERS.md:497`).
- **Stale text in the doc.** Row 497 also says upgrading pins in existing computers is not
  triggered. The code and the setup-versions section say the fingerprint update runs after
  each Start (`guest_computer_use.rs:424-546`; `docs/SiloUI-MACOS-COMPUTERS.md:104-130`).
  Treat row 497's upgrade clause as outdated.

---

## 5. Shared input and recordings as proof

**No screen lock or input lease is part of the API.** This follows 95 A-8 and preserves Silo's current shared-input contract (`docs/SiloUI-DESKTOP-VIEWER-DIRECTION.md:11-14`; `docs/SiloUI-DESKTOP.md:363-364`).

**Recordings are guest-side orchestration through `guest.exec.*` and `guest.files.*` (70 §2), with no engine capture/recording method (95 A-9).** Silo's host setup still image is not this recorder (`src-tauri/src/macos_computers/guest_screen.rs:1-8`).

- **Linux (B-24):** use guest `ffmpeg` against display `:1` (the probe used `:1.0`) with `XAUTHORITY=/run/silo-desktop/user/Xauthority`. The installed ffmpeg 6.1.1 captured a 1440×900 JPEG; without Xauthority the attempt failed. This qualifies the capture source/authentication, not a Linux movie start/stop test. Fjord runs video capture as guest work, waits for encoder/file finalization and reads the artifact through `guest.files.*` ([linux.md §B-24](probes/linux.md#b-24--linux-ffmpeg-screen-capture); image source `app/SiloUI/guest-image/Dockerfile:55`).
- **macOS (B-24):** use a guest ScreenCaptureKit recorder app as its own Aqua LaunchAgent. Grant its code identity `kTCCServiceScreenCapture` using the same `csreq`/TCC-row mechanism Silo uses for computer use, and write the matching `ScreenCaptureApprovals.plist` ledger (`src-tauri/guest/macos/silo-computer-use.zsh:205-237`, `:295-326`, `:364-371`). The qualified guest had SIP disabled, as Silo setup requires (30 §3). The recorder must run under the identity whose TCC row was granted; `launchctl asuser` alone does not change SSH responsibility or grant permission. SSH `screencapture` and a direct CLI LaunchAgent produced no movie; an SSH-launched ScreenCaptureKit app returned -3801 before the own-agent/TCC path succeeded ([macos.md initial §B-24](probes/macos.md#b-24-macos--blocked), [Follow-up §B-24](probes/macos.md#b-24-macos--confirmed)).
- **macOS completion/retrieval evidence:** with no host viewer window open, that guest recorder finalized a 10.233333 s H.264 movie at 1280×800, 1,056,640 on-disk bytes, then retrieved it to the host. Use finalized on-disk metadata, not the recorder's intermediate `recordedFileSize` (687,109 bytes in this run). Fjord installs/invokes/stops guest recorder artifacts with generic guest methods and reads the finalized file; persistent recorder packaging and cancellation remain implementation work ([macos.md Follow-up §B-24](probes/macos.md#b-24-macos--confirmed)).

## Coverage table

| Tauri command / event / bridge method | API method | Note |
| --- | --- | --- |
| `read_desktop_state` (desktop.rs:942) | `desktop.status` | Its `computerUse` object is also the Linux result of `computerUse.state` (§4) |
| `desktop_action` (desktop.rs:951), every `action` | `desktop.action` | Kind `job` (`job:<n>`, 05 §4.2 E). `setup-computer-use` maps directly to canonical `computerUse.setup`; `setup-lcu` is excluded (95 §3). No old action or duplicate setup route is accepted |
| `set_computer_use_approval` (desktop.rs:883) | `computerUse.approval` | Linux EXISTS, macOS NEW (80 §2 N7) |
| `change_computer_configuration` (runtime.rs:4322), desktop fields only | `computers.configuration.change` | Owned by 10 §3; this section fixes `desktop.startWithComputer` (80 §2 N3) |
| `open_desktop` (desktop_viewer.rs:317) | `display.viewer.open` (remote identity check, name) | Window creation, title, focus, size: UI-only (WebviewWindowBuilder, desktop_viewer.rs:382-425) |
| `desktop_viewer_attach` (desktop_viewer.rs:545) | `display.viewer.open` (connect: tunnel, proxy, registry) | Child webview bounds, inset, cookie set, navigation, focus: UI-only (desktop_viewer.rs:571-689) |
| `desktop_viewer_detach` (desktop_viewer.rs:716) | `display.viewer.close` | Closing the child webview: UI-only |
| `desktop_viewer_clipboard` (desktop_viewer.rs:697) | `clipboard.transfer` (Linux: `action`, `connectionId` required) | Shortcuts and menu triggers: UI-only (viewer_shortcuts.rs:123-131, app_menu.rs:383-387) |
| `desktop_viewer_sound_support` (desktop_viewer_media.rs:305) | `display.viewer.sound.check` | |
| `desktop_viewer_sound_cancel` (desktop_viewer_media.rs:332) | `display.viewer.sound.cancel` | |
| `desktop_viewer_set_audio` (desktop_viewer_media.rs:339) | `display.viewer.audio.set` | Mute preference storage: UI-only (client localStorage, SiloUI-DESKTOP.md:821-826) |
| `desktop_viewer_reset_screen` (desktop_viewer_media.rs:359) | `display.viewer.screen.reset` | |
| `skip_computer_use_wait` (runtime.rs:3617) | `computers.creation.skipComputerUseWait` | Owned by 10 §3 (80 §2 N6) |
| `chatgpt_app_status` (chatgpt_app.rs:2318) | `preparation.chatgpt.status` | Owned by 20 §4.2.3 (80 §2 N5) |
| `chatgpt_app_retry` (chatgpt_app.rs:2335) | `preparation.chatgpt.retry` | Owned by 20 §4.2.4 (80 §2 N5) |
| event `silo://viewer-drag` (transfer.rs:70) | none | UI-only: OS drag state over the client's own window (transfer.rs:1286-1291) |
| event `silo://viewer-drop` (transfer.rs:71) | input to `files.upload` (directory `/home/silo/Downloads`) | The token indirection is Tauri capability plumbing, so UI-only (transfer.rs:1279-1305) |
| event `silo://desktop-viewer-page` (desktop_viewer.rs:465) | none | UI-only: the client sees its own page loads and calls `display.viewer.sound.check` again |
| event `desktop-clipboard` (viewer_clipboard.rs:22) | none | UI-only, not an API event: reports shortcut-started transfers to the Tauri shell (viewer_clipboard.rs:250-256); an API client gets the `Report` as the `clipboard.transfer` result (80 §2 N9) |
| event `chatgpt-app-status` (chatgpt_app.rs:79) | `preparation.chatgpt.changed` | 05 §4.2 D; 80 §2 N5 |
| event `silo://application-state-changed` (desktop.rs:824, :848; computer_use.rs:1348, :1366) | `computers.changed` | 05 §4.2 D; payload open (05 §10 OQ 18) |
| bridge `desktop.status` (remote.rs:245) | `desktop.status` | |
| bridge `desktop.action` (remote.rs:246) | `desktop.action` | Every `action`, including `setup-computer-use` |
| bridge `desktop.connect` (remote.rs:244) | `desktop.connect` (engine-to-engine only) | Never exposed to clients (desktop.rs:961) |
| bridge `computerUse.approval` (remote.rs:249) | `computerUse.approval` | Same name (80 §2 N7) |
| bridge `chatgpt.status` (remote.rs:247) | `preparation.chatgpt.status`; historical name removed (95 §3) | 80 §2 N5 |
| bridge `chatgpt.retry` (remote.rs:248) | `preparation.chatgpt.retry`; historical name removed (95 §3) | 80 §2 N5 |
| guest `/__silo/v1/<op>` reserved route (desktop_proxy.rs:360) | engine-internal (proxy), reached by the page via `display.viewer.page` | |
| `Page::eval` seam (desktop_bridge.rs:421-430) | `display.viewer.page` | NEW event, delivered to one client (05 §4.2 D) |
| `desktop_viewer_bench` (main.rs:21, :311) | none | Development build benchmark (`main.rs:20`, `:310`, `desktop_bridge.rs:52-53` `#[cfg(debug_assertions)]`), not product |
| (future) runner `display.sock` (#1482) | `display.native.attach` | Later, gated |

## Open questions

1. **DECIDED (95 A-5):** hand the loopback viewer cookie to a client authorized as the same OS user by peer euid (95 §2); current cookie source is `desktop_viewer.rs:661-666`. WKWebView cookie handling remains B-18.
2. **PARTLY B-18:** WKWebView fixture security/media checks and live Silo cookie/bridge/media access passed (§2; [linux.md §B-18](probes/linux.md#b-18--wkwebview-security-and-media-checks), [Follow-up §B-18](probes/linux.md#b-18-live-silo-desktop-proxy-in-wkwebview)). Live downloads/all-frame coverage and Fjord's native paste confirmation remain OPEN.
3. **DECIDED (95 A-28), PARTLY B-21:** client-independent connections are NEW engine/streamer work (§2). Current Silo reuses one registry entry; a second live client took over the first. Independent close, resize and clipboard regression remains OPEN ([linux.md §B-21](probes/linux.md#b-21--two-viewer-clients), [Follow-up §B-18](probes/linux.md#b-18-live-silo-desktop-proxy-in-wkwebview)).

4. **DECIDED (95 A-4):** state events carry new state plus sequence numbers, with bounded subscriber buffers and re-read after a gap or reconnect (95 §2; 05 event catalogue). Current viewer loss is detected through socket failure (`runtime/checkpoints.rs:2159`; `remote.rs:460`); 95 adds no separate `display.viewer.closed` payload or event requirement.
5. **DECIDED (95 A-32):** the page relay stays limited to `window.__silo.invoke` calls (`desktop_bridge.rs:529-535`; 95 §2).
6. **DECIDED (95 A-33):** `files.upload` enforces viewer drops to Downloads on the engine (95 §2; current window-label enforcement: `transfer.rs:1386-1390`; 50 §files.upload).
7. **Native display: resize, HiDPI, audio, clipboard.**
   - #1482 has no resize, a window at the scanout's physical size, and no clipboard.
   - Resize and audio exist only as steamac patches against upstream libkrun
     (`docs/research/desktop-native-display-2026-10-09.md:49-50`).
   - *Settles it:* the virtio-gpu work promised for MicroSandbox 0.8.x (#1805), and
     whether display and input are part of it.
   - Same as 80 §4 C-1.
8. **Native display: frames across processes.**
   - #1482's viewer maps the runner's files directly. With `silod` as a LaunchAgent and
     Fjord as another process of the same user, the client would map files under the
     sandbox runtime directory.
   - *Settles it:* whether the engine passes the file paths (as in #1482) or file
     descriptors or IOSurfaces. The research doc names IOSurface→Metal as VMPal's zero-copy
     path (`docs/research/desktop-native-display-2026-10-09.md:17-24`).
   - Same as 80 §4 C-1.
9. **DECIDED (95 A-8):** no screen lock, input lease or arbitration methods; retain Silo's current no-input-leases direction (`docs/SiloUI-DESKTOP-VIEWER-DIRECTION.md:11-14`; 95 §1).
10. **DECIDED (95 A-9):** proof recording runs inside the guest without a viewer: Linux ffmpeg and the macOS built-in screen recorder (95 §1). SETTLED capture mechanisms are in §5: ffmpeg/Xauthority on Linux and a ScreenCaptureKit guest Aqua agent with its own Silo-style TCC grant on macOS ([linux.md §B-24](probes/linux.md#b-24--linux-ffmpeg-screen-capture), [macos.md Follow-up §B-24](probes/macos.md#b-24-macos--confirmed)).
11. **macOS computer-use state fields.** Resolved: 80 §2 N7 (`computerUse.state` gives the
    record-derived fields, plus the receipt fields 30 §10 lists, read on demand; §4).
12. **Ownership of the ChatGPT app methods and the creation-wait skip.** Resolved: 80 §2 N5
    (`preparation.chatgpt.status` / `.retry`, owned by 20) and N6
    (`computers.creation.skipComputerUseWait`, owned by 10).
13. **DECIDED (95 A-34):** keep the guest desktop port hidden behind the proxy (`desktop.rs:597-607`; 95 §2).

14. **macOS parity adapters (B-31, 95 A-19).** The desktop service is Linux/Xfce/Selkies (`src-tauri/guest/desktop-service.py:1186-1191`); macOS owns a VZ window and Screen Sharing stream (30 §5; 95 A-20). No cited source supplies macOS equivalents for Linux desktop actions, Selkies audio/page controls or later shared-frame transport. *Settles it:* map and probe each common feature against the macOS display routes; do not install a Linux desktop or invent a macOS frame protocol.
15. **SETTLED B-24 capture mechanism (95 A-9):** §5 records Linux capture and macOS no-window movie finalization/retrieval. Linux movie lifecycle, recorder packaging, cancellation and artifact cleanup still need normal implementation validation; these were not observed by the probes.
