# P1 Fjord UI Review Fixes

All 11 findings from [p1-fjord-ui.review.md](p1-fjord-ui.review.md) are fixed on `main`. Each regression test is in `Tests/FjordTests/ComputersTests.swift`.

| # | Finding | Fix commit(s) | Regression test(s) |
|---|---|---|---|
| 1 | Normal quit reports fictional running computers | `55779d8c` `fix(computers): keep demo inventory out of production quit` | `normalQuitSkipsComputerInspectionWhenComputersAreOffOrEngineIsAbsent` |
| 2 | A refused macOS shutdown traps the quit dialog | `513b6e19` `fix(computers): recover quit after refused shutdown`; `eee7eb45` `fix(computers): stabilize quit and delete regressions` | `refusedMacosStopRestoresQuitChoicesAfterJobSuccess` |
| 3 | Shared subscriptions race with SwiftUI view lifetimes | `286d7db8` `fix(computers): serialize shared subscription lifecycle` | `overlappingActivationsAndTeardownLeaveNoLateSubscription` |
| 4 | `computers.changed` has the wrong payload shape | `5dd2b18e` `fix(computers): merge partial inventory change events` | `platformOnlyComputerEventsMergeWithoutReplacingOtherPlatform` |
| 5 | Linux deletion omits the required expected configuration | `82f8ab87` `fix(computers): require expected Linux delete configuration`; `eee7eb45` `fix(computers): stabilize quit and delete regressions` | `linuxDeleteCarriesAndEnforcesExpectedConfiguration` |
| 6 | Accepted jobs can fail without showing an error | `3054d1d5` `fix(computers): surface asynchronous job failures` | `acceptedJobFailureIsShownBeforeItIsAcknowledged` |
| 7 | Linux checkpoint changes leave the UI stale | `3d08f651` `fix(computers): consume checkpoint change events` | `completedCheckpointJobsApplyDelayedCheckpointEvents` |
| 8 | Setup progress drops contract fields | `7724db20` `fix(computers): preserve source-specific job progress`; `a212d8ce` `fix(computers): return progress presentation values`; `94ad9f65` `fix(computers): compile review regression fixtures` | `setupProgressDecodesEveryCanonicalFieldAndDrivesPresentation` |
| 9 | Missed-event recovery is absent | `30b8af33` `fix(computers): recover event gaps and retained jobs`; `e767cf03` `fix(computers): throw for unavailable void calls` | `staleComputerListResponseCannotReplaceANewerEvent`; `sequenceGapAndReconnectReReadComputerAndOperationState`; `retainedJobOutcomeIsRecoveredThroughJobGet`; `jobGetRecoversACompletionWhenTheFinishedEventIsLost` |
| 10 | Queued work has neither “Waiting…” nor Cancel | `7fff9732` `fix(computers): show and cancel queued operations` | `waitingQueueEntryRendersWithoutProgressAndCanBeCancelled` |
| 11 | Creation and fork requests fail on ordinary hosts or repeat use | `549e711c` `fix(computers): generate valid host-sized computer requests` | `creationAndForkUseUniqueValidNamesWithinSmallHostLimits` |

## Validation

- `swift build` passed on the final source tree.
- The final `scripts/test.sh` run passed: 1,594 tests in 157 suites.
- Re-rendered with `.build/debug/Fjord --window-shots .build/shots computer`. The refreshed shots are `.build/shots/window-computers.png`, `.build/shots/window-computer-queue.png`, `.build/shots/window-computer-detail.png`, and `.build/shots/window-computers-quit-dialog.png`.
- Inspected the refreshed queue shot; it shows the waiting label and Cancel action.
