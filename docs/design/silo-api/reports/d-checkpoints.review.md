Found **one P1 and four P2 issues** in the reviewed changes. Read-only source review; no files changed, tests run, or apps launched. Links use current worktree line numbers.

1. **P1: Launch upgrade can delete damaged macOS checkpoints.**  
   [macos_computers/checkpoints.rs:337](/Users/polarzero/silo-work/d-checkpoints/app/SiloUI/src-tauri/engine/src/macos_computers/checkpoints.rs:337) promotes any JSON declaring schema 1 without validating required fields or folder identity. A record missing `reason` becomes schema 2, fails deserialization, and the subsequent [sweep deletes its folder and images](/Users/polarzero/silo-work/d-checkpoints/app/SiloUI/src-tauri/engine/src/macos_computers/checkpoints.rs:311). Linux similarly rewrites structurally invalid histories at [runtime/checkpoints.rs:854](/Users/polarzero/silo-work/d-checkpoints/app/SiloUI/src-tauri/engine/src/runtime/checkpoints.rs:854), contradicting the report’s preservation claim.  
   **Fix:** validate converted records before replacement; preserve invalid originals and protect them from sweep. Test missing fields, invalid enums, mismatched IDs, and upgrade followed by sweep.

2. **P2: Retention deletes using stale settings after queue admission.**  
   Both [Linux:1012](/Users/polarzero/silo-work/d-checkpoints/app/SiloUI/src-tauri/engine/src/runtime/checkpoints.rs:1012) and [macOS:1339](/Users/polarzero/silo-work/d-checkpoints/app/SiloUI/src-tauri/engine/src/macos_computers.rs:1339) check the count **before** waiting for the deletion gate. Turning retention off while queued still permits deletion. Increasing the count also leaves the original deletion plan active, deleting checkpoints the new count retains.  
   **Fix:** after admission, reread settings and records and recheck candidate eligibility. Add blocked-gate tests for zero and increased counts.

3. **P2: Linux jobs report running before admission.**  
   [checkpoints/mod.rs:423](/Users/polarzero/silo-work/d-checkpoints/app/SiloUI/src-tauri/engine/src/checkpoints/mod.rs:423) marks jobs running when the worker starts, before it waits for the operation gate. Consequently, `operations.job.get` reports running while the queue reports waiting. A persistence failure is logged and execution continues.  
   **Fix:** transition to running after successful admission, before mutation; handle transition failure. Test waiting, admission, cancellation while waiting, and failed persistence.

4. **P2: macOS automatic-off refusal loses its error code.**  
   The post-admission check at [macos_computers.rs:1990](/Users/polarzero/silo-work/d-checkpoints/app/SiloUI/src-tauri/engine/src/macos_computers.rs:1990) correctly refuses capture, but [completion:1264](/Users/polarzero/silo-work/d-checkpoints/app/SiloUI/src-tauri/engine/src/macos_computers.rs:1264) records `internal`, whereas pre-admission refusal and Linux return `permission_denied`.  
   **Fix:** preserve typed failures through completion. Test changing three to zero while capture waits, checking both the absent checkpoint and durable error code.

5. **P2: Archive inspection startup failure strands an accepted job.**  
   [exports.rs:100](/Users/polarzero/silo-work/d-checkpoints/app/SiloUI/src-tauri/silod/src/methods/checkpoints/exports.rs:100) treats registry existence as successful startup. If acceptance succeeds but `mark_running` fails, [inspection_worker returns an error without terminalizing the job](/Users/polarzero/silo-work/d-checkpoints/app/SiloUI/src-tauri/engine/src/backup_controller.rs:912). The handler discards that worker error and returns its ID, leaving a waiting job without completion.  
   **Fix:** expose startup failure explicitly and terminalize accepted jobs; inject a registry failure in a handler regression.

Retention rechecks restore dependencies under the deletion gate; I found no additional active-restore corruption race. Missing regressions cover both restore/deletion admission orders, pending Start, fork and lineage dependencies, unreadable journals, and interrupted multi-record upgrades.

macOS usage correctly avoids summing APFS clone sizes. Its [usage test:9374](/Users/polarzero/silo-work/d-checkpoints/app/SiloUI/src-tauri/engine/src/macos_computers.rs:9374) uses only a disk checkpoint, leaving memory-byte projection and empty-history zero untested.

**Next action:** fix the launch upgrade’s validation and sweep interaction first.