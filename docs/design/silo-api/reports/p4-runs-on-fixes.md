# P4 Router “Runs on” fixes

This report records the fixes for every finding in [`p4-runs-on.review.md`](p4-runs-on.review.md) and closes the implementation gaps that do not require a live Silo guest. Each finding was fixed test-first: its regression test failed before the implementation change and passed afterward.

## Review findings

| Finding | Commit | Regression test |
| --- | --- | --- |
| Guest starts failed in the normal dispatcher because they have no local prepared peer. | `f5b2edfd` | `dispatcherRecordsGuestStartWithoutExpectingLocalPeerPreparation` |
| Retry after an uncertain admission could create a second guest message. | `ce50e740` | `guestRelayRetryReconcilesTheOriginalNonceAfterAdmissionReplyIsLost`; `guestRelayAckReadFailureRetainsTheAdmittedPayloadForRetry`; `dispatcherGuestRetryCompletesTheOriginalDecisionWithoutASecondWrite` |
| Composer form answers were written on This Mac instead of routed to the guest. | `84b8a495` | `answerFormRoutesMatchedGuestFormToTheGuestHook` |
| Local mirror refresh could overwrite authoritative guest execution state. | `f71c48a9` | `guestTurnCompletionAndIdentitySurviveLocalMirrorRefresh` |
| Turning Router off during first guest installation could leave that install enabled. | `cab4e4f0` | `disablingRouterDuringGuestInstallWaitsAndRevokesTheInstallation` |
| A stale form approval could be admitted after Router changed while guest lookup was suspended. | `0e3e87c2` | `routerOffDuringGuestAccountLookupRejectsAStaleFormApproval` |
| Session matching used a fabricated SSH alias, allowed ambiguous ownership, and rejected editable/empty-prefill cases. | `cede945d` | `desktopSessionDecodesItsActualSSHHostAlias`; `emptyPrefillsMatchAndADesktopSessionCanOnlyBeClaimedOnce`; `personCanSelectTheActualDesktopSessionAfterEditingThePrefill` |
| A project tag could start another guest session instead of matching the existing one. | `444b5631` | `aProjectTagWithAnExistingGuestSessionDoesNotStartAnotherSession` |
| Guest delivery and abort checks incorrectly depended on local Claude availability. | `3adbbaf2` | `dispatcherSendsAndChecksAbortForGuestWithoutLocalClaude` |
| Removing Fjord from a mixed guest hook entry did not persist the nested change. | `d207fb53` | `guestDisablePersistsNestedRemovalFromAMixedHookEntry` |
| A settings symlink retargeted during retry could direct writes to the old target. | `b81b75f9` | `retriesFollowTheCurrentSettingsSymlinkTarget` |
| Coalesced folder acknowledgement hints waited until the full timeout to reread the expected receipt. | `ac4b662d` | `guestRelayConsumesCoalescedFolderAcknowledgementHintsImmediately` |
| Guest form hooks could ignore termination while stdin stayed open. | `012de58f` | `guestFormHookExitsQuietlyOnTerminationWhileStdinIsHeldOpen`; `guestFormHookBoundsAnOpenStdinRead` |

## Production gaps closed without a live engine

| Gap | Commit | Test or evidence |
| --- | --- | --- |
| Production guest operations were not connected to generated Silo methods. | `8d5ff81e` | `generatedGuestClientAdaptsGuestCallsAndWatches` |
| Saved guest targets and execution state did not rehydrate with their watches after launch. | `8d5ff81e` | `launchRehydratesSavedGuestTargetsAndExecutionState` |
| Placement inventories did not preserve owner identity for duplicate computer IDs. | `5012a232` | `placementInventoriesKeepDuplicateComputerIdsScopedToTheirOwners` |
| Guest transcript reads lacked stable-tail caching and replacement/shrink invalidation. | `084acb7e` | `guestTranscriptCacheReusesStableTailAndInvalidatesOnReplacementAndShrink` |
| Guest background task state did not read the guest fd table. | `fce5bbf3` | `guestBackgroundCommandTasksUseTheGuestFdTable` |
| Guest installation required Node to be preinstalled; computer deletion lacked durable SSH settings and engine alias cleanup. | `61849cd2` | `guestInstallerProvisionsPinnedOfficialNodeWhenNodeIsMissing`; `computerDeletionCleansRouterAliasesBeforeDeleteAndFinalizesAfterSuccess`; `guestAliasCleanupRetriesAfterEngineReconnectAndCleansDesktopSettings` |
| Guest transcript source and RepoWorld routing needed qualification. | `61849cd2` | `guestTurnCompletionAndIdentitySurviveLocalMirrorRefresh`; `notificationRepoWorldIncludesMatchedGuestSessionThroughItsSourceProject` |
| Remote placement needed a dedicated Runs on popover capture. | `61849cd2` | Offscreen `--window-shots` capture: [`p4-runs-on-placement-popover.png`](p4-runs-on-placement-popover.png) |

The production adapter is `SiloGuestClient`; it maps generated guest account, exec, file, watch, alias, event, and background-job calls. The mock remains the in-process test adapter. Runtime provisioning pins Node.js `24.21.0`; the version and per-platform SHA-256 values in `GuestNodeRuntime.swift` were checked against the [official Node.js release archive](https://nodejs.org/en/download/archive/v24.21.0) and its [official SHA-256 manifest](https://nodejs.org/download/release/v24.21.0/SHASUMS256.txt). Provisioning downloads and verifies the archive on the guest, stages the new runtime, and restores the previous runtime if installation fails.

## Remaining live-engine gate

No live Silo guest was available for end-to-end validation of installation, form delivery, guest transcript updates, and reconnect behavior. That remains the release gate. The focused tests above exercise those boundaries through the mock and generated-client fake; they do not substitute for a live guest run.

## Final verification

- `swift build` passed. SwiftPM warned that six existing fixture JSON files are unhandled resources.
- `scripts/test.sh` was invoked once after the build. After about six minutes, its log contained 1,628 passing test cases across 160 completed suites and no reported test failures. Two suites (`RouterMCP` and `GuestRouterTests`) had started without completion, and the required `Test run with … tests passed` summary was absent. The test helper was still alive in the app's main run loop, so I terminated that invocation; the script exited 1. This is an incomplete full-suite run, not a clean suite pass, and it was not rerun.
- The script replaced the contents of the pre-existing untracked `test.log` with this run's output. It remains untracked and was not staged; I did not preserve the previous contents.
