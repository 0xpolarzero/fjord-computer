# 20 · Checkpoints, exports, migration, preparation and the device

Domains: `checkpoints.*`, `exports.*`, `migration.*`, `preparation.*`, `device.*` (dependencies only).
Written against the brief in [00-brief.md](00-brief.md).

**Source snapshot.** Silo repo `/Users/polarzero/code/projects/microsandbox-workspaces`, HEAD `94d81937` (2026-10-10). Paths below are relative to:

- `src-tauri/src/…` = `app/SiloUI/src-tauri/src/…` (Rust)
- `src/…` = `app/SiloUI/src/…` (TypeScript UI)
- `docs/…` = the repo's `docs/` folder

Every Tauri command in scope is registered in `src-tauri/src/main.rs:134-137,152-155,234,247-266,278-283`.

**Shared facts used by every section below.**

- **Window checks.** Many commands refuse a caller that is not the `main` window:
  - macOS checkpoints: `src-tauri/src/macos_computers.rs:755-761`;
  - exports: `src-tauri/src/backup_controller.rs:405-409`;
  - the pre-upgrade backup: `src-tauri/src/pre_upgrade_backup.rs:462-468`.

  **DECIDED (95 A-5):** replace these labels with same-OS-user authorization by peer euid; clients authorized that way may invoke these methods, including setting changes ([95 Part 2](95-decisions.md#2-technical-defaults); 05 authentication).
- **Engine shutdown.** Most changes call `runtime::shutdown::ensure_accepting_operations`. Today’s combined Silo shutdown fails with "Silo is quitting and stopping its local computers. Wait for shutdown to finish." (`src-tauri/src/runtime/shutdown.rs:50-58`), quoted below as **E-QUIT**. This is historical engine-shutdown evidence: Fjord Quit offers Cancel / Keep running / Stop and quit, Keep running disconnects only the client, and a Fjord update/crash never stops computers (95 A-2; 05 §6).
- **The migration gate.** Every Linux checkpoint change (create, fork, restore, abandon, delete) first calls `runtime_migration::ensure_ready_async`; `read_checkpoint_usage` does not (§1.2.6):
  - the calls: `src-tauri/src/runtime/checkpoints.rs:783,1782,2188,2476,2753`;
  - until the migration is `complete` or `not-required`, it fails with "Finish the Silo runtime migration before using computers.";
  - or with "Saved migration data needs manual repair. The file was preserved." when the saved state is unreadable (`src-tauri/src/runtime_migration.rs:861-876`).

  Below this is **E-MIGRATION**.
- **Queue admission (95 A-31/§3):** NEW macOS checkpoint and export/import work waits in the shared queue, exposed as “Waiting…” with Cancel; contention is not an immediate `BUSY` refusal. After admission, genuine state/setup/disk preconditions are checked. Existing busy-message lists below are historical adapter evidence; source `src-tauri/src/macos_computers.rs:1843-1872`, queue seam `src-tauri/src/runtime/operation_gate.rs:69-126,1031-1072`.
- **The operation gate.** Linux checkpoint work and exports wait in Silo's operation gate (`operations.*`, another section). The gate's errors are `GateError::{AlreadyQueued, Nested, Busy, Abandoned, Cancelled, NotCancellable}` (`src-tauri/src/runtime/operation_gate.rs:39-51`). Its operation kinds include `CheckpointCapture`, `CheckpointRestore`, `CheckpointFork`, `CheckpointDelete`, `Export` and `Import` (`src-tauri/src/runtime/operation_gate.rs:75-80`). Below this is **E-GATE**.
- **Bridge errors.** A remote call fails with a `BridgeError { code, message }`:
  - the code is one of `update_in_progress | unsupported_remote_operation | cancelled | already_queued | busy | not_found | incompatible_version | internal` (`src-tauri/src/bridge_error.rs:4-24`);
  - today an owner that does not serve the method answers "This Silo version does not support that remote operation." (`src-tauri/src/remote.rs:273-274`).
  - Every String error becomes `internal` on the wire (`src-tauri/src/bridge_error.rs:104-108`). The macOS `BUSY`, `NOT_READY` and `CANCELLED` quoted below are Rust message constants (`src-tauri/src/macos_computers/checkpoints.rs:40-44`), not wire codes. NEW stable snake_case macOS refusal codes are added to `ErrorCode` and its fixtures (justified by [95 A-10](95-decisions.md#2-technical-defaults)). Exact mappings require the refusal-code probe in 10 Q13; the current message constants are not silently treated as wire codes.
- **Jobs.** Every method of Kind `job` below follows the one job contract, [05 §4.2 E](05-engine-architecture.md#job-contract), and its cancellation, 05 §4.2 F:
  - it returns `{jobId}` at once; what today's command returns at the end moves, unchanged, to `operations.job.finished.result`;
  - progress is `operations.job.progress` with the `source` named in the method, or, when the method has none, its gate entry on `operations.queue.changed` and the domain's `*.changed` event;
  - cancel is `operations.cancel {jobId}`; NEW unknown job ids return `not_found`. Completed outcomes are saved to disk, survive engine restart, and are dropped only after a client acknowledges showing them through `operations.job.acknowledge` (justified by [95 §3](95-decisions.md#3-amendments-owner-2026-10-13-later), overriding A-25; 05 job contract). Running/interrupted-job recovery remains probe B-37; no unsourced replay mechanism is promised.
- **Events.** Event names below are the ones of 05's [event catalogue](05-engine-architecture.md#event-catalogue) (80 §2 N15). NEW events carry the new state plus envelope `seq`, with bounded subscriber buffers and re-reads after gaps/reconnect; remote events use a Stream-class bridge through the local engine (justified by [95 A-3/A-4](95-decisions.md#2-technical-defaults)).
- **Computer and device params.** Per-computer methods take `computerId` plus `deviceId?` (10's `ComputerRef`, flattened); device-level methods take `deviceId?`. Absent `deviceId` means this engine (80 §2 N16).

**Owner amendment, 95 §3:** only canonical API names are accepted by local and SSH transports. Silo’s Tauri UI moves to those names; historical command/bridge names below identify source code, not accepted aliases. Persistent upgrades run once at launch through `runtime_migration`; normal method calls neither read old layouts nor migrate them. This overrides the earlier name-key migration and alias policies ([95 §3](95-decisions.md#3-amendments-owner-2026-10-13-later)).

**Host scope, amended by 95 §3:** engine hosts and remote controllers are Macs only. Both Linux and macOS computers remain supported guests. “Linux” below denotes the Linux computer/guest unless explicitly labeled as retired host-source evidence. Linux engine services, Debian/AppImage engine updates and headless Linux host setup are outside this API ([95 §3](95-decisions.md#3-amendments-owner-2026-10-13-later)).

---

## 1. `checkpoints.*`

### 1.1 The model on both platforms

| Concept | Linux computer | macOS computer |
| --- | --- | --- |
| What a checkpoint is | A MicroSandbox snapshot member in the computer's lineage group, plus Silo's record of it. The data and its reference graph belong to MicroSandbox (`src-tauri/src/runtime/checkpoints.rs:1-2`). | A folder `checkpoints/<id>/` under the computer's folder. It holds `checkpoint.json`, APFS clones `disk.img` and `auxiliary-storage.img`, and `state.vzvmsave` for a memory checkpoint (`src-tauri/src/macos_computers/checkpoints.rs:1-14,26-32`). |
| **Memory checkpoint** | `scope: "full"` when the computer is `Running`. It runs `msb snapshot create … --full --guest-flush required --integrity` (`src-tauri/src/runtime/checkpoints.rs:648-657,708-722`). | `kind: memory`, shown as `scope: "full"`. It pauses the computer, calls `saveMachineStateTo`, clones the files while the computer is paused, then resumes it (`src-tauri/src/macos_computers/checkpoints.rs:342-348,416-439`; `src-tauri/src/macos_computers/engine.rs:1120`). It is refused when the framework can't save the memory (`:379-383`). |
| **Disk checkpoint** | `scope: "disk"` when the computer is `Created` or `Stopped` (`src-tauri/src/runtime/checkpoints.rs:650`). | `kind: disk`, shown as `scope: "disk"`: clones of the disk and auxiliary storage (`src-tauri/src/macos_computers/checkpoints.rs:436-439,448-452`). |
| Id | `c` followed by 31 hex digits (`src-tauri/src/runtime/checkpoints.rs:242-258`). A checkpoint recorded from a pending restore (before its first Start) carries a separate native member id, `nativeId`; older records used `id` for both (`:16-19,26-30,618-625,1933-1940`). | A UUID (`src-tauri/src/macos_computers/checkpoints.rs:174-176,384`). |
| Name | 1 to 80 printable characters, trimmed (`src-tauri/src/runtime/checkpoints.rs:586-591`). | The same rules, with separate messages (`src-tauri/src/macos_computers/checkpoints.rs:186-201`). |
| **Recovery checkpoint** | Restore saves "Before restore" with `reason: "before-restore"`: memory when the computer was running, the disk otherwise (`src-tauri/src/runtime/checkpoints.rs:2022-2045`). | Restore first calls `create(…, RECOVERY_NAME, Reason::BeforeRestore)` (`src-tauri/src/macos_computers/checkpoints.rs:34,486-489`). |
| What Restore leaves | The runtime computer is removed and a **pending restore** is saved. The computer stays stopped until an explicit Start (`src-tauri/src/runtime/checkpoints.rs:2160-2179`). | The disk and auxiliary storage are swapped in through a journal, and a **pending restore** goes into the record. The computer stays stopped (`src-tauri/src/macos_computers/checkpoints.rs:476-510`; `src-tauri/src/macos_computers.rs:2016-2035`). |
| Fork | A new stopped computer in the inventory, whose pending restore points at the checkpoint (`src-tauri/src/runtime/checkpoints.rs:1651-1681`). | A new computer that clones the checkpoint's disk, gets a new MAC address and machine identifier, and is then **personalized** in the background (`src-tauri/src/macos_computers.rs:2069-2194`). |
| Unfinished Restore | Visible as `unfinishedRestore` and can be abandoned (`src-tauri/src/runtime/checkpoints.rs:2378-2469`). | A journal settled at load (`src-tauri/src/macos_computers.rs:527-544`). Start refuses until then (`:1370-1372,1461-1462`). It can't be abandoned (§1.5). |
| Retention | NEW automatic pre-run checkpoints retain the latest 3 per computer by default, configurable/off; manual checkpoints are never deleted automatically (justified by 95 A-18; §1.4). Existing plan kept all until explicit deletion (`docs/SiloUI-CHECKPOINTS-PLAN.md` "Checkpoint action feedback", lines 241-243). | Same NEW pre-run policy (95 A-18); explicit computer deletion still deletes its checkpoints (`docs/SiloUI-MACOS-COMPUTERS.md` "Checkpoints", Delete). |
| Remote (on another device) | `checkpoint.create`, `checkpoint.fork` and `checkpoint.restore` over the bridge (`src-tauri/src/remote.rs:263-265`), historical names dropped in favor of canonical `checkpoints.create/fork/restore` (95 §3). | None (`docs/SiloUI-MACOS-COMPUTERS.md` "On another Mac": "Checkpoints and clipboard transfer are not offered for remote computers"). |

#### Checkpoint record (the type in computer views)

How each platform serializes it today:

- **Linux** `Checkpoint` (`src-tauri/src/runtime/checkpoints.rs:13-24`), serialized as-is into the computer view (`src-tauri/src/runtime.rs:620-621,4722`):
  - `id: string`;
  - `nativeId?: string` (only when it differs); historical field fallback is not retained: any layout upgrade runs at launch via `runtime_migration` (95 §3).
  - `name: string`;
  - `createdAt: number`, Unix milliseconds (`src-tauri/src/runtime.rs:3621-3627`);
  - `scope: "full" | "disk"`;
  - `reason: "manual" | "before-restore"`, checked at load (`src-tauri/src/runtime/checkpoints.rs:185-187`).
- **macOS** `Summary` (`src-tauri/src/macos_computers/checkpoints.rs:88-117`):
  - `id`, `name`;
  - `createdAt: string` (RFC 3339, `:330-334`);
  - `scope: "full" | "disk"`;
  - `reason: "manual" | "before-restore"`;
  - `sizeBytes?: number`: bytes of the saved memory only (`:79-81,432-433`).
- **macOS fields not exposed.** The record behind `Summary` is `Meta` (`:63-86`). It also has `schemaVersion`, `macosVersion`, `hostBuild` and `computerUseVersion`, which `Summary` drops.
- **The UI contract.** `ComputerCheckpoint` is `{ id, name, createdAt: string, scope, reason, sizeBytes? }` (`src/features/application/model/checkpoint-source.ts:4-11`). The UI turns Linux milliseconds into ISO strings at the native boundary (`src/desktop/production-source.ts:78-89`).

The API type `Checkpoint` is the UI contract plus NEW `kind: "manual" | "automatic"`, justified by [95 A-18](95-decisions.md#1-owner-decisions). This distinguishes automatic pre-run records from existing manual/recovery records without inventing another discriminator:

```
Checkpoint { id: string, name: string, createdAt: string /* ISO 8601 */, scope: "full" | "disk",
             reason: "manual" | "before-restore", kind: "manual" | "automatic", sizeBytes?: number /* macOS memory bytes only */ }
```

#### Checkpoint operation (in computer views)

- **Linux** `Operation` (`src-tauri/src/runtime/checkpoints.rs:53-61`): `{ kind, status: "running" | "failed", stage, error? }`.
  - Silo writes `kind: "capture"` (`:703-708`), `kind: "restore"` (`:2039-2044`) and, while the Start of a pending restore runs, `kind: "fork"` with stage "Starting from checkpoint" (`:1290-1295, 1385-1390`). It never writes `delete`.
  - A failure stays in the view as `status: "failed"` until the next success, or until a delete clears it (`:750-765, 2735-2741`).
- **macOS** `Operation` (`src-tauri/src/macos_computers/checkpoints.rs:128-154`): `{ kind: "capture" | "restore" | "fork" | "delete", status: "running", stage }`.
  - No failed state is kept: the command returns the error.
- **UI** `ComputerCheckpointOperation` is `{ kind: "capture" | "fork" | "restore" | "delete", status: "running" | "failed", stage, error? }` (`src/features/application/model/checkpoint-source.ts:13-18`).
  - The UI also shows a client-side placeholder operation of the command's kind (capture, fork, restore or delete; `abandon_restore` shows as restore) while a command runs (`src/desktop/production-source.ts:1589-1597`).

#### Pending restore: what it is and when it applies

**Linux.** `PendingRestore { checkpointId, sourceComputer, state: "full" | "disk" }` (`src-tauri/src/runtime/checkpoints.rs:46-51`; UI `src/features/application/model/checkpoint-source.ts:29-33`).

- **The id is not the checkpoint's id.** `checkpointId` here is the *native member* id (`:1946-1950, 2169-2173, 1660-1664`), not the Silo checkpoint id. For an import it is a `silo-backup-<n>-<n>-<n>` member or a checkpoint's native id (`:985-1003`).
- **Three things set it:**
  1. **Restore**, after replacing the runtime computer (`:2160-2179`);
  2. **Fork**, on the child (`:1658-1664`);
  3. **Import** of an export file, with `state: "disk"` and a deny-all network policy (`:1023-1039`).
- **It applies only on an explicit Start.** The user's Start runs `start_pending` (`src-tauri/src/runtime.rs:5238-5252`). That runs `msb restore <source>:<member>`:
  - with `--disk-only` when a disk is taken from a full member;
  - with `--cow-mem` for a full restore;
  - with Silo's GitHub and secret proxy environment (`src-tauri/src/runtime/checkpoints.rs:1290-1340`).
- **Everything else is refused until then:**
  - while it is pending, the computer is listed as Stopped, "Ready to start from checkpoint" (`:870-900`);
  - automatic launch starts skip it (`src-tauri/src/runtime.rs:5207-5209`);
  - other lifecycle actions are refused with "<name> starts from a checkpoint first. Use Start on its page." (`src-tauri/src/runtime.rs:1097-1102, 5269-5275`; `src-tauri/src/runtime/checkpoints.rs:2369-2377`);
  - so is storage reclamation (`src-tauri/src/runtime/storage.rs:823-825`).
- **The Start can be retried.** A Start that fails keeps the pending restore. A retry reuses the attempt's computer when it ran (`src-tauri/src/runtime/checkpoints.rs:1196-1270, 1352-1392`).

**macOS.** `PendingRestore { checkpointId, memory: bool }` (`src-tauri/src/macos_computers/checkpoints.rs:119-126`), shown as `pendingRestore` (`src-tauri/src/macos_computers.rs:90-91`).

- **Only Restore sets it** (`src-tauri/src/macos_computers.rs:2017-2018`).
- **The next Start decides** (`src-tauri/src/macos_computers/checkpoints.rs:741-762`):
  - it restores the memory when the checkpoint holds memory, the state file still exists and the Mac's build (`kern.osversion`) is unchanged;
  - otherwise it boots from the disk with a note saying why.
- **The framework can still refuse.** If the framework rejects the saved memory, the computer boots from the disk and the note says so (`src-tauri/src/macos_computers.rs:1481-1543`; `src-tauri/src/macos_computers/checkpoints.rs:765-767`).
- **Start uses it up before any machine runs on the disk:** at once when it boots from the disk, after the memory is loaded when it restores it, or when the framework rejects the memory. A memory start that fails outright keeps it (`src-tauri/src/macos_computers.rs:1394-1401, 1464-1476, 1493-1532`).

#### Restore journal and unfinished Restore

**Linux.** `RestoreJournal { targetCheckpointId, recoveryCheckpoint, priorRunning, phase: "capturing" | "secured" }` (`src-tauri/src/runtime/checkpoints.rs:63-70`). It is exposed as `UnfinishedRestore { checkpointId, checkpointName: string | null, phase }` (`:2378-2403`; UI `src/features/application/model/checkpoint-source.ts:20-27`).

- **What it blocks** while unfinished:
  - creating a checkpoint (`src-tauri/src/runtime/checkpoints.rs:630`);
  - forking the current state (`:1551-1553`);
  - exporting a checkpoint (`:915-919`);
  - deleting a checkpoint (`:2627-2631`).
- **Getting out of it:** retry Restore with the same target (`:2016-2022`), or abandon it (§1.2.5).

**macOS.** `restore-journal.json` with phase `staging | swapping` (`src-tauri/src/macos_computers/checkpoints.rs:513-533`).

- **On load:**
  - `staging` is rolled back;
  - `swapping` is rolled forward to a pending restore;
  - an unreadable journal keeps every file and blocks Start (`:672-710`; `src-tauri/src/macos_computers.rs:527-544`).
- **Messages:**
  - Start, Create and Restore refuse with "A Restore of this computer did not finish. Restart Silo to settle it before starting the computer." (`src-tauri/src/macos_computers.rs:1370-1372, 1461-1462, 1953-1954, 1989-1990`);
  - Delete of the checkpoint the journal names is refused (`src-tauri/src/macos_computers/checkpoints.rs:716-725`).

### 1.2 Methods

**Names.** Every transport/client uses canonical `checkpoints.*` names. The historical singular bridge names (`src-tauri/src/remote.rs:263-265`) are dropped, as are domain cancel names; clients use `operations.cancel` (95 §3).

**Jobs.** Every checkpoint change below is Kind `job` with a `job:<n>` id, engine-assigned (05 §4.2 E):
- **Linux** checkpoint jobs hold gate entries of kind `checkpointCapture`, `checkpointRestore`, `checkpointFork` or `checkpointDelete` (`OperationKind`, camelCase on the wire, `src-tauri/src/runtime/operation_gate.rs:69-92`), each linked to its job by the NEW `OperationEntry.jobId?`. They have no progress source: clients follow the gate entry on `operations.queue.changed` and `checkpointOperation.stage` in the computer view, and `checkpoints.changed` fires when the work ends.
- **macOS** checkpoint jobs NEW join the shared queue with the corresponding checkpoint kind and stable computer id (justified by [95 A-31](95-decisions.md#2-technical-defaults); 10 §6; `src-tauri/src/runtime/operation_gate.rs:69-126`). They retain `source: "macos"` progress with row `data`, at most once a second as today (05 §4.2 E item 4). Waiting entries are shown as “Waiting…” with Cancel and are cancellable; contention waits instead of returning the historical `BUSY` message (95 §3). Running operations without a supported cancellation seam refuse cancellation. Today macOS jobs bypass the gate and `NotCancellable` reaches the client as `internal` (05 §4.2 F).

#### 1.2.1 checkpoints.create

- **Kind:** job (`job:<n>`, 05 §4.2 E).
  - Linux runs it under the gate with kind `CheckpointCapture`. It can be cancelled, and is flagged slow after 15 minutes (`src-tauri/src/runtime/checkpoints.rs:790-799`). `msb snapshot create` has a 900 s timeout (`:723`).
  - macOS runs it on a blocking thread and claims the computer for one checkpoint operation (`src-tauri/src/macos_computers.rs:1843-1872, 1946-1981`).
- **Platforms:** both.
- **Status:** EXTENDED: existing capture commands/bridge below; NEW automatic/manual kind and retention plus captured-checkpoint result (95 A-18), remote macOS capture (95 A-14/A-19) and macOS Waiting/Cancel admission (95 A-31/§3). Existing adapters:
  - Linux: EXISTS, tauri `create_checkpoint` (`src-tauri/src/runtime/checkpoints.rs:777-808`); bridge `checkpoint.create`, its historical bridge command (`src-tauri/src/remote.rs:263, 1345-1348`; owner side `src-tauri/src/remote_access.rs:144-156`).
  - macOS: EXISTS, tauri `create_macos_checkpoint` (`src-tauri/src/macos_computers.rs:848-859`). NEW over the bridge: canonical `checkpoints.create` answers for macOS computers too (§1.3).
  - The `checkpoint` field of the result is NEW (§1.4).
- **Params:**
  - `computerId: string`. Linux: the computer's UUID (`src-tauri/src/runtime/checkpoints.rs:164`). macOS: the record id `id`.
  - `deviceId?: string` (80 §2 N16).
  - `name: string`.
  - NEW `kind?: "manual" | "automatic"`, default `"manual"`; persisted/returned and used for pre-run retention, justified by [95 A-18](95-decisions.md#1-owner-decisions) (§1.4). Existing `reason: "before-restore"` captures remain engine-owned and are outside automatic retention.
- **Result:** `{jobId}` (`job:<n>`, 05 §4.2 E). `operations.job.finished.result`: `{ checkpoint: Checkpoint }`, NEW, see §1.4. What today's commands return instead:
  - Linux returns the whole application state (`ApplicationSource`, owned by `computers.*`) (`:802-803`). The bridge result is thrown away by the controller (`src-tauri/src/remote.rs:1380`; 80 §5 B-9).
  - macOS returns `()` (`src-tauri/src/macos_computers.rs:1980`). The internal `checkpoints::create` already returns the new `Meta`, but the command drops it (`src-tauri/src/macos_computers/checkpoints.rs:373-377`; `src-tauri/src/macos_computers.rs:1979-1980`; 80 §5 B-9).
- **Progress and events:**
  - Linux: no progress source; the gate entry (kind `checkpointCapture`) on `operations.queue.changed`, and `checkpointOperation.stage` "Capturing computer state" in the computer view (`src-tauri/src/runtime/checkpoints.rs:703-708`). `checkpoints.changed` when done (today `silo://application-state-changed`, `:804`).
  - macOS: `operations.job.progress` with `source: "macos"`, carrying the stages "Preparing", "Pausing the computer and saving its memory", "Copying the disk" (`src-tauri/src/macos_computers.rs:1833-1840`; `src-tauri/src/macos_computers/checkpoints.rs:428-444`). Today they are pushed as `silo://macos-computers-changed` (`src-tauri/src/macos_computers.rs:50, 667-669`), which becomes the macOS part of `computers.changed`.
- **Cancel:** `operations.cancel {jobId}` (05 §4.2 F). Linux: through the gate entry, which opts in. macOS: waiting entries are cancellable; running work without a safe cancellation seam returns `NotCancellable` (NEW queue contract, justified by 95 A-31).
- **Errors (Linux):**
  - E-MIGRATION, E-GATE, E-QUIT.
  - "Checkpoint name must contain 1 to 80 printable characters." (`src-tauri/src/runtime/checkpoints.rs:586-591`).
  - "Silo could not identify this computer. Refresh its status and retry the checkpoint action." (`:164`).
  - Checkpoint-history read failures: "…could not be read.", "…is too large; it was preserved.", "…is invalid; it was preserved.", "Checkpoint environment is invalid; it was preserved." (`:163-223`). Save failures: "…could not be saved.", "…could not be encoded.", "…could not be synced." (`:333-351`).
  - For a computer that has a pending restore:
    - "A Restore recovery is unfinished. Resolve it before creating a checkpoint."
    - "The pending checkpoint reference is invalid. It was preserved."
    - Here create records the *pending* member as a new checkpoint without capturing anything (`:594-629`).
  - "Finish the pending Restore before creating another checkpoint." (`:630, 768-775`).
  - "The computer runtime identity changed. No checkpoint was made." (`:633-642`).
  - "Wait until the computer is running or stopped before creating a checkpoint." (`:648-657`).
  - "This computer still uses the old workspace disk. Finish runtime migration before creating a checkpoint." (`:660-677`).
  - "An interrupted checkpoint could not be removed. Retry after its dependencies are released." (`:680-691`).
  - A capture or verification failure from `msb`. It is kept as `checkpointOperation { status: "failed", stage: "Checkpoint failed" | "Verification failed" }` (`:723-765`).
  - The join failure "Silo could not finish creating the checkpoint. Refresh its history before trying again." (`:805-808`).
  - The network-policy checks run only for fork and restore (`:1396-1436`), not here.
- **Errors (macOS):**
  - "macOS computers need a Mac with Apple silicon." or the engine's reason (`src-tauri/src/macos_computers.rs:51, 763-769`).
  - "This computer no longer exists."
  - "This computer is being deleted."
  - Historical `BUSY` "A checkpoint operation is in progress on this computer. Wait for it to finish.": NEW queue contention waits with Cancel instead (95 A-31/§3).
  - "Installation was interrupted. Delete this computer and create it again."
  - `NOT_READY` "Checkpoints need a computer whose setup has finished. Use Retry setup first."
  - "macOS is still being installed on this computer."
  - "This computer is still being set up."
  - Historical "Wait for the computer to finish starting or stopping.": NEW conflicting queued work waits, then rechecks state after admission (95 A-31/§3). (`src-tauri/src/macos_computers.rs:1851-1853`; `src-tauri/src/macos_computers/store.rs:18-19, 275-309`; `src-tauri/src/macos_computers/checkpoints.rs:40-44`).
  - the unfinished-Restore message (`src-tauri/src/macos_computers.rs:1953-1955`).
  - The name rules (`src-tauri/src/macos_computers/checkpoints.rs:186-201`).
  - Low disk space for the memory: "This Mac is low on disk space: …" (`src-tauri/src/macos_computers.rs:1936-1944`; `src-tauri/src/macos_computers/templates.rs:666-676`).
  - "This computer's memory can't be saved (<why>). Stop it to save a checkpoint of its disk." (`src-tauri/src/macos_computers/checkpoints.rs:379-383`). Silo never quietly takes a different kind (`docs/SiloUI-MACOS-COMPUTERS.md` "Checkpoints", Create).
  - `CANCELLED` "The checkpoint operation was cancelled." (`:44, 440-442`).
  - File errors through `store::io_error` (`src-tauri/src/macos_computers/store.rs:461-470`).
  - E-QUIT (`src-tauri/src/macos_computers.rs:857`).
- **Semantics:**
  - **Linux ordering.** Capture is ordered per computer by stable id and doesn't take the device-wide lane (`src-tauri/src/runtime/checkpoints.rs:786-797`).
  - **Linux paused computer.** A paused computer is recovered before the capture (`:643-647`).
  - **macOS pause.** A running macOS computer is paused for a few seconds and then resumed whatever happens (`docs/SiloUI-MACOS-COMPUTERS.md` "Checkpoints", Create; the same section's "Measured" paragraph, 2026-10-10: save 2.1 s, clones about 1 s).
  - **macOS cleanup.** A partial folder is removed on failure and swept at launch (`src-tauri/src/macos_computers/checkpoints.rs:384-410, 260-272`).
  - **Not idempotent today.** Two calls make two checkpoints. Over the bridge, the transport `operationId` (the idempotency key of one Change request, 05 §4.1; not a job id) keeps a retry after a lost connection from running it twice (`src-tauri/src/remote.rs:1281-1291`; `src-tauri/src/remote/operations.rs:1-9`).

#### 1.2.2 checkpoints.restore

- **Kind:** job (`job:<n>`, 05 §4.2 E).
  - Linux: gate kind `CheckpointRestore`, *not* cancellable, flagged slow after `RESTORE_EXPECTED_DURATION` = 60 min (`src-tauri/src/runtime/checkpoints.rs:6, 2195-2204`).
  - macOS: a claimed checkpoint operation (`src-tauri/src/macos_computers.rs:1983-2035`).
- **Platforms:** both.
- **Status:** EXTENDED: existing restore commands/bridge below; NEW remote macOS restore (95 A-14/A-19) and macOS Waiting/Cancel admission (95 A-31/§3). Existing adapters:
  - Linux: EXISTS, tauri `restore_checkpoint` (`src-tauri/src/runtime/checkpoints.rs:2182-2213`); bridge `checkpoint.restore`, its historical bridge command (`src-tauri/src/remote.rs:265, 1353-1356`; `src-tauri/src/remote_access.rs:168-174`).
  - macOS: EXISTS, tauri `restore_macos_checkpoint` (`src-tauri/src/macos_computers.rs:861-872`). NEW over the bridge: canonical `checkpoints.restore` answers for macOS computers too (§1.3).
- **Params:** `computerId: string`, `deviceId?: string`, `checkpointId: string` (a Silo checkpoint id).
- **Result:** `{jobId}` (`job:<n>`, 05 §4.2 E). `operations.job.finished.result`: today's return value, unchanged:
  - Linux: `ApplicationSource` (`:2205-2206`).
  - macOS: `()`.
  - Afterwards the computer view shows the pending restore (§1.1).
- **Progress and events:**
  - Linux: no progress source; the gate entry (kind `checkpointRestore`) on `operations.queue.changed`, and the stages "Creating recovery checkpoint", then "Replacing computer generation" in `checkpointOperation.stage` (`src-tauri/src/runtime/checkpoints.rs:2039-2044, 2131-2136`).
  - macOS: `operations.job.progress` with `source: "macos"`, carrying the stages "Saving a recovery checkpoint", "Stopping the computer", "Restoring the disk" (`src-tauri/src/macos_computers/checkpoints.rs:485-497`).
  - Events as in §1.2.1.
- **Cancel:** `operations.cancel {jobId}` (05 §4.2 F). Linux: a waiting entry leaves the queue; a running one answers `NotCancellable`, because it never opts in. macOS: waiting entries are cancellable; running work without a safe cancellation seam returns `NotCancellable` (NEW queue contract, justified by 95 A-31).
- **Errors (Linux):**
  - E-MIGRATION, E-GATE, E-QUIT, plus the history load and save errors from §1.2.1.
  - "The selected checkpoint no longer exists." (`src-tauri/src/runtime/checkpoints.rs:1903-1908`).
  - A snapshot-verification failure (`:1909`).
  - With a pending restore:
    - "A previous Restore recovery is unfinished. The pending checkpoint was preserved."
    - "The pending checkpoint reference is invalid. It was preserved."
    - "The current network policy is missing. The pending checkpoint was preserved."
    - Here restore turns the pending member into a "Before restore" entry and points the pending restore at the target (`:1911-1964`).
  - "The computer runtime identity changed. No Restore was performed." (`:1996-2001`).
  - "The current network policy is unavailable." and the network-rule errors (`:2002-2007, 451-575`).
  - "Wait until the computer is running or stopped before Restore." (`:2008-2015`).
  - The unfinished-Restore message, when retrying with another target (`:2016-2021, 2358-2368`).
  - The failures of pause and capture. A failure before the recovery checkpoint exists is undone (`abandon_capture`, `:1831-1863, 2059-2119`).
  - "The computer did not remain paused. No replacement was made." (`:2080-2091`).
  - "The computer resumed after its recovery checkpoint. Restore was stopped to protect later writes." (`:2139-2144`).
  - "The original computer did not stop. Its recovery checkpoint was preserved." (`:2151-2157`).
  - The join failure "Silo could not finish Restore. Open the Checkpoints tab to review recovery and retry Restore." (`:2212`).
  - Any error after the journal is saved is recorded as `checkpointOperation { kind: "restore", status: "failed" }` (`:1865-1892`).
- **Errors (macOS):**
  - The admission errors from §1.2.1.
  - The unfinished-Restore message (`src-tauri/src/macos_computers.rs:1989-1991`).
  - "This checkpoint no longer exists." (`src-tauri/src/macos_computers/checkpoints.rs:252-257`).
  - The low-disk message (`src-tauri/src/macos_computers.rs:1999`).
  - Failure to detach the disk (`offline_setup::ensure_detached`, `:2000`).
  - "Nothing was changed. The recovery checkpoint could not be saved: <message>" (`src-tauri/src/macos_computers/checkpoints.rs:488-490`).
  - `CANCELLED` (`:490-492`).
  - "The computer did not stop in time." (`src-tauri/src/macos_computers.rs:1898-1905`).
  - Clone or journal I/O errors (`src-tauri/src/macos_computers/checkpoints.rs:640-670`).
- **Semantics:**
  - **Recovery checkpoint first.** Both platforms save the recovery checkpoint before changing anything. It stays in the list whether or not the rest succeeds (`src-tauri/src/runtime/checkpoints.rs:2120-2130`; `src-tauri/src/macos_computers.rs:2014-2015`).
  - **The computer stays stopped.** On Linux the runtime computer is removed and Start applies the target (`src-tauri/src/runtime/checkpoints.rs:2158-2179`). On macOS the files are swapped and Start resumes memory or boots the disk (§1.1).
  - **Linux after a crash.** A secured journal whose runtime computer is gone becomes a pending restore on the next Restore or Start (`:1957-1985, 1120-1157`).

#### 1.2.3 checkpoints.fork

- **Kind:** job (`job:<n>`, 05 §4.2 E).
  - Linux runs two lanes, so the job holds two gate entries of kind `CheckpointFork` in turn:
    - the source's lane, not cancellable, slow after 10 min, which captures "Fork point" when no checkpoint is given;
    - then the device lane for the inventory write, slow after 60 s (`src-tauri/src/runtime/checkpoints.rs:1731-1765`).
  - macOS returns once the files are cloned, which ends the job. Personalization goes on in the background as the fork's own setup (`src-tauri/src/macos_computers.rs:2069-2142`).
- **Platforms:** both.
- **Status:** EXTENDED: existing fork commands/bridge below; NEW remote macOS fork (95 A-14/A-19) and macOS Waiting/Cancel admission (95 A-31/§3). Existing adapters:
  - Linux: EXISTS, tauri `fork_checkpoint` (`src-tauri/src/runtime/checkpoints.rs:1775-1806`); bridge `checkpoint.fork`, its historical bridge command (`src-tauri/src/remote.rs:264, 1349-1352`; `src-tauri/src/remote_access.rs:157-167`).
  - macOS: EXISTS, tauri `fork_macos_checkpoint` (`src-tauri/src/macos_computers.rs:874-886`). NEW over the bridge: canonical `checkpoints.fork` answers for macOS computers too (§1.3).
- **Params:**
  - `computerId: string`;
  - `deviceId?: string`;
  - `checkpointId: string | null`. Linux accepts `null`, meaning "fork the current state" (`src-tauri/src/runtime/checkpoints.rs:1541-1563`). macOS requires an id (`src-tauri/src/macos_computers.rs:880`);
  - `newName: string`.
- **Result:** `{jobId}` (`job:<n>`, 05 §4.2 E). `operations.job.finished.result`: today's return value, unchanged:
  - Linux: `ApplicationSource`.
  - macOS: `()`.
  - The fork's id is not returned on either platform today (`src-tauri/src/runtime/checkpoints.rs:1775-1806`; 80 §5 B-9; §Open questions).
- **What the fork gets.**
  - **Linux.** It copies the source's configuration with a new id and name. Its pending restore points at the member. It inherits the source's network policy and environment. Computer-use settings, GitHub assignments and secret assignments are copied, and rolled back on failure (`src-tauri/src/runtime/checkpoints.rs:1622-1729`). The fork is stopped and needs an explicit Start (`docs/SiloUI-CHECKPOINTS-PLAN.md` "Direction and accepted decisions").
  - **macOS: the fork is personalized.**
    1. It gets a new record with the source's CPUs, memory and disk, a new MAC address, `computerUseVersion` from the checkpoint, and `setup.needsPersonalizing = true` (`src-tauri/src/macos_computers.rs:2086-2105, 2161-2167`).
    2. `clone_for_fork` copies the checkpoint's disk, the auxiliary storage and the source's hardware model, writes a new machine identifier, and copies the source's password and keys to `inherited-access/` (`src-tauri/src/macos_computers/checkpoints.rs:771-831`).
    3. The background setup runs the personalization script over SSH with the inherited credentials. It sets the fork's own password, key, host keys, keychain and name, then verifies them and deletes `inherited-access/` (`src-tauri/src/macos_computers/provision.rs:134-136, 256-364`; `src-tauri/src/macos_computers/personalize.rs:1-12`).
    4. A memory state can't move to a new MAC address or machine identifier, so a fork always starts from the disk (`docs/SiloUI-MACOS-COMPUTERS.md` "Checkpoints", Fork).
- **Progress and events:**
  - Linux: no progress source; the gate entries (kind `checkpointFork`) on `operations.queue.changed`. Today the UI shows only a client placeholder stage (`src/desktop/production-source.ts:1595`). `checkpoints.changed` when done.
  - macOS: `operations.job.progress` with `source: "macos"` for the source row, which shows `Fork` "Copying the checkpoint". The fork's own row shows `State::Copying`, then `SettingUp` with "Personalizing the computer" (`src-tauri/src/macos_computers.rs:1833-1840, 2101-2105, 2170-2176`; `src-tauri/src/macos_computers/provision.rs:290`), in the macOS part of `computers.changed` (today `silo://macos-computers-changed`).
- **Cancel:** `operations.cancel {jobId}` (05 §4.2 F). Linux: a waiting entry leaves the queue; a running one answers `NotCancellable`. macOS: waiting entries are cancellable; running work without a safe cancellation seam returns `NotCancellable` (NEW queue contract, justified by 95 A-31).
- **Errors (Linux):**
  - E-MIGRATION, E-GATE, E-QUIT, name validation (`src-tauri/src/runtime/checkpoints.rs:1527`).
  - "The source computer is not a local computer." (`:1529-1536`).
  - "The fork name is already in use or the computer limit was reached." (`:1503-1516`).
  - The unfinished-Restore message (`:1551-1553`).
  - "The pending checkpoint reference is invalid or has unfinished recovery. It was preserved." (`:1438-1468`).
  - "The source network policy is missing. No fork was created." and "The source computer identity changed. No fork was created." (`:1396-1436`).
  - "The selected checkpoint no longer exists."
  - "The fork checkpoint was not recorded." (`:1566-1580`).
  - "The source computer no longer exists. No fork was created." (`:1633-1641`).
  - Name reservation against macOS names: "Computer names must be unique." (`:1767-1773`; `src-tauri/src/computer_names.rs:13`).
  - A rollback that didn't finish adds " Cleanup was incomplete: …". A publication it can't verify adds "…The fork's checkpoint and assignments were preserved…" (`src-tauri/src/runtime/checkpoints.rs:1690-1729`).
  - The join failure "Silo could not finish creating the fork. Refresh the computer list before trying again." (`:1802-1805`).
  - Every capture error from §1.2.1 when `checkpointId` is null.
- **Errors (macOS):**
  - The admission errors.
  - "Computer names must be unique." (reservation, `src-tauri/src/macos_computers.rs:2079-2080`).
  - "This checkpoint no longer exists." (`src-tauri/src/macos_computers/checkpoints.rs:252-257`).
  - The low-disk message for `COPY_ESTIMATE` of 4 GiB (`src-tauri/src/macos_computers/templates.rs:37`).
  - Request validation: name, "A macOS computer named '<n>' already exists.", CPU, memory and disk limits (`src-tauri/src/macos_computers/store.rs:162-195`).
  - Clone failures.
  - "Creating the fork was cancelled." (`src-tauri/src/macos_computers.rs:2132-2141`).
  - Later, in the background setup: "This fork has lost the access it was copied with. Delete it and fork the checkpoint again." (`src-tauri/src/macos_computers/provision.rs:41-42`).

#### 1.2.4 checkpoints.delete

- **Kind:** job (`job:<n>`, 05 §4.2 E).
  - Linux: device-wide gate kind `CheckpointDelete`, slow after 5 min (`src-tauri/src/runtime/checkpoints.rs:2757-2763`).
  - macOS: a claimed operation of kind `Delete` (`src-tauri/src/macos_computers.rs:2037-2067`).
- **Platforms:** both.
- **Status:** EXTENDED: existing Linux/macOS deletion commands below; NEW remote deletion (95 A-14) and macOS Waiting/Cancel admission (95 A-31/§3). Existing adapters:
  - Linux: EXISTS, tauri `delete_checkpoint` (`src-tauri/src/runtime/checkpoints.rs:2747-2777`).
  - macOS: EXISTS, tauri `delete_macos_checkpoint` (`src-tauri/src/macos_computers.rs:888-898`).
  - **Over the bridge: NEW,** wire name `checkpoints.delete` (80 §2 N4). There is no `checkpoint.delete` in `METHODS` (`src-tauri/src/remote.rs:236-271`), and the UI refuses: "Delete checkpoints of this computer in Silo on its own device." (`src/desktop/production-source.ts:1590`). Required by the owner decisions "The API must expose everything Silo can do today" and "Engines on other devices are reached over SSH" (00-brief.md "What was decided"). Remote management is decided by [95 A-14](95-decisions.md#1-owner-decisions).
- **Params:** `computerId: string`, `deviceId?: string`, `checkpointId: string`.
- **Result:** `{jobId}` (`job:<n>`, 05 §4.2 E). `operations.job.finished.result`: Linux `ApplicationSource`; macOS `()`.
- **Progress and events:** Linux: no progress source; the gate entry (kind `checkpointDelete`) on `operations.queue.changed`, then `checkpoints.changed`. macOS: `operations.job.progress` with `source: "macos"` (`checkpointOperation.kind: "delete"`).
- **Cancel:** `operations.cancel {jobId}` (05 §4.2 F). Linux: a waiting entry leaves the queue; a running one answers `NotCancellable`, because it never opts in (`src-tauri/src/runtime/checkpoints.rs:2757-2763`). macOS: waiting entries are cancellable; running work without a safe cancellation seam returns `NotCancellable` (NEW queue contract, justified by 95 A-31).
- **Errors (Linux).** The reasons from `deletion` (the unfinished Restore, the pending Start and the `blocker_message` texts) are also returned by `checkpoints.usage` as `deleteBlocker` (§1.2.6; `src-tauri/src/runtime/checkpoints.rs:2880-2887`):
  - E-MIGRATION, E-GATE, E-QUIT;
  - "The selected checkpoint no longer exists." (`src-tauri/src/runtime/checkpoints.rs:2703-2708`);
  - "Finish or abandon the unfinished Restore before deleting a checkpoint." (`:2627-2631`);
  - "<computer> starts from this checkpoint the next time it starts. Start <computer> first." (`:2637-2645`);
  - the dependency reasons from `blocker_message`, for example "Used by …", "…builds on this checkpoint. Delete … first.", "…can't be deleted while it is the latest state <computer> builds on." (`:2570-2618`);
  - "The checkpoint could not be deleted; it was kept. <cause>" (`:2722-2729`);
  - the join failure "Silo could not finish deleting the checkpoint. Refresh its history before trying again." (`:2773-2776`).
- **Errors (macOS):**
  - The admission errors.
  - "This checkpoint no longer exists." (`src-tauri/src/macos_computers/checkpoints.rs:252-257, 276`).
  - The unfinished-Restore message, when the journal pins the checkpoint (`src-tauri/src/macos_computers.rs:2044-2046`).
  - "The next Start of this computer continues from this checkpoint. Start the computer first, or restore another checkpoint." (`:2047-2054`).
  - File removal errors (`src-tauri/src/macos_computers/checkpoints.rs:274-289`).
- **Semantics:**
  - **Linux removes as little as possible.** The native member goes only when nothing else needs it, and it never passes `--force` (`src-tauri/src/runtime/checkpoints.rs:2694-2745`). Afterwards it retries members whose deletion was deferred, from `checkpoint-cleanup.json` (`:2741-2744, 2952-3090`).
  - **macOS removes the record first,** so a delete cut short is never listed (`src-tauri/src/macos_computers/checkpoints.rs:273-289`).

#### 1.2.5 checkpoints.abandonRestore

- **Kind:** job (`job:<n>`, 05 §4.2 E). Gate kind `CheckpointRestore`, slow after 5 min (`src-tauri/src/runtime/checkpoints.rs:2481-2488`).
- **Platforms:**
  - Linux: EXISTS.
  - macOS: NEW, required by `docs/SiloUI-MACOS-COMPUTERS.md` "Not covered yet" (Checkpoints row: "Not done: … abandoning a Restore"). Its requirement is decided by 95 A-19; the mechanism is unsourced (Q2).
- **Status:** EXTENDED: tauri `abandon_restore` (`src-tauri/src/runtime/checkpoints.rs:2472-2501`); NEW remote exposure and macOS abandon-restore adapter (95 A-14/A-19; Q2), with macOS Waiting/Cancel admission (95 A-31/§3). Existing adapters:
  - Linux: EXISTS, tauri `abandon_restore` (`src-tauri/src/runtime/checkpoints.rs:2471-2501`).
  - Over the bridge: NEW, wire name `checkpoints.abandonRestore` (80 §2 N4). Not in `METHODS` (`src-tauri/src/remote.rs:236-271`). The UI refuses: "Abandon this Restore in Silo on the computer's own device." (`src/desktop/production-source.ts:1591`). Required by the same owner decisions as §1.2.4 (80 §4 A-14).
- **Params:** `computerId: string`, `deviceId?: string`.
- **Result:** `{jobId}` (`job:<n>`, 05 §4.2 E). `operations.job.finished.result`: `ApplicationSource` (Linux).
- **Progress and events:** no progress source; the gate entry (kind `checkpointRestore`, label "Abandoning Restore") on `operations.queue.changed`, then `checkpoints.changed` (today `silo://application-state-changed`, `src-tauri/src/runtime/checkpoints.rs:2493`).
- **Cancel:** `operations.cancel {jobId}` (05 §4.2 F): a waiting entry leaves the queue; a running one answers `NotCancellable`, because it never opts in (`:2481-2488`).
- **Errors (Linux):**
  - E-MIGRATION, E-GATE, E-QUIT.
  - "<name> has no unfinished Restore." (`src-tauri/src/runtime/checkpoints.rs:2412-2417`).
  - "<name> was already replaced by this Restore. Start <name> to finish it, or Restore another checkpoint." (`:2418-2432`).
  - "The computer runtime identity changed. The Restore was not abandoned." (`:2433-2443`).
  - "<name> could not be resumed or stopped. The unfinished Restore was kept." (`:2444-2452`).
  - The join failure "Silo could not abandon Restore. Open the Checkpoints tab to review recovery and retry." (`:2499-2502`).
- **Semantics:**
  - It works only while the original computer still exists.
  - It resumes or stops a computer that the Restore left paused.
  - A recovery checkpoint already saved stays in the list. One that was only partly captured is removed (`:2405-2469`).

#### 1.2.6 checkpoints.usage

- **Kind:** query. It runs `msb` listings, so it is slower than the computer view (`src-tauri/src/runtime/checkpoints.rs:2802-2894`).
- **Platforms:**
  - Linux: EXISTS.
  - macOS: NEW, required by `docs/SiloUI-MACOS-COMPUTERS.md` "Not covered yet": "a size breakdown (only a memory checkpoint's state file is counted)". Today macOS has only `Summary.sizeBytes`, the memory state's bytes (`src-tauri/src/macos_computers/checkpoints.rs:79-81, 98-99`).
- **Status:** EXTENDED: tauri `read_checkpoint_usage` (`src-tauri/src/runtime/checkpoints.rs:2896-2912`); NEW remote exposure (95 A-14) and macOS size/dependency projection (95 A-19; Q3). Existing adapters:
  - Linux: EXISTS, tauri `read_checkpoint_usage` (`src-tauri/src/runtime/checkpoints.rs:2896-2912`).
  - Over the bridge: NEW, wire name `checkpoints.usage` (80 §2 N4). Not in `METHODS`. Required as in §1.2.4.
- **Params:** `computerId: string`, `deviceId?: string`.
- **Result:** `CheckpointUsage` (`src-tauri/src/runtime/checkpoints.rs:2779-2800`; UI `src/features/application/model/checkpoint-source.ts:42-54`):
  ```
  { totalBytes: number | null,
    checkpoints: [{ id, sizeBytes?, usedBy?: string[], deleteBlocker?: string }] }
  ```
  - NEW macOS projection: memory-file bytes are measurable; APFS clone-private/reclaimable disk bytes are not established by B-7. Omit unsupported per-checkpoint sizes and return `totalBytes:null` for an unmeasurable aggregate; never sum `du` clone totals (§1.4; [macos.md Follow-up §B-7](probes/macos.md#b-7--measured-at-volume-level)).

  - `totalBytes` counts each member once, and is `null` when any member can't be measured.
- **Errors:**
  - "This computer is not a local computer." (`src-tauri/src/runtime/checkpoints.rs:361`).
  - The history load errors, such as "Checkpoint history could not be read." (`:163-168`).
  - `msb` list errors through `safe_activity_error`.
  - The join failure "Silo could not read checkpoint disk usage. Refresh the Storage tab and retry." (`src-tauri/src/runtime/checkpoints.rs:2907-2909`).
  - It does **not** call the migration gate.
- **Related:** `storage_totals` (`src-tauri/src/runtime/checkpoints.rs:2912-2947`) feeds the Storage tab's per-computer checkpoint bytes and count. That belongs to `storage.*`.

### 1.3 Remote checkpoints (Connections bridge)

- **The Tauri wrapper.** `remote_checkpoint_action(deviceId, computerId, action: "create" | "fork" | "restore", name?, checkpointId?, newName?)` (`src-tauri/src/remote.rs:1362-1385`). In the API it is `checkpoints.create`, `checkpoints.fork` or `checkpoints.restore` with `deviceId`, one per `action` value (§5):
  - it maps the action onto bridge methods with params `{computerId, name}`, `{computerId, checkpointId|null, newName}` and `{computerId, checkpointId}` (`:1336-1360`);
  - local errors: "Invalid computer identity.", "Missing checkpoint name.", "Missing fork name.", "Missing checkpoint identity.", "Unsupported checkpoint operation." (`:1343-1358`);
  - the join failure "Silo could not finish the checkpoint action on the remote device. Reconnect to it and refresh the computer before retrying." (`:1383`);
  - it throws the owner's result away and returns `()` (`:1380`; 80 §5 B-9).
- **Names on the wire.** All checkpoint methods use canonical `checkpoints.*` names on both transports; historical singular names are dropped (95 §3).
- **Jobs on another device.** A remote checkpoint job runs on the owner's engine; NEW its events are relayed through the controller's local engine by a Stream-class bridge (justified by [95 A-3/A-4](95-decisions.md#2-technical-defaults); 05 §4.2 E).
- **The owner side.** The owner resolves `computerId` through its own inventory and calls the same local commands (`src-tauri/src/remote_access.rs:144-176`). Any other method gets "This Silo version does not support that remote operation." (`:180`).
- **The 122-minute deadline.**
  - `request_timeout` gives the three checkpoint methods `2 × (RESTORE_EXPECTED_DURATION + 60 s)` = 2 × 61 min = **122 min** (`src-tauri/src/remote.rs:981-990`; `src-tauri/src/runtime/checkpoints.rs:6`). Other methods get 600 s, or 2100 s for desktop-capable work (`src-tauri/src/remote.rs:991-1009`).
  - The change must *start* within half the remaining window, sent as `startWithinMs` (`:1322`; owner `:2260-2265`). The other half is kept for the owner's work and the transport (`:986-988`). A test checks that each method keeps at least 61 min after admission (`:2482-2495`).
- **Replay safety.**
  - A change carries an `operationId`, the transport idempotency key (05 §4.1; not a job id), and a retry after a lost connection reuses it (`:1281-1291`).
  - The owner attaches retries to the change it already accepted. Today its transport result cache keeps results for 1 h, gives a disconnected controller 10 s to reattach, and keeps a marker on disk so a restart never replays a change (`src-tauri/src/remote/operations.rs:1-9,22-26`). This historical transport cache does not define completed API job retention: 95 §3 requires durable outcomes until acknowledgement.
  - Owner errors: `EXPIRED`, `REUSED`, "…already accepted. Its result is uncertain…", `ALREADY_FINISHED`, `STILL_RUNNING` (`:33-40`).
- **What is missing remotely:**
  - **No delete, abandon or usage** over the bridge (§1.2.4–1.2.6).
  - **No macOS checkpoints remotely.** The macOS bridge methods are only `macos.snapshot`, `macos.create`, `macos.action` (historical source names dropped in favor of `computers.list`, `computers.create` and the lifecycle methods, 95 §3) and the display methods (`src-tauri/src/remote.rs:266-271`). `macos.action` carries only `start | stop | force-stop | delete | setup` (`src-tauri/src/macos_computers/store.rs:40-47`). This is a documented gap (`docs/SiloUI-MACOS-COMPUTERS.md` "Not covered yet", Remote computers row).
  - **NEW:** every `checkpoints.*` method reachable for a computer on another device, on both platforms. For macOS this means canonical `checkpoints.*` bridge methods answer for macOS computers too, as 30 says (30 §10; 80 §2 N4), and `.delete`, `.abandonRestore` and `.usage` serve both kinds. The bridge params for macOS ids are 80 §4 C-5. Required by the owner decisions "Not a single feature may be dropped", "The API must also add what's missing, for macOS computers", "Engines on other devices are reached over SSH", and Fjord's "always-on host Mac, and controllers on other Macs" (00-brief.md "What was decided").
  - Long methods keep the existing 122-minute budget and `operationId` replay rules. Changing those numbers is not required by any source.

### 1.4 Checkpoints before unattended runs (automatic checkpoints)

**DECIDED (95 A-18):** automatic checkpoints are taken before unattended runs and retain the latest **3 per computer** by default; manual checkpoints are never deleted automatically ([95 Part 1](95-decisions.md#1-owner-decisions)).

- `checkpoints.create` is EXTENDED with NEW automatic-checkpoint behavior, justified by 95 A-18: the caller passes `kind: "automatic"` and `name: "Before run: <task>, deleted automatically"`, then waits for `{checkpoint}` in the successful job outcome before starting the unattended run. `kind` defaults to `"manual"` for ordinary callers; `"before-restore"` remains engine-owned recovery capture. Names retain the existing 1–80 printable-character limit, so clients truncate the task portion (§1.1; `src-tauri/src/runtime/checkpoints.rs:586-591`; `src-tauri/src/macos_computers/checkpoints.rs:186-201`).
- NEW `kind: "manual" | "automatic"` is persisted and returned on both platforms; a one-time launch upgrade assigns existing records `kind: "manual"` and keep their existing `reason`, whose validators accept only `manual | before-restore` (`src-tauri/src/runtime/checkpoints.rs:185-187`; `src-tauri/src/macos_computers/checkpoints.rs:55-61`; 95 A-18).
- NEW retention keeps the newest configured count of `kind: "automatic"` records for each computer by creation time. Cleanup runs only after the replacement checkpoint succeeds; it never deletes `kind: "manual"` records, including existing `before-restore` recovery records. Existing deletion safety stays: pinned pending restores, unfinished restores and lineage dependencies can defer physical cleanup (Linux `src-tauri/src/runtime/checkpoints.rs:2627-2645,2694-2745,2952-3090`; macOS `src-tauri/src/macos_computers/checkpoints.rs:716-725`; §1.2.4). Exact handling of retention overflow when deletion is blocked is an implementation probe (§6 Q12 / 80 B-33), not permission to force-delete dependencies.
- NEW setting `automaticCheckpointRetentionCount: u32` (default `3`) lives in 60's settings table, justified by 95 A-18. `0` turns automatic checkpoints off; a positive value sets the per-computer count. The run caller reads that setting and skips capture when off; the engine refuses `kind: "automatic"` creation when off so all clients follow one policy. Turning it off does not delete existing checkpoints. No scheduling method is added: the run caller invokes the existing checkpoint method before launching work (00-brief.md "What Fjord will use the engine for").
- NEW `checkpoints.create` returns the exact checkpoint made. Linux today returns the application state whose first list entry is the capture (`src-tauri/src/runtime/checkpoints.rs:626,735,801-803`); macOS drops its new `Meta` (`src-tauri/src/macos_computers.rs:1979-1980`). The job returns `{checkpoint: Checkpoint}`, justified by 95 A-18.
- A pending Linux restore requires explicit Start (`src-tauri/src/runtime.rs:5207-5209`); macOS Start refuses while capture runs (`src-tauri/src/macos_computers.rs:1367-1369`). Engine update saves are a separate lifecycle concern (95 A-6; 05 §6) and do not consume the pre-run quota.

**Measured retention cost (B-7).** On the 64 GiB macOS template with 8 GiB VM RAM, the initial APFS disk/auxiliary clone cost 88 KiB of volume space; a synced 1 GiB guest random write cost about 1.04 GiB. Saving memory consumed 2,755,304 KiB (about 2.63 GiB), and the checkpoint disk/auxiliary clone cost another 52 KiB. Three similarly sized retained memory states alone would therefore use about 7.88 GiB, before subsequent copy-on-write disk changes. This is a planning estimate from one configuration, not a quota or a per-checkpoint reclaimable count ([macos.md Follow-up §B-7](probes/macos.md#b-7--measured-at-volume-level)).

Keep the default last-three policy (95 A-18), with count/off settings and dependency-safe deferred cleanup above. The checkpoint disk's 64 GiB logical size and its `du` allocation cannot be summed across APFS clones as private storage. `Checkpoint.sizeBytes` continues to mean saved memory-file bytes; macOS `checkpoints.usage` must return unknown/omit unsupported disk-private or reclaimable measurements instead of presenting logical bytes or `du` as space that deletion frees. Per-file private extent accounting remains OPEN in B-7 ([macos.md §B-7](probes/macos.md#b-7--partly), [Follow-up §B-7](probes/macos.md#b-7--measured-at-volume-level)).

### 1.5 macOS gaps, all NEW

From `docs/SiloUI-MACOS-COMPUTERS.md` "Not covered yet", Checkpoints row: "Done for local computers. Not done: export and import of a checkpoint, a size breakdown (only a memory checkpoint's state file is counted), and abandoning a Restore". Remote checkpoints come from the Remote computers row.

| Gap | API method | Note |
| --- | --- | --- |
| Size breakdown | `checkpoints.usage` for macOS | The clones share blocks with the computer (`src-tauri/src/macos_computers/checkpoints.rs:79-81`), so a "bytes it would free" figure needs a measuring method. Open. |
| Abandon a Restore | `checkpoints.abandonRestore` for macOS | The macOS journal settles on its own when computers load (`src-tauri/src/macos_computers.rs:527-544`), the adapter semantics remain a probe (§6 Q2); parity is decided by 95 A-19. |
| Remote checkpoints | `checkpoints.*` routed to the owning device | §1.3. |
| Export and import of a checkpoint | `exports.create` with `checkpointId`, and `exports.import`, for macOS | §2.1. macOS computers also have no whole-computer export ("Export, import and backup: None"). |
| Cancel a checkpoint operation | NEW macOS work joins the operation queue (95 A-31); waiting entries are cancellable, running operations advertise only cancellation their adapter supports. Linux capture already supports gate cancellation (`src-tauri/src/runtime/checkpoints.rs:797-798`). | Today Quit sets a cancel flag (`docs/SiloUI-MACOS-COMPUTERS.md` "Checkpoints", Lifecycle), with no command in `src-tauri/src/macos_computers/store.rs:40-47`; qualifying safe running cancellation is an adapter probe, not an invented guarantee. |

---

## 2. `exports.*` (export and import)

### 2.1 Facts

- **Format 4 file** (`.silo-backup`), written by `write_immutable_package` (`src-tauri/src/backup.rs:3222-3330`):
  - the bytes in order: `MAGIC` = `"SILO-BACKUP\0\0\0\0\0"` (16 bytes), `FORMAT_VERSION` = 4 as a big-endian u32, the manifest length as a big-endian u64, the JSON manifest, then one payload per computer (`:19-20, 3274-3279`);
  - the manifest is `PackageManifest { schemaVersion, createdAtMs, runtime: { name, version, snapshotFormat, guestArchitecture }, computers: [{ name, runtimeConfig, computerConfiguration, payloadSize, payloadSha256, volumes: [] }] }`, with unknown fields denied (`:471-502`);
  - each payload is a MicroSandbox `snapshot save --with-parents --with-image` of a capture (`:742-755`);
  - **refusals:** any format other than 4 (`:1962-1972`); NEW refuse a runtime other than the bundled MicroSandbox version, a runtime not named "microsandbox", or a `snapshotFormat` that does not match the current version (justified by 95 §3: historical 0.7.2/0.7.4 acceptance branches are removed) (`:1948, 1974-2006`);
  - the whole-file limit is 8 TiB (`:40`), and 1 GiB is kept free on the destination volume (`:39, 3260-3268`);
  - `docs/SiloUI-VOCABULARY.md` "Saved data": "Exports use format 4. Silo refuses exports in other formats".
- **What an export captures.**
  - **A whole-computer export** (no checkpoint) takes a `silo-backup-<i>-<suffix>` capture with `--guest-flush`, verifies it and writes it. The capture stays as a lineage parent (`src-tauri/src/backup.rs:686-740`).
  - There are at most 128 such captures per computer (`:37, 697-702`).
  - **A checkpoint export** packages that checkpoint's existing member (`src-tauri/src/backup.rs:425-428`; `src-tauri/src/runtime/checkpoints.rs:909-958`).
- **What an import creates.** A new stopped computer whose pending restore is `state: "disk"`. It has deny-all network, no GitHub token, and a fresh computer-use approval. It needs an explicit Start (`src-tauri/src/runtime/checkpoints.rs:973-1040`; `docs/SiloUI-CHECKPOINTS-PLAN.md` "Direction and accepted decisions").
- **The operation journal.** `backup-operation.json` sits next to `backup-history.json` in the app data folder (`src-tauri/src/backup_controller/recovery.rs:195`; `src-tauri/src/backup_controller.rs:20-22`).
  - Fields: `{ version: 1, id, archive, request, cancelled, terminal, awaitingUpgrade?, unseen? }`.
  - `request` is either `{ kind: "backup", names, computers, running, checkpointId?, pendingCapture? }` or `{ kind: "restore", name, source: string | null, id: string | null, group? }` (`src-tauri/src/backup_controller/recovery.rs:7-78`).
  - **Intent is written before side effects.** After a relaunch, recovery never repeats an export or an import. It removes partial output and reports a result. It adopts only a verified export file, or an import already saved under its journaled id (`:1-4`).
  - **One operation at a time.** A new one is refused while a journal is unfinished: "An interrupted operation still needs to finish. Relaunch Silo to resume it." (`:520-541`).
  - **Startup waits for import recovery** before computer recovery and automatic starts (`:134-139`).
  - **An unreadable journal** is set aside as `backup-operation.unreadable-<date>.json` (`:290-330`).
- **Only one transfer runs at a time:** "Another export or import is running." (`src-tauri/src/backup_controller.rs:929-932, 1660-1663`; `src-tauri/src/backup.rs:381`).
- **macOS computers have no export or import.**
  - The docs say so: `docs/SiloUI-MACOS-COMPUTERS.md` "Not covered yet": "Export, import and backup | None".
  - In code, an export looks the computer up in the Linux inventory only, and fails with "Computer '<name>' is not managed by Silo. Choose a Silo computer to export." (`src-tauri/src/backup_controller.rs:1337-1345`).
  - **NEW**, justified by [95 A-19](95-decisions.md#1-owner-decisions): macOS export, import, and checkpoint export (§1.5). The archive format/mechanism is unsourced and remains Q4/C-4; format 4 cannot be assumed to carry VZ state.
- **No export or import over the bridge.** No `backup.*` or `export.*` method is in `METHODS` (`src-tauri/src/remote.rs:236-271`). **NEW:** export and import for computers on another device, required by "Not a single feature may be dropped" and "Engines on other devices are reached over SSH" (00-brief.md). The file then lives on the engine's device (§Open questions).
- **The API takes paths. Choosers and reveal are UI-only.**
  - `choose_backup_destination` shows a folder dialog, canonicalizes the choice, **remembers it** (saved to `backup-history.json` best effort; after a write failure only for this session) and publishes it (`src-tauri/src/backup_controller.rs:506-543, 182-202`).
  - `start_backup` then refuses any `destination` that isn't exactly the remembered one: "Choose the export destination again before starting." (`:829-843`). The UI passes the path the chooser returned (`src/desktop/production-source.ts:1949, 1970`).
  - `choose_backup_archive` shows a file dialog filtered to `.silo-backup` and returns the path (`src-tauri/src/backup_controller.rs:546-567`). The UI passes it to `inspect_backup_archive` and `start_restore` (`src/desktop/production-source.ts:1954, 1918, 1986`). `start_restore` only requires an absolute path (`src-tauri/src/backup_controller.rs:1658-1660`).
  - `reveal_backup_archive` opens the file manager on the last successful export's `archivePath`, only when it matches byte for byte and the file still exists (`:685-732`).
  - In the API, the dialogs and the file-manager reveal belong to the client. The path rule needs one NEW method, `exports.destination.set` (§2.2.2).

### 2.2 Methods

#### 2.2.1 exports.state

- **Kind:** query.
- **Platforms:** both, local and remote. macOS support is NEW, justified by 95 A-19; archive mechanism remains Q4.
- **Status:** EXTENDED: tauri `read_backup_state` (`src-tauri/src/backup_controller.rs:453-496`); NEW remembered `destination` field (00 brief, no drawing UI), remote state and macOS export/import state (95 A-14/A-19; Q4).
- **Params:** NEW `deviceId?: string`, justified by 95 A-14; absent means this engine.
- **Result:** `BackupState` (`:86-106`):
  - `snapshotId: string`, a revision counter;
  - `operationId?: string`, the journal id. It is the `<id>` of the `exports:` job id (05 §4.2 E). It keeps its field name here; it is not the bridge's transport `operationId` (05 §4.1), which is the idempotency key of one Change request (80 §2 N11);
  - `availability: "available" | "unavailable"`, with `availabilityMessage?`;
  - `archives: []`, always empty (E-45, `docs/SiloUI-REVIEW-REMEDIATION-PLAN.md:490`; `src-tauri/src/backup_controller.rs:95-96`);
  - `operation: Operation | null`;
  - `resultUnseen?: true`.
- **The `Operation` type** (`:47-84`):
  - `Running { kind: "running", operation: "backup" | "restore", archive, runningNames, targetName?, progress, indeterminate?, canCancel?, phases: [{ title, detail, tone }] }`;
  - `Result { kind: "result", operation, archive, runningNames, targetName?, outcome: "success" | "failed" | "cancelled", title, message, detail? }`.
- **The `Archive` type:** `{ name, archivePath, completedLabel, size, destination, computers, checkpointName? }` (`:27-38`).
- **NEW field `destination?: string`:** the remembered export folder. Today it is used only as the dialog's starting folder (`:515-523`) and by the destination check (`:829-843`). A client that draws its own chooser needs the value. Required by "except drawing UI" (00-brief.md).
- **Events:** `exports.changed` on every change (today `silo://application-state-changed`, `:411-414`). NEW `BackupState` plus envelope `seq` (justified by 95 A-4). A running export or import also reports on `operations.job.progress` with `source: "backup"` (§2.2.5).
- **Errors:**
  - "Export and import status could not be read. Relaunch Silo and retry." (`:463-465`).
  - The availability message "The interrupted export or import could not finish. Relaunch Silo to retry. Saved progress was preserved." (`:477-479`).

- **Remote params:** NEW `deviceId?: string`; call through the local engine and SSH, justified by 95 A-3/A-14. Paths designate the owning engine's filesystem; returning archive bytes to a controller remains the transport probe Q5.

#### 2.2.2 exports.destination.set

- **Platforms:** both, local and remote; macOS NEW, justified by 95 A-19; archive mechanism remains Q4.
- **Kind:** command.
- **Status:** EXTENDED: tauri `choose_backup_destination` already canonicalizes/remembers the chosen folder (`src-tauri/src/backup_controller.rs:507-539`); NEW caller-supplied `path` without a dialog (00 brief, no drawing UI) and remote/macOS export support (95 A-14/A-19). Reuse the existing steps:
  - canonicalize the path;
  - require valid UTF-8 ("Silo cannot use paths containing non-UTF-8 names…", `:498-502`);
  - `remember_destination`, which keeps the folder and tries to save it (`:180-202`);
  - publish the change.

  Required because the API takes paths, and `exports.create` accepts only the remembered destination (`:829-843`).
- **Params:** `path: string`.
- **Result:** `{ destination: string }`, the canonical path.
- **Errors:** "Silo could not use the selected destination: <io error>" (`:534-535`); the UTF-8 message.

- **Remote params:** NEW `deviceId?: string`; call through the local engine and SSH, justified by 95 A-3/A-14. Paths designate the owning engine's filesystem; returning archive bytes to a controller remains the transport probe Q5.

#### 2.2.3 exports.inspect

- **Platforms:** both, local and remote; macOS NEW, justified by 95 A-19; archive mechanism remains Q4.
- **Kind:** job (`inspect:<requestId>`, 05 §4.2 E). It can run for minutes: it reads and hashes the whole file and changes no state (`src-tauri/src/backup_controller.rs:569-628`). It never enters the gate (05 §4.2 E, fact 2).
- **Status:** EXTENDED: tauri `inspect_backup_archive` (`src-tauri/src/backup_controller.rs:574-585`); NEW remote/macOS archive inspection (95 A-14/A-19; Q4) and durable acknowledged job outcome (95 §3).
- **Params:**
  - `archivePath: string`;
  - `requestId?: string`, generated when absent. Starting a new inspection cancels the previous one (`:641-654`).
- **Result:** `{jobId}` (`inspect:<requestId>`, 05 §4.2 E). `operations.job.finished.result`: `ArchiveInspectionResult { archive: Archive, valid: boolean, reason?: string }` (`:107-114`), which today's command returns.
  - An invalid file comes back as `valid: false` with the `BackupError` text as `reason`, not as an error (`:607-626`). It stays in `result` (05 §4.2 E item 5).
  - The `BackupError` variants: `Busy`, `Cancelled`, `CommandTimeout`, `CommandFailed`, `Conflict`, `FileConflict`, `ImportGroupConflict`, `InvalidArchive`, `InsufficientSpace`, `UnsupportedArchive`, `UnsupportedStorage`, `InvalidRequest`, `Io` and `Json`, with their texts (`src-tauri/src/backup.rs:351-403`).
- **Progress:** no progress source today, and none is added (05 §4.2 E item 4).
- **Cancel:** `operations.cancel {jobId}` (05 §4.2 F), routed to `cancel_backup_inspection(requestId)`.
- **Outcome after the fact:** NEW saved to disk, retained across restart, and dropped only after `operations.job.acknowledge` confirms a client showed it (justified by 95 §3; shared job contract). Interrupted-running-job recovery remains B-37.

- **Remote params:** NEW `deviceId?: string`; call through the local engine and SSH, justified by 95 A-3/A-14. Paths designate the owning engine's filesystem; returning archive bytes to a controller remains the transport probe Q5.

#### 2.2.5 exports.create (export)

- **Platforms:** both, local and remote; macOS NEW, justified by 95 A-19; archive mechanism remains Q4.
- **Kind:** job (`exports:<BackupState.operationId>`, 05 §4.2 E).
  - Today it returns the `operationId` (the journal id, `BackupState.operationId`) at once. Progress and the result arrive through `exports.state` (`src-tauri/src/backup_controller.rs:775-802`).
  - It takes the device-wide gate kind `Export`. It can be cancelled while it waits and while it runs, is flagged slow after 60 min, and gives up waiting after `RESTORE_TIMEOUT` of 60 min (`:20, 1242-1284, 1286-1316`).
- **Status:** EXTENDED: tauri `start_backup` (`src-tauri/src/backup_controller.rs:782-802`); NEW id-selected export (95 A-11/§3), remote/macOS export support (95 A-14/A-19; Q4) and job-scoped cancellation (05 job contract).
- **Params:**
  - `destination: string`, which must equal the remembered destination;
  - `computerIds: string[]`, computer ids (NEW contract, justified by [95 A-11](95-decisions.md#2-technical-defaults)); convert stored name-keyed selections once at launch via `runtime_migration` and resolve ids on the owner (`src-tauri/src/backup_controller.rs:1337-1345` is today's name lookup);
  - `checkpointId?: string`, which requires exactly one computer (`:823-904`).
- **Result:** `{jobId}` (`exports:<operationId>`, 05 §4.2 E), wrapping the `operationId` today's command returns. `operations.job.finished.result`: `BackupState.operation` with `kind: "result"` (§2.2.1). A failed or cancelled export stays data there (`outcome`), not `error` (05 §4.2 E item 5).
- **Events:** `operations.job.progress` with `source: "backup"`, whose `data` is `BackupState.operation` while `kind: "running"`, with `phases` (05 §4.2 E item 4); `exports.changed` on every change. A client that missed `finished` reads `exports.state`.
- **Cancel:** `operations.cancel {jobId}` (05 §4.2 F), routed to `cancel_backup_operation`. Requiring the `<id>` to match `BackupState.operationId` is NEW; today the command takes no id.
- **File name:**
  - `<computer>-<YYYY-MM-DD>.silo-backup`, or `<computer>-checkpoint-<date>`, or `Silo-Export-<date>`;
  - a `-2`, `-3`… suffix avoids existing files (`:734-760`).
- **Progress phases** (in the `phases` of the `backup` progress): "Capture and verify", or "Using checkpoint "<name>"" (`:960-972`), with "Waiting for other computer work" while queued (`:1190-1238`).
- **Errors (refused synchronously):**
  - "Silo could not use the export destination: …";
  - "Choose the export destination again before starting.";
  - name validation;
  - "Choose exactly one computer to export from a checkpoint.";
  - "Computer '<n>' is not managed by Silo…";
  - the `export_source` errors: unfinished Restore, "That checkpoint is still being captured…", "The selected checkpoint no longer exists.", "…could not identify this computer's checkpoints…" (`src-tauri/src/runtime/checkpoints.rs:909-958`);
  - "Another export or import is running.";
  - the journal-begin errors (`src-tauri/src/backup_controller.rs:829-932`).
- **Errors (as the result):**
  - `outcome: "failed"` with the message, or `"cancelled"`. The default detail is "No export file was saved." (`:1155-1188`).
  - Further worker errors: "Choose at least one computer to export.", "Exporting from a checkpoint supports one computer at a time.", the computer-shape errors (`:1329-1540`), and the `BackupError` texts.
  - A worker that panics gives "Silo hit an internal error and stopped this operation." (`:993-1033`).
- **Notification:** today a system notice for failures and long successes (`:1578-1610`); NEW the engine retains the latest notice per key for Fjord and posts no OS notification (justified by 95 A-27; 60 `notifications.list`).

- **Remote params:** NEW `deviceId?: string`; call through the local engine and SSH, justified by 95 A-3/A-14. Paths designate the owning engine's filesystem; returning archive bytes to a controller remains the transport probe Q5.

#### 2.2.6 exports.import

- **Platforms:** both, local and remote; macOS NEW, justified by 95 A-19; archive mechanism remains Q4.
- **Kind:** job (`exports:<BackupState.operationId>`, 05 §4.2 E).
  - Today it returns once the journal is saved. The result arrives through `exports.state`.
  - The gate kind `Import` is **not** cancellable once admitted (`src-tauri/src/backup_controller.rs:1846-1853`). Cancel is refused after commit: `canCancel: false`, "This operation is finishing and can no longer be cancelled." (`:2069-2077, 2096-2114`).
- **Status:** EXTENDED: tauri `start_restore` (`src-tauri/src/backup_controller.rs:1565-1576,1646-1733`); NEW returned job id (05 job contract; 80 §5 B-9) and remote/macOS import (95 A-14/A-19; Q4).
- **Params:**
  - `archivePath: string`, absolute;
  - `newName: string`;
  - `sourceName?: string`, which computer in a multi-computer file.
- **Result:** `{jobId}` (`exports:<operationId>`, 05 §4.2 E). Returning it is NEW (80 §5 B-9): today the command returns `()` (`:1564-1576`) and the `operationId` is read from `exports.state` (`:483-487`). `operations.job.finished.result`: `BackupState.operation` with `kind: "result"`; a failed or cancelled import stays data there (`outcome`).
- **Events:** `operations.job.progress` with `source: "backup"` (`BackupState.operation` while running, with `phases`); `exports.changed` on every change.
- **Cancel:** `operations.cancel {jobId}` (05 §4.2 F), routed to `cancel_backup_operation`, with today's refusal once `canCancel` is false.
- **Errors:**
  - Synchronous: name validation; "Choose the export file again."; "Another export or import is running."; journal-begin errors (`:1653-1688`).
  - As the result:
    - "The selected computer is not in this export.";
    - "Choose which computer to import from this export.";
    - "A computer named <n> already exists.";
    - "A runtime computer named <n> already exists.";
    - the identity and settings mismatch messages (`:1793-1795, 1855-1876, 1936-1951`);
    - the `BackupError` texts.
  - The detail defaults to "No computer was added. The export file was not changed." After unpacking it becomes "…Data unpacked for it may still use disk space." For an import it can't verify, "…Its imported disks were kept for recovery." (`:1096-1112, 1155-1188`).

- **Remote params:** NEW `deviceId?: string`; call through the local engine and SSH, justified by 95 A-3/A-14. Paths designate the owning engine's filesystem; returning archive bytes to a controller remains the transport probe Q5.

#### 2.2.8 exports.dismiss

- **Platforms:** both, local and remote; macOS NEW, justified by 95 A-19; archive mechanism remains Q4.
- **Kind:** command.
- **Status:** EXTENDED: tauri `dismiss_backup_operation` (`src-tauri/src/backup_controller.rs:2117-2141,2166-2190`); NEW remote exposure and macOS export-result projection (95 A-14/A-19; Q4).
- **Params:**
  - `expectedOperation`: the exact JSON of the result being dismissed;
  - `expectedOperationId?: string`.
- **Result:** `boolean`, whether it was dismissed. It never dismisses a running operation, a stale result or a mismatched result.
- **Semantics:** dismissing a failed recovery whose journal is still pending abandons that retry (E-43, `docs/SiloUI-REVIEW-REMEDIATION-PLAN.md:488`; `src-tauri/src/backup_controller.rs:2177-2190`).

- **Remote params:** NEW `deviceId?: string`; call through the local engine and SSH, justified by 95 A-3/A-14. Paths designate the owning engine's filesystem; returning archive bytes to a controller remains the transport probe Q5.

#### 2.2.9 exports.acknowledge

- **Platforms:** both, local and remote; macOS NEW, justified by 95 A-19; archive mechanism remains Q4.
- **Kind:** command.
- **Status:** EXTENDED: tauri `acknowledge_backup_result` (`src-tauri/src/backup_controller.rs:2147-2163`); NEW remote exposure and macOS export-result projection (95 A-14/A-19; Q4).
- **Params:** `expectedOperationId: string`.
- **Result:** `boolean`, whether the result was still unseen.
- **Semantics:** it marks the domain export snapshot’s upgrade-produced result as seen (`resultUnseen`); that snapshot stays until `exports.dismiss` (`src-tauri/src/backup_controller.rs:97-104`). The durable job outcome is a separate record, dropped only by `operations.job.acknowledge` after a client shows it (95 §3). Domain acknowledgement/dismissal never expires an unacknowledged job outcome.

---

- **Remote params:** NEW `deviceId?: string`; call through the local engine and SSH, justified by 95 A-3/A-14. Paths designate the owning engine's filesystem; returning archive bytes to a controller remains the transport probe Q5.

## 3. `migration.*` (launch upgrade and pre-upgrade backup)

**Scope (95 §3):** this is the sole permitted upgrade route and runs at launch before normal engine work. `migration.state` observes that launch attempt; conversion-trigger commands are retired, and failed launch upgrade recovery is a launch-time concern. Layout conversion and new field defaults are committed here once; normal reads accept only the resulting current schema. Existing launch integration is `src-tauri/src/main.rs:301-308`.

### 3.1 Facts

- **The one-time storage upgrade at launch (95 §3).**
  - Its state is `MigrationState { version, status: "scanning" | "running" | "failed" | "complete" | "not-required", stage, logs, migratedCount, failedCount, totalCount, canContinue, logPath?, error? }` (`src-tauri/src/runtime_migration.rs:80-95, 156-160`; UI `src/desktop/runtime-migration-boundary.tsx:14-24`).
  - It is saved in `runtime-migration.json`. The generation in use is `runtime-generation.json`, pointing at `runtime-checkpoints-converted` or `runtime-checkpoints-clean` (`src-tauri/src/runtime_migration.rs:16-20`).
- **Until the migration ends, nothing runtime runs.** Every runtime use is refused until `complete` or `not-required`, and so is every Linux checkpoint change, through E-MIGRATION (`:861-906`). macOS computers don't call this gate (no `runtime_migration` reference under `src-tauri/src/macos_computers*`).
- **When it runs.** Conversion starts automatically at launch when the status is `scanning`, after the export controller has settled its journal (`:845-859`; `src-tauri/src/main.rs:301-308`).
- **Historical restart behavior:** successful conversion and "Continue" restarted the app (`src-tauri/src/runtime_migration.rs:673-684,1069-1078`). The current API retires runtime conversion triggers; only the permitted launch upgrade can require supervisor restart (95 §3; Open question 8).
- **Vocabulary conversion is part of the permitted launch upgrade, not a runtime API.** `runtime_migration::vocabulary::run` is a one-time conversion of saved data to the current vocabulary. It runs first at startup and has no command (`src-tauri/src/main.rs:294`; `src-tauri/src/runtime_migration/vocabulary.rs:1-6, 173`).
- **The pre-upgrade backup (read/measure/delete/acknowledge remain current administrative methods, not conversion triggers; 95 §3).**
  - After a migration that converted every computer, `<app data>/runtime` is kept as a pre-upgrade backup. That holds only while the converted generation is selected and the status is `complete` (`src-tauri/src/runtime_migration.rs:1080-1090`).
  - **14-day retention.** `RETENTION` is 14 days, counted from `startedAt` in `pre-upgrade-backup.json` (`src-tauri/src/pre_upgrade_backup.rs:1-13, 43-46, 67-76, 163-169`).
  - **Deletion is checked hourly.** An hourly thread deletes the folder when it is due (`:47-49, 415-460`).
  - **Never deleted automatically when the record is unreadable** (`:11-13`).
  - **Historical "Continue" protection:** the folder was the sole copy of unconverted computers and was not offered/measured/deleted (`:6-7,52`). Preserve that data-safety refusal in launch recovery; the current API has no "Continue" conversion command (95 §3).

### 3.2 Methods

#### 3.2.1 migration.state

- **Platforms:** both. Linux-computer runtime/image adapter runs on supported Mac hosts; macOS-computer parity is NEW, justified by [95 A-19](95-decisions.md#1-owner-decisions). The VZ migration/preparation mechanism and platform result mapping are unsourced; §6 Q13 / 80 B-34 must qualify them. The cited `msb`/Linux-image behavior is not a VZ implementation.
- **Kind:** query.
- **Status:** EXTENDED: tauri `read_runtime_migration_state` (`src-tauri/src/runtime_migration.rs:966-980`); NEW macOS launch-upgrade state projection (95 A-19/§3; Q13).
- **Result:** `MigrationState`.
- **Events:** `migration.changed` on every change (today `silo://application-state-changed`, `:961, 1030`; UI subscription `src/desktop/runtime-migration-boundary.tsx:42`). NEW `MigrationState` plus envelope `seq` (justified by 95 A-4).
- **Errors:** "Migration state is unavailable." (`src-tauri/src/runtime_migration.rs:976, 979`).

#### 3.2.4 migration.preUpgradeBackup.get

- **Platforms:** both. Linux-computer runtime/image adapter runs on supported Mac hosts; macOS-computer parity is NEW, justified by [95 A-19](95-decisions.md#1-owner-decisions). The VZ migration/preparation mechanism and platform result mapping are unsourced; §6 Q13 / 80 B-34 must qualify them. The cited `msb`/Linux-image behavior is not a VZ implementation.
- **Kind:** query, cheap: it measures nothing.
- **Status:** EXTENDED: tauri `read_pre_upgrade_backup` (`src-tauri/src/pre_upgrade_backup.rs:487-494`); NEW `path` field for client reveal (00 brief, no drawing UI) and macOS pre-upgrade-backup projection (95 A-19; Q13).
- **Result:** `{ deleteAt: string | null, noticePending: boolean } | null` (`:232-262`).
  - `deleteAt` is `null` when the record can't be read.
  - The whole result is `null` when there is no backup.
- **NEW field `path: string`:** the folder that `reveal_pre_upgrade_backup` opens (`:522-541`). The reveal is UI-only, so the client needs the path to show it itself. Required by "except drawing UI" (00-brief.md).
- **Events:** `migration.preUpgradeBackup.changed` when it is deleted, by hand or after 14 days (today `silo://pre-upgrade-backup-changed`, `:50, 448-451, 515-517`; UI `src/desktop/pre-upgrade-backup.ts:13`). NEW payload carries `migration.preUpgradeBackup.get` result plus envelope `seq` (justified by 95 A-4).

#### 3.2.5 migration.preUpgradeBackup.measure

- **Platforms:** both. Linux-computer runtime/image adapter runs on supported Mac hosts; macOS-computer parity is NEW, justified by [95 A-19](95-decisions.md#1-owner-decisions). The VZ migration/preparation mechanism and platform result mapping are unsourced; §6 Q13 / 80 B-34 must qualify them. The cited `msb`/Linux-image behavior is not a VZ implementation.
- **Kind:** query, slow: it walks the folder.
- **Status:** EXTENDED: tauri `measure_pre_upgrade_backup` (`src-tauri/src/pre_upgrade_backup.rs:498-505`); NEW macOS pre-upgrade-backup measurement (95 A-19; Q13).
- **Result:** allocated bytes, or `null` once the backup is gone.
- **Errors:** "Silo could not measure the pre-upgrade backup." (`:317-327`).

#### 3.2.6 migration.preUpgradeBackup.delete

- **Platforms:** both. Linux-computer runtime/image adapter runs on supported Mac hosts; macOS-computer parity is NEW, justified by [95 A-19](95-decisions.md#1-owner-decisions). The VZ migration/preparation mechanism and platform result mapping are unsourced; §6 Q13 / 80 B-34 must qualify them. The cited `msb`/Linux-image behavior is not a VZ implementation.
- **Kind:** command.
- **Status:** EXTENDED: tauri `delete_pre_upgrade_backup` (`src-tauri/src/pre_upgrade_backup.rs:508-520`); NEW macOS pre-upgrade-backup deletion (95 A-19; Q13).
- **Errors:**
  - `NOT_A_BACKUP`, `IN_USE`, `REDIRECTED`, `UNINSPECTABLE` (`:52-56`).
  - "A converted computer's image still reads files from the pre-upgrade backup, so Silo kept it…" or "…could not check… so it kept it…" (`:329-348`).
  - "Silo could not finish deleting the pre-upgrade backup: … Your computers were not affected. Try again." (`:389-413`).
  - The blocking failure "The pre-upgrade backup could not be read. Relaunch Silo and retry." (`:476-483`).
- **Semantics:** one deletion runs at a time. Historical deletion also cleaned the previous runtime’s alias symlink (`:59-61,350-388`); that legacy cleanup belongs only to the one-time launch upgrade, and no old-runtime alias path is consulted by this method (95 §3).

#### 3.2.7 migration.preUpgradeBackup.acknowledgeNotice

- **Platforms:** both. Linux-computer runtime/image adapter runs on supported Mac hosts; macOS-computer parity is NEW, justified by [95 A-19](95-decisions.md#1-owner-decisions). The VZ migration/preparation mechanism and platform result mapping are unsourced; §6 Q13 / 80 B-34 must qualify them. The cited `msb`/Linux-image behavior is not a VZ implementation.
- **Kind:** command.
- **Status:** EXTENDED: tauri `acknowledge_pre_upgrade_backup_notice` (`src-tauri/src/pre_upgrade_backup.rs:544-552`); NEW macOS pre-upgrade-backup notice acknowledgement (95 A-19; Q13).
- **Semantics:** the migration screen has told the user about the backup.

---

## 4. `preparation.*` and `device.*`

### 4.1 Facts

- **What gets prepared.** At launch Silo prepares two things in the background, without the operation gate (`docs/SiloUI-PREPARATION.md` "Background preparation", "Behavior"):
  1. **The Linux guest image.** Downloaded on first use (about 400 MiB), verified by size and SHA-256 against `guest-image/image-lock.json`, published read-only at `<app data>/guest-image/<version>/image.tar.gz`, then imported with `msb image load` (`docs/SiloUI-GUEST-IMAGES.md` "Download on first use"; `src-tauri/src/preparation.rs:266-323`).
     - **Nothing is downloaded** when the runtime cache already holds the pinned image (`guest_image::is_imported_as`, `src-tauri/src/preparation.rs:271-283`).
     - **Messages:** "Silo could not download the VM image. Check your network connection, then retry."; "…is no longer available at its pinned location. Update Silo."; "Free at least N MiB to prepare Silo's VM image, then retry."; "…did not match its checksum and was removed. Retry." (`docs/SiloUI-GUEST-IMAGES.md` "Download on first use", Messages; `src-tauri/src/preparation.rs:494, 541`; `src-tauri/src/guest_image.rs:239`).
  2. **The LCU archive.** Pinned in `src-tauri/guest/lcu-lock.json` for the guest architecture, verified by SHA-256 and published read-only at `<app data>/lcu/<version>/<archive>`, mode 0444 inside 0555 (`docs/SiloUI-PREPARATION.md` "LCU storage"; `src-tauri/src/preparation.rs:28, 330-353`).
- **Who waits for it.** Actions that need an item join the run already in flight, or start one (`ensure_image`, `ensure_lcu`). A creation waits for the image before it takes the gate (`docs/SiloUI-GUEST-IMAGES.md` "Download on first use", When).
- **Remote devices prepare their own copies.** A remote creation waits on the owner's preparation (same doc, "Remote computers"). There is no preparation method over the bridge (`src-tauri/src/remote.rs:236-271`).
- **The ChatGPT for Linux app** has its own worker and status (`src-tauri/src/preparation.rs:6`; `docs/SiloUI-CHATGPT-APP.md` "Behavior").
  - Every device downloads the pinned `.deb` from OpenAI by itself, with no consent step, and keeps one read-only copy that its computers mount.
  - It is reachable remotely through the bridge methods `chatgpt.status` (Read) and `chatgpt.retry` (Change) (`src-tauri/src/remote.rs:247-248`; owner `src-tauri/src/remote_access.rs:43-46`).
  - **Naming.** These go under `preparation.*` here, as `preparation.chatgpt.status` and `preparation.chatgpt.retry`, with the event `preparation.chatgpt.changed`. This section owns them; 40's former `computerUse.app.status` / `computerUse.app.retry` no longer exist (80 §2 N5).

#### Engine behaviour: unused ChatGPT app versions are removed

- **Status:** EXISTS, internal. No command, event or bridge method; the callers are the
  worker's ready hook and the automatic startup path (`src-tauri/src/chatgpt_app.rs:2042-2054,
  2196-2200, 2225-2227`).
- **Platforms:** host-level on each device, protecting running Linux computers
  (`src-tauri/src/chatgpt_app/auto.rs:3-4`; `src-tauri/src/chatgpt_app.rs:2056-2066`).
- **What it removes:** stale `.staging-*` under the storage root and `published/`;
  unpinned `published/<version>-<debarch>` folders and their publication records;
  records of unpinned versions even when their folder is gone; and downloads whose
  names do not begin with `chatgpt_<pinned version>_<arch>.deb`. This collection path
  passes an empty `in_use` set (`src-tauri/src/chatgpt_app.rs:1875-1922, 2125-2128`).
- **When:** at startup immediately after the first status read, and after the worker
  publishes the pinned version (`src-tauri/src/chatgpt_app.rs:2196-2200, 2225-2227`;
  `docs/SiloUI-CHATGPT-APP.md` "Behavior", lines 59-64).
- **Preconditions:** checked inside the device-wide operation gate, taken through hidden
  try-admission `try_device_hidden("Removing unused ChatGPT app versions")`
  (`src-tauri/src/chatgpt_app.rs:2110-2128`;
  `src-tauri/src/runtime/operation_gate.rs:912-917`).
  - No Linux computer may be running (`src-tauri/src/chatgpt_app.rs:2063-2065`;
    `src-tauri/src/runtime/update_recovery.rs:176-183`). All computers mount the whole
    `published/` folder, and a running guest may still use its previous version until
    its next boot sync (`docs/SiloUI-CHATGPT-APP.md` "Behavior", lines 62-64).
  - The inventory and deletion share the gate used by starts, restores and resumes,
    so no computer can begin booting from a version between those steps. Other gate
    work skips the pass instead of queueing it (`src-tauri/src/chatgpt_app.rs:2028-2034`).
- **The storage lock is never awaited inside the gate.** `RootLock::try_take` skips a
  pass while a download or extraction holds the lock; waiting there would stall
  lifecycle work and Quit (`src-tauri/src/chatgpt_app.rs:1858-1874, 2036-2038`).
- **Retry:** a skipped pass stays pending. One `chatgpt-app-gc` thread retries every
  120 s until a pass runs; a pass skipped while the retry loop is ending restarts that
  loop (`src-tauri/src/chatgpt_app.rs:2040-2054, 2068-2108`).
- **Client visibility:** collection publishes no preparation status, and its hidden gate
  entry never appears in `operations.queue.changed` snapshots
  (`src-tauri/src/chatgpt_app.rs:2042-2128`;
  `src-tauri/src/runtime/operation_gate.rs:912-917`; 05 §4.2 E item 1).

### 4.2 Methods

#### 4.2.1 preparation.status

- **Platforms:** both. Linux-computer runtime/image adapter runs on supported Mac hosts; macOS-computer parity is NEW, justified by [95 A-19](95-decisions.md#1-owner-decisions). The VZ migration/preparation mechanism and platform result mapping are unsourced; §6 Q13 / 80 B-34 must qualify them. The cited `msb`/Linux-image behavior is not a VZ implementation.
- **Kind:** query.
- **Status:** EXTENDED: tauri `read_preparation_status` (`src-tauri/src/preparation.rs:355-358`); NEW macOS image/LCU preparation projection (95 A-19; Q13).
- **Result:** `PreparationStatus { image: PreparationTask, lcu: PreparationTask }` (`:49-54`; UI `src/desktop/preparation.ts:9-17`).
  - `PreparationTask { state: "pending" | "running" | "ready" | "failed", fraction: 0..100 | null, message: string | null, retryable: boolean }` (`src-tauri/src/preparation.rs:31-47`).
  - The image's `fraction` shows the download. It is `null` while the image is verified and imported (`:300-323`).
  - The LCU download is indeterminate (`docs/SiloUI-PREPARATION.md` "Behavior").
- **Events:** `preparation.changed` with the full `PreparationStatus`, as today's `silo://preparation-status`, which is **sent only to the `main` window** (`src-tauri/src/preparation.rs:27, 231-235`). The engine needs to send it to every subscribed client (§4.3).

#### 4.2.2 preparation.retry

- **Platforms:** both. Linux-computer runtime/image adapter runs on supported Mac hosts; macOS-computer parity is NEW, justified by [95 A-19](95-decisions.md#1-owner-decisions). The VZ migration/preparation mechanism and platform result mapping are unsourced; §6 Q13 / 80 B-34 must qualify them. The cited `msb`/Linux-image behavior is not a VZ implementation.
- **Kind:** command. It returns the status at once and progress follows as `preparation.changed` events (`src-tauri/src/preparation.rs:360-365, 251-266`).
- **Status:** EXTENDED: tauri `retry_preparation` (`src-tauri/src/preparation.rs:360-365`); NEW macOS image/LCU preparation retry (95 A-19; Q13).
- **Semantics:** it starts again whatever is not ready, and joins any run in flight.
- **Errors:** none at the command. Failures appear as `state: "failed"` with a `message`, for example "Preparation stopped unexpectedly. Retry." (`:104-111`). "Silo is still starting. Retry in a moment." is returned to callers of `ensure_lcu` and never stored in the task; a retry drops it and the task stays `pending` (`:263, 341-344`).

#### 4.2.3 preparation.chatgpt.status

- **Platforms:** both. Linux-computer runtime/image adapter runs on supported Mac hosts; macOS-computer parity is NEW, justified by [95 A-19](95-decisions.md#1-owner-decisions). The VZ migration/preparation mechanism and platform result mapping are unsourced; §6 Q13 / 80 B-34 must qualify them. The cited `msb`/Linux-image behavior is not a VZ implementation.
- **Kind:** query.
- **Status:** EXTENDED: tauri `chatgpt_app_status` (`src-tauri/src/chatgpt_app.rs:2318-2330`), bridge `chatgpt.status` (`src-tauri/src/remote.rs:247`); NEW macOS app-preparation status projection (95 A-19; Q13). Existing adapters:
  - EXISTS, tauri `chatgpt_app_status` (`src-tauri/src/chatgpt_app.rs:2315-2330`).
  - Bridge `chatgpt.status` (`src-tauri/src/remote.rs:247`).
  - On the wire between engines, only `preparation.chatgpt.status` is accepted; the historical `chatgpt.status` name is dropped (95 §3).
  - Owned here; it replaces 40's former `computerUse.app.status` (80 §2 N5).
- **Params:** `deviceId?: string` (80 §2 N5, N16; the Tauri command's param is named `device`). Omitted means this device. A UUID means that device; anything else is "Invalid device." (`src-tauri/src/chatgpt_app.rs:2241-2247`).
- **Result:** `Status`, tagged by `state` (`:186-210`):
  - `idle`;
  - `downloading { receivedBytes, totalBytes }`;
  - `verifying`;
  - `extracting`;
  - `ready { path, version }`;
  - `failed { reason, retryable }`;
  - Historical remote `{ state: "unknown" }` version fallback (`:2284-2312`) is dropped from the current contract; clients/engines require the current schema and integration (95 §3).
- **Events:** `preparation.chatgpt.changed` for this device, with the status as today (§4.3).
- **Errors:** "Invalid device."; "Update Silo on that device to use computer use."; "Could not encode the ChatGPT app status."; "The ChatGPT app task stopped unexpectedly."; bridge errors (`:2245, 2260, 2271-2283`).

#### 4.2.4 preparation.chatgpt.retry

- **Platforms:** both. Linux-computer runtime/image adapter runs on supported Mac hosts; macOS-computer parity is NEW, justified by [95 A-19](95-decisions.md#1-owner-decisions). The VZ migration/preparation mechanism and platform result mapping are unsourced; §6 Q13 / 80 B-34 must qualify them. The cited `msb`/Linux-image behavior is not a VZ implementation.
- **Kind:** command.
  - It wakes the worker and returns the status at once (`src-tauri/src/chatgpt_app.rs:2212-2222, 2332-2343`).
  - Progress follows as `preparation.chatgpt.changed` events (local; today `chatgpt-app-status`) or later status reads.
- **Status:** EXTENDED: tauri `chatgpt_app_retry` (`src-tauri/src/chatgpt_app.rs:2335-2343`), bridge `chatgpt.retry` (`src-tauri/src/remote.rs:248`); NEW macOS app-preparation retry (95 A-19; Q13). Owned here; it replaces 40’s former `computerUse.app.retry` proposal (80 §2 N5).
- **Params:** `deviceId?: string`, as in §4.2.3 (the Tauri command's param is named `device`, `src-tauri/src/chatgpt_app.rs:2334-2340`).

#### Engine behaviour: automatic ChatGPT app preparation

- **Status:** EXISTS, internal. `computer_use::install` starts `start_automatic` on a
  background thread (`src-tauri/src/computer_use.rs:1732-1743`;
  `src-tauri/src/chatgpt_app.rs:2223-2238`).
- **At startup:** read the status (the first full digest in the process), collect unused
  versions (§4.1), then reconcile computer use in running computers and stop if the
  pinned version is published. Otherwise wait 10 s and start the worker
  (`src-tauri/src/chatgpt_app.rs:2223-2238`;
  `src-tauri/src/chatgpt_app/auto.rs:13-14`).
- **One worker per process:** a second start wakes the running worker rather than
  starting another. `PREPARING` covers a second preparation caller in the process;
  `ensure` also takes a cross-process `flock` on `<root>/.lock`
  (`src-tauri/src/chatgpt_app/auto.rs:59-107`;
  `src-tauri/src/chatgpt_app.rs:2142-2154, 2177-2180`;
  `docs/SiloUI-CHATGPT-APP.md` "Behavior", lines 26-27).
- **Priority:** utility QoS on the Mac host; unpacking tools inherit it. The historical Linux-host nice-10 branch is retired (95 §3)
  (`src-tauri/src/chatgpt_app/auto.rs:138-152`;
  `src-tauri/src/chatgpt_app.rs:2182-2185`).
- **Schedule:**
  - Ready: run the ready hook once and stop. It applies computer use in running Linux
    computers and collects unused app versions (`src-tauri/src/chatgpt_app/auto.rs:27-40`;
    `src-tauri/src/chatgpt_app.rs:2196-2200`).
  - Non-retryable failure, such as a hash mismatch or a pinned version OpenAI no longer
    serves: stop (`src-tauri/src/chatgpt_app/auto.rs:42-46`).
  - Retryable failure, including network, firewall, disk space or another run in
    progress: wait 30 s, 1 min, 2 min, 5 min, 10 min, 30 min, then hourly and try again.
    The failure stays the reported status during the wait
    (`src-tauri/src/chatgpt_app/auto.rs:16-25, 47-53`;
    `docs/SiloUI-CHATGPT-APP.md` "Automatic preparation", lines 168-172).
- **`preparation.chatgpt.retry`:** wakes a waiting worker and resets the schedule's
  failure count; if no worker runs and the app is not ready, it starts one. A Retry
  racing a terminal failure either keeps that worker running or claims its successor
  (`src-tauri/src/chatgpt_app/auto.rs:51-53, 64-81, 123-135`;
  `src-tauri/src/chatgpt_app.rs:2212-2222`).
- **Nothing waits for the download:** creation, start and restore need only the possibly
  empty `published/` folder (`docs/SiloUI-CHATGPT-APP.md` "Automatic preparation",
  lines 175-180).

#### 4.2.5 device.dependencies

- **Kind:** query, slow. Three groups run one after another, each under its own budget: system 4 s, MicroSandbox 15 s, Git 10 s. A group that times out runs once more with a fresh budget, so a report can take up to about 58 s (`src-tauri/src/dependencies.rs:21-25, 1211-1257`). The UI gives up at 60 s (`src/desktop/dependencies.ts:65-70`).
- **Platforms:** Mac hosts only (95 §3), serving both computer kinds.
- **Status:** EXISTS (renamed): tauri `read_dependencies` (`src-tauri/src/dependencies.rs:1259-1293`); re-expose the existing Mac-host dependency report as `device.dependencies`. Retired Linux-host branches are removed by 95 §3; no NEW Mac-host behavior is added. No bridge method exists today.
- **Params:** `requestId: string`, not blank and at most 128 bytes ("Invalid dependency-check request ID", `:1265-1267`).
- **Result:** `DependencyReport { schemaVersion, requestId, checkedAtMs, checks: [{ id, title, status: "pass" | "failed" | "unavailable" | "timeout", detail, remediation }] }` (`:73-99`). The checks, by id:
  - `system-os` (`:591-…`);
  - `system-virtualization`:
    - on the Mac host, `sysctl kern.hv_support` = 1 (`src-tauri/src/dependencies.rs:699-760`);
    - the historical Linux-host `/dev/kvm`/`KVM_CREATE_VM` branch (`:762-843`) is retired and absent from the result contract (95 §3);
  - `runtime-microsandbox`: the bundled `msb` signature on the Mac host, its manifest and its version (`src-tauri/src/dependencies.rs:845-995`); the historical Linux-host executable-hash branch is retired from the result contract (95 §3);
  - `tool-git`, `tool-git-lfs`: the bundled Git and Git LFS (`:996-1203`).
- **Errors:**
  - "Silo could not locate its bundled tools." and "…bundled resources." (`src-tauri/src/bundled_tools.rs:6-16`).
  - "Silo resource directory is unavailable: …" (`src-tauri/src/dependencies.rs:1269-1272`).
  - "Dependency checks could not run: …" (`:1290`).
- **Note:** the macOS-computer "unsupported" reason (Apple silicon, the engine's own check) is part of the `MacosComputersState` that `computers.list` returns as its `macos` member (80 §2 N1), not this report (`src-tauri/src/macos_computers.rs:651-657`).

### 4.3 Events in these domains

Names are the ones of 05's [event catalogue](05-engine-architecture.md#event-catalogue) (80 §2 N15). Clients receive them through `events.subscribe` (05 §4.2 D).

| Event (today) | Payload today | Emitted by | API event |
| --- | --- | --- | --- |
| `silo://application-state-changed` (Linux checkpoint sites) | none | `src-tauri/src/runtime/checkpoints.rs:804, 1797, 2208, 2493, 2768` | `checkpoints.changed`. NEW computer/checkpoint state and `checkpoints.usage` results plus envelope `seq` (justified by 95 A-4; §1.1) |
| `silo://application-state-changed` (export controller) | none | `src-tauri/src/backup_controller.rs:411-414` | `exports.changed`. NEW `BackupState` plus envelope `seq` (justified by 95 A-4). Running progress is also `operations.job.progress` with `source: "backup"` |
| `silo://application-state-changed` (migration) | none | `src-tauri/src/runtime_migration.rs:961, 1030` | `migration.changed`. NEW `MigrationState` plus envelope `seq` (justified by 95 A-4) |
| `silo://macos-computers-changed` | `MacosComputersState` (with `checkpoints`, `checkpointOperation`, `pendingRestore` per computer) | `src-tauri/src/macos_computers.rs:50, 667-669` | the macOS part of `computers.changed`, which keeps its payload (owned by 10); the progress of a macOS checkpoint job is `operations.job.progress` with `source: "macos"` |
| `silo://preparation-status` | `PreparationStatus` | `src-tauri/src/preparation.rs:27, 231-235` (main window only) | `preparation.changed`, with `PreparationStatus` as today |
| `chatgpt-app-status` | `Status` plus `device: null` | `src-tauri/src/chatgpt_app.rs:79, 1967-1987` | `preparation.chatgpt.changed`, with the status as today |
| `silo://pre-upgrade-backup-changed` | none | `src-tauri/src/pre_upgrade_backup.rs:50, 450, 516` | `migration.preUpgradeBackup.changed`. NEW `migration.preUpgradeBackup.get` result plus envelope `seq` (justified by 95 A-4) |
| `silo://operation-queue-changed` | none | `src-tauri/src/main.rs:298-300` | `operations.queue.changed`, owned by `operations.*` (10 §6); the queue shows both Linux and NEW macOS checkpoint/export work (95 A-31/§3) |
| none: today the commands return | — | — | `operations.job.finished` ends every job of this section, with the `result` each method gives (05 §4.2 E item 5) |

---

## 5. Coverage table

Every historical row maps to its canonical API method or event, or "UI-only, not in API" with its reason. Jobs follow 05 §4.2 E; their id space is in the Note.

| Current surface | Kind | API method | Note |
| --- | --- | --- | --- |
| `runtime::checkpoints::create_checkpoint` | tauri | `checkpoints.create` (Linux) | job `job:<n>`, gate kind `checkpointCapture`; result gains `checkpoint` (NEW, §1.4) |
| `runtime::checkpoints::fork_checkpoint` | tauri | `checkpoints.fork` (Linux) | job `job:<n>`, gate kind `checkpointFork` (two entries in turn) |
| `runtime::checkpoints::restore_checkpoint` | tauri | `checkpoints.restore` (Linux) | job `job:<n>`, gate kind `checkpointRestore` |
| `runtime::checkpoints::delete_checkpoint` | tauri | `checkpoints.delete` (Linux) | job `job:<n>`, gate kind `checkpointDelete` |
| `runtime::checkpoints::abandon_restore` | tauri | `checkpoints.abandonRestore` (Linux) | job `job:<n>`, gate kind `checkpointRestore` |
| `runtime::checkpoints::read_checkpoint_usage` | tauri | `checkpoints.usage` (Linux) | query |
| `macos_computers::create_macos_checkpoint` | tauri | `checkpoints.create` (macOS) | job `job:<n>`, progress `source: "macos"`; waiting entries support Cancel, running unsupported cancellation returns `NotCancellable` (95 A-31/§3) |
| `macos_computers::restore_macos_checkpoint` | tauri | `checkpoints.restore` (macOS) | job `job:<n>`, progress `source: "macos"`; waiting entries support Cancel, running unsupported cancellation returns `NotCancellable` (95 A-31/§3) |
| `macos_computers::fork_macos_checkpoint` | tauri | `checkpoints.fork` (macOS) | job `job:<n>`, progress `source: "macos"`; waiting entries support Cancel, running unsupported cancellation returns `NotCancellable` (95 A-31/§3); includes personalization |
| `macos_computers::delete_macos_checkpoint` | tauri | `checkpoints.delete` (macOS) | job `job:<n>`, progress `source: "macos"`; waiting entries support Cancel, running unsupported cancellation returns `NotCancellable` (95 A-31/§3) |
| `remote::remote_checkpoint_action` action=`create` | tauri | `checkpoints.create` with `deviceId` | Controller-side wrapper (§1.3) |
| `remote::remote_checkpoint_action` action=`fork` | tauri | `checkpoints.fork` with `deviceId` | Controller-side wrapper (§1.3) |
| `remote::remote_checkpoint_action` action=`restore` | tauri | `checkpoints.restore` with `deviceId` | Controller-side wrapper (§1.3) |
| `checkpoint.create` | bridge (Change) | Historical source → canonical `checkpoints.create` | Historical name dropped (95 §3); canonical method covers both platforms; 122-min window |
| `checkpoint.fork` | bridge (Change) | Historical source → canonical `checkpoints.fork` | Historical name dropped (95 §3); canonical method covers both platforms; 122-min window |
| `checkpoint.restore` | bridge (Change) | Historical source → canonical `checkpoints.restore` | Historical name dropped (95 §3); canonical method covers both platforms; 122-min window |
| (none) | NEW bridge | `checkpoints.delete` | Wire name = API name (80 §2 N4); §1.3 |
| (none) | NEW bridge | `checkpoints.abandonRestore` | Wire name = API name (80 §2 N4); §1.3 |
| (none) | NEW bridge | `checkpoints.usage` | Wire name = API name (80 §2 N4); §1.3 |
| (none) | NEW | `checkpoints.usage` for macOS | §1.5 |
| (none) | NEW | `checkpoints.abandonRestore` for macOS | justified by 95 A-19; §1.5; mechanism Q2 |
| `backup_controller::read_backup_state` | tauri | `exports.state` | Gains `destination` (NEW) |
| `backup_controller::choose_backup_destination` | tauri | UI-only, not in API. Its side effect is `exports.destination.set` (NEW) | Native folder dialog (`src-tauri/src/backup_controller.rs:524-529`) |
| `backup_controller::choose_backup_archive` | tauri | UI-only, not in API. The path goes to `exports.inspect` and `exports.import` | Native file dialog (`:553-560`) |
| `backup_controller::inspect_backup_archive` | tauri | `exports.inspect` | job `inspect:<requestId>` |
| `backup_controller::cancel_backup_inspection` | tauri | Historical source → canonical `operations.cancel` | `jobId: "inspect:<requestId>"` (05 §4.2 F); historical cancel name dropped (95 §3) |
| `backup_controller::reveal_backup_archive` | tauri | UI-only, not in API. The client reveals `operation.archive.archivePath` | Opens the platform file manager (`:726-728`) |
| `backup_controller::start_backup` | tauri | `exports.create` | job `exports:<BackupState.operationId>` |
| `backup_controller::start_restore` | tauri | `exports.import` | job `exports:<BackupState.operationId>`; returning it is NEW (80 §5 B-9) |
| `backup_controller::cancel_backup_operation` | tauri | Historical source → canonical `operations.cancel` | the running `exports:` job (05 §4.2 F); historical cancel name dropped (95 §3); canonical call identifies the job |
| `backup_controller::dismiss_backup_operation` | tauri | `exports.dismiss` | |
| `backup_controller::acknowledge_backup_result` | tauri | `exports.acknowledge` | |
| (none) | NEW | `exports.create` for macOS computers (and their checkpoints) | justified by 95 A-19; §2.1, §1.5; archive probe Q4 |
| (none) | NEW | `exports.import` for macOS computers | justified by 95 A-19; §2.1, §1.5; archive probe Q4 |
| (none) | NEW | every `exports.*` method with `deviceId` (remote devices) | justified by 95 A-14/A-19; §2.1; transport probe Q5 |
| `runtime_migration::read_runtime_migration_state` | tauri | `migration.state` | |
| `runtime_migration::retry_runtime_migration` | historical tauri | No runtime API: retired by 95 §3 | Conversion runs only in launch `runtime_migration` (`src-tauri/src/main.rs:301-308`); historical command evidence `runtime_migration.rs:992-1034`. |
| `runtime_migration::continue_after_migration_failure` | historical tauri | No runtime API: retired by 95 §3 | Failure recovery belongs to launch `runtime_migration` (`src-tauri/src/main.rs:301-308`); historical command evidence `runtime_migration.rs:1036-1080`. |
| `runtime_migration::vocabulary::run` | startup step, not a command | not in API | Runs before anything reads saved data (`src-tauri/src/main.rs:294`) |
| `pre_upgrade_backup::read_pre_upgrade_backup` | tauri | `migration.preUpgradeBackup.get` | Gains `path` (NEW) |
| `pre_upgrade_backup::measure_pre_upgrade_backup` | tauri | `migration.preUpgradeBackup.measure` | |
| `pre_upgrade_backup::delete_pre_upgrade_backup` | tauri | `migration.preUpgradeBackup.delete` | |
| `pre_upgrade_backup::reveal_pre_upgrade_backup` | tauri | UI-only, not in API. The client reveals `path` | Opens the platform file manager (`src-tauri/src/pre_upgrade_backup.rs:537-538`) |
| `pre_upgrade_backup::acknowledge_pre_upgrade_backup_notice` | tauri | `migration.preUpgradeBackup.acknowledgeNotice` | |
| `preparation::read_preparation_status` | tauri | `preparation.status` | |
| `preparation::retry_preparation` | tauri | `preparation.retry` | |
| `chatgpt_app::chatgpt_app_status` | tauri | `preparation.chatgpt.status` | Owned here (80 §2 N5); param `device` becomes `deviceId?` |
| `chatgpt_app::chatgpt_app_retry` | tauri | `preparation.chatgpt.retry` | Owned here (80 §2 N5); param `device` becomes `deviceId?` |
| `chatgpt.status` | bridge (Read) | Historical source → canonical `preparation.chatgpt.status` | Historical wire name dropped; canonical name only (95 §3) |
| `chatgpt.retry` | bridge (Change) | Historical source → canonical `preparation.chatgpt.retry` | Historical wire name dropped; canonical name only (95 §3) |
| `dependencies::read_dependencies` | tauri | `device.dependencies` | EXISTS (renamed) Mac-host report; Linux-host KVM/hash checks retired (95 §3). |
| `silo://application-state-changed` (Linux checkpoint sites) | event | `checkpoints.changed` | NEW full-state sequenced payload (95 A-4) |
| `silo://application-state-changed` (export controller) | event | `exports.changed` | NEW full-state sequenced payload (95 A-4); running progress is `operations.job.progress` `source: "backup"` |
| `silo://application-state-changed` (migration) | event | `migration.changed` | NEW full-state sequenced payload (95 A-4) |
| `silo://macos-computers-changed` (checkpoint fields) | event | `computers.changed` (macOS part) | Keeps its payload; checkpoint job progress is `operations.job.progress` `source: "macos"` |
| `silo://preparation-status` | event | `preparation.changed` | Keeps its payload |
| `chatgpt-app-status` | event | `preparation.chatgpt.changed` | Keeps its payload (80 §2 N5) |
| `silo://pre-upgrade-backup-changed` | event | `migration.preUpgradeBackup.changed` | NEW full-state sequenced payload (95 A-4) |
| `silo://operation-queue-changed` | event | `operations.queue.changed` | Owned by `operations.*` (10 §6) |

---

## 6. Open questions

1. **DECIDED (95 A-18):** automatic pre-run checkpoints use `kind: "automatic"`, retain 3 per computer by default, and expose count/off settings; manual records are never deleted automatically (§1.4; [95](95-decisions.md)).
2. **DECIDED (95 A-18/A-19):** the grouped checkpoint decision sets pre-run retention and requires macOS `checkpoints.abandonRestore` parity. **Mechanism probe remains:** 95 A-18 does not define “abandon” for the staging/swapping journal or pending restore; determine whether settlement or dropping pending restore preserves existing recovery invariants (80 C-8; `src-tauri/src/macos_computers/checkpoints.rs:672-710`; 80 C-3).
3. **Size breakdown for macOS, probe B-7.** APFS clones share blocks with the computer (`docs/SiloUI-MACOS-COMPUTERS.md` "Checkpoints", Create). Use the operation-level measurements in §1.4; qualify per-file private/reclaimable accounting before extending the size projection; parity is decided by 95 A-19. PARTLY: operation-level physical costs are measured in §1.4 and [macos.md Follow-up §B-7](probes/macos.md#b-7--measured-at-volume-level). Per-file private/reclaimable bytes remain OPEN; retain the existing memory-only `sizeBytes` meaning.
4. **DECIDED (95 A-19):** macOS computer/checkpoint export and import are required. **Archive mechanism probe remains (C-4):** format 4 carries only MicroSandbox snapshots (`src-tauri/src/backup.rs:20,471-502,1974-2006`); qualify representation for VZ disk, auxiliary storage, hardware model and optional memory rather than inventing format 5.
5. **DECIDED (95 A-19/A-14):** remote export/import is required through the controller's local engine (95 A-3). **Transport probe remains:** paths belong to the owning engine; qualify archive-byte transfer to/from a controller, including size/error/interrupt behavior. Existing exports are local-only (§2.1).
6. **DECIDED (95 A-18):** `checkpoints.create` returns its checkpoint for the pre-run workflow; imports return their canonical job id (05 job contract; 80 §5 B-9 (code finding, not the retired Linux-host probe)). **Unanswered result question:** 95 does not decide whether `checkpoints.fork` additionally returns the new computer id; current Linux/macOS results lack it (`src-tauri/src/runtime/checkpoints.rs:1775-1806`; `src-tauri/src/macos_computers.rs:2069-2142`). Preserve existing result until the contract is sourced.
7. **DECIDED (95 A-18/A-11):** the pre-run checkpoint policy is fixed and computer references use stable `computerId`. **Checkpoint-id question remains:** A-11 does not replace Linux `pendingCheckpointRestore.checkpointId`, which names a native member, not a computer (`src-tauri/src/runtime/checkpoints.rs:1946-1950,2169-2173`). 95 A-18 gives no answer; research C-3/C-8 must establish a recoverable Silo checkpoint id, especially for imports without one.
8. **DECIDED (95 A-25, amended by §3):** conversions run only at launch, with no migration job or runtime restart-trigger API. Clients reconnect/re-read after supervised launch (95 A-4; 05); completed job outcomes survive on disk until `operations.job.acknowledge` confirms they were shown (95 §3). Recovery of jobs interrupted while running remains B-37. **Launch probe remains:** qualify supervised `silod` startup/restart around the permitted upgrade, whose historical successful conversion calls `app.restart()` (`src-tauri/src/runtime_migration.rs:680-684`; launch seam `src-tauri/src/main.rs:301-308`).
9. **DECIDED (95 A-12):** platform state enums remain and host resource limits belong to device facts. **Unanswered field question:** 95 does not decide whether to expose macOS memory-checkpoint `hostBuild` in `Summary`; current Start reports disk fallback when it differs (`src-tauri/src/macos_computers/checkpoints.rs:741-762`). Keep the field unexposed until a sourced requirement chooses it (80 C-10).
10. **DECIDED (95 A-5):** replace main-window checks with peer-euid same-OS-user authorization, including settings mutation ([95](95-decisions.md); 05).
11. **DECIDED (95 A-25, amended by §3):** `migration.retry` and `migration.continueAfterFailure` are retired; launch `runtime_migration` is the sole conversion trigger (`src-tauri/src/main.rs:301-308`). No retry job, terminal job boundary, running cancel route or client-triggered conversion/restart remains. Clients observe the launch upgrade with `migration.state` and re-read after reconnect (95 A-4/§3). Other completed jobs retain durable outcomes until acknowledgement, with interrupted-running-job recovery qualified by B-37 (95 §3). Historical command behavior (`runtime_migration.rs:1019-1034,1036-1080`) is source evidence only.
12. **Implementation probe B-33 for automatic retention (95 A-18):** qualify deferred deletion when an old automatic checkpoint is pinned by lineage or pending restore, and one-time launch upgrade of durable kind/settings records. Existing safety blockers forbid forced deletion (`src-tauri/src/runtime/checkpoints.rs:2627-2645,2694-2745,2952-3090`; `src-tauri/src/macos_computers/checkpoints.rs:716-725`). The target count is decided; physical-byte cleanup under dependencies must be measured.

13. **Implementation probe B-34 for macOS migration/preparation parity (95 A-19):** qualify `migration.*` and `preparation.*` adapters and result mappings for VZ computers. The existing generation migration converts MicroSandbox storage, and ChatGPT preparation downloads/mounts a Linux `.deb` (§3.1, §4.1); these sources establish no VZ conversion or macOS application provisioning. This is mechanism research, not an open parity decision.
