Reviewed the five requested commits at `a6cb55ba`, excluding `dbe4cc77`. Read-only: no files changed, tests run, or computers started. Locations below are under `app/SiloUI/src-tauri/`.

1. **P1 — Abort and rollback can replay a guest over advanced disks.**  
   `engine/src/engine_update/transaction.rs:363` resumes the original guest before recording `Resumed`; rollback does the same at `:212`. A crash between resume and journal commit leaves a retryable capture. macOS recovery then replaces the advanced disks with captured disks and replays memory. Linux does likewise if the resumed runtime subsequently stops or crashes.  
   **Fix:** persist an armed transition before every resume, including original-generation resumes; retain its disk and generation identity. Add crash tests for abort and partial-save rollback.

2. **P1 — Failed recovery reopens ordinary operations over unresolved saved state.**  
   `engine/src/engine_update/mod.rs:348` ends the hold even when recovery fails. Failed preparation also ends it at `silod/src/methods/services.rs:385`, then clears preparation state at `:409`. The guards reopen admission; `updatePending` does not protect computer operations. A user can cold-start, modify, or delete a computer whose capture remains retryable.  
   **Fix:** reserve unresolved computer IDs and their configuration until recovery settles; project pending state after failed preparation. Test start, delete, and configuration changes against retained captures.

3. **P1 — Linux recovery deletes the original sandbox before validating recovery inputs.**  
   `engine/src/runtime/update_save.rs:455` removes a stopped/crashed sandbox before checking snapshot availability, configuration, and checkpoint metadata at `:475–486`. Missing or unreadable recovery inputs therefore destroy the original disk before reporting failure.  
   **Fix:** validate first and preserve the original working disk until restoration succeeds. Test a crashed sandbox with a missing capture and assert that removal never occurs.

4. **P1 — Failed macOS restore falsely reports storage ownership as released.**  
   `engine/src/macos_computers/update_save.rs:209` passes unconditional `Ok(())` to `settle_failed_start`. Cleanup at `:366` and `:374` ignores force-stop errors and does not await release. A retained VM can still own storage while the registry reports `Stopped`.  
   **Fix:** use the existing `ensure_released` seam and pass its actual outcome, retaining `Stopping` until release is proved. Test refused and delayed framework stops.

5. **P1 — A prepared macOS capture lacks durable ancestor-directory creation.**  
   `engine/src/macos_computers/update_save.rs:388` creates `update-saves/<transaction>` recursively, but `:414` syncs only the innermost directory. The new entries in its parent directories are not synced before the separate engine journal records `Saved`. Power loss can preserve the journal while losing the capture path.  
   **Fix:** sync newly created directory ancestors before committing capture references; verify filesystem-operation ordering.

6. **P2 — Abort cannot recover macOS computers after a failed release-stage shutdown.**  
   `engine/src/macos_computers/update_save.rs:159` retains the paused VM until process exit, while `engine/src/engine_update/transaction.rs:307` records `Released`. If a later journal write or settings flush fails, abort selects `Restore` at `:546`; `begin_restore` refuses the original, still-owned computer.  
   **Fix:** attempt generation-checked `resume_held` for released entries when the original remains owned; restore only when it is gone. Test release followed by journal or flush failure.

7. **P2 — Real recovery probes do not prove the journaled generation or attempt resumed.**  
   `engine/src/runtime/update_save.rs:125` and `engine/src/macos_computers/update_save.rs:216` ignore the attempt ID and accept a running computer with the same computer ID. Linux also omits the available runtime-instance identity. A replacement run can settle the wrong capture and trigger its deletion.  
   **Fix:** persist original runtime identity and active restore identity, propagate the journal attempt ID, and require exact matches in release/resume/probe.

8. **P2 — Coordinator death leaves computers held indefinitely; startup ignores installer ownership.**  
   `silod/src/methods/services.rs:393` retains preparation without the specified watchdog. `engine/src/engine_update/mod.rs:346` also restores unconditionally on restart, without reconciling installer ownership. A dead caller leaves guests paused indefinitely; an old engine restart can resume them during an active handoff.  
   **Fix:** implement installer-lock reconciliation and the specified five-second probe/30-second abandoned-preparation abort, serialized with shutdown.

9. **P2 — SIGTERM does not enforce the session-end deadline.**  
   `engine/src/engine_update/mod.rs:400` only sets `session_ending` when attaching to an existing shutdown; `:498` still derives the deadline from the original request. Fresh session-end shutdown also reaches unbounded gate/release waits and Linux stop commands without the overall deadline. OS termination can interrupt this work instead of completing the bounded shutdown.  
   **Fix:** store the earliest absolute deadline and propagate it through active work, gate acquisition, runtime commands, release, and finalization. Test blocked operations and SIGTERM escalation.

10. **P2 — Legacy onboarding drafts turn successful settings writes into errors.**  
    `silod/src/methods/services.rs:157` converts raw update/flush snapshots into the canonical type without clearing the retained draft. `read(false)` clears it, but update and flush do not. With a valid legacy draft, a preference can persist before the response fails, and `settings.changed` is absent.  
    **Fix:** apply the existing public-settings projection before canonical conversion. Test update and flush with a legacy settings document containing a draft.

The current crash tests miss abort/rollback execution boundaries and actual storage persistence. Their fake macOS release destroys the VM immediately, unlike production, and their fake probe validates attempt IDs more strictly than production. Real Linux hold/flush/full-snapshot continuity and macOS replacement/rollback remain unqualified.

I found no defect in checkpoint-count validation or implemented socket-level `engine.disconnect` isolation. Viewer cleanup and accepted-job survival still need concurrent disconnect coverage.

**Next action:** fix the original-resume journal boundary in finding 1.