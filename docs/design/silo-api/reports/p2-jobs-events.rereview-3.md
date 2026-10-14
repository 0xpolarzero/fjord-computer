| Gap | Status |
|---|---|
| Successor erases predecessor’s unpublished result | **FIXED**: export, import, recovery, and panic paths publish before releasing `busy`. |
| Startup recovery cannot replace restart placeholders | **FIXED**: registry completion now replaces tagged placeholders. |
| Checkpoint progress follows finish | **FIXED**: publication and both guard removals share the progress lock. |

New findings:

- **P2: Failed recovery publishes a stale running snapshot.** [backup_controller.rs:1072](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/engine/src/backup_controller.rs:1072) publishes while `busy=true`. When recovery fails or result persistence leaves the journal pending, `backup_state` substitutes the journal’s `Running` operation and reports availability as available. `finish` releases `busy` without another event, leaving `exports.changed` subscribers with the wrong state. This also affects panic recovery with pending cleanup.

- **P2: A transient recovery failure becomes immutable.** [registry.rs:384](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/engine/src/jobs/registry.rs:384) clears `recovery_placeholder` even when recovery publishes a failure while retaining a pending journal. After relaunch, successful recovery produces a different outcome that the registry rejects. `job.get` retains the transient failure; a subsequent launch with the settled journal also fails startup reconciliation.

No new deadlock or lock-order inversion found in the touched paths, including panic publication and checkpoint cleanup. Source review only; tests not rerun.

**Merge verdict: DO NOT MERGE. Fix the two recovery regressions and add deterministic coverage.**