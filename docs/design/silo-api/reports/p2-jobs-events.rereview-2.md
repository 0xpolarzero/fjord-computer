Reviewed `aac4a98c..67695ea1` read-only. No tests rerun; regression judgments below come from test-source inspection.

| Item | Status | Does the regression catch it? |
|---|---|---|
| Remaining #5: completion persistence | **FIXED** | Yes for live completion: forces SQLite failure, checks admission suspension, retries the retained result, then checks admission resumes. |
| Remaining #11: Tauri notifications | **FIXED** | Partial. Tests check native delivery/withdrawal helpers, but miss RuntimeHost miswiring or an added toast event. Production routing matches main. |
| Additional P1 #1: predecessor result under successor ID | **FIXED** | Yes for the wrong journal lookup. It misses replacement of the entire view. |
| Additional P1 #2: push startup conflict | **FIXED** | Yes. Durable success/error regressions preserve registry outcomes and require successful reconciliation. |
| P2 #4: progress after finish | **NOT FIXED** | Partial. Lifecycle regression catches stale progress; checkpoint cleanup remains racy. |
| P3 #5: backlog byte accounting | **FIXED** | Yes. Tests compare serialized envelope bytes, exact-limit admission, one-byte overflow, escaping, and sequence widths. |

Additional findings and the remaining race:

- **P1: A successor can erase its predecessor’s unpublished result.** Export releases `busy` before publication at [backup_controller.rs:1286](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/engine/src/backup_controller.rs:1286); import does likewise at [line 1984](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/engine/src/backup_controller.rs:1984). Pause A there, let B replace both journal and view, then resume A. A publishes B’s progress; A remains `Running`, with its result lost. The identity regression preserves A’s view and misses this schedule.

- **P2: Startup recovery cannot replace interrupted backup/import placeholders.** Recovery now reaches `publish_finished` at [backup_controller.rs:574](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/engine/src/backup_controller.rs:574), which rejects the registry’s restart placeholder at [registry.rs:377](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/engine/src/jobs/registry.rs:377). The recovered result reaches the journal, but `job.get` keeps the generic interrupted error. The persistence regression never reopens and resumes an operation.

- **P2, remaining #4: Checkpoint progress can follow finish.** [macos_computers.rs:1263](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/engine/src/macos_computers.rs:1263) removes the pending-completion guard after releasing the publication lock, before removing the active checkpoint mapping. Stale progress resumed between those removals passes the active check and publishes after finish. The lifecycle-only regression misses it.

No further P1/P2 found in push reconciliation or backlog accounting.

**Merge verdict: DO NOT MERGE. Fix these three gaps and add deterministic regressions.**