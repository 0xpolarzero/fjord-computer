# 10 · Computers: inventory, configuration, lifecycle and the operations around them

Silo snapshot: `/Users/polarzero/code/projects/microsandbox-workspaces` at `94d81937` (2026-10-10). Unless a path says otherwise:

- `src-tauri/…` means `app/SiloUI/src-tauri/src/…`;
- `ui/…` means `app/SiloUI/src/…`;
- `docs/…` means the Silo repo's `docs/`.

This section covers:

- the computer inventory and its state;
- configuration changes;
- start, stop, restart, dismiss and the launchers;
- Git identities;
- the operation queue;
- the activity journals, logs and workspace storage;
- device capacity;
- the remote counterparts of all of the above.

Other sections own these neighbours, and this one only points at them:

- macOS-only details: templates, setup steps, the display window and Force stop's engine call;
- checkpoints;
- `desktop.*` and `computerUse.*`;
- `sshAccess.*` / `guest.*`, which the terminal and editor launchers rely on;
- `settings.*`, `notifications.*` and `events.*` as a transport.

**Owner amendment, 95 §3:** only canonical API names are accepted by local and SSH transports. Silo’s Tauri UI moves to those names; historical command/bridge names below identify source code, not accepted aliases. Persistent upgrades run once at launch through `runtime_migration`; normal method calls neither read old layouts nor migrate them. This overrides the earlier name-key migration and alias policies ([95 §3](95-decisions.md#3-amendments-owner-2026-10-13-later)).

**Host scope, amended by 95 §3:** engine hosts and remote controllers are Macs only. Both Linux and macOS computers remain supported guests. “Linux” below denotes the Linux computer/guest unless explicitly labeled as retired host-source evidence. Linux engine services, Debian/AppImage engine updates and headless Linux host setup are outside this API ([95 §3](95-decisions.md#3-amendments-owner-2026-10-13-later)).

---

## 0. Conventions

### 0.1 Two inventories today, one domain in the API

Silo keeps Linux and macOS computers apart:

- **Linux computers:**
  - saved in `computers.json` (`src-tauri/runtime.rs:813`);
  - read with `read_application_state`;
  - changed with `change_computer_configuration`;
  - lifecycle through `computer_action`;
  - they run in MicroSandbox (`msb`).
- **macOS computers:**
  - live in the Silo process (`src-tauri/macos_computers.rs:1-12`);
  - read with `read_macos_computers`;
  - created with `create_macos_computer`;
  - lifecycle through `macos_computer_action` (`src-tauri/macos_computers.rs:823-835`).

Names are unique across both kinds. A name is reserved under one lock before either side records it (`src-tauri/computer_names.rs:1-40`; Linux at `src-tauri/runtime.rs:4355-4359`, macOS at `src-tauri/macos_computers.rs:982-984`).

The brief asks for one method per concept, covering both platforms (00-brief.md "Shared domains"). Every method below therefore says how it applies to each kind. Where a concept exists for one kind only, the other kind gets a typed refusal: `unsupported_remote_operation` is the closest existing code (`src-tauri/bridge_error.rs:6-15`).

### 0.2 Addressing a computer: local and remote with one method

| Today | Addressed by | Source |
| --- | --- | --- |
| Local Linux lifecycle, terminal, editor | Display **name** (`computer_action(action, name, path)`) | `src-tauri/runtime.rs:3255-3261` |
| Local storage, logs | Stable **id** (`computerId`) | `src-tauri/runtime/storage.rs:745-758`, `src-tauri/runtime_logs.rs:9-10` |
| macOS | Stable **id** | `src-tauri/macos_computers.rs:823-835` |
| Remote | `deviceId` + `computerId`, or the target string `silo-remote:<deviceId>:<computerId>` | `src-tauri/remote_access.rs:8-19`; docs/SiloUI-CONNECTIONS.md "Implementation boundaries" ("Every remote target combines a stable device UUID and computer UUID") |

The UI already uses one string for both cases:

- a local row's target is its name;
- a remote row's target is `silo-remote:…` (`ui/features/application/model/connections.ts:10-21`).

Silo already routes some commands by that string. `computer_action` with `open-terminal`/`open-editor` accepts a `silo-remote:` name and reaches the owner through the bridge:

- `src-tauri/terminal.rs:75-93`;
- `src-tauri/editor.rs:32-43`;
- `ui/desktop/production-source.ts:1211`, which sends non-lifecycle remote actions to `computer_action`.

**`ComputerRef` (NEW type).** Every per-computer method below takes it:

```
ComputerRef = { computerId: string /* UUID */, deviceId?: string /* UUID; absent = this engine */ }
```

- `computerId` is the stable id. Every Linux and macOS computer already has one: `ComputerConfiguration.id`, validated as a UUID (`src-tauri/runtime.rs:6118-6122`), and `Record.id` (`src-tauri/macos_computers/store.rs:77`), a v4 UUID set by `new_record` (`store.rs:198-201`). Using it instead of the name follows Silo's own choice: lifecycle ordering keys on the id "so a rename never lets two operations on the same computer run concurrently" (`src-tauri/runtime/operation_gate.rs:22-26`; `resolve_computer_id`, `src-tauri/runtime.rs:6272-6286`).
- `deviceId` maps one to one onto the `silo-remote:<deviceId>:<computerId>` target. When it is present, the engine forwards the call over the Connections bridge (§11).
- **On the wire it is flattened:** every per-computer method takes `computerId` + `deviceId?` as two top-level params, and device-level methods take `deviceId?` alone (80 §2 N16). "`ComputerRef`" below means that pair. The `silo-remote:<deviceId>:<computerId>` string stays a Tauri-client presentation key, not an API param.
- **DECIDED (95 A-3):** clients call only their local engine; that engine forwards `deviceId` calls over SSH ([95 Part 2](95-decisions.md#2-technical-defaults)). **DECIDED (95 A-11):** convert stored name keys to `computerId` once at launch via `runtime_migration`, including identities and export selection; names remain presentation ([95 Part 2](95-decisions.md#2-technical-defaults); Q10).
- Required by: the brief, "Engines on other devices are reached over SSH" and one method per concept (00-brief.md "What was decided", "Shared domains").

### 0.3 Errors

The wire error is `BridgeError { code, message }` (`src-tauri/bridge_error.rs:17-24`). `code` is one of:

- `update_in_progress`
- `unsupported_remote_operation`
- `cancelled`
- `already_queued`
- `busy`
- `not_found`
- `incompatible_version`
- `internal`

(`src-tauri/bridge_error.rs:4-15`.)

How Silo's internal errors map onto these codes:

- `GateError` maps to `already_queued`, `busy` or `cancelled`; everything else becomes `internal` (`src-tauri/bridge_error.rs:115-126`).
- `RuntimeError` maps `Busy` to `busy` and `Cancelled` to `cancelled`; `Admission(GateError)` follows the `GateError` rule (so it can be `already_queued`); everything else becomes `internal`, with the message from `safe_activity_error` (`src-tauri/bridge_error.rs:127-139`).
- Many commands in scope return a plain `String` error rather than `BridgeError`, for example `change_computer_configuration` (`src-tauri/runtime.rs:4322-4327`) and every local macOS command in `macos_computers.rs` (`src-tauri/macos_computers.rs:781-912`); the remote macOS commands return `BridgeError` (`src-tauri/macos_remote.rs:131-162`). Such errors reach a client as untyped text. In this API they are `internal` unless noted.

The internal error kinds a client may see described are:

- `RuntimeError`: `Busy`, `Admission`, `Invalid`, `Unavailable`, `Launch`, `TimedOut`, `Cancelled`, `Failed{operation, exit_code, detail}`, `Malformed`, `Partial` (`src-tauri/runtime.rs:199-226`);
- `GateError`: `AlreadyQueued`, `Nested`, `Busy`, `Abandoned`, `Cancelled`, `NotCancellable` (`src-tauri/runtime/operation_gate.rs:38-52`).

---

## 1. Types

### 1.1 `ComputerConfiguration` (Linux): `src-tauri/runtime.rs:302-320`

| JSON field | Rust type | Meaning and rules |
| --- | --- | --- |
| `id` | `String` | Stable identity; must be a UUID, unique (`runtime.rs:6118-6122`). Also written as runtime label `silo.machine-id` (`runtime.rs:5620-5621`) and checked before Silo changes or starts a runtime computer (`ensure_computer_identity`, `runtime.rs:4944-4961`; callers such as `2128`, `5212`, `5918`); the state read checks only the managed label (`ensure_managed`, `runtime.rs:4444-4447`). |
| `name` | `String` | Display name and MicroSandbox name. 1–32 chars, `[a-z][a-z0-9-]*` (`runtime.rs:6204-6220`); unique case-insensitively in the request (`runtime.rs:6123-6127`) and across macOS computers (`computer_names.rs:1-40`). Cannot change after creation (`runtime.rs:5484-5486`). |
| `cpus` | `u8` | Boot CPU count, `1..=maxCPUs` (`runtime.rs:6137-6142`). |
| `maxCPUs` | `u8` | CPU ceiling, `≤` device logical CPUs (`runtime.rs:2008-2013`). |
| `memoryGiB` | `u32` | Boot memory, `1..=maxMemoryGiB` (`runtime.rs:6143-6148`). |
| `maxMemoryGiB` | `u32` | Memory ceiling, `≤` physical memory (`runtime.rs:2014-2024`). |
| `workspaceStorageGiB` | `u32` | Size of the owned `/workspace` disk (`runtime.rs:5616-5617`). Cannot be resized (`runtime.rs:5487-5493`). |
| `runtimeStorageGiB` | `u32` | Root disk size (`--root-disk`, `runtime.rs:5614-5615`). Cannot be resized (same rule). Both disks are `> 0` and their sum `×1024` must not overflow (`runtime.rs:6149-6157`). |
| `desktop` | `Option<DesktopConfiguration>` | Optional guest desktop; see 1.2. Cannot be removed once present (`runtime.rs:5477-5483`). |

The struct is `deny_unknown_fields` (`runtime.rs:303`). The UI parser passes unknown fields through (`ui/desktop/production-source.ts:124-130`).

The wrapper `ComputerConfigurationRequest { schemaVersion: u8, computers: Vec<ComputerConfiguration> }` (`runtime.rs:295-300`) has these rules:

- `schemaVersion` must be `1` (`runtime.rs:6104-6108`);
- at most 64 computers (`MAX_COMPUTER_COUNT`, `runtime.rs:49`, `6109-6113`).

### 1.2 `DesktopConfiguration`: `src-tauri/desktop.rs:8-18`

| Field | Type | Meaning |
| --- | --- | --- |
| `startWithComputer` | `bool`, default `true` | Start the desktop session with the computer. |
| `builtIn` | `bool`, omitted when false | The image ships the desktop and computer use (v4+). Silo decides it at creation; a client's value is ignored (`desktop.rs:13-15`, `runtime.rs:364-397`, `desktop.rs:42-80`). A built-in desktop always starts with its computer (`runtime.rs:390-396`). |

### 1.3 `ApplicationSource`: the state document

Rust: `src-tauri/runtime.rs:552-566`. UI parser: `ui/desktop/production-source.ts:206-224`.

| Field | Rust type | Meaning |
| --- | --- | --- |
| `runtimeRepair` | `Option<Value>` | `null` on a normal read. In the shell (1.9): `{status:"unavailable", reason, recovery}` (`runtime.rs:2893-2901`). UI shape `{status: needed\|unavailable, reason, recovery?, checking?}` (`production-source.ts:178-180`). |
| `computers` | `Vec<ApplicationComputer>` | Linux computers in saved order (1.4). |
| `activities` | `Vec<Value>` | Setup, lifecycle and secret activity, newest first, at most 200 (`runtime.rs:4768-4771`); entry shape in 1.10. |
| `computerConfigurationOperation` | `Option<Value>` | Always `null` from Rust (`runtime.rs:4776`). The UI tracks its own in-flight change (`production-source.ts:215-216`, `1338`). |
| `repositoryPushOperations` | `Vec<Value>` | Push state, merged in by enrichment (`runtime.rs:2832-2834`); owned by `push.*`. |
| `github` | `Value` | GitHub snapshot (`runtime.rs:2867-2871`); owned by `github.*`. |
| `secrets` | `Vec<Value>` | Secrets snapshot (`runtime.rs:4712`); owned by `secrets.*`. |
| `deviceCapacity` | `Option<DeviceCapacity>`, omitted when unmeasured | See §10. |

The UI adds fields that do not come from the engine:

- `backup` and `preferences`, legacy defaults (`production-source.ts:220-223`; docs/SiloUI-RUNTIME-ERRORS.md, the paragraph on D-20);
- `computerOperationsUnavailable` (`production-source.ts:957`, `970`), and `localUpdating` on the client snapshot rather than the source (`production-source.ts:1053`);
- `device` on remote rows (`ui/features/application/model/application-source.ts:163`; read by `computerTarget`, `connections.ts:19-21`).

These are client presentation and not part of the API.

### 1.4 `ApplicationComputer`: one Linux row

Rust: `src-tauri/runtime.rs:591-628`. UI: `production-source.ts:132-153`.

| Field | Type | Meaning |
| --- | --- | --- |
| `configuration` | `ComputerConfiguration` | Saved configuration. |
| `purpose` | `String` | Always `"Local MicroSandbox"` (`runtime.rs:4663`, `5007`). |
| `state` | `ComputerState` | `running` \| `starting` \| `stopped` \| `failed` (1.5). |
| `stateDetail` | `String` | Human detail (`"Running"`, `"Stopping"`, `"Paused"`, `"Updating"`, …) (`runtime.rs:4968-5004`; `"Updating"` at `4488-4490`). |
| `canDismissError` | `bool` | True only for an unacknowledged `Crashed` runtime with an `updated_at` stamp (`runtime.rs:5010-5015`). |
| `lifecycleFailure`, `lifecycleFailureDiagnostic` | `string?` (flattened `LifecycleFailureView`) | Latest undismissed failed start, stop or restart: one line plus details (`src-tauri/runtime_activity.rs:241-281`). |
| `attention` | `{level: warning\|error, message}?` | Configuration drift, crash, a stale read, a log-cleanup failure, a secret revocation, a checkpoint record error (`runtime.rs:639-650`, `4734-4753`, `5034-5114`, `2737-2746`; stale read `4505-4512`; start refresh `start_refresh_attention`, `1439`); a failed repository discovery also sets a warning (`2854-2861`). |
| `freshness` | `fresh` \| `stale` | `stale` means this row's own read failed while idle; runtime fields are the last known values (`runtime.rs:652-659`, `4501-4514`). |
| `settling` | `bool`, omitted when false | An operation overlapped the read; runtime fields are from the last idle read (`runtime.rs:606-611`, `4484-4495`). |
| `repositories` | `Vec<Value>` | Discovered guest repositories (running, fresh rows only) (`runtime.rs:2835-2865`); owned by `push.*`. |
| `files`, `ports`, `logs` | `Vec<Value>` | Always empty from the runtime read (`runtime.rs:5021-5023`). Listing is served by `files.*` and `network.*`. |
| `githubRepositories`, `secretNames`, `pendingSecretRevocations` | `Vec<String>` | `githubRepositories` is always empty from Rust (`runtime.rs:4675`, `5024`, `runtime/checkpoints.rs:887`); `secretNames` and `pendingSecretRevocations` are secrets projections (`runtime.rs:4740-4766`). |
| `checkpoints`, `pendingCheckpointRestore`, `checkpointOperation`, `unfinishedRestore` | see the checkpoints section | Loaded per computer (`runtime.rs:4717-4738`). The types live in `src-tauri/runtime/checkpoints.rs:15`, `47`, `55`, `2381`. |

### 1.5 Computer states

**Linux `ComputerState`** (`src-tauri/runtime.rs:630-637`), mapped from the MicroSandbox status (`runtime.rs:4968-5004`):

| Runtime status | `state` | `stateDetail` | `attention` |
| --- | --- | --- | --- |
| `Running` | `running` | `Running` | Config drift or start-refresh warning |
| `Starting` | `starting` | `Starting` | — |
| `Draining` | `starting` | `Stopping` | — |
| `Created`, `Stopped` | `stopped` | `Stopped` | Config drift |
| `Paused` | `stopped` | `Paused` | — |
| `Crashed`, acknowledged (§4.5) | `stopped` | `Stopped` | Config drift |
| `Crashed` | `failed` | `The MicroSandbox runtime reported a crash.` | error: "The computer runtime crashed. Restart it to retry." |
| anything else | `failed` | `…unknown state '<s>'.` | error |

Silo also synthesises these rows:

- a placeholder row before a read, `failed`, `State unavailable` (`runtime.rs:4660-4683`);
- `starting`/`Updating` for a settling row with no earlier reading whose own read also failed (`runtime.rs:4488-4490`); with no earlier reading but a good read, the row keeps this read's values (`4492`);
- a pending-restore row read from Silo's record (`runtime.rs:4433-4437`).

Historical UI fallback showed a newer/unknown state as `stopped` and `stale` (`production-source.ts:151-153`); that compatibility path is dropped, and clients require the current schema (95 §3).

**macOS `State`** (`src-tauri/macos_computers/store.rs:21-36`):

`preparing` · `copying` · `downloading` · `installing` · `setting-up` · `stopped` · `starting` · `running` · `stopping` · `failed`.

The allowed transitions are the table at `src-tauri/macos_computers.rs:187-213`:

- Start from `stopped`/`failed`;
- Stop from `running`;
- Force stop from `starting`/`running`/`stopping`;
- Delete from `stopped`/`failed`, which cancels while `preparing … setting-up`.

**DECIDED (95 A-12):** retain both platform enums; each inventory row has NEW `kind: "linux" | "macos"`, which discriminates its existing state enum ([95 Part 2](95-decisions.md#2-technical-defaults)).

### 1.6 `MacosComputer` and `MacosComputersState`

`src-tauri/macos_computers.rs:68-114`.

`MacosComputer` fields:

- `id`, `name`;
- `cpus: u64`, `memoryGiB: u64`, `diskGiB: u64`;
- `osVersion?`;
- `state`;
- `progress?: f64`, `detail?`;
- `displayOpen`;
- `installed`, `setupComplete`, `needsPersonalizing`;
- `checkpoints`, `checkpointOperation?`, `pendingRestore?`.

`MacosComputersState` fields:

- `supported`, `unsupportedReason?`;
- `computers`;
- `template?: {macosVersion, build, current}`;
- `minDiskGiB`.

`CreateRequest` is `{name, cpus, memoryGiB, diskGiB}` (`src-tauri/macos_computers/store.rs:138-145`). `Action` is `start` \| `stop` \| `force-stop` \| `delete` \| `setup` (`store.rs:38-47`). Templates, setup and display belong to the macOS section.

### 1.7 Other types used below

| Type | Source |
| --- | --- |
| `DeviceCapacity { logicalCpus, physicalMemoryBytes, maxMemoryGib }` | `src-tauri/runtime.rs:568-589` |
| `OperationQueue { running, waiting }`, `OperationEntry`, `OperationKind` | `src-tauri/runtime/operation_gate.rs:69-126`; UI `ui/features/application/model/operation-queue.ts:8-56` |
| `ComputerConfigurationProgress` (setup progress event) | `src-tauri/runtime.rs:3462-3494`; UI `ui/contracts/silo.ts:89-111` (the UI also allows a `revision` field Rust never writes, `silo.ts:96`) |
| `FailureReport { code, summary, exit_code, diagnostic, partial }` (internal, not serialized) | `src-tauri/runtime.rs:3739-3748` |
| Existing `ComputerIdentity { computer, name, email, apply }`; NEW API `ComputerIdentity { computerId, name, email, apply }`, replacing the name key and one-time launch conversion of saved keys via `runtime_migration` (justified by 95 A-11) | `src-tauri/runtime.rs:2028-2035`; [95 A-11](95-decisions.md#2-technical-defaults) |
| Log `Query`, `Entry`, `Page` | `src-tauri/runtime_logs.rs:7-59` |
| `StorageState`, `ReclaimEntry` | `src-tauri/runtime/storage.rs:35-75` |

---

## 2. Inventory and state

### computers.list
- **Kind:** query.
- **Platforms:** both. On supported Mac hosts where macOS computers cannot run (Intel Macs or an unsupported engine) the macOS part reports `supported:false` with `unsupportedReason` (`src-tauri/macos_computers.rs:651-658`).
- **The canonical read** of computers of both kinds, on this engine and on remote engines (80 §2 N1, N2). It replaces the names `macos.snapshot` (30) and `connections.devices.snapshot` (60 §1.7) as API methods; remote reads route through the local engine ([95 Part 2 A-3](95-decisions.md#2-technical-defaults)).
- **Status:** EXTENDED: existing Linux/macOS inventory reads below; NEW combined result and per-row `kind` (95 A-12), plus autonomous upkeep (95 A-26). Existing adapters:
  - tauri `read_application_state` (`src-tauri/runtime.rs:2663-2698`) and `read_macos_computers` (`src-tauri/macos_computers.rs:781-794`);
  - remote: tauri `device_snapshot` (`src-tauri/remote.rs:1467-1489`) and `remote_macos_snapshot` (`src-tauri/macos_remote.rs:131-138`);
  - bridge `runtime.snapshot` (`src-tauri/runtime/remote_ops.rs:6-12`) and `macos.snapshot` (`src-tauri/macos_remote.rs:68-70`). Both historical names are dropped; the wire method is `computers.list` (95 §3); their `remote.rs` registry entries are at `remote.rs:238` and `266`.
- **Params:**
  - `deviceId?: string`: another engine (§11).
  - `refreshRepositories?: bool`: rescan guest repositories instead of using the short-lived cache (`runtime.rs:2665-2666`, `2814-2821`).
- **Result:** `{ linux: ApplicationSource, macos: MacosComputersState }`, with NEW `kind: "linux"` on each Linux row and `kind: "macos"` on each macOS row; the discriminator preserves the existing platform state enums (justified by [95 A-12](95-decisions.md#2-technical-defaults)).
  - Both members are existing types (1.3, 1.6). The wrapper is NEW, required by one method per concept (00-brief.md "Shared domains").
- **Errors:**
  - `update_in_progress`: a configuration attempt is live, or device-wide work is running and still overlaps after a second attempt 100 ms later (`runtime.rs:2906-2967`; `BridgeError::updating`, `bridge_error.rs:46-51`).
  - `internal`: inventory mismatch, meaning the runtime lists a Silo-managed computer that metadata doesn't know (`runtime.rs:4402`, `4420-4422`).
  - `internal`: storage migration not ready (`runtime.rs:2668`; `ensure_ready_async` returns a `String`, `src-tauri/runtime_migration.rs:913-922`).
  - The macOS read also fails when called from a non-main window (`macos_computers.rs:755-761`); that check is UI-only and does not carry over. It can also fail when the data folder is missing (`macos_computers.rs:518-522`, `546-552`).
- **Semantics (Linux):**
  1. Reads `computers.json`.
  2. Lists runtime computers with label `silo.managed=true`.
  3. Inspects each computer (`runtime.rs:4407-4461`).
  4. Settles rows against the operation gate's per-computer generations (`runtime.rs:4463-4519`).
  5. Enriches with pushes, repositories and GitHub (`runtime.rs:2823-2872`).
- **Side effects of a read:**
  - today schedules due secret revocations (`runtime.rs:2671`); NEW engine timers also drive this work with no client connected (justified by [95 A-26](95-decisions.md#2-technical-defaults));
  - today starts expired-log cleanup in the background, at most hourly per stopped computer, as a hidden device operation (`runtime.rs:2676-2684`, `2700-2796`); NEW engine timers retain that limit and the one-pass guards (justified by [95 A-26](95-decisions.md#2-technical-defaults));
  - caches settled rows (`runtime.rs:4542-4583`).
  - **With `deviceId` (the controller side), each Linux read feeds that device's health**, as 60 §1.7 records for `device_snapshot`: success clears the health record (`poll_succeeded`); any failure except `update_in_progress` goes to `close_after_failed_poll`; `update_in_progress` is not counted (`src-tauri/remote.rs:1480-1484`). After 3 failures the controller closes the device's tunnels and viewers (§11).
- **Semantics (macOS):**
  - loads the registry, refreshes the template and latest build, and returns `snapshot()` (`macos_computers.rs:786-792`, `651-665`);
  - today macOS transitions happen under the registry lock (`macos_computers.rs:187-191`); NEW queue admission serializes them by stable id before taking the registry lock (justified by [95 A-31](95-decisions.md#2-technical-defaults); §6).
- **Sources:**
  - the UI calls both: `production-source.ts:986-1057` and `ui/desktop/macos-computers.ts:6`;
  - per-row merge rules: `production-source.ts:1027-1044`.

### computers.shell
- **Kind:** query.
- **Platforms:** both. Linux adapter exists; macOS platform support is NEW, justified by [95 A-19](95-decisions.md#1-owner-decisions). The macOS mechanism/result mapping is unsourced; Q13 / 80 B-34 must establish it.
- **Status:** EXTENDED: tauri `read_application_shell` (`src-tauri/runtime.rs:2877-2901`); NEW macOS recovery result and remote exposure (95 A-19/A-14; Q13).
- **Params:** `error: string`: the reason shown in `runtimeRepair.reason`, at most 1,024 chars (`runtime.rs:2896-2898`).
- **Result:** `ApplicationSource` with:
  - `computers: []`;
  - `runtimeRepair: {status:"unavailable", reason, recovery}`;
  - real `activities`, `secrets` and `github`.
- **Semantics:**
  - "The controller UI can remain usable when local computer inspection fails. This is never used for a remote owner's snapshot and never invents local computer states" (`runtime.rs:2874-2875`).
  - The UI calls it when the local read fails or is `update_in_progress` and remote devices are connected (`production-source.ts:953-975`).
  - **DECIDED (95 A-29):** retain this recovery read for clients showing remote computers while the local runtime is down ([95 Part 2](95-decisions.md#2-technical-defaults)).

- **Remote contract:** NEW `deviceId?` forwards through the local engine and SSH, justified by [95 A-3/A-14/A-19](95-decisions.md); existing Linux implementations are reused under canonical names; missing adapters require Q13. Historical bridge names are not accepted (95 §3).

### computers.configuration.read
- **Kind:** query.
- **Platforms:** both. Linux adapter exists; macOS platform support is NEW, justified by [95 A-19](95-decisions.md#1-owner-decisions). The macOS mechanism/result mapping is unsourced; Q13 / 80 B-34 must establish it.
- **Status:** EXTENDED: existing saved-configuration read below; NEW macOS configuration projection (95 A-19; Q13). Existing adapters:
  - tauri `read_computer_configuration` (`src-tauri/runtime.rs:2649-2661`);
  - bridge `runtime.configuration` (`src-tauri/runtime/remote_ops.rs:21-24`, `remote.rs:240`).
- **Params:** `deviceId?`.
- **Result:** `ComputerConfigurationRequest` (1.1).
- **Semantics:** reads saved metadata only, "This command does not infer or return a running/stopped state" (`runtime.rs:2655-2656`). The UI uses it to draw loading rows before live state arrives (`production-source.ts:2063-2075`).

- **Remote contract:** NEW `deviceId?` forwards through the local engine and SSH, justified by [95 A-3/A-14/A-19](95-decisions.md); existing Linux implementations are reused under canonical names; missing adapters require Q13. Historical bridge names are not accepted (95 §3).

### Health watch (engine behaviour; surfaced through `notifications.*` and the NEW event `computers.unexpectedChange`, §12.2)

`src-tauri/health_watch.rs`, installed by `notifications::install` (`src-tauri/notifications.rs:119-122`). There is no command.

- **What it detects:** state changes nobody asked for. A difference from the per-computer baseline is reported only when the gate generation for that computer is unchanged and the computer was idle around the reading (`health_watch.rs:1-6`, `91-138`).
- **Reading:**
  - `runtime::health_observations` runs the normal row read with a 5 s budget per runtime call (`runtime.rs:2969-3072`);
  - a reading is `Discarded` (metadata changed), `Unavailable`, or `Computers(Vec<ComputerReading{id,name,state,generation,settled}>)` (`health_watch.rs:29-45`);
  - `state` is `Running`/`Stopped`/`Starting`/`Failed`, or "Health or configuration check failed" when `attention` is set (`runtime.rs:3047-3057`).
- **Cadence:**
  - every 10 s while something runs, backing off with failures up to 5 min;
  - otherwise it waits for gate activity, with a 5 min fallback (`health_watch.rs:15-27`, `140-148`, `242-273`);
  - each running computer gets an exit waiter (`msb wait --timeout 600s`) that wakes the watch at once when it stops (`runtime.rs:3074-3097`, `health_watch.rs:207-240`).
- **Output:** notices in category `Changes`:
  - one per changed computer, or one grouped notice above 3 (`health_watch.rs:122-137`, `161-195`);
  - "health checks unavailable" after 2 failed reads, and "available again" afterwards (`health_watch.rs:62-89`).
- **macOS:**
  - not covered by this watch: it reads only the MicroSandbox runtime (`runtime.rs:3007-3031`);
  - macOS has its own 2 s machine watcher that moves states forward (`macos_computers.rs:53`, `2256-2300`) but sends no notices: the "Not covered yet" table gives "Status panel, tray, notifications, start with Silo" as "None" (docs/SiloUI-MACOS-COMPUTERS.md "Not covered yet").

---

## 3. Changing configuration

### computers.configuration.change
- **Kind:** job (05 §4.2 E). Today the command blocks until the change is applied and verified, and returns the new state; progress events are keyed by `requestId`.
- **Platforms:** Linux today. On macOS:
  - create and delete map to `computers.create` and `computers.delete`;
  - edit and reorder do not exist today ("Editing resources after creation: None. CPUs and memory are fixed at creation", docs/SiloUI-MACOS-COMPUTERS.md "Not covered yet").
  - NEW macOS CPU/memory edits use the existing row fields `cpus`, `memoryGiB`; `diskGiB` is fixed after creation (justified by [95 A-12](95-decisions.md#2-technical-defaults)). The exact macOS edit adapter and optimistic-check shape are unsourced; probe Q13 / 80 B-34 must settle them. Linux `expected: ComputerConfiguration` is not silently reused for macOS.
- **Hosts the desktop fields too:** 40's desktop changes (`desktop.startWithComputer`) are fields of `ComputerConfiguration` (1.2) and go through this method; there is no separate `computers.update` (80 §2 N3).
- **Status:** EXTENDED: existing configuration-change adapters below; NEW stopped-macOS CPU/memory editing (95 A-12/A-19), plus id-based retry target (95 A-11/§3). Existing adapters:
  - tauri `change_computer_configuration` (`src-tauri/runtime.rs:4317-4373`);
  - bridge `runtime.upsert` / `runtime.delete` for Upsert and Delete only (`src-tauri/runtime/remote_ops.rs:33-114`; §11). Their historical names are dropped; calls use `computers.configuration.change` (95 §3).
- **Params:**
  - `change: ComputerConfigurationChange` (`runtime.rs:442-472`), a tagged union on `kind`:
    - `{kind:"upsert", configuration: ComputerConfiguration, expected?: ComputerConfiguration|null}`: create when `expected` is null, else edit;
    - `{kind:"delete", computerId: string, expected: ComputerConfiguration}`;
    - `{kind:"reorder", order: string[], expectedOrder: string[]}`: permutations of ids;
    - `{kind:"batch", changes: ComputerConfigurationChange[]}`: applied in order to a draft; any rejection rejects all; nesting is refused (`runtime.rs:465-471`, `505-517`).
  - `requestId?: string`:
    - names this change's progress events and journal entries;
    - generated as a UUID when absent;
    - must be non-blank and at most 256 chars (`runtime.rs:4125-4131`).
  - NEW `retryComputerId?: string` replaces name-valued `retryComputer`, justified by 95 A-11: stable id of a computer whose verification to rerun even if its configuration is unchanged (`runtime.rs:5339-5349`, `5422-5428`).
- **Optimistic check (`expected`):**
  - `change_computer` requires the targeted computer to equal `expected`, ignoring `desktop.builtIn` (`runtime.rs:343-407`). Otherwise it rejects with:
    - `Stale` (changed);
    - `Missing` (deleted);
    - `WrongTarget` (id mismatch) (`runtime.rs:332-341`).
  - Reorder checks that the current order equals `expectedOrder` (`runtime.rs:409-440`).
  - Rejection texts: "This computer changed while your edit was waiting…", "This computer no longer exists.", "These computers changed while your edit was waiting…" (`runtime.rs:538-548`).
  - The UI derives the change set from the committed list it edited from (`ui/features/application/model/computer-change.ts:81-104`, `production-source.ts:1303-1345`).
- **Result:** `{jobId}` at once (`setup:<requestId>`, 05 §4.2 E). `operations.job.finished.result`: `ApplicationSource` after the change (`runtime.rs:4241-4242`), unchanged.
  - A failed refresh does not fail a finished change: rows come back `stale` with the reason (`runtime.rs:4599-4644`).
  - A client that missed `finished` reads the outcome with `activity.setup.read` (05 §4.2 E item 5).
- **Progress/events:** `operations.job.progress` with `source: "setup"`, `data` = today's `ComputerConfigurationProgress` with every field (05 §4.2 E item 4), sent only to the client that started the job, as today's `emit_to("main")`. Today's steps, all carried unchanged:
  - Before the gate (creation only): `silo://computer-configuration-progress` steps `computer-image-wait`, `chatgpt-app-wait`, `chatgpt-app-download` (with `downloadedBytes`/`totalBytes`) and `chatgpt-app-failed` (`runtime.rs:3562-3587`).
  - Under the gate, every event is appended to the setup journal and emitted to the main window (`runtime.rs:4172-4185`):
    - `setup-started`;
    - per computer `computer-removal` 0/1;
    - `computer-configuration` 0/1;
    - `computer-disk-preparation`, `computer-image-preparation` / `computer-image-import`, `computer-runtime-preparation`;
    - `desktop-installation` 0/1;
    - `computer-use-setup` / `computer-use-pending`;
    - `computer-settings`;
    - `computer-verification` 0/1;
    - the runtime's own image steps (`image-resolving` … `runtime-waiting`, emitted at `runtime.rs:1036-1059`, journal texts `4035-4042`);
    - then `setup-completed` or `setup-failed` with `failureCode`, `exitCode`, `diagnostic`, `partial` (`runtime.rs:4211-4239`).
  - Message texts: `runtime.rs:3496-3560`.
  - Warnings `host-memory-warning` and `activity-storage-warning` (`runtime.rs:4191-4196`, `3973-3980`).
  - The local command emits no `silo://application-state-changed`; it returns the new state. Over the bridge, `runtime.upsert`/`runtime.delete` emit it before the change, after each progress step and at the end (`remote_ops.rs:49`, `101`, `112`). In the API that hint is `computers.changed`.
  - Its gate entry (kind `computerConfiguration`) on `operations.queue.changed`, and `operations.job.finished` at the end.
- **Cancel:** `operations.cancel {jobId}` (05 §4.2 F). As today, only a waiting gate entry leaves the queue; the running change never opted in and answers `NotCancellable` (reaching the client as `internal`). The creation wait before the gate is not cancellable; `computers.creation.skipComputerUseWait` skips its ChatGPT part.
- **Errors:** in `operations.job.finished.error`. Strings today, i.e. `internal`. They come from:
  - the `expected` rejections above;
  - validation (1.1);
  - device ceilings (§10);
  - the edit rules below;
  - `Partial`: some changes were applied and kept; the message adds "Completed changes were kept; reload the computer list before retrying." (`runtime.rs:223-225`, `254-255`, `5450-5457`);
  - "Computer names must be unique." from the cross-kind reservation (`computer_names.rs:13`);
  - quitting (`runtime/shutdown.rs:50-59`).
- **Semantics:**
  1. **Creation waits first, outside the gate,** for the VM image import and (for built-in computer use) the ChatGPT for Linux download, "holding the device-wide gate for minutes would stall every lifecycle operation and Quit" (`runtime.rs:4335-4344`; `src-tauri/creation_inputs.rs:1-4`, `91-154`, `225-246`). Quit ends the wait (`creation_inputs.rs:112-114`, `147`).
  2. **Device-wide gate,** kind `ComputerConfiguration`, which records the ids being deleted so work on them can yield (`runtime.rs:4346-4348`; `operation_gate.rs:628-649`).
  3. **Fresh metadata is read under the gate,** the change applied, the new names reserved (`runtime.rs:4352-4359`).
  4. `apply_configuration_with_progress` (`runtime.rs:4133-4243`):
     - validates the request and ceilings;
     - applies desktop defaults;
     - prepares the recovery journal (`configuration-operation.json`, `src-tauri/runtime/configuration_recovery.rs:26-38`);
     - runs `apply_whole_configuration_with_progress` (`runtime.rs:5327-5458`): **removals first**, then creates or edits; each computer's metadata is written and the computer verified before the next one (`runtime.rs:5440-5445`).
  5. **On failure:** NEW retained notice per key for Fjord, with no engine OS notification (justified by 95 A-27), except for stale-edit rejections. Today native notice titles come from `runtime.rs:494-503,4305-4315`.
  6. **On success:** delivered notices of deleted computers are withdrawn (`runtime.rs:4365-4371`).
  - **Idempotency:**
    - a no-change submission is resolved client-side without a call (`production-source.ts:1320-1324`);
    - re-applying a committed configuration is a no-op unless `retryComputerId` identifies it (NEW, justified by 95 A-11), or a failed verification is pending for a computer in it (`runtime.rs:5422-5429`, `4157-4171`);
    - there is no server-side dedupe by `requestId`.
- **Sources:** UI caller `production-source.ts:1317-1350`.

#### Create, per kind
- **Linux create** (`create_computer_with_progress`, `runtime.rs:5541-5697`):
  - Preflight: the name must be absent from the runtime, and the runtime must support the GitHub and working-account protocols.
  - It prepares the guest image and runs `msb create … --no-start` with label `silo.managed=true`, `silo.machine-id=<id>` and the storage labels, `--net-strict=true` and the GitHub secret.
  - It checks the computer stayed stopped and verifies the guest tools.
  - It installs the desktop if set, records the computer-use approval, and finishes computer use or marks it pending.
  - A failed create cleans up (`runtime.rs:5648-5669`, `5809`).
- **macOS create:** `computers.create` below.

#### Edit rules (Linux)
`validate_computer_update` and `update_computer` (`runtime.rs:5473-5494`, `5909-6003`):

- **Name is fixed:** "Bundled MicroSandbox cannot rename computer…" (`runtime.rs:5484-5486`). The UI makes it read-only once created (`ui/features/computers/components/computer-editor.tsx:290`).
- **Disks are fixed:** "Storage disks cannot be resized in place" (`runtime.rs:5487-5493`); read-only in the UI (`computer-editor.tsx:307-308`).
- **The desktop can be added or toggled, never removed** (`runtime.rs:5477-5483`). A desktop-only change reconfigures without a stop (`runtime.rs:5917-5930`; `desktop.rs:82-92`).
- **CPU and memory changes:**
  - stop a running computer first, which must reach `Stopped`;
  - then `msb modify … --next-start` (`runtime.rs:5944-5988`);
  - the UI asks "Stop … and save? … The new settings apply when you start it again." (`computer-editor.tsx:332`);
  - a computer in any state other than Running/Stopped/Created is refused (`runtime.rs:5959-5963`).
- **Deletion requires a stopped (or Created/Crashed) computer,** or a pending-restore attempt (`runtime.rs:6018-6066`). It removes in order:
  - runtime;
  - network state;
  - metadata;
  - lifecycle intent;
  - secrets;
  - GitHub;
  - volumes;
  - checkpoint snapshots (`runtime.rs:5386-5415`).

#### Duplicate
UI-only composition, not an engine method. The UI copies a configuration with a new UUID and the next free name, then submits it as a create (`ui/features/onboarding/model/computer-configuration.ts:58-67`; `ui/features/computers/model/use-computer-editing.ts:180-186`).

In the API, a client calls `computers.create` with the copied fields. macOS has no Duplicate; it has Fork from a checkpoint (checkpoints section).

### computers.create
- **Kind:** job (05 §4.2 E).
- **Platforms:** both.
- **Status:** EXTENDED: existing Linux/macOS creation below; NEW macOS queue admission, “Waiting…” and Cancel before admission (95 A-31/§3). Existing adapters:
  - **Linux:** `change_computer_configuration` with `{kind:"upsert", expected:null}` (`runtime.rs:446-452`); bridge `runtime.upsert` with `expected:null`; tauri `remote_upsert_computer` (`src-tauri/remote.rs:1684-1721`).
  - **macOS:** tauri `create_macos_computer` (`src-tauri/macos_computers.rs:812-821`); bridge `macos.create` (`src-tauri/macos_remote.rs:71-76`), whose historical name is dropped; the wire method is `computers.create` with `kind: "macos"` (95 §3).
- **Params:** NEW wrapper over the two existing request types:
  - `{kind:"linux", configuration: ComputerConfiguration, requestId?}`
  - `{kind:"macos", request: CreateRequest}`
  - plus `deviceId?`.
- **Result:** at once (05 §4.2 E item 3):
  - Linux: `{jobId}` (`setup:<requestId>`). `operations.job.finished.result`: `ApplicationSource`, unchanged.
  - macOS: `{jobId}` (`job:<n>`) plus the new `MacosComputer` row in state `preparing`, as today's command returns it before creation continues in the background (`macos_computers.rs:978-1005`). Today's command returns nothing more at the end, so `operations.job.finished` carries no `result`; the outcome is the row's `state` in `computers.list` (05 §4.2 E item 5).
- **Progress:**
  - Linux: `operations.job.progress` with `source: "setup"`, as in `computers.configuration.change`.
  - macOS: `operations.job.progress` with `source: "macos"`, `data` = `{computerId, state, progress, detail, checkpointOperation}` of the row (05 §4.2 E item 4). Today these are the row's `state` (`preparing → downloading → installing → setting-up`, or `copying` from a template), `progress` and `detail`, pushed on `silo://macos-computers-changed` with every state change, progress at most once per second (`macos_computers.rs:50`, `52`, `667-669`, `706-725`). The macOS part of `computers.changed` keeps carrying the whole state.
- **Cancel:**
  - Linux: `operations.cancel {jobId}` (05 §4.2 F), with the rules of `computers.configuration.change`.
  - macOS: NEW waiting queue entries are cancellable (95 A-31); running create returns `NotCancellable` through `operations.cancel`, and existing `computers.delete` remains its supported cancellation path (05 §4.2 F).
- **Errors:**
  - Linux: as above.
  - macOS:
    - name, CPU, memory and disk bounds (`store.rs:162-196`): CPUs `2..=host`; memory `4..=host−4 GiB`; disk `max(32, template)..=1024` GiB;
    - "macOS computers need a Mac with Apple silicon." (`macos_computers.rs:51`);
    - quitting (`macos_computers.rs:819`).
- **Semantics:**
  - **Remote Linux create:** the controller then sets `computerUse.approval` on the new computer from its own setting (`remote.rs:1700-1716`).
  - **Linux "waits for the image and ChatGPT"** before the gate, as described above. The skip control is `computers.creation.skipComputerUseWait`.

### computers.delete
- **Kind:** job (05 §4.2 E).
- **Platforms:** both.
- **Status:** EXTENDED: existing Linux/macOS deletion below; NEW macOS queue admission, “Waiting…” and Cancel before admission (95 A-31/§3). Existing adapters:
  - **Linux:** `change_computer_configuration` `{kind:"delete"}`; bridge `runtime.delete` (`remote_ops.rs:33-114`); tauri `remote_delete_computer` (`remote.rs:1722-1746`).
  - **macOS:** `macos_computer_action` action `delete` (`macos_computers.rs:823-835`, `1714-1767`); bridge `macos.action` (historical bridge command; dropped by 95 §3).
- **Params:** `ComputerRef` and, for Linux, `expected: ComputerConfiguration`, which is required (`runtime.rs:453-458`), and `requestId?` as in `computers.configuration.change` (it is the same command).
- **Result:** `{jobId}` at once: Linux `setup:<requestId>`, macOS `job:<n>` (05 §4.2 E). `operations.job.finished.result`, unchanged from today's return:
  - Linux: `ApplicationSource`;
  - macOS: `null` locally (the tauri command returns `()`), the full `MacosComputersState` remotely (`macos_remote.rs:77-83`).
- **Progress:** Linux `operations.job.progress` with `source: "setup"` (`computer-removal` steps, as in `computers.configuration.change`); macOS `source: "macos"`.
- **Cancel:** `operations.cancel {jobId}` (05 §4.2 F): Linux as in `computers.configuration.change`; macOS waiting entries are cancellable; running work retains `NotCancellable` (NEW, justified by 95 A-31).
- **Semantics:**
  - **Linux:** see the deletion rules above.
  - **macOS:**
    - Delete of a computer being created cancels and removes it (`DeleteMode::Cancel`, `store.rs:239-251`);
    - a stopped or failed computer is removed from disk;
    - starting, running or stopping is refused ("Stop the computer first.");
    - today refused while a checkpoint operation runs (`macos_computers.rs:1723-1725`); NEW queue admission waits as “Waiting…” with Cancel, then rechecks deletion preconditions (95 A-31/§3).
  - **Linux (local and remote):** delivered notices for the computer are withdrawn (`runtime.rs:4367-4370`; remote: `remote.rs:1741-1744`). macOS delete withdraws none; macOS computers have no notifications (docs/SiloUI-MACOS-COMPUTERS.md "Not covered yet").

### computers.configuration.retry
- **Kind:** job (05 §4.2 E).
- **Platforms:** both. Linux adapter exists; macOS platform support is NEW, justified by [95 A-19](95-decisions.md#1-owner-decisions). The macOS mechanism/result mapping is unsourced; Q13 / 80 B-34 must establish it.
- **Status:** EXTENDED: tauri `retry_computer_configuration` (`src-tauri/runtime.rs:4253-4303`); NEW remote recovery and shared macOS projection (95 A-14/A-19; macOS setup itself is `macos.setup.retry`).
- **Params:** `requestId?`, NEW `retryComputerId?` (as in `computers.configuration.change`; 95 A-11/§3); the historical name-valued `retryComputer` parameter is retired.
- **Result:** `{jobId}` at once (`setup:<requestId>`, 05 §4.2 E). `operations.job.finished.result`: `ApplicationSource`, unchanged.
- **Progress/cancel:** as in `computers.configuration.change`: `operations.job.progress` with `source: "setup"`; `operations.cancel {jobId}` (05 §4.2 F).
- **Semantics:**
  - "Resume a failed computer setup or verification without the UI resending a whole list" (`runtime.rs:4245-4251`).
  - It re-applies the request saved in the recovery journal against current state, or re-verifies the committed inventory when nothing is pending (`runtime.rs:4282-4287`).
  - Concurrent changes since the failure are rejected by recovery reconciliation.
  - Same creation wait, device gate (kind `ComputerConfiguration`, label "Retrying computer settings") and name reservation as a change (`runtime.rs:4267-4294`).
  - **macOS equivalent:** Retry setup (`macos_computer_action` `setup`), which is `macos.setup.retry`, owned by the macOS section (80 §2 N1).

- **Remote contract:** NEW `deviceId?` forwards through the local engine and SSH, justified by [95 A-3/A-14/A-19](95-decisions.md); existing Linux implementations are reused under canonical names; missing adapters require Q13. Historical bridge names are not accepted (95 §3).

### computers.creation.skipComputerUseWait
- **Kind:** command.
- **Platforms:** both. Linux adapter exists; macOS platform support is NEW, justified by [95 A-19](95-decisions.md#1-owner-decisions). The macOS mechanism/result mapping is unsourced; Q13 / 80 B-34 must establish it.
- **Status:** EXTENDED: tauri `skip_computer_use_wait` (`src-tauri/runtime.rs:3615-3619`); NEW remote exposure and macOS creation-wait adapter (95 A-14/A-19; Q13). No bridge method exists today; the canonical name replaces 40’s former proposal (80 §2 N6).
- **Params:** `requestId: string`: the creation's request id.
- **Result:** none.
- **Semantics:**
  - "Finish without computer use" from the creation toast while it waits for ChatGPT for Linux.
  - Marks the request skipped (`src-tauri/creation_inputs.rs:169-174`). The waiting creation then records its new computers to skip computer-use setup (`creation_inputs.rs:115-117`, `239-244`), and their creation consumes that mark (`runtime.rs:5682-5695`).
  - Unknown ids are accepted silently.
  - UI caller: `ui/desktop/computer-use-bridge.ts:33`.

---

- **Remote contract:** NEW `deviceId?` forwards through the local engine and SSH, justified by [95 A-3/A-14/A-19](95-decisions.md); existing Linux implementations are reused under canonical names; missing adapters require Q13. Historical bridge names are not accepted (95 §3).

## 4. Lifecycle

### 4.1 Shared lifecycle semantics (Linux)

Every Linux lifecycle action goes through `computer_action` (`src-tauri/runtime.rs:3255-3418`), or `runtime.action` for remote calls (`src-tauri/runtime/remote_ops.rs:116-237`). Both paths share the following.

- **Gate:**
  - per-computer scope keyed by the stable id;
  - kind `Lifecycle`;
  - dedupe key `computer:<id>:<action>`: a double-click returns `already_queued`, which the command turns into success with no error row or notification (`runtime.rs:3287-3316`, `3438-3448`; `operation_gate.rs:741-743`).
- **Cancellable while running:** start and restart only (`runtime.rs:3301`); stop is not, and its runtime call is wrapped `uncancellable` (`src-tauri/runtime/lifecycle_recovery.rs:195-207`).
- **Expected duration** (flags slow work; nothing is killed): start/restart 180 s, stop 120 s, other 600 s (`runtime.rs:3294-3300`).
- **Automatic retry:**
  - start, stop and restart retry transient failures (`TimedOut`, `Launch`) after 2 s and 5 s;
  - the gate is re-acquired per attempt and one cancel token spans the attempts;
  - a Quit that began meanwhile cancels the sequence (`runtime.rs:3110-3253`).
  - `dismiss-error` runs once (`runtime.rs:3356-3370`).
- **Re-read under the gate:** the computer is re-found by id, so a rename or delete while waiting is caught (`runtime.rs:3325-3332`).
- **Device resources** are re-measured, and the computer's CPU and memory ceilings are validated against them before start (`runtime.rs:3336`; `lifecycle_recovery.rs:179`, `317-319`).
- **Pending checkpoint restore:**
  - an explicit Start activates it;
  - stop and restart are refused with the explicit-start message (`runtime.rs:5231-5285`).
- **Notifications:** NEW retain the latest lifecycle notice per key for Fjord with no engine OS notification (justified by 95 A-27); today success (when slow), cancellation and failure notices are `runtime.rs:3385-3417`; owned by `notifications.*`.
- **Return today:** the full `ApplicationSource` after the action. Other rows are captured as they are, and the UI uses only the target row (`production-source.ts:1219-1225`).

**In the API (80 §2 N11; 05 §4.2 E/F).** Start, stop and restart become Kind `job`:
- the method returns `{jobId}` at once, `job:<n>` (engine-assigned; no id exists today);
- today's return value, `ApplicationSource`, moves unchanged to `operations.job.finished.result`;
- the steps are `operations.job.progress` with `source: "lifecycle"` (§4.4); the job's current gate entry (kind `lifecycle`) is on `operations.queue.changed`, one entry per attempt, all linked by `OperationEntry.jobId` (§6);
- cancel is `operations.cancel {jobId}`, routed to the current gate entry with today's cancellability: start and restart opt in, stop does not; between retry attempts the shared token stops the next attempt (05 §4.2 F);
- **a duplicate is not an error, as today:** when the dedupe key finds the same action already waiting, the job ends with `operations.job.finished` carrying the current `ApplicationSource` and no `error`, as today's command "returns current state without an error row or notification" (`runtime.rs:3438-3448`).
- `computers.dismissError` stays a command: it runs once and returns at once.

**macOS lifecycle:**

- `macos_computer_action` (`src-tauri/macos_computers.rs:823-835`, `1325-1334`).
- Start and Setup are refused while quitting (`macos_computers.rs:831-833`).
- Today there is no operation gate, dedupe key, retry or cancel: transitions are checked under the registry lock (`macos_computers.rs:1351-1425`, `1662-1712`; table at `187-213`). NEW admission waits in the shared queue, shown as “Waiting…” with Cancel; queue contention does not return the historical checkpoint-busy refusal. After admission the adapter re-reads state and checks genuine preconditions; running work advertises only supported cancellation (justified by 95 A-31 and §3; §6).
- Results are `()`. State arrives on `silo://macos-computers-changed`.
- In the API, macOS start and stop are Kind `job` (`job:<n>`): progress is `operations.job.progress` with `source: "macos"`, the result is today's (`null` locally, `MacosComputersState` remotely), and queued work accepts `operations.cancel`; running work without safe cancellation answers `NotCancellable` (95 A-31/§3; 05 §4.2 E/F). `computers.forceStop` stays a command.

### computers.start
- **Kind:** job (05 §4.2 E; 80 §2 N11). Long: today the Linux command returns after the computer is running and verified.
- **Platforms:** both.
- **Status:** EXTENDED: existing Linux/macOS start below; NEW macOS queue admission, “Waiting…” and Cancel before admission (95 A-31/§3). Existing adapters:
  - **Linux:** tauri `computer_action` `action="start"` (`runtime.rs:3255`); bridge `runtime.action` (`remote_ops.rs:29-31`, `remote.rs:241`); tauri `remote_computer_action` (`remote.rs:1578-1632`).
  - **macOS:** `macos_computer_action` `start`; bridge `macos.action` (historical bridge command; dropped by 95 §3); tauri `remote_macos_action` (`src-tauri/macos_remote.rs:155-166`).
- **Params:** `ComputerRef`.
- **Result:** `{jobId}` at once (`job:<n>`, 05 §4.2 E). `operations.job.finished.result`, unchanged from today's return:
  - Linux: `ApplicationSource`; a duplicate request also ends with it and no error (§4.1);
  - macOS: none locally, `MacosComputersState` remotely.
- **Progress:**
  - **Linux:** `operations.job.progress` with `source: "lifecycle"` (§4.4; today `silo://lifecycle-progress`), then `computers.changed` (today `silo://application-state-changed`).
  - **macOS:** `operations.job.progress` with `source: "macos"`: `starting` → `running`, or `failed`/`stopped`, today via `silo://macos-computers-changed` (`macos_computers.rs:1383-1424`).
- **Cancel:** `operations.cancel {jobId}` (05 §4.2 F). Linux start opts in (`runtime.rs:3301`); running macOS work answers `NotCancellable`; queued macOS work is cancellable (NEW, justified by 95 A-31).
- **Errors:**
  - **Linux:**
    - "This computer no longer exists.";
    - device-ceiling errors (§10);
    - "<name> is not ready for this action…" (`lifecycle_recovery.rs:182-187`);
    - "…did not reach the Running state. Retry to continue the saved action." (`lifecycle_recovery.rs:228-236`);
    - `cancelled`;
    - `busy`;
    - quitting.
  - **macOS** (`store.rs:253-270`; `macos_computers.rs:1363-1372`):
    - "Installation was interrupted…";
    - needs personalizing;
    - already running / still stopping / still being installed or set up;
    - historical checkpoint-busy refusal: queue contention now waits with Cancel (95 A-31/§3);
    - an unfinished restore;
    - "Macs run at most two macOS guests at once" (docs/SiloUI-MACOS-COMPUTERS.md "Behaviour", Start and stop).
- **Semantics (Linux):**
  1. A durable intent is saved before `msb start` (§4.5).
  2. After boot: network and SSH access are reconciled (`runtime.rs:1145-1149`).
  3. The working account is checked and, for a new computer whose record is missing, prepared; layout conversion runs only in the launch upgrade (95 §3) (§13, "Engine behaviour: working-account preparation after each boot"). On failure the computer is stopped again "so a running Computer always has its account" (`src-tauri/src/runtime.rs:1248-1271`).
  4. Built-in computer use is installed in the background (`runtime.rs:1267-1268`).
  5. Automatic storage reclamation may run after start (§9).

### computers.stop
- **Kind:** job (05 §4.2 E; 80 §2 N11).
- **Platforms:** both.
- **Status:** EXTENDED: tauri `computer_action` action=`stop` (`src-tauri/runtime.rs:3256-3418`), bridge `runtime.action` (`src-tauri/runtime/remote_ops.rs:116-237`), tauri `macos_computer_action` action=`stop` (`src-tauri/macos_computers.rs:824-835`), bridge `macos.action` (`src-tauri/macos_remote.rs:77-83`); NEW macOS queue admission, “Waiting…” and Cancel before admission (95 A-31/§3).
- **Params:** `ComputerRef`.
- **Result:** as for start: `{jobId}` (`job:<n>`); `operations.job.finished.result` is today's return.
- **Progress:** Linux stop emits no lifecycle steps today (§4.4), so it reports through its gate entry on `operations.queue.changed` and `computers.changed`; macOS `operations.job.progress` with `source: "macos"`.
- **Cancel:** `operations.cancel {jobId}` (05 §4.2 F) answers `NotCancellable` once it runs: Linux stop does not opt in, macOS has no cancel. A waiting stop on either platform leaves the queue (NEW macOS admission, justified by 95 A-31).
- **Errors:**
  - **Linux:** "<name> did not stop in time. Check its status and retry." (not retried; `lifecycle_recovery.rs:217-226`).
  - **macOS:** "This computer isn't running." (`macos_computers.rs:1669-1674`); the historical checkpoint-busy refusal becomes queue waiting with Cancel (95 A-31/§3).
- **Semantics:**
  - **Linux:**
    - not cancellable;
    - automatic reclamation runs before the stop (§9; `lifecycle_recovery.rs:191-193`);
    - secrets are notified when the computer stops (`lifecycle_recovery.rs:214-216`).
  - **macOS:**
    - shuts the guest down over SSH (15 s) once setup has made the account;
    - before that, presses the virtual power button, which asks in-guest (`macos_computers.rs:1575-1660`, `1683-1700`);
    - a guest ignoring the request for 20 s returns to `running` (`macos_computers.rs:54-55`, `209-213`).

### computers.restart
- **Kind:** job (05 §4.2 E; 80 §2 N11).
- **Platforms:** both. Linux adapter exists; macOS platform support is NEW, justified by [95 A-19](95-decisions.md#1-owner-decisions). The macOS mechanism/result mapping is unsourced; Q13 / 80 B-34 must establish it.
- **Status:** EXTENDED: tauri `computer_action` action=`restart` (`src-tauri/runtime.rs:3256-3418`), bridge `runtime.action` (`src-tauri/runtime/remote_ops.rs:116-237`); NEW macOS restart adapter (95 A-19; Q13).
- **Params:** `ComputerRef`.
- **Result:** `{jobId}` at once (`job:<n>`). `operations.job.finished.result`: `ApplicationSource`, unchanged.
- **Progress:** `operations.job.progress` with `source: "lifecycle"` (§4.4).
- **Cancel:** `operations.cancel {jobId}` (05 §4.2 F); restart opts in, with the limits below.
- **Semantics:**
  - one intent goes StopPending → StartPending, saved between phases;
  - a cancel is honoured between the stop and start steps, never during stop (`lifecycle_recovery.rs:157-175`, `195-198`);
  - a crashed computer restarts without a stop (`lifecycle_recovery.rs:135-140`, `164-175`).

- **Remote contract:** NEW `deviceId?` forwards through the local engine and SSH, justified by [95 A-3/A-14/A-19](95-decisions.md); existing Linux implementations are reused under canonical names; missing adapters require Q13. Historical bridge names are not accepted (95 §3).

### computers.forceStop
- **Kind:** command.
- **Platforms:** macOS. On Linux it is refused: locally "Unknown computer action 'force-stop'…" (`lifecycle_recovery.rs:279-283`), remotely "Unsupported remote lifecycle action." (`remote_ops.rs:160-165`); Linux has no force stop.
- **Status:** EXTENDED: tauri `macos_computer_action` action=`force-stop` (`src-tauri/macos_computers.rs:824-835,1703-1712`), bridge `macos.action` (`src-tauri/macos_remote.rs:77-83`); NEW macOS queue admission, “Waiting…” and Cancel before admission (95 A-31/§3).
- **Params:** `ComputerRef`.
- **Result:** none, or `MacosComputersState` remotely.
- **Semantics:**
  - turns the machine off immediately;
  - allowed from `starting`/`running`/`stopping` (`macos_computers.rs:194-199`);
  - the engine call is owned by the macOS section. The name is `computers.forceStop`, refused on Linux (resolved: 80 §2 N19).

### computers.dismissError
- **Kind:** command.
- **Platforms:** both. Linux adapter exists; macOS platform support is NEW, justified by [95 A-19](95-decisions.md#1-owner-decisions). The macOS mechanism/result mapping is unsourced; Q13 / 80 B-34 must establish it.
- **Status:** EXTENDED: tauri `computer_action` action=`dismiss-error` (`src-tauri/runtime.rs:3256-3418,5278-5280`), bridge `runtime.action` (`src-tauri/runtime/remote_ops.rs:160-165`); NEW macOS error-dismissal projection (95 A-19; Q13).
- **Params:** `ComputerRef`.
- **Result:** `ApplicationSource`.
- **Semantics:** see §4.5. Runs once, without retry (`runtime.rs:3356-3370`).

- **Remote contract:** NEW `deviceId?` forwards through the local engine and SSH, justified by [95 A-3/A-14/A-19](95-decisions.md); existing Linux implementations are reused under canonical names; missing adapters require Q13. Historical bridge names are not accepted (95 §3).

### computer_action `open-terminal` / `open-editor`: UI-only launchers

`computer_action` short-circuits these two before any gate (`runtime.rs:3263-3276`):

- **Terminal** (`src-tauri/terminal.rs:19-48`, `49-74`, `75-103`):
  - checks the computer is a configured local computer and is `Running` ("Start <name> first.");
  - builds an `msb exec <name> --user <silo> --no-start --workdir /workspace --tty` command line;
  - opens the user's chosen terminal app on this device;
  - **remote:** writes a private SSH config through the owner and opens `ssh -F … -t <alias>` locally (`terminal.rs:76-93`).
- **Editor** (`src-tauri/editor.rs:32-104`):
  - validates the folder inside the guest (`test -d`);
  - writes an SSH config whose `ProxyCommand` runs the bundled `msb ssh serve <name> --stdio --no-start` on the Mac host (`editor.rs:807-839`). The historical AppImage `--msb-ssh-serve` branch (`editor.rs:862-864`) is retired by 95 §3; it is not an engine launch path;
  - probes SSH, then launches the user's editor with Remote SSH.

Launching an application on the user's screen is drawing UI and is excluded (00-brief.md "The API must expose everything Silo can do today except drawing UI"); docs/SiloUI-CONNECTIONS.md "User behavior" item 6 ("Terminals and editors launch on the controlling device").

The engine-side parts (SSH alias and config, transport, guest path check) belong to 50: `guest.sshAlias.ensure` (with its optional `path` check) and `terminal.command` (80 §2 N10). For macOS computers, the "Not covered yet" table gives "Terminal, editor, Files, network ports, GitHub, secrets, working account" as "None" (docs/SiloUI-MACOS-COMPUTERS.md "Not covered yet").

### 4.2 Timeouts

| What | Value | Source |
| --- | --- | --- |
| Runtime read (`list`, `inspect`) | 10 s | `runtime.rs:44` |
| Runtime mutation (`create`, `start`, `modify`) | 180 s | `runtime.rs:45` |
| Runtime `stop`, `remove` | 45 s | `runtime.rs:46` |
| Lifecycle expected duration (UI "slow" flag) | start/restart 180 s, stop 120 s, other 600 s | `runtime.rs:3294-3300` |
| Auto-retry delays | 2 s, 5 s | `runtime.rs:3111` |
| Waiting for a transitional state to settle | 180 s | `lifecycle_recovery.rs:122-129` |
| Identity work per computer (expected) | 600 s | `runtime.rs:2068` |
| Health read per runtime call | 5 s | `runtime.rs:2970` |
| Exit wait | 10 min | `runtime.rs:3076` |
| Cancel grace after admission | 250 ms | `operation_gate.rs:506` |
| Remote request window | 600 s; 2,100 s for creates that may get a desktop, the `desktop.action` updates `update-streamer`/`setup-lcu`/`setup-computer-use`, and `computerUse.approval`; checkpoints 2 × (restore + 60 s) | `remote.rs:981-1011` |
| Remote queued start deadline | half the remaining window (`startWithinMs`) | `remote.rs:1321-1322` |
| macOS SSH shutdown (Stop) | 15 s | `macos_computers.rs:1581` |
| macOS Quit: graceful / SSH / forced | 60 s / 8 s / 8 s | `macos_computers.rs:56-61` |

### 4.3 Lifecycle intent journals (Linux)

Directory: `lifecycle-operations/<sha256(computerId)>.json` beside `computers.json` (`src-tauri/runtime/lifecycle_recovery.rs:24-29`).

An `Intent` holds (`lifecycle_recovery.rs:5-20`):

- `version` (1);
- `computer_id`, `name`;
- `action` (`start`/`stop`/`restart`);
- `phase` (`stop-pending`/`start-pending`);
- the activity `event`.

Behaviour:

- **Written and synced before any runtime mutation** (`lifecycle_recovery.rs:30-49`, `316-321`).
- **Resumed when an explicit action repeats.** "Only an intact intent for this exact action is resumed"; a different action supersedes the saved one and settles its activity as replaced (`lifecycle_recovery.rs:285-337`).
- **Retired on success or user cancel,** so launch never resumes an abandoned action (`lifecycle_recovery.rs:252-266`). A failed start keeps its intent for Retry.
- **At launch,** `lifecycle_recovery::recover` settles every saved action under a device gate labelled "Resuming computer actions" (`lifecycle_recovery.rs:442-523`):
  - resumed or unreadable **stops** are added to `keep_stopped`, which overrides start-at-launch;
  - per-action failures are listed without blocking the rest.
- **Before an update,** intents for computers not in the resume set are retired (`lifecycle_recovery.rs:391-430`).

A related durable record is the configuration journal `configuration-operation.json { version, previous, request }` (`src-tauri/runtime/configuration_recovery.rs:26-38`). It is recovered at launch by `configuration_recovery::recover` (`startup.rs:186-206`). While an attempt is live it blocks snapshots with `update_in_progress` (`configuration_recovery.rs:580-596`).

macOS keeps no intent journal. A computer created before a crash shows the interruption on the next launch (`macos_computers.rs:993-994`; `store.rs:18-19`).

### 4.4 `silo://lifecycle-progress`

- **Payload:** `{computerId, action, step}`, emitted while the gate is held (`runtime.rs:3340-3351`).
- **Steps** (`LifecycleStep`, `runtime.rs:1273-1292`):
  - `boot`: before `msb start`;
  - `network`: the computer is up; ports and SSH are being connected;
  - `account`: the working account is being checked.
- **Emit sites:**
  - `runtime.rs:1142-1149`: start, restart and boot (the only production site; `runtime.rs:7151` is a test).
- On `network`, the engine also sends `silo://application-state-changed` "so the row leaves 'stopped' as soon as the computer is up" (`runtime.rs:3337-3349`).
- **UI:** shows "Starting the computer", "Connecting the network", "Checking the computer account" (`ui/features/application/model/lifecycle-progress.ts:1-20`, `production-source.ts:1093-1098`).
- **Gaps:**
  - The sink is installed only by the local `computer_action` (`runtime.rs:3352-3354`).
  - Remote actions (`remote_ops.rs:208-221`) and launch starts (`runtime.rs:5131-5132`) emit no steps.
  - macOS emits none; its progress is the row's `state`/`detail` (`operations.job.progress` with `source: "macos"` in the API).
- **In this API:** the steps are `operations.job.progress` with `source: "lifecycle"`, `data` = `{computerId, action, step}` unchanged, broadcast as today, keyed by the lifecycle job's `jobId` (05 §4.2 E item 4). There is no `computers.lifecycleProgress` event. The refresh sent on `network` is `computers.changed`.
- **Proposal kept from this section:** also emit the steps for remote and launch starts, which have none today (gaps above).

### 4.5 Crash acknowledgement / Dismiss (Linux)

`src-tauri/runtime/crash_acknowledgement.rs`. Behaviour per docs/SiloUI-CONNECTIONS.md "Close and Quit" ("Dismiss on a crashed computer acknowledges that crash…").

1. **Check:** verifies managed status and id label, that the status is `Crashed`, and a fingerprint `[id, name, updated_at]` (`crash_acknowledgement.rs:25-40`, `50-76`).
2. **Clean up:** removes a pending failed intent (`lifecycle_recovery.rs:340-360`).
3. **Record:** writes `acknowledged-crashes/<sha256(id)>.json` atomically (`crash_acknowledgement.rs:16-24`, `77-91`).
4. **Activity:** marks the latest lifecycle failure as dismissed (`runtime_activity.rs:283-300`).
5. **Effect:** an acknowledged crash reads as `stopped` (`runtime.rs:4983-4987`).
6. **Invalidation:** a later runtime timestamp or any start, stop or restart clears the acknowledgement (timestamp in the fingerprint: `crash_acknowledgement.rs:38-48`; explicit actions: `crash_acknowledgement.rs:94-103`, `runtime.rs:5281-5283`).

Dismiss never starts the computer, deletes data or erases history (docs/SiloUI-CONNECTIONS.md "Close and Quit").

### 4.6 Start computers at launch

**EXISTS for Linux.** `startup::install` runs once from native setup (`src-tauri/startup.rs:152-268`; `src-tauri/main.rs:345`), in this order:

1. Storage-migration check and backup recovery (`startup.rs:161-176`).
2. Image-cache repair and preparation start (`startup.rs:177-185`).
3. Configuration recovery; a failure stops here (`startup.rs:186-206`).
4. Lifecycle recovery (`startup.rs:207-226`).
5. NEW update recovery resumes the saved pre-update running set before launch selection; ordinary reboot from disk is not successful save/resume (justified by [95 A-6](95-decisions.md#1-owner-decisions); 05 §6). Today recovery restarts the pre-update set and skips launch selection (`startup.rs:227-234`; `src-tauri/runtime/update_recovery.rs:1-2`); the state-save integration is a probe in 05.
6. Start the selected computers one by one through `runtime::start_at_launch`, which takes the computer's lifecycle lane with the same label, key and cancellability as a user Start (`runtime.rs:5116-5186`).

Further rules:

- **Selection:** settings `startComputersAtLaunch` and `startupComputerIds` (`ui/features/preferences/model/settings.ts:7-8`, `41-42`; `src-tauri/settings.rs:251`, `274`), only after onboarding is complete (`startup.rs:18-37`). The historical no-list fallback to `dev`/first computer (`startup.rs:61-85`) is retired; any required settings normalization runs once at launch through `runtime_migration`, never in normal reads/selection (95 §3).
- **Explicit stops win:** recovered explicit stops are removed from the selection (`startup.rs:39-46`, `86`).
- **Not started at launch:** a fork or restore that waits for its explicit first Start (`runtime.rs:5188-5195`, `5207-5209`).
- **Failures:** notified, and shown as a dialog in the main window (`startup.rs:247-265`).
- **Historical combined-app shutdown:** cancels startup and waits for the start in progress (`startup.rs:270-287`; `settings.rs:852-862`). Client Quit uses §4.7; Keep running and a Fjord crash/update leave engine launch work running (95 A-2).

**Gap: macOS computers are excluded.**

- `settings_for_launch` keeps only ids present in the Linux `computers.json` (`startup.rs:87-101`).
- `start_at_launch_with` errors "A computer selected for launch no longer exists" for any other id (`runtime.rs:5203-5205`).
- The UI offers local rows from the Linux source (`ui/features/application/pages/general-page.tsx:96-110`; `ui/features/application/model/startup-computers.ts:4-6`).
- Silo documents it: the "Not covered yet" table gives "Status panel, tray, notifications, start with Silo" as "None" (docs/SiloUI-MACOS-COMPUTERS.md "Not covered yet").
- → EXTENDED `computers.launch` (§12.1): NEW macOS selected starts and observable launch outcome. 30's `macos.startAtLaunch` is the same gap; its name is dropped for `computers.launch` (80 §2 N19).

### 4.7 Client Quit

**DECIDED (95 A-2):** when computers run, Fjord asks “Quit Fjord? 2 computers are running: dev, linux-1.” and offers **Cancel / Keep running / Stop and quit** ([95 Part 1](95-decisions.md#1-owner-decisions)). The client reads `computers.list` for running ids/names; Cancel leaves it connected, Keep running disconnects only that client, and Stop and quit calls `computers.stop` for the selected running computers and waits for outcomes before disconnecting (05 §6; `runtime/shutdown.rs:96-129`, `macos_computers.rs:1575-1700`). A Fjord update or crash never requests computer stop. Engine updates separately save and resume running computers (95 A-6; 05 §6).

The following is the existing combined app shutdown implementation, retained as a source for explicit engine shutdown rather than the client Quit policy:

- **Entry points:**
  - tauri `quit_app` (`src-tauri/status_panel.rs:177-179`) → `settings::request_quit`;
  - the exit request → `begin_exit` (`src-tauri/settings.rs:937-971`).
- **Sequence:**
  1. Shutdown stops admission (`runtime/shutdown.rs:13-20`, `50-59`), and `begin_exit` emits `silo://shutdown-state-changed true` (`settings.rs:959-960`).
  2. After the frontend flush, `finish_exit` calls `stop_local_computers` (`settings.rs:879-918`).
  3. `shutdown::stop_local_computers` (`runtime/shutdown.rs:96-129`):
     - cancels every waiting operation and takes the device gate with kind `Shutdown` (`shutdown.rs:131-154`);
     - closes SSH access and viewers;
     - stops **macOS** computers (`macos_computers::stop_all`: graceful SSH or framework stop within the deadline, then forced; disk images detached; `macos_computers.rs:2424-2555`);
     - stops every present Linux computer in parallel through `lifecycle_recovery::perform("stop")`, relabelling the queue entry "Stopping <name> (i of n)" (`shutdown.rs:156-291`).
- **Failure:** a failed stop keeps the app open with an error and does not restart stopped computers (`settings.rs:890-893`, `920-935`).
- **Scope:**
  - computers on other devices are never stopped (docs/SiloUI-CONNECTIONS.md "Close and Quit");
  - logout, shutdown and SIGTERM use a bounded deadline and never cancel the exit (`settings.rs:981-1017`, `1026-1041`).

Q4 is settled by 95 A-2: client Quit follows Cancel / Keep running / Stop and quit; the source shutdown sequence above applies only to explicit engine shutdown (05 §6).

---

## 5. Identities

### computers.identities.verify
- **Kind:** query.
- **Platforms:** both. Linux adapter exists; macOS platform support is NEW, justified by [95 A-19](95-decisions.md#1-owner-decisions). The macOS mechanism/result mapping is unsourced; Q13 / 80 B-34 must establish it.
- **Status:** EXTENDED: tauri `verify_computer_identities` (`src-tauri/runtime.rs:2038-2051`); NEW `computerId` keys (95 A-11/§3), remote exposure and macOS Git identity checking (95 A-14/A-19; Q13).
- **Params:** `identities: ComputerIdentity[]`:
  - NEW `computerId` replaces the name-valued `computer` field; convert stored name keys once at launch via `runtime_migration` (justified by [95 A-11](95-decisions.md#2-technical-defaults));
  - `name` and `email` are Git values;
  - `apply` says whether this identity should be applied (`runtime.rs:2028-2035`).
- **Result:** `bool`: every requested identity is already applied.
- **Semantics:**
  - Never boots a computer: a stopped computer counts as `false`; a running one is checked with `exec --no-start` (`runtime.rs:2088-2145`, `2320-2338`).
  - Each computer is checked in its own cancellable lane (`runtime.rs:2061-2070`).
  - An empty list is true only when no computers exist (`runtime.rs:2101-2103`).
  - More than 64 entries → `false` (`runtime.rs:2097-2099`, `MAX_COMPUTER_COUNT` at `runtime.rs:49`).

- **Remote contract:** NEW `deviceId?` forwards through the local engine and SSH, justified by [95 A-3/A-14/A-19](95-decisions.md); existing Linux implementations are reused under canonical names; missing adapters require Q13. Historical bridge names are not accepted (95 §3).

### computers.identities.configure
- **Kind:** job (per-computer lanes; 05 §4.2 E).
- **Platforms:** both. Linux adapter exists; macOS platform support is NEW, justified by [95 A-19](95-decisions.md#1-owner-decisions). The macOS mechanism/result mapping is unsourced; Q13 / 80 B-34 must establish it.
- **Status:** EXTENDED: tauri `configure_computer_identities` (`src-tauri/runtime.rs:2148-2173`); NEW `computerId` keys (95 A-11/§3), remote exposure and macOS Git identity application (95 A-14/A-19; Q13).
- **Params:** `identities: ComputerIdentity[]` with NEW `computerId` replacing `computer`; retain `name`, `email`, `apply`, and skip entries with `apply:false` (justified by [95 A-11](95-decisions.md#2-technical-defaults); `runtime.rs:2028-2035`).
- **Result:** `{jobId}` at once (`job:<n>`). `operations.job.finished.result`: none, as today; failures in `operations.job.finished.error`.
- **Progress:** no progress source; its gate entries ("Saving Git identity for <name>") on `operations.queue.changed` (05 §4.2 E item 4).
- **Cancel:** `operations.cancel {jobId}`, routed to its current gate entry under the gate rules (05 §4.2 F).
- **Errors:**
  - "Each computer needs one valid Git name and email address.";
  - "Computer '<x>' is not a configured local computer…";
  - identity changed;
  - "Silo could not verify the saved Git identity…" (`runtime.rs:2197-2261`).
  - Today a native notification is sent on failure (`runtime.rs:2169-2181`); NEW the engine retains the latest notice per key for Fjord and posts no OS notification (justified by [95 A-27](95-decisions.md#1-owner-decisions); 60 `notifications.list`).
- **Semantics:**
  - Validates everything first.
  - Then, per computer in its own lane (label "Saving Git identity for <name>"):
    1. removes boot-time identity environment overrides (`msb modify --env-rm …`);
    2. writes `git config --global` and `jj config set --user` with values passed as positional arguments (never interpolated), temporarily booting a stopped computer;
    3. verifies the result (`runtime.rs:2230-2262`, `2275-2318`).
  - A related single-computer path with auto-retry is used by GitHub apply (`runtime.rs:2616-2647`); it is owned by `github.*`.

---

- **Remote contract:** NEW `deviceId?` forwards through the local engine and SSH, justified by [95 A-3/A-14/A-19](95-decisions.md); existing Linux implementations are reused under canonical names; missing adapters require Q13. Historical bridge names are not accepted (95 §3).

## 6. Operations

This section owns the `operations.list` and `operations.cancel` entries; their params and semantics follow the job contract (05 §4.2 E, F). **NEW outcome lifecycle, justified by 95 §3 (overrides A-25):** the engine saves completed job outcomes to disk, reloads them after restart, and removes an outcome only after a client acknowledges showing it through `operations.job.acknowledge` (owned by 05). There is no one-hour job-outcome expiry. Recovery of work interrupted while running remains probe B-37; retained completion does not imply replaying unfinished work.

### operations.list
- **Kind:** query.
- **Platforms:** both. NEW macOS work joins the same queue by `computerId`, waits in `waiting` with “Waiting…” and Cancel rather than a contention refusal, and uses the existing conflict scopes and admission order (justified by [95 A-31](95-decisions.md#2-technical-defaults)). Today macOS work bypasses the gate and reports `state`/`checkpointOperation` (`src-tauri/macos_computers.rs:187-213`; `src-tauri/macos_computers/checkpoints.rs:128-154`).
- **Status:** EXTENDED: tauri `read_operation_queue` (`src-tauri/runtime.rs:55-58`); NEW macOS waiting work (95 A-31/§3), remote queue exposure (95 A-14), job links and durable `unacknowledgedJobIds` (95 §3 Job results).
- **Params:** `deviceId?`: NEW for remote. Today a controller does not see another device's queue: there is no bridge method among `remote.rs:236-272`.
- **Result:** NEW extended `OperationQueue { running: OperationEntry[], waiting: OperationEntry[], unacknowledgedJobIds: JobId[] }`. `running`/`waiting` retain their sourced queue meaning; waiting is in admission order. NEW `unacknowledgedJobIds` lists every completed outcome retained on the target engine, including after restart, so a fresh client can discover, read with `operations.job.get`, show and then `operations.job.acknowledge` it (justified by 95 §3 Job results; 05 job contract). This does not expose or imply resumed unfinished processes; durable inventory/recovery mechanics are B-37. Each `OperationEntry` (`operation_gate.rs:94-118`) has:
  - `id: u64`: one per admission, so a retried lifecycle job gets a new entry per attempt (`runtime.rs:3160-3178`);
  - `jobId?: JobId`: NEW (05 §4.2 E item 1). Links the entry to its job; absent for gate work that is not a job (Kind `command` methods);
  - `label`;
  - `kind`;
  - `computerId?`, `computerName?` (display only);
  - `sinceMs`;
  - `cancellable`: always true while waiting;
  - `expectedMs?`;
  - `blockedByHidden`: a waiting entry is held up by hidden maintenance (`operation_gate.rs:999-1029`).
- **`OperationKind`** (`operation_gate.rs:69-92`):
  - `lifecycle`;
  - `checkpointCapture`, `checkpointRestore`, `checkpointFork`, `checkpointDelete`;
  - `export`, `import`;
  - `storageReclaim`;
  - `githubApply`;
  - `push`;
  - `portPublish`, `portRemove`;
  - `shutdown`;
  - `computerConfiguration`;
  - `other`.
- **Scopes** (`operation_gate.rs:18-36`):
  - `Device` conflicts with everything;
  - `Computer{id}` conflicts only with the same id.
  - Admission is first-come-first-served among conflicting requests, so device work is never starved (`operation_gate.rs:1-9`, `216-228`).
- **Hidden entries:**
  - log cleanup, storage trim and similar housekeeping take the gate without appearing in the queue (`operation_gate.rs:150-152`, `305-311`; `runtime.rs:2777`, `runtime/storage.rs:729`);
  - most use `try_` admission and never wait (`operation_gate.rs:866-950`); the computer-use apply after each boot is the exception: a hidden blocking `acquire_while`, bounded by a deadline (`src-tauri/computer_use.rs:1225-1236`).

### operations.cancel
- **Kind:** command.
- **Platforms:** both. NEW macOS waiting entries can be cancelled through the gate; running macOS work retains `NotCancellable` where the existing adapter has no safe cancellation (justified by [95 A-31](95-decisions.md#2-technical-defaults); `operation_gate.rs:1031-1072`; 05 §4.2 F).
- **Status:** EXTENDED: tauri `cancel_operation` (`src-tauri/runtime.rs:60-65`); NEW job-target routing and `not_found` for an unknown job (95 §3), per-log-export cancellation (95 A-30), remote cancellation (95 A-14) and macOS Waiting/Cancel admission (95 A-31/§3).
- **Params:**
  - `jobId: JobId`: cancels the job, routed by its space as in the table of 05 §4.2 F (`setup:` and `job:` jobs holding gate entries go to their current gate entry; log export to its job-scoped cancel (95 A-30); waiting macOS work can be cancelled and running unsupported cancellation/update downloads return `NotCancellable` (95 A-31));
  - `deviceId?: string`: route to the owning engine through the local engine (95 A-3). Raw gate `id` cancellation is not exposed; it is historical source evidence, retired by 95 §3.
- **Result:** none. The cancelled job’s `operations.job.finished` carries `error.code: "cancelled"` when today’s command returns cancellation as an error; transfers keep their `{status: "cancelled"}` data in `result` (05 §4.2 E item 5 and F).
- **Errors:** `NotCancellable` → `internal` "This operation can't be cancelled." (`operation_gate.rs:51`, `62`; `bridge_error.rs:115-126`). NEW stable snake_case codes for macOS refusals are added to `ErrorCode` and fixtures (justified by [95 A-10](95-decisions.md#2-technical-defaults)); exact refusal mapping remains Q13 rather than invented codes.
- **One cancel method:** all clients, including Tauri, call `operations.cancel {jobId}`. Domain cancel names are dropped (95 §3; 05 §4.2 F).
- **Gate semantics** (`operation_gate.rs:1031-1072`), used internally for a `jobId` routed to its current gate entry; no public raw-id path (95 §3):
  - a **waiting** entry leaves the queue and its caller gets `cancelled`;
  - a **running** entry is signalled only if it opted in (`allow_cancel`), with a 250 ms grace for work that has just been admitted;
  - an unknown `jobId` returns `not_found` (95 A-25 and §3 Job results); today's raw gate unknown-id success is not a retained API path (`operation_gate.rs:1053-1055`; 95 §3);
  - a cancelled lifecycle action retires its intent (§4.3);
  - between lifecycle retry attempts there is no entry, and the job's shared cancel token stops the next attempt (`runtime.rs:3167-3178`; 05 §4.2 F).

### Gate errors and dedupe

| `GateError` | When | Wire code |
| --- | --- | --- |
| `AlreadyQueued` | Same dedupe `key` already waiting (`operation_gate.rs:741-743`) | `already_queued`; lifecycle callers turn it into success (`runtime.rs:3438-3448`) |
| `Nested` | Thread already holds an operation (`operation_gate.rs:730-732`) | `internal` |
| `Busy` | A `try_` admission found conflicting work (`operation_gate.rs:886-888`) | `busy` |
| `Abandoned` | Caller stopped waiting, e.g. a remote request's `startWithinMs` passed (`operation_gate.rs:438-450`, `782-797`) | `internal` |
| `Cancelled` | User cancel; or a lifecycle retry superseded by a newer request on the same computer (`operation_gate.rs:734-740`) | `cancelled` |
| `NotCancellable` | Cancel of running, non-cancellable work | `internal` |

### Event `silo://operation-queue-changed`
- **Status:** EXTENDED: existing event `silo://operation-queue-changed` emits an empty payload whenever the gate changes; NEW canonical event carries the queue and sequence number (95 A-4): entries queued, admitted, finished or cancelled (`src-tauri/main.rs:297-300`; `operation_gate.rs:604-609`).
- **UI behaviour:** refetches with `read_operation_queue` (`production-source.ts:552-566`, `1083`).
- **In this API:** NEW `operations.queue.changed` carries the new `OperationQueue` plus envelope `seq`; bounded buffers require re-reading after a gap or reconnect (justified by [95 A-4](95-decisions.md#2-technical-defaults); 05 §4.2 D).

---

## 7. Activity

### activity.setup.read
- **Kind:** query.
- **Platforms:** both. Linux adapter exists; macOS platform support is NEW, justified by [95 A-19](95-decisions.md#1-owner-decisions). The macOS mechanism/result mapping is unsourced; Q13 / 80 B-34 must establish it.
- **Status:** EXTENDED: tauri `read_setup_activity` (`src-tauri/runtime.rs:4104-4123`); NEW remote exposure and macOS setup-journal projection (95 A-14/A-19; Q13).
- **Params:** none.
- **Result:** `ComputerConfigurationProgress[]`, at most 512 (`runtime.rs:3877`, `4013`).
- **Semantics:**
  - Reads `setup-activity.json` (`runtime.rs:3629-3631`), bounded to 1 MiB and validated (`runtime.rs:3994-4031`).
  - Messages are **re-derived** from the step and category, so a modified file cannot inject text (`runtime.rs:4032-4058`, `3692-3710`).
  - When no setup journal is live in this process and the last attempt has no outcome, it appends and persists `setup-interrupted` (`runtime.rs:4060-4082`, `4115-4123`). So the read can write.
  - The UI calls it at start (`production-source.ts:785-795`, `1133`).
  - A remote setup's progress is not available to the controller (§11).

- **Remote contract:** NEW `deviceId?` forwards through the local engine and SSH, justified by [95 A-3/A-14/A-19](95-decisions.md); existing Linux implementations are reused under canonical names; missing adapters require Q13. Historical bridge names are not accepted (95 §3).

### Activity in the state (`ApplicationSource.activities`)

Built by `runtime_activity::read` (`src-tauri/runtime_activity.rs:321-366`) plus secret activities (`runtime.rs:4768-4771`). Entry shape, all JSON:

- `id`;
- `category` (`computer`/`git`/`backup`/`secrets`/`github`/`system`);
- `title`, `detail`;
- `occurredAt`, `time` (ISO);
- `tone` (`success`/`neutral`/`warning`/`danger`);
- `status` (`running`/`completed`);
- `computer?`;
- `diagnostic?`;
- `partial?`;
- `cancelled?`;
- `progress?`, `progressLabel?`.

UI: `production-source.ts:157-167`. The sources are:

- **Setup journal** (`setup-activity.json`): one entry per event, `detail:"Computer setup"`, `diagnostic` and `partial` from `setup-failed` (`runtime_activity.rs:323-332`).
- **Lifecycle journal** (`computer-activity.json`, `runtime_activity.rs:35-37`):
  - `Event { id, action, computer, computerId, timestamp, completed, failure?, diagnostic?, dismissed, cancelled, process, processSession }` (`runtime_activity.rs:5-28`);
  - at most 200 entries and 1 MiB (`runtime_activity.rs:3`, `39-119`).
  - Titles: "Computer started/stopped/restarted", "Starting/Stopping/Restarting computer", either one + " failed", "Start/Stop/Restart cancelled" (`runtime_activity.rs:337`, `341-345`).
  - An unfinished entry from another process reads as interrupted: "Silo closed before the result was verified." (`runtime_activity.rs:333-351`).
  - A failure to write the history adds an "Activity history unavailable" warning entry and never fails the action (`runtime_activity.rs:121-140`, `317-319`).

### Failure reporting fields

Contract: docs/SiloUI-RUNTIME-ERRORS.md and docs/SiloUI-FAILURE-REPORTING.md.

`failure_report` (`runtime.rs:3739-3842`) gives every failure:

- **`code`**, one of:
  - `auth`
  - `access`
  - `disk`
  - `permission`
  - `network`
  - `timeout`
  - `integrity`
  - `resources`
  - `configuration`
  - `unavailable`
  - `runtime`

  (`runtime.rs:3633-3673`, `3780-3813`; UI enum `ui/contracts/silo.ts:105`).
- **`summary`**: one line that never contains raw runtime output or the exit code (`runtime.rs:3676-3690`).
- **`exitCode`**.
- **`diagnostic`**: the runtime's own explanation, filtered like Logs, at most 8,192 chars (`runtime.rs:3712-3737`). Only the diagnostic carries "Exit code N".
- **`partial`**: completed changes were kept.

| Payload | Summary | Details | Partial |
| --- | --- | --- | --- |
| `setup-failed` progress event | `message` | `diagnostic` | `partial` |
| Application workspace (`ApplicationComputer`) | `lifecycleFailure` | `lifecycleFailureDiagnostic` | — |
| Activity entry | `title`, `detail` | `diagnostic` | `partial` |

(Table from docs/SiloUI-RUNTIME-ERRORS.md.)

- The latest failed lifecycle event per **computer id** is projected into `lifecycleFailure` until a later success or a Dismiss (docs/SiloUI-FAILURE-REPORTING.md; `runtime_activity.rs:252-281`).
- Early boot failures from `logs/boot-error.json` are read as one Runtime log record (docs/SiloUI-FAILURE-REPORTING.md).
- **macOS:** failures are the row's `state:"failed"` and `detail` (`macos_computers.rs:1783-1810`), plus its setup log (§8). There is no activity journal.

---

## 8. Logs

### logs.query
- **Kind:** query.
- **Platforms:** both.
  - **Linux:** the runtime's retained `exec`/`runtime`/`kernel` logs and `boot-error.json` (`src-tauri/runtime_logs.rs:506-569`).
  - **macOS:** the setup log `<app log dir>/macos-computers/<id>/runtime.log`, in the format of the Linux `runtime` source (`src-tauri/macos_computers/setup_log.rs:1-8`, `34-43`; routed at `runtime_logs.rs:610-614`, `macos_computers.rs:1336-1340`).
- **Status:** EXTENDED: existing query/bridge adapters below serve Linux logs and macOS setup logs; NEW macOS guest/runtime log collection beyond setup (95 A-19; mechanism remains Q13). Existing adapters:
  - tauri `query_computer_logs` (`src-tauri/runtime_logs.rs:711-719`);
  - bridge `runtime.logs` (`src-tauri/runtime/remote_ops.rs:13-20`, `remote.rs:239`), which serves both kinds (`runtime_logs.rs:658-671`).
- **Params:** `Query` (`runtime_logs.rs:7-23`):
  - `computerId`;
  - `deviceId?`: another device id forwards to it; `"local"` or the own id means this device (`runtime_logs.rs:595-609`);
  - `query?`: case-insensitive substring, at most 4,096 chars;
  - `source?`: `all`\|`stdout`\|`stderr`\|`output`\|`system`\|`runtime`\|`kernel`;
  - `since?`, `until?`: RFC 3339; reversed ranges are refused;
  - `cursor?`;
  - `limit?`: clamped to 1..200, default 200;
  - `aroundId?`: context around a record;
  - `follow?`: the previous snapshot token; reads only what was appended (`runtime_logs.rs:727-746`, `433`, `784-794`).
- **Result:** `Page` (`runtime_logs.rs:40-59`):
  - `entries: Entry[]`, each `{id, line, occurredAt, computerId, computerName, deviceId, deviceName, source, session?, guestTimestamp?}` (`runtime_logs.rs:24-39`);
  - `nextCursor?`;
  - `oldestAvailableTimestamp?`, `newestAvailableTimestamp?`;
  - `totalMatches`;
  - `timestampEstimated`;
  - `unsupported?`: the owner can't serve logs (`runtime_logs.rs:618-638`);
  - `unreadableRecords?`;
  - `snapshot?`: the follow token.
- **Paging and caching:**
  - A search builds an index snapshot of matching offsets. Cursors are `<snapshot>:<index>`.
  - Snapshots expire after 30 min idle, at most 16, within a 128 MiB budget.
  - Too many matches → "This search has too many matches…" (`runtime_logs.rs:386-408`, `936-985`).
  - Rotation during paging → "Logs rotated during this request. Refresh the search." (`runtime_logs.rs:409-426`).
- **Retention:**
  - At most 7 days and 250 MiB per computer, split between host execution records and guest console (`src-tauri/log_retention.rs:9-13`; docs/SiloUI-LOGS.md "Retention").
  - Running computers enforce it in the runtime.
  - Silo cleans a **stopped** computer's logs opportunistically on a fresh search, under a hidden try-lock on its lane, never waiting (`runtime_logs.rs:639-657`, `690-702`), and hourly from state reads (`runtime.rs:2700-2796`).
  - The macOS setup log rotates at 1 MiB and keeps 3 files (`setup_log.rs:19-23`).
- **Sensitive-output filtering** (EXISTS; before search, context, paging, Follow and export results leave the engine; `docs/SiloUI-LOGS.md`, "Search and investigation", lines 126-158):
  - ANSI and other control sequences are stripped first (`src-tauri/src/runtime_activity.rs:372-414`, `490-494`). Each matching line becomes `[Sensitive runtime output hidden]` (`src-tauri/src/runtime_activity.rs:490-529`) when it:
    - lies inside a PEM block, from a line containing `-----begin` through the line containing `-----end`;
    - contains a secret-looking assignment: `secret`, `token`, `key`, `passw` or `credential`, followed by optional word characters, quotes and whitespace, then `:` or `=` (`src-tauri/src/runtime_activity.rs:416-431`);
    - carries a credential option: `-u`, `--user`, `--proxy-user`, or a long option with a part `password`, `passwd`, `passphrase`, `token`, `secret`, `key`, `credential` or `credentials` (`src-tauri/src/runtime_activity.rs:458-484`);
    - contains URL user information, or a decoded query parameter named `sig`, `signature`, `x-amz-signature`, `x-goog-signature` or matching an assignment marker (`src-tauri/src/runtime_activity.rs:433-456`);
    - contains `authorization`, `bearer `, `ghp_`, `ghs_`, `ghu_`, `ghr_`, `github_pat_`, `private key`, `environment:` or `"env"` (`src-tauri/src/runtime_activity.rs:507-520`).
  - PEM state crosses records per `(stream, execution session)`, scanning rotated segments oldest first. An unterminated block stays hidden through that session's retained output (`src-tauri/src/runtime_logs.rs:106-151`; `docs/SiloUI-LOGS.md`, "Search and investigation", lines 126-132).
  - Each indexed match stores its initial PEM state, so context, pages, Follow and exports that start inside a block still hide its body (`src-tauri/src/runtime_logs.rs:913-925`, `452-456`; `docs/SiloUI-LOGS.md`, "Search and investigation", lines 126-132).
  - The open-session table shares the 128 MiB index budget. Exceeding it fails with "This search has too many matches. Narrow its time range or search text." rather than dropping the state of an open block (`src-tauri/src/runtime_logs.rs:140-145`, `936-941`).
  - Search matches the filtered body, so searching for a hidden value finds nothing (`src-tauri/src/runtime_logs.rs:374-377`, `913-915`). Filtering happens after runtime persistence and does not guarantee removal of arbitrary secrets; exports still require review before sharing (`docs/SiloUI-LOGS.md`, "Search and investigation", lines 134-139, 157-158).
- **Damaged and oversized records become placeholders or truncated text rather than failing the query or export** (EXISTS; `src-tauri/src/runtime_logs.rs:243-320`; `docs/SiloUI-LOGS.md`, "Search and investigation", lines 99-106):
  - Reading takes at most 1 MiB + 1 byte; the remainder of an oversized line is skipped to its newline within the captured segment (`src-tauri/src/runtime_logs.rs:176-219`, `358-368`).
  - `exec` JSON lines over 1 MiB become `[Execution log record over 1 MiB omitted]`; invalid JSON or a non-string/missing `d` becomes `[Unreadable execution log record]`. `e: "b64"` becomes `[Binary runtime output]` and remains readable. A missing or invalid `t` uses the segment's file time and is marked estimated (`src-tauri/src/runtime_logs.rs:258-281`).
  - An unterminated `exec` write is not yet a record: scanning stops before it and Follow reads it again once complete. Unterminated console chunks remain searchable (`src-tauri/src/runtime_logs.rs:369-380`, `74-81`; `docs/SiloUI-LOGS.md`, "Search and investigation", lines 84-90).
  - An unreadable or oversized `boot-error` becomes `[Unreadable boot failure record]` (`src-tauri/src/runtime_logs.rs:283-295`).
  - Oversized `runtime`/`kernel` console records keep at most their first 64 KiB, cut at a UTF-8 boundary, plus ` … [record over 1 MiB truncated]`, and are marked unreadable. Their time is parsed from the first word, otherwise the file time is used and marked estimated; a parsed `kernel` time sets `guestTimestamp` because the guest chose it (`src-tauri/src/runtime_logs.rs:176-181`, `220-227`, `296-318`).
  - Placeholders carry source `system` for exec or `runtime` for boot failures, and the file time marked estimated (`src-tauri/src/runtime_logs.rs:247-265`, `294`).
  - `timestampEstimated` and `unreadableRecords` aggregate the retained records scanned for the snapshot, including records that do not match the search. The flags are not restricted to records returned on the current page (`src-tauri/src/runtime_logs.rs:810-814`, `865-882`, `485-487`). Export coverage carries both flags (`src-tauri/src/log_export.rs:178-185`).

### logs.export
- **Kind:** job (05 §4.2 E).
- **Platforms:** both, local and remote, through `logs.query`.
- **Status:** EXTENDED: tauri `export_computer_logs` (`src-tauri/log_export.rs:80-115`); NEW explicit client-selected destination (00 brief, no drawing UI), job-scoped cancellation (95 A-30) and durable acknowledged job outcome (95 §3).
- **Params:**
  - `requests: Query[]`, 1–100 (`log_export.rs:87-89`);
  - `destination: string` (NEW param). Today the destination comes from a native save dialog (`log_export.rs:95-101`). A dialog is UI, so the engine method takes the path the client chose. Required by 00-brief.md ("everything Silo can do today except drawing UI").
- **Result:** `{jobId}` at once (`job:<n>`, 05 §4.2 E). `operations.job.finished.result`: `bool`, `false` when cancelled, as today. NEW completed outcomes are saved to disk, survive restart, and are dropped only after `operations.job.acknowledge` confirms a client showed them (justified by [95 §3](95-decisions.md#3-amendments-owner-2026-10-13-later); 05 job contract). Running-job recovery remains B-37.
- **Progress:** none. It has no progress source and takes no gate entry; only `operations.job.finished` reports it (05 §4.2 E item 4).
- **Cancel:** `operations.cancel {jobId}` (05 §4.2 F). NEW cancellation targets only that log-export job (justified by [95 A-30](95-decisions.md#2-technical-defaults)); today's process-wide generation counter (`log_export.rs:15-25`) must be replaced by a job-scoped cancellation token.
- **Filtering and damaged records:** the `logs.query` rules above apply to every exported page; export consumes those pages and carries their `timestampEstimated` and `unreadableRecords` flags into coverage (`src-tauri/src/log_export.rs:162-192`).
- **Output:** JSON Lines, written atomically: the file is replaced only after every page succeeded (`log_export.rs:42-71`). It contains:
  - a header `{type:"silo-log-export", version:1, note}`;
  - per request, a `coverage` line with the search text hidden;
  - every entry.

  (`log_export.rs:141-202`.)
- **Errors:**
  - "A log export is already in progress." (one at a time, `log_export.rs:123-124`);
  - "Update Silo on the remote device…" for `unsupported`;
  - a cursor that does not advance.
- **Gate:** the existing command also requires the main window (`log_export.rs:27-33`); that check is UI-only.

---

## 9. Storage

### storage.read
- **Kind:** query.
- **Platforms:** both. Linux adapter exists; macOS platform support is NEW, justified by [95 A-19](95-decisions.md#1-owner-decisions). The macOS mechanism/result mapping is unsourced; Q13 / 80 B-34 must establish it.
- **Status:** EXTENDED: tauri `read_workspace_storage` (`src-tauri/runtime/storage.rs:745-751`); NEW remote exposure and macOS storage projection (95 A-14/A-19; Q13).
- **Params:** `computerId` (UUID).
- **Result:** `StorageState` (`storage.rs:59-75`):
  - `history: ReclaimEntry[]`, each `{at, trigger: manual|afterStart|beforeStop|scheduled, reclaimedBytes?, error?}` (NEW removal of the historical `legacy` tag, justified by 95 §3; current source enum `storage.rs:35-44`), newest first, at most 50;
  - `workspaceHostBytes?`, `runtimeHostBytes?`, `checkpointHostBytes?`, `checkpointCount`;
  - `workspaceUsedBytes?`, `workspaceCapacityBytes?`: measured in the guest with `df`, only when the computer is running (`storage.rs:368-398`);
  - `lastReclaimedBytes?`, `lastTrimAt?`, `lastError?`.
- **Semantics:**
  - Takes no gate, so status stays readable during other work (`storage.rs:761-772`).
  - A pending restore with no runtime computer reports zeros and the history (`storage.rs:792-819`).

- **Remote contract:** NEW `deviceId?` forwards through the local engine and SSH, justified by [95 A-3/A-14/A-19](95-decisions.md); existing Linux implementations are reused under canonical names; missing adapters require Q13. Historical bridge names are not accepted (95 §3).

### storage.reclaim
- **Kind:** job (05 §4.2 E).
- **Platforms:** both. Linux adapter exists; macOS platform support is NEW, justified by [95 A-19](95-decisions.md#1-owner-decisions). The macOS mechanism/result mapping is unsourced; Q13 / 80 B-34 must establish it.
- **Status:** EXTENDED: tauri `reclaim_workspace_storage` (`src-tauri/runtime/storage.rs:752-758`); NEW remote exposure and macOS storage-reclamation adapter (95 A-14/A-19; Q13).
- **Params:** `computerId`.
- **Result:** `{jobId}` at once (`job:<n>`). `operations.job.finished.result`: `StorageState`, as today.
- **Progress:** no progress source; its gate entry (kind `storageReclaim`) on `operations.queue.changed` (05 §4.2 E item 4).
- **Cancel:** `operations.cancel {jobId}`, routed to its gate entry under the gate rules (05 §4.2 F).
- **Errors:**
  - "Start the computer before reclaiming…";
  - unexpected workspace mount;
  - "Restart this computer in Silo before reclaiming space…" (the worker is not verified);
  - unfinished restore ("Start <name> first." when a pending restore has no runtime computer yet, `storage.rs:800-803`; otherwise "The computer has an unfinished restore…", `storage.rs:822-825`);
  - "The runtime shortened the workspace disk…" (`storage.rs:420-437`, `513-531`, `822-826`).
- **Semantics:**
  - Device gate, kind `StorageReclaim` (`storage.rs:763-768`).
  - Runs `fstrim /workspace` in the guest with a 15 s budget (`storage.rs:8`, `401-511`).
  - Every disk layer is held open and its length restored if the runtime shortened it.
  - The record is saved under `storage-maintenance/<id>.json` before and after the trim (`storage.rs:86-91`, `464-509`).

- **Remote contract:** NEW `deviceId?` forwards through the local engine and SSH, justified by [95 A-3/A-14/A-19](95-decisions.md); existing Linux implementations are reused under canonical names; missing adapters require Q13. Historical bridge names are not accepted (95 §3).

### Automatic reclamation (engine behaviour)

Policy: docs/SiloUI-STORAGE-RECLAMATION.md "Policy".

| Trigger | Rule | Source |
| --- | --- | --- |
| After a successful start | Last success at least 7 days ago | `storage.rs:547-599`, called at `lifecycle_recovery.rs:238-240` |
| Every 60 s monitor | Same 7-day rule; one running computer per tick, in rotating order; hidden device try-lock | `storage.rs:640-743` |
| Before Stop, Restart or Quit | Last success at least 24 h ago | `storage.rs:533-545`, called at `lifecycle_recovery.rs:191-193` |
| Any automatic trigger | Also at least 24 h since the last attempt | `storage.rs:142-151` |

- Quit shares one 15 s maintenance deadline (`runtime/shutdown.rs:13-16`, `35-44`).
- Failures never veto a stop (`storage.rs:624-637`).
- The monitor also recovers interrupted checkpoint data (`storage.rs:710-722`).

---

## 10. Device capacity

**Linux.** `ApplicationSource.deviceCapacity` (`runtime.rs:562-565`, `568-589`, filled at `4780-4783`) has:

| Field | Computed from |
| --- | --- |
| `logicalCpus` | `std::thread::available_parallelism()` (`runtime.rs:1883-1893`) |
| `physicalMemoryBytes` | macOS `sysctl hw.memsize` (`runtime.rs:1895-1941`); the historical Linux-host `sysinfo` branch is retired by 95 §3 |
| `maxMemoryGib` | `physicalMemoryBytes / 2^30`, rounded down |

The field is absent when either measure fails. Every change is then rejected (`runtime.rs:562-564`, `1995-2007`).

**How limits are checked.** `validate_device_ceiling` (`runtime.rs:1989-2026`):

- requires `maxCPUs ≤ logicalCpus` and `maxMemoryGiB × 2^30 ≤ physicalMemoryBytes`;
- runs on every saved computer in a change (`runtime.rs:1943-1957`);
- runs again before each start, from the runtime's inspected `max_cpus` and `max_memory_mib` (`runtime.rs:1959-1987`; `lifecycle_recovery.rs:179`, `317-319`).

The boot values `cpus` and `memoryGiB` are only bounded by their ceilings (`runtime.rs:6137-6148`). The UI fits new-computer defaults to half the device (`ui/features/computers/model/computer-limits.ts:71-90`); that is client policy.

**macOS.** `HostLimits` (`src-tauri/macos_computers/store.rs:147-160`; `src-tauri/macos_computers/engine.rs:289-307`):

- `cpus` = available parallelism, or 2 if unreadable;
- `memory_gib` = `hw.memsize >> 30`, or 8 if unreadable.

A request must satisfy:

- CPUs `2..=max(cpus, 2)`;
- memory `4..=max(memory−4, 4)` GiB;
- disk `max(32, minDiskGiB)..=1024` GiB (`store.rs:10-15`, `162-196`).

**DECIDED (95 A-12):** expose these host limits in `device.facts` (60), as NEW fields derived from `HostLimits` and the cited validation; keep disk size fixed after creation ([95 Part 2](95-decisions.md#2-technical-defaults)). Today only `minDiskGiB` is reported (`macos_computers.rs:111-113`).

---

## 11. Remote counterparts

One method serves both targets: `ComputerRef.deviceId` absent means this engine. When it is present, the engine sends the matching bridge method to that device. The UI's `silo-remote:<deviceId>:<computerId>` target is that pair (`src-tauri/remote_access.rs:8-19`; docs/SiloUI-CONNECTIONS.md "Implementation boundaries").

| API method | Local today | Remote today (controller tauri → bridge) | Owner dispatch |
| --- | --- | --- | --- |
| `computers.list` (Linux part) | `read_application_state` | `device_snapshot(deviceId, refreshRepositories?)` (`remote.rs:1467-1489`) → `runtime.snapshot` | `remote_ops.rs:6-12` |
| `computers.list` (macOS part) | `read_macos_computers` | `remote_macos_snapshot` (`macos_remote.rs:131-138`) → `macos.snapshot` | `macos_remote.rs:68-70` |
| `computers.configuration.read` | `read_computer_configuration` | — (bridge only) → `runtime.configuration` | `remote_ops.rs:21-24` |
| `computers.create` (Linux) | `change_computer_configuration` `{kind:"upsert", expected:null}` | `remote_upsert_computer(deviceId, configuration, expected?)` with no `expected` (`remote.rs:1684-1721`) → `runtime.upsert` | `remote_ops.rs:36-114` |
| `computers.configuration.change` (Upsert edit) | `change_computer_configuration` | `remote_upsert_computer` with `expected` → `runtime.upsert` | same |
| `computers.delete` | `change_computer_configuration` | `remote_delete_computer(deviceId, computerId, expected)` (`remote.rs:1722-1746`) → `runtime.delete` | same |
| `computers.create` (macOS) | `create_macos_computer` | `remote_macos_create` → `macos.create` | `macos_remote.rs:71-76` |
| `computers.start/stop/restart/dismissError` | `computer_action` | `remote_computer_action(deviceId, computerId, action, name?)` (`remote.rs:1578-1632`) → `runtime.action {computerId, action}` | `remote_ops.rs:116-237` |
| `computers.start/stop/forceStop/delete` (macOS) | `macos_computer_action` | `remote_macos_action` → `macos.action` | `macos_remote.rs:77-83` |
| `logs.query` | `query_computer_logs` | same command with `deviceId` → `runtime.logs` | `remote_ops.rs:13-20` |

The third column records historical adapters; those names are dropped. Both local and SSH transports use the canonical API name in the first column (95 §3). A remote job's `jobId` is the owner engine's id. NEW Stream-class bridge subscriptions carry state events and job outcomes through the local engine (justified by [95 A-3/A-4](95-decisions.md#2-technical-defaults); 05 §4.2).

**Transport rules** (`remote.rs:1260-1330`, `2225-2284`):

- Protocol version 5 (`remote.rs:36`).
- `Read` methods are sent once.
- `Change` methods (`runtime.action`, `runtime.upsert`, `runtime.delete`, `macos.create`, `macos.action`; `remote.rs:236-272`):
  - carry a fresh `operationId` (UUID) and `startWithinMs`;
  - after a lost connection they are re-sent with the same `operationId` (delays 1 s and 4 s), and the owner attaches the retry to the change it already accepted (`remote.rs:1288-1330`);
  - queued work that cannot start in time is abandoned.
- Historical controller-engine shutdown cancels a pending remote change ("The remote action was cancelled when Silo began shutting down…", `remote.rs:1308-1315`). Client Keep running disconnects only its attachment; it does not trigger engine shutdown or cancel admitted work (95 A-2; 05 §6).

**Owner side:**

- Remote lifecycle uses the same lane, key, labels, cancellability, expected durations and auto-retry as local (`remote_ops.rs:116-120`, `177-234`).
- Remote upsert and delete take the device gate as "Applying remote change". They are refused while a local change waits for Retry (`remote_ops.rs:84-91`), and return the owner's `ApplicationSource`.
- Unknown `runtime.*` methods are refused before any gate (`remote_ops.rs:32-35`).

**Controller side:**

- Lifecycle notices name the computer `silo-remote:<deviceId>:<computerId>` (`remote.rs:1634-1643`).
- `device_snapshot` (`computers.list {deviceId}`) tracks poll health (§2). After 3 failures it closes tunnels and viewers (`remote.rs:1490-1577`). For 20 s after that, network-state reads answer from the last error without reconnecting (`remote.rs:1547-1560`, used only at `remote_network.rs:221-226`); the snapshot itself always re-polls.

**Differences between remote and local** (gaps the unified API either closes or documents):

1. **No reorder or batch remotely:** only `runtime.upsert` and `runtime.delete` (`remote_ops.rs:33-35`).
2. **Progress:**
   - a remote create emits no `computer-configuration-progress` to the controller; the owner only emits `application-state-changed` per step (`remote_ops.rs:100-102`);
   - no setup journal is written: `apply_whole_configuration_with_progress` is called without `apply_configuration_with_progress` (`remote_ops.rs:94-104` vs `runtime.rs:4138-4243`);
   - no lifecycle steps (§4.4).
3. **No creation wait before the gate** for image or ChatGPT on remote upsert (no `creation_inputs` call in `remote_ops.rs:36-114`).
4. **No cross-kind name reservation** on remote upsert (no `computer_names::reserve` in `remote_ops.rs`). → Q7.
5. **Not bridged:**
   - operation queue, cancel, setup activity, identities, storage, skip-wait, retry: no bridge method (`remote.rs:236-272`);
   - Connections doc: account configuration stays on the owning device (docs/SiloUI-CONNECTIONS.md "User behavior").

---

## 12. Added behavior and subscriptions

### 12.1 computers.launch
- **Kind:** query, plus the NEW behaviour that the engine's launch pass starts selected macOS computers.
- **Platforms:** both computer kinds; host macOS only (95 §3).
- **Status:** EXTENDED: tauri `read_settings` exposes launch selection (`src-tauri/settings.rs:779-792`, settings keys `:251,274`); `startup::install` applies it (`src-tauri/startup.rs:152-268`). NEW `LaunchStatus.lastPass` exposes the previously dialog-only outcome, and macOS computers join launch selection (95 A-19; 00 brief’s always-on host). The canonical status covers both kinds; it replaces 30’s former `macos.startAtLaunch` name (80 §2 N19). Selection remains `settings.update {startupComputerIds, startComputersAtLaunch}` (60). Required by:
  - the Silo gap "start with Silo: None" for macOS computers (docs/SiloUI-MACOS-COMPUTERS.md "Not covered yet"), and its cause in code (`startup.rs:87-101`, `runtime.rs:5203-5205`);
  - Fjord's need for "One long-lived dev computer: usually macOS, with Xcode and LCU" and "An always-on host Mac" (00-brief.md "What was decided", bullet "What Fjord will use the engine for");
  - the owner decision that the engine runs as a LaunchAgent in the user's GUI login session (00-brief.md "What was decided"). Its start is the "launch".
- **Selection:** unchanged, through `settings.*`: `startComputersAtLaunch` and `startupComputerIds` (EXISTS, `ui/features/preferences/model/settings.ts:7-8`). The behaviour change is that ids of this engine's **macOS** computers are kept:
  - `settings_for_launch` filters against both inventories, not only `computers.json`;
  - the launch pass routes a macOS id to the macOS Start (`macos_computers.rs:1351-1425`) instead of `runtime::start_at_launch`.
  - The existing ordering is kept: configuration and lifecycle recovery, then update recovery, then selected starts (`startup.rs:186-246`).
- **Params:** `deviceId?`.
- **Result** (NEW type `LaunchStatus`):
  - `enabled: bool`: from `startComputersAtLaunch`;
  - `computerIds: string[]`: the effective selection after the existing filtering (`startup.rs:48-104`);
  - `lastPass: { finishedAt: u64, failures: string[] } | null`: today these strings exist only in a notification and a main-window dialog (`startup.rs:247-265`). A UI-less engine must hand them to clients (00-brief.md: "everything Silo can do today except drawing UI").
- **Semantics:**
  - Same lanes and dedupe as a user Start for Linux (`runtime.rs:5154-5186`).
  - For macOS the registry's Start rules apply (`store.rs:253-268`).
  - A macOS computer that is not set up or needs personalizing reports its existing message as a failure.
  - Client disconnect never cancels launch work (95 A-2); engine update admission follows save/resume (95 A-6; 05 §6). Today startup cancellation is `startup.rs:270-287`.

### 12.2 Computer events: the `computers.*` and `operations.*` topics of `events.subscribe`
- **Not a method of its own.** This section first proposed a `computers.watch` subscription. It is the `computers.*` and `operations.*` topics of `events.subscribe` (05 §4.2 D; 80 §2 N15): `events.subscribe {events: ["computers.*", "operations.*"]}`. Names and payloads are the ones of 05's [event catalogue](05-engine-architecture.md#event-catalogue); each event arrives in the 05 envelope with its per-subscription `seq`.
- **Platforms:** both.
- **Status:** NEW. Required by:
  - the owner decision that Silo becomes a long-running engine with several clients: Fjord, the Tauri UI, other devices (00-brief.md "What was decided"). Today's notifications are Tauri `app.emit` calls that reach only the in-process webview (e.g. `runtime.rs:3371`; `main.rs:298-300`);
  - Fjord's Router "Runs on" and Triage "Run in a computer" needs (00-brief.md "What was decided", bullet "What Fjord will use the engine for"), which act on a computer's state as it changes;
  - the Silo gap that clients poll:
    - the UI re-reads the whole state every 10 s while visible (`ui/desktop/production-source.ts:1124-1132`);
    - it refetches on every unit-payload event (`production-source.ts:1140-1149`);
    - controllers poll remote devices ("Controller views refresh remote state periodically", docs/SiloUI-CONNECTIONS.md "Implementation boundaries").
- **DECIDED (95 A-4):** events carry new state plus sequence numbers, subscriber buffers are bounded, and clients re-read on gaps/reconnect; remote subscriptions use a Stream-class bridge through the local engine (95 A-3; 05 §4.2 D). An unsolicited initial snapshot is not established by that decision; the initial read/subscription race remains a transport probe in 05.
- **Events** (catalogue names only):

| Event | Payload | Replaces (EXISTS) |
| --- | --- | --- |
| `computers.changed` | NEW `{ linux?: ApplicationSource, macos?: MacosComputersState }`, the new state of the kind that changed, plus envelope `seq` (justified by 95 A-4); the macOS part retains its existing state payload | `silo://application-state-changed` with `()` payload, at its computer emit sites (e.g. `runtime.rs:3371`, `remote_ops.rs:49`, `startup.rs:243`, `lifecycle_recovery.rs:449`); `silo://macos-computers-changed` (`macos_computers.rs:50`, `667-669`) |
| `computers.unexpectedChange` | `{computerId, name, state}`, the health watch's finding (NEW) | the health watch's notices (`health_watch.rs:91-138`), today only notifications |
| `operations.queue.changed` | NEW `OperationQueue`, plus envelope `seq` (justified by 95 A-4) | `silo://operation-queue-changed` with `()` payload (`main.rs:298-300`) |
| `operations.job.progress` | `{jobId, kind?, computerId?, source, data}` (05 §4.2 E): `source: "lifecycle"` with `{computerId, action, step: boot\|network\|account}`; `source: "setup"` with `ComputerConfigurationProgress`; `source: "macos"` with the row's `{computerId, state, progress, detail, checkpointOperation}` | `silo://lifecycle-progress` (`runtime.rs:3343-3346`); `silo://computer-configuration-progress` (`runtime.rs:3586`, `4181-4183`; `configuration_recovery.rs:632`); the progress part of `silo://macos-computers-changed`. This section's proposal: also lifecycle steps for remote and launch starts (§4.4), and setup progress for remote upserts (§11 item 2) |
| `operations.job.finished` | `{jobId, result?, error?}` (05 §4.2 E) | none: today the command returns |

- **Semantics:**
  - A `computers.changed` follows the same settle rules as `computers.list`: rows touched by running work are `settling` (`runtime.rs:4463-4519`).
  - While a configuration attempt is live, the engine sends nothing for Linux rather than `update_in_progress` (`runtime.rs:2906-2935`).
  - NEW remote relays use Stream-class bridge subscriptions; snapshots remain the recovery reads after reconnect or a sequence gap (justified by 95 A-4; Q8).

---

## 13. Coverage

### Tauri commands

One row per command, or per value of the argument it fans out on. Each row names exactly one canonical method, or says why it is not in the API.

| Tauri command | File:line | API method |
| --- | --- | --- |
| `read_application_state` | `runtime.rs:2663` | `computers.list` (Linux part) |
| `read_application_shell` | `runtime.rs:2876` | `computers.shell` |
| `read_computer_configuration` | `runtime.rs:2649` | `computers.configuration.read` |
| `change_computer_configuration` `{kind:"upsert", expected:null}` | `runtime.rs:4321` | `computers.create` `{kind:"linux"}` |
| `change_computer_configuration` `{kind:"delete"}` | `runtime.rs:4321` | `computers.delete` |
| `change_computer_configuration` `{kind:"upsert"}` with `expected`, `reorder`, `batch` | `runtime.rs:4321` | `computers.configuration.change` |
| `retry_computer_configuration` | `runtime.rs:4252` | `computers.configuration.retry` |
| `skip_computer_use_wait` | `runtime.rs:3616` | `computers.creation.skipComputerUseWait` |
| `computer_action` `start` | `runtime.rs:3255` | `computers.start` |
| `computer_action` `stop` | `runtime.rs:3255` | `computers.stop` |
| `computer_action` `restart` | `runtime.rs:3255` | `computers.restart` |
| `computer_action` `dismiss-error` | `runtime.rs:3255` | `computers.dismissError` |
| `computer_action` `open-terminal` | `runtime.rs:3263-3276` | UI-only, not in API: it launches an app on the user's screen (§4.1, 00-brief.md "except drawing UI"). It is built on `terminal.command` (50) |
| `computer_action` `open-editor` | `runtime.rs:3263-3276` | UI-only, not in API, for the same reason (§4.1). It is built on `guest.sshAlias.ensure` (50; 80 §2 N10) |
| `configure_computer_identities` | `runtime.rs:2147` | `computers.identities.configure` |
| `verify_computer_identities` | `runtime.rs:2037` | `computers.identities.verify` |
| `read_setup_activity` | `runtime.rs:4103` | `activity.setup.read` |
| `read_operation_queue` | `runtime.rs:55` | `operations.list` |
| `cancel_operation` | `runtime.rs:62` | `operations.cancel` (`{id}`) |
| `runtime_logs::query_computer_logs` | `runtime_logs.rs:711` | `logs.query` |
| `log_export::export_computer_logs` | `log_export.rs:80` | `logs.export` (the save dialog is UI-only; the engine takes `destination`) |
| `log_export::cancel_log_export` | `log_export.rs:73` | Historical source → canonical `operations.cancel {jobId}` (one export job; 95 A-30/§3; 05 §4.2 F) |
| `storage::read_workspace_storage` | `runtime/storage.rs:745` | `storage.read` |
| `storage::reclaim_workspace_storage` | `runtime/storage.rs:752` | `storage.reclaim` |
| `remote::device_snapshot` | `remote.rs:1467` | `computers.list` with `deviceId` (10 §2; routing topology remains 80 §4 A-3) |
| `remote::remote_computer_action` `start` | `remote.rs:1578` | `computers.start` with `deviceId` |
| `remote::remote_computer_action` `stop` | `remote.rs:1578` | `computers.stop` with `deviceId` |
| `remote::remote_computer_action` `restart` | `remote.rs:1578` | `computers.restart` with `deviceId` |
| `remote::remote_computer_action` `dismiss-error` | `remote.rs:1578` | `computers.dismissError` with `deviceId` |
| `remote::remote_upsert_computer` without `expected` | `remote.rs:1684` | `computers.create` with `deviceId` |
| `remote::remote_upsert_computer` with `expected` | `remote.rs:1684` | `computers.configuration.change` with `deviceId` |
| `remote::remote_delete_computer` | `remote.rs:1722` | `computers.delete` with `deviceId` |
| `macos_computers::read_macos_computers` | `macos_computers.rs:781` | `computers.list` (macOS part) |
| `macos_computers::create_macos_computer` | `macos_computers.rs:812` | `computers.create` `{kind:"macos"}` |
| `macos_computers::macos_computer_action` `start` | `macos_computers.rs:823` | `computers.start` |
| `macos_computers::macos_computer_action` `stop` | `macos_computers.rs:823` | `computers.stop` |
| `macos_computers::macos_computer_action` `force-stop` | `macos_computers.rs:823` | `computers.forceStop` |
| `macos_computers::macos_computer_action` `delete` | `macos_computers.rs:823` | `computers.delete` |
| `macos_computers::macos_computer_action` `setup` | `macos_computers.rs:823` | `macos.setup.retry` (owned by 30) |
| `macos_remote::remote_macos_snapshot` | `macos_remote.rs:131` | `computers.list` with `deviceId` (macOS part) |
| `macos_remote::remote_macos_create` | `macos_remote.rs:141` | `computers.create` `{kind:"macos"}` with `deviceId` |
| `macos_remote::remote_macos_action` `start` | `macos_remote.rs:155` | `computers.start` with `deviceId` |
| `macos_remote::remote_macos_action` `stop` | `macos_remote.rs:155` | `computers.stop` with `deviceId` |
| `macos_remote::remote_macos_action` `force-stop` | `macos_remote.rs:155` | `computers.forceStop` with `deviceId` |
| `macos_remote::remote_macos_action` `delete` | `macos_remote.rs:155` | `computers.delete` with `deviceId` |
| `macos_remote::remote_macos_action` `setup` | `macos_remote.rs:155` | `macos.setup.retry` with `deviceId` (owned by 30) |
| `status_panel::quit_app` | `status_panel.rs:177` | UI-only, not in API: the app exit is the client's. Its stopping half is `engine.shutdown {stopComputers: true}` (05 §6.2); client Quit follows Cancel / Keep running / Stop and quit (95 A-2; §4.7) |

### Events

| Event | Emitted at | API |
| --- | --- | --- |
| `silo://application-state-changed` (computer emit sites) | about 40 sites in all, e.g. `runtime.rs:3348`, `3371`; `remote_ops.rs:49`, `112`; `startup.rs:243`; `shutdown.rs:127` | `computers.changed` (§12.2). Its other emit sites are other domains' events (05 §4.2 D) |
| `silo://lifecycle-progress` | `runtime.rs:3344` | `operations.job.progress` (`source: "lifecycle"`) |
| `silo://computer-configuration-progress` | `runtime.rs:3586`, `4181`, `4183`; `configuration_recovery.rs:632` | `operations.job.progress` (`source: "setup"`) |
| `silo://operation-queue-changed` | `main.rs:299` | `operations.queue.changed` |
| `silo://macos-computers-changed` | `macos_computers.rs:50` (the `CHANGED_EVENT` constant), `668` | `computers.changed` (macOS part); its row progress is also `operations.job.progress` (`source: "macos"`), 05 §9.3 |
| `silo://shutdown-state-changed` | `settings.rs:924`, `960` | `engine.shutdown.changed` (owned by 05) |

### Bridge methods

These are historical source commands; none remains a wire alias. Every client/bridge calls the canonical method in the API column (95 §3).

| Bridge method | `remote.rs` line | API |
| --- | --- | --- |
| `runtime.snapshot` | 238 | Historical source → canonical `computers.list` (Linux part) |
| `runtime.logs` | 239 | Historical source → canonical `logs.query` |
| `runtime.configuration` | 240 | Historical source → canonical `computers.configuration.read` |
| `runtime.action` `start` | 241 | Historical source → canonical `computers.start` |
| `runtime.action` `stop` | 241 | Historical source → canonical `computers.stop` |
| `runtime.action` `restart` | 241 | Historical source → canonical `computers.restart` |
| `runtime.action` `dismiss-error` | 241 | Historical source → canonical `computers.dismissError` |
| `runtime.upsert` with `expected: null` | 242 | Historical source → canonical `computers.create` (Linux) |
| `runtime.upsert` with `expected` | 242 | Historical source → canonical `computers.configuration.change` |
| `runtime.delete` | 243 | Historical source → canonical `computers.delete` (Linux) |
| `macos.snapshot` | 266 | Historical source → canonical `computers.list` (macOS part) |
| `macos.create` | 267 | Historical source → canonical `computers.create` `{kind:"macos"}` |
| `macos.action` `start` | 268 | Historical source → canonical `computers.start` |
| `macos.action` `stop` | 268 | Historical source → canonical `computers.stop` |
| `macos.action` `force-stop` | 268 | Historical source → canonical `computers.forceStop` |
| `macos.action` `delete` | 268 | Historical source → canonical `computers.delete` |
| `macos.action` `setup` | 268 | Historical source → canonical `macos.setup.retry` (owned by 30) |

### Engine behaviours without a command

| Behaviour | Source | API surface |
| --- | --- | --- |
| Health watch | `health_watch.rs:242-273` | `notifications.*` + `computers.unexpectedChange` |
| Start at launch | `startup.rs:152-268` | `computers.launch` (§12.1) |
| Lifecycle and configuration recovery | `lifecycle_recovery.rs:442-523`, `configuration_recovery.rs:598` | Runs at engine start; results in `computers.launch.lastPass` and activity |
| Automatic storage reclamation | `runtime/storage.rs:533-743` | Results in `storage.read.history` |
| Working-account readiness and preparation after boot | `src-tauri/src/working_account.rs:39-65`; `src-tauri/src/runtime.rs:1248-1271` | EXISTS, internal: `computers.start` step 3; labelled operation queue step and lifecycle failures; detailed rules below. |
| Expired log cleanup | `src-tauri/src/runtime.rs:2676-2701`, `2770-2796`; `src-tauri/src/runtime_logs.rs:639-657` | NEW timer trigger (95 A-26), retaining at most hourly cleanup per stopped computer under a hidden device gate; fresh searches try the computer's gate. Historical client-read trigger (Q12; 05 "Engine behaviour: maintenance that today runs on client reads"). |

#### Engine behaviour: working-account preparation after each boot (Linux)
- **Status:** EXISTS, internal: `working_account::prepare` already prepares the working account; historical per-boot layout conversion is retired (95 §3). Source: (`src-tauri/src/working_account.rs:39-65`; caller `src-tauri/src/runtime.rs:1248-1271`).
- **Readiness check:** keep the current account-record check via `msb exec --user root --no-start`, with a 30 s guest limit and 45 s host timeout. It reads `/var/lib/silo/working-account.json`; the current layout is `{"schemaVersion":1,"user":"silo","home":"/home/silo"}` (`src-tauri/src/working_account.rs:15-20,28-56`). A refused check fails Start; the caller stops the computer so a running computer has its working account (`runtime.rs:1248-1271`).
- **New-computer preparation:** retain creating `silo` with UID/GID 1001, `/home/silo`, `/bin/bash`, workspace ownership, passwordless sudo, access verification and an atomic final account record (`src-tauri/guest/working-account.py:259-264,272-285`). Do not preserve the old-account rename/home-copy branches as runtime compatibility paths (95 §3; historical branches `working-account.py:250-258,268-271`).
- **Launch upgrade only:** any existing guest account layout requiring conversion must be completed during the allowed launch upgrade using `runtime_migration`, before normal client work. Its integration is unsourced: probe B-34 must qualify safely preparing the guest during launch and removing the per-boot conversion. No new runtime fallback or second migration route is specified (95 §3; current launch seam `src-tauri/src/main.rs:301-308`).
- **Record persistence:** account records live on the computer’s disk, so restores/forks/imports carry them (`src-tauri/src/working_account.rs:7-8`); import/restore of an unsupported account layout cannot re-enable a conversion on Start (95 §3).
- **API surface:** preparation uses the labelled operation step and lifecycle failure reporting already sourced by `src-tauri/src/working_account.rs:58-65`, `runtime/operation_gate.rs:1134-1165` (§4.4/§4.5; 05 job contract). Guest account access is 70 `guest.account`; normal calls require the current layout (95 §3).

#### Engine behaviour: maintenance that today runs on client reads
- **Status:** EXTENDED, internal: `read_application_state` already schedules pending secret revocations and expired-log cleanup, including through bridge `runtime.snapshot`; `read_network_state` schedules published-port repair; NEW timer triggers run those duties without client reads (95 A-26). Source implementations (`src-tauri/src/runtime.rs:2663-2701`; `src-tauri/src/runtime/remote_ops.rs:6-11`; `src-tauri/src/network.rs:827-836`). The full cross-domain contract is 05 "Engine behaviour: maintenance that today runs on client reads"; NEW engine timers drive these duties independently of reads (justified by [95 A-26](95-decisions.md#2-technical-defaults); Q12).
- **Skipped work:** a busy computer gate skips revocation until a later state refresh; a stop clears its pending records (`src-tauri/src/runtime.rs:13029-13060`; `src-tauri/src/secrets.rs:369-379`). State-read log cleanup skips a busy hidden device gate, while fresh-log-search cleanup skips a busy computer gate (`src-tauri/src/runtime.rs:2770-2796`; `src-tauri/src/runtime_logs.rs:639-657`). Port repair skips a busy computer gate, and desired rules are also reapplied after successful starts (`src-tauri/src/network.rs:729-770`, `973-984`).
- **The health watch supplies no replacement today:** its bounded reads use `read_application_state_with`, which only builds state and does not run these passes (`src-tauri/src/health_watch.rs:242-273`; `src-tauri/src/runtime.rs:3007-3031`, `4378-4384`).

---

## 14. Open questions

| # | Question | What would settle it |
| --- | --- | --- |
| Q1 | **DECIDED (95 A-12):** Keep the platform state enums and add `kind` per row; see §1.5 and `computers.list`. | [95](95-decisions.md). Mechanism probes remain Q13 where stated. |
| Q2 | **DECIDED (95 A-29):** `computers.shell` stays. | [95](95-decisions.md). Mechanism probes remain Q13 where stated. |
| Q3 | Resolved: 80 §2 N19 (`computers.forceStop`, refused on Linux). | — |
| Q4 | **DECIDED (95 A-2):** Quit offers Cancel / Keep running / Stop and quit; updates and crashes never stop computers (§4.7). | [95](95-decisions.md). Mechanism probes remain Q13 where stated. |
| Q5 | **DECIDED (95 A-30):** Cancel one log export by its job id; the process-wide cancel counter is replaced (§8). | [95](95-decisions.md). Mechanism probes remain Q13 where stated. |
| Q6 | **DECIDED (95 A-12):** Report macOS host limits in device facts; disks remain fixed (§10). | [95](95-decisions.md). Mechanism probes remain Q13 where stated. |
| Q7 | Remote `runtime.upsert` does not reserve names across kinds and skips the image/ChatGPT wait (§11 items 3–4). Is that intended, or a bug the engine should fix? | **OPEN B-10:** run 2 upsert/delete failed with `EINVAL` before any framed result; inventories retained only the original stopped computers and original `workspace-1` identity. No macOS name collision existed, and creation-preparation wait was unmeasured. Resolve the bridge reproduction during implementation, then test the cross-kind collision/wait and confirm intent with maintainers ([linux.md Connections (run 2) §B-10](probes/linux.md#b-10--duplicate-name-remote-upsert-and-wait)). |
| Q8 | **DECIDED (95 A-4):** Owner pushes full-state sequenced events through a Stream-class SSH bridge; gap/reconnect requires re-read (§12.2). | [95](95-decisions.md). Mechanism probes remain Q13 where stated. |
| Q9 | **DECIDED (95 A-31):** macOS work waits in the shared operation queue, shown as “Waiting…” with Cancel, rather than a contention refusal (95 §3); no screen lock is introduced (95 A-8; §6). | [95](95-decisions.md). Mechanism probes remain Q13 where stated. |
| Q10 | **DECIDED (95 A-11):** Identities are keyed by `computerId`; convert existing name keys once at launch via `runtime_migration` (§5). | [95](95-decisions.md). Mechanism probes remain Q13 where stated. |
| Q11 | **DECIDED (95 A-14):** Another Mac manages everything through its local engine and SSH; add missing bridge adapters (§11). | [95](95-decisions.md). Mechanism probes remain Q13 where stated. |
| Q12 | **DECIDED (95 A-26):** Engine timers run secret revocation retries, log expiry and port repair without client reads; retain existing pass guards (§13). | [95](95-decisions.md). Mechanism probes remain Q13 where stated. |

| Q13 | **Implementation probe B-34 for decided macOS parity (95 A-19), CPU/memory edits (95 A-12), typed refusals (95 A-10), and remote management (95 A-14):** qualify the missing adapters for the Linux-only methods above, their platform result mappings, the macOS resource edit optimistic-check shape and stable refusal-code mapping. Linux storage trim and setup-journal formats do not establish a macOS mechanism. | A disposable adapter/reproduction against the existing VM registry, guest SSH seam and APFS storage; cite verified mechanisms before implementation. Requirement is decided; mechanism is unsourced. The allowed launch upgrade also needs a qualified guest-account conversion and normalization of any historical storage `legacy` trigger; no per-method conversion/fallback is retained (95 §3). |
