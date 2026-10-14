**Merge verdict: do not merge.** Thirteen original findings are fixed; #5 and #11 remain incomplete. The review also found two P1 failures at the export and recovery seams.

Reviewed `cf35f080..71974e42`, with HEAD at `71974e42`, against current main `fc0f286f`. Read-only: no files changed, tests rerun, or apps launched. “Yes” below means the test source and existing reverted-red/restored-green logs support the regression, not an independently repeated mutation run.

| # | Finding | Status | Does its regression fail without the fix? |
|---|---|---|---|
| 1 | Upload conflict continuation | **FIXED** | **Yes.** Reused-ID assertion fails; continuation tests also check progress and cancellation ownership. Frontend mocks still bypass the real registry. |
| 2 | Push crash before initial progress | **FIXED** | **Yes.** Waiting-placeholder and unreadable-journal regressions fail. Completed-outcome/journal divergence remains uncovered below. |
| 3 | Failed macOS lifecycle recorded as success | **FIXED** | **Yes.** Snapshot completion regression fails. Tests exercise the result seam, without a live framework failure. |
| 4 | macOS effects before durable acceptance | **FIXED** | **Yes.** Reversion executes the forbidden effect; separate regressions detect premature restore recovery. |
| 5 | Completion persistence failure | **NOT FIXED** | **Yes, for normal finish paths.** Export/import completion bypasses retention and admission suspension; no regression covers that path. |
| 6 | Export cancellation reaches successor | **FIXED** | **Yes.** Stale cancellation incorrectly succeeds when reverted. Deterministic successor state substitutes for competing threads. |
| 7 | Events precede Subscribe reply | **FIXED** | **Yes, at the helper boundary.** Red observes event before reply. The original concurrent `operations.list` wire scenario remains untested. |
| 8 | Notice resync loses updates | **FIXED** | **Yes, for projection exclusion.** Full snapshot/reply/writer resync is established by source inspection, without an integrated regression. |
| 9 | Oversized outcomes cannot be retrieved | **FIXED** | **Yes.** Chunk reassembly, completion marker, and bounded-error regressions fail when reverted. |
| 10 | Generic macOS cancellation deletes creation | **FIXED** | **Yes.** Admitted cancellation incorrectly succeeds; waiting cancellation checks zero effects and durable `Cancelled`. |
| 11 | Existing Tauri toast behavior changes | **NOT FIXED** | **Yes, but the assertion enforces the bug.** It fails when the extra `silo://notice` event is removed, although main uses native-only delivery here. |
| 12 | Engine sequence and fanout disagree | **FIXED** | **Yes.** Deterministic reversion observes `[2,1]` instead of `[1,2]` across subscribers. |
| 13 | Downstream buffering escapes backlog limits | **FIXED** | **Yes.** Held downstream events retain count/byte reservations. Exact encoded-byte accounting remains approximate. |
| 14 | NotCancellable maps to `busy` | **FIXED** | **Yes.** Regression exercises the typed registry error and requires `internal`. |
| 15 | Finished jobs retain cancellation closures | **FIXED** | **Yes.** Regression observes actual closure destruction before acknowledgement. |

The fix report cites unrelated green logs for #14 and #15. Passing evidence for the named tests exists in the registry worktree’s `silod-dispatcher-suite.log` and `registry-suite.log`.

**Additional findings and remaining seams:**

1. **P1: An export can finish its successor with the predecessor’s result.** [backup_controller.rs:510](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/engine/src/backup_controller.rs:510) copies the result separately from the journal identity read at line 519. Export A releases `busy` before publication at [line 1284](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/engine/src/backup_controller.rs:1284). Pause A after copying its result; let B replace the terminal journal and register its running job; resume A. A now commits its result under `exports:B`, removing B’s cancellation handler while B continues executing. B’s eventual result conflicts with that immutable wrong outcome. No regression covers publication against successor replacement.

2. **P1: Stale push journals still prevent silod startup.** A journal completion save can fail at [host_push_operations.rs:469](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/engine/src/host_push_operations.rs:469), while SQLite successfully records completion. After restart, the stale `pushing` journal becomes `unknown`. [Startup reconciliation:558](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/engine/src/host_push_operations.rs:558) tries to replace the durable terminal outcome; [registry.rs:491](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/engine/src/jobs/registry.rs:491) rejects it, and [app.rs:120](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/silod/src/app.rs:120) propagates the error before socket binding. Repairing a journal after the new unreadable-journal recovery produces the same conflict. Existing recovery tests cover replaceable placeholders only.

3. **P1, remaining #5: Export/import completion bypasses persistence protection.** [backup_controller.rs:570](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/engine/src/backup_controller.rs:570) uses `reconcile_finished` for ordinary live completion. Its [registry path:467](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/engine/src/jobs/registry.rs:467) neither retains failed writes nor suspends admission. SQLite failure only logs; new mutations remain admitted, and `job.get` has no pending outcome to retry. The domain journal preserves the result, but the required in-process behavior remains missing.

4. **P2: Progress can arrive after terminal completion.** [macos_computers.rs:755](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/engine/src/macos_computers.rs:755) copies active jobs, then publishes after releasing their lock. A concurrent lifecycle completion can publish finish first. [registry.rs:257](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/engine/src/jobs/registry.rs:257) accepts subsequent progress as a no-op, but [jobs/mod.rs:139](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/engine/src/jobs/mod.rs:139) still publishes it. Consumers receive stale starting/stopping progress after finish. This predates the fix range; no regression covers it.

5. **P3: Backlog byte limits still undercount encoded envelopes.** [events/mod.rs:522](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/engine/src/events/mod.rs:522) adds a fixed 128-byte allowance. Normal UUID envelope overhead already exceeds that by seven bytes at sequence 1 and grows with sequence length. Reservation lifetime is corrected; exact wire-byte limits remain unverified.

**The existing Tauri events and toasts are not unchanged compared with main.** Setup progress still targets the main client; the inspected lifecycle, transfer, update, and application-refresh paths retain their legacy names and payload construction. The upload continuation intentionally changes transfer identity and toast ownership.

The notice path remains incompatible:

- [runtime.rs:159](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/src/commands/runtime.rs:159) newly emits `silo://notice` for native-only runtime notices. Lifecycle failure therefore produces both `computer:<id>:lifecycle` and `lifecycle::<id>` toasts; long successes gain persistent completion toasts.
- [runtime.rs:80](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/src/commands/runtime.rs:80) removes native delivery. The frontend handler uses `native: false`, so unfocused system notifications are lost.
- [runtime.rs:85](/Users/polarzero/silo-work/p2-jobs-events/app/SiloUI/src-tauri/src/commands/runtime.rs:85) replaces native notification withdrawal with canonical notice clearing, leaving delivered OS notifications behind.

The unnumbered adapter and retry-attachment gaps acknowledged in the fix report also remain. **Fix the persistence, successor-publication, startup, and Tauri notification failures, then add deterministic regressions before merging.**