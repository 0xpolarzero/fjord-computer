# P2 Swift client fixes

Date: 2026-10-14
Base commit: `75cda32407796a315c6454e1c78a67330bf99a31`
Implementation commit: `9d2e98cd` (`fix: harden Silo socket client`)

## Findings resolved

1. **Reconnect poisoning:** keep a candidate transport unpublished until handshake and subscription restoration succeed. On failure, close it, invalidate its generation, clear partial subscription mappings, and reset local server IDs.
2. **Socket backpressure:** serialize blocking frame writes on a per-socket writer queue. The reader and shutdown remain independent; disconnect closes immediately when a write is still blocked.
3. **Reconnect event ordering:** buffer candidate events through subscription restoration, send `.reconnected` after all subscriptions return, then replay the buffered events.
4. **Caller cancellation:** reject pre-cancelled requests, remove and resume pending callers with `CancellationError`, and ignore late replies for cancelled request IDs. This remains separate from `operations.cancel`.
5. **Disconnect during handshake:** track the opening transport and connection attempt, cancel and close them on disconnect, and recheck connection generation after suspension points.
6. **Unsubscribe during restoration:** recheck local membership after the server reply and unsubscribe the new server ID if the local subscription was removed.
7. **Ignored-event sequences:** emit `.sequenceAdvanced` for projected-out events and advance the model/mock cursors. Real sequence gaps still trigger recovery.
8. **Explicit null results:** generate presence-aware decoders for job-finished, job-outcome, and response-envelope results so JSON `null` remains `.null` while an omitted field remains `nil`.
9. **Generator robustness:** replace the prose-dependent deletion with structural declaration-boundary removal. Add transform tests for changed documentation, an intervening declaration, and presence-aware result decoding.

The fake Unix socket server now accepts multiple connections and supports gated requests, fragmented writes, and per-request handlers. The job fixtures use `job:123`; the fixture test reads the `JobId` pattern from the pinned schema and checks all three IDs against it. The socket client suite is serialized, and its recorder waits are bounded so a missing delivery fails instead of hanging the suite.

## Verification

Verification ran in `/private/tmp/fjord-p2-client-verify`, a clean export of the base commit with only this track’s client, generator, test, and fixture files overlaid. The shared worktree had concurrent Router, Forms, and Guest edits; an earlier shared-tree test build was interrupted while `GuestRouterTests.swift` changed.

- `swift build` — passed. It emitted existing Swift 6 concurrency warnings in unrelated UI sources.
- `scripts/test.sh` — passed: 1,617 tests in 161 suites.
- `swift test --filter SiloAPIClientTests` — passed: 11 tests.
- `node --test tools/silo-swift/generator-transforms.test.mjs` — passed: 2 tests.
- `scripts/generate-engine-client.sh --check` — passed; generated Swift matches the checked-in schema.
- `git diff --check` — passed.

No findings remain open. The concurrent track’s files and untracked artifacts were not staged or committed.
