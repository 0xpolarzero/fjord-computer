# P4 Runs on test diagnosis

## Cause

The incomplete run implicated `RouterMCP` and `GuestRouterTests`. The old `test.log` records `answerFormRoutesMatchedGuestFormToTheGuestHook()` failing because its expected guest answer file was missing. It records `routerOffDuringGuestAccountLookupRejectsAStaleFormApproval()` starting without completing.

Both paths used `GuestRouterRuntime.shared`, which holds one mutable store and a client map. Swift Testing ran the two suites concurrently, so one suite could replace the runtime's store or client while the other suite was validating or writing a guest form. In the guest regression test, that made the answer stop before calling `AccountPausingGuestClient.account(for:)`; the test then waited forever on its entry continuation. The RouterMCP test could validate or write through runtime state owned by the other test.

The standalone baseline also exposed the same leak in `aForkIsCutFromTheOriginalsTranscriptAndItsFirstMessagePrepared()`: a local session was read as a guest session after another test had populated the shared runtime.

Two relay fixtures also pre-created acknowledgements. `GuestRelayInbox` correctly reads an existing acknowledgement before writing a message, so those fixtures skipped the write the tests expected.

## Fix

`RouterTools` now uses an injectable `GuestRouterRuntime`, defaulting to the app's shared runtime; tests create an isolated runtime for each tools instance. The guest suite is serialized, and its relay fixtures now create the acknowledgement only when the message is admitted.

Replaced polling, sleeps, and test-side timer deadlines in the two suites with continuations tied to the work under test: form bridge refresh completion, dispatcher completion, guest watch refresh completion, Router-off disable completion, plugin readiness, and key reload control. Relay tests disable the production timeout and use mock watch events. The hook stdin test substitutes an immediate microtask for its production timer. Watch completion signals fire after both successful and failed refreshes.

## Verification

- `swift test --filter RouterMCP`: 46 tests passed.
- `swift test --filter GuestRouterTests`: 34 tests passed.
- `scripts/test.sh` ran once and passed. The original untracked `test.log` was restored after capturing this run's log.

Final summary: `✔ Test run with 1658 tests in 162 suites passed after 47.569 seconds.`
