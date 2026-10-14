# P4 triage computers fixes

All 18 findings are fixed on `main`. Each listed regression was added before its implementation and observed failing first. The guest supervisor tests launch the real `Resources/GuestRuns/run.mjs`; the clone and branch tests use real Git repositories in temporary directories.

## Upstream API needs

1. **macOS resource edits:** add a generated `macosResources` variant to `computers.configuration.change`. It needs `computerId`, the displayed baseline as `expected: { cpus, memoryGiB, diskGiB }`, the new `cpus` and `memoryGiB` values, and the normal `requestId`. Fjord disables macOS resource editing and shows “Coming soon” until the generated client contains this contract.
2. **Owner routing for `guest.exec.get`:** add an optional top-level `deviceId?: string` to the generated method parameters. Silo must use `(deviceId, jobId)` to retrieve the owning guest's job. Fjord now persists the owner `deviceID` with each run and carries its `GuestReference` through the guest-client boundary; the generated request cannot send the owner until this field exists.

## Findings, commits, and regression tests

1. **Supervisor rejects Fjord UUIDs** — `b35303ca` (`fix: accept standard guest run UUIDs`). Test: `GuestRunSupervisorTests.standardUUIDConfigReachesClaude`.
2. **Fresh clone has no `FETCH_HEAD`** — `6771739f` (`fix: choose correct git base for run branches`). Tests: `ComputerRunGitTests.freshCloneCanCreateRunBranchFromHeadWithoutFetchHead`; `ComputerRunGitTests.fetchedCloneCanCreateRunBranchFromFetchHead`.
3. **macOS resource edit uses an unsupported wire variant** — `2e56b09a` (`fix: disable macOS resource edits until API contract exists`). Test: `ComputersTests.macosResourceEditStaysDisabledUntilTheWireContractExists`.
4. **Linux Files starts outside `/workspace`** — `bb600588` (`fix: constrain computer file browsing roots`). Tests: `ComputerFilesTests.linuxFilesStartAtWorkspaceRoot`; `ComputerFilesTests.macosFilesStayUnavailableUntilTheEngineDefinesTheirRoot`.
5. **Suspended updates overwrite newer run state** — `9d9e6200` (`fix: harden computer run recovery and ownership`). Tests: `ComputerRunTests.cancellationFinishingAfterRunCompletionKeepsTheTerminalRecord`; `ComputerRunTests.acknowledgementFinishingAfterNewerRunStatePreservesTheNewState`; `ComputerRunTests.savingAStaleTerminalRunKeepsTheNewerSummaryAndProofPath`.
6. **Rollback overlaps runs and duplicate restores** — `9d9e6200` (`fix: harden computer run recovery and ownership`). Tests: `ComputerRunTests.overlappingRollbackRequestsSubmitOnlyOneRestore`; `ComputerRunTests.loadingAPendingRollbackReservesItsTargetAgainstAnotherRestore`; `ComputerRunTests.confirmedRollbackRejectionCanBeRetried`.
7. **Restart does not reserve active run targets** — `9d9e6200` (`fix: harden computer run recovery and ownership`). Test: `ComputerRunTests.loadingAnActiveComputerRunReservesItsTarget`.
8. **Upload conflicts and data cancellations look successful** — `d49d3838` (`fix: handle file upload outcomes`). Tests: `ComputerJobOutcomeTests.uploadConflictOutcomeIsPresentedWithConflictingNames`; `ComputerJobOutcomeTests.uploadDataCancellationIsPresentedAsCancelled`; `ComputerJobOutcomeTests.uploadConflictOffersKeepBothWithTheOriginalSelection`.
9. **Successful outcomes are acknowledged before presentation** — `f75d6b8f` (`fix: retain job receipts until acknowledged`). Test: `ComputerJobReceiptTests.successfulJobIsRetainedUntilItsReceiptIsPresented`.
10. **Cancel before Claude admission has no effect** — `9d9e6200` (`fix: harden computer run recovery and ownership`). Tests: `ComputerRunTests.cancelBeforeClaudeAdmissionPersistsIntentAndCancelsCheckpointJob`; `ComputerRunTests.cancellationDuringCheckpointingPreventsClaudeAdmission`.
11. **Recorder startup failure or cancellation leaks guest processes** — `3eae18ab` (`fix: clean up guest recorder on startup cancellation`). Tests: `GuestRunSupervisorTests.recorderReadinessFailureBootsOutAndStopsTheGuestRecorder`; `GuestRunSupervisorTests.sigtermDuringRecorderStartupBootsOutAndStopsTheGuestRecorder`.
12. **Job retrieval drops the owner identity** — `9d9e6200` (`fix: harden computer run recovery and ownership`). Test: `ComputerRunTests.identicalGuestJobIDsAreRetrievedWithTheirPersistedOwners`. The generated `guest.exec.get` request still needs the top-level `deviceId?: string` field listed above.
13. **Missing Claude result is reported as success** — `9d9e6200` (`fix: harden computer run recovery and ownership`). Test: `ComputerRunTests.missingStructuredClaudeResultCannotBecomeSuccess`.
14. **Zero checkpoint retention blocks unattended runs** — `9d9e6200` (`fix: harden computer run recovery and ownership`). Test: `ComputerRunTests.zeroAutomaticCheckpointRetentionRunsWithoutCreatingCheckpoint`.
15. **Resource edit loses the displayed optimistic baseline** — `b35b50df` (`fix: reject stale computer resource edits`). Test: `ComputersTests.resourceEditPreservesACompetingConfigurationChangeDuringStop`.
16. **Viewer scripts are lost or deduplicated** — `ee238c69` (`fix: serialize computer viewer lifecycle and scripts`). Tests: `ComputerViewerTests.viewerQueuesPageScriptsUntilReadyAndExecutesIdenticalCommandsTwice`; `ComputerViewerTests.viewerPageEventsRemainOrderedAcrossCoalescedModelUpdates`.
17. **Viewer connections outlive or replace their UI owner** — `ee238c69` (`fix: serialize computer viewer lifecycle and scripts`). Tests: `ComputersTests.overlappingViewerOpensCloseTheSupersededConnection`; `ComputersTests.closingWhileViewerOpenIsPendingClosesTheLateConnection`.
18. **Long result summaries hide actions and proof work blocks the UI** — `4391ec50` (`fix: keep triage result actions visible`). Test: `ComputerRunResultShotTests.minimumHeightLongSummaryShotExercisesResultCardScrolling`. Proof movie writes and poster extraction now run away from the main actor.

## Verification

- `swift build` passed.
- Re-rendered 17 matching computer window shots into `.build/shots/p4-triage`; inspected the macOS resource state and `.build/shots/p4-triage/window-triage-computer-run-result-long-min.png`. The result actions remain visible at minimum height.
- `scripts/test.sh` passed: 1,715 tests across 170 suites.
