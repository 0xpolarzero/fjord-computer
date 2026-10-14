Reviewed the seven non-merge track commits through `d02f9ab1`. Locations refer to committed code, excluding worktree changes. Read-only review; no tests or VMs ran.

1. **P2: Normal Linux setup progress bypasses the requesting client.**  
   [runtime/mod.rs:170](/Users/polarzero/silo-work/d-computers/app/SiloUI/src-tauri/engine/src/runtime/mod.rs:170) publishes setup stages, warnings, and `setup-failed` only as a legacy event to `"main"`. The new audience binding covers creation waits and completion, but these stages never become `operations.job.progress`. This violates 05’s progress audience and failure-detail contract.  
   **Fix:** route the common setup publisher through canonical progress encoding and the bound audience. Test actual setup stages and failure details with two clients.

2. **P2: Early setup failures broadcast requester-only outcomes.**  
   [computers.rs:489](/Users/polarzero/silo-work/d-computers/app/SiloUI/src-tauri/silod/src/methods/computers.rs:489) releases the setup binding before fallback completion; `finish_job_error` uses `Audience::All`. Runtime-readiness failures take this path, so another client receives the requester’s terminal error.  
   **Fix:** preserve the requester audience through completion, then release it. Add a two-client readiness-failure test.

3. **P2: Successful Linux job results omit required row discriminators.**  
   The new lifecycle and configuration adapters at [computers.rs:783](/Users/polarzero/silo-work/d-computers/app/SiloUI/src-tauri/silod/src/methods/computers.rs:783) and [computers.rs:890](/Users/polarzero/silo-work/d-computers/app/SiloUI/src-tauri/silod/src/methods/computers.rs:890) delegate completion to engine serialization without adding `kind`. `ApplicationComputer.kind` is mandatory in `silo-api`; `computers.changed.linux` has the same defect. Immediate reads add the discriminator correctly.  
   **Fix:** share canonical state encoding across reads, completion results, and events. Deserialize successful payloads containing a Linux row in regression tests.

4. **P2: Socket disconnect leaves macOS display gateways alive.**  
   Cleanup added at [context.rs:113](/Users/polarzero/silo-work/d-computers/app/SiloUI/src-tauri/silod/src/context.rs:113) is bypassed by actual socket teardown. Gateways inserted at [computers.rs:1415](/Users/polarzero/silo-work/d-computers/app/SiloUI/src-tauri/silod/src/methods/computers.rs:1415) remain in the static registry. Detached pending requests can also insert a gateway after disconnect.  
   **Fix:** invoke gateway cleanup during socket teardown and reject registration for disconnected clients. Test that disconnecting A closes only A’s gateway, including an in-flight session request.

5. **P2: macOS create breaks the job acceptance boundary.**  
   [computers.rs:1003](/Users/polarzero/silo-work/d-computers/app/SiloUI/src-tauri/silod/src/methods/computers.rs:1003) awaits creation, which waits for queue admission before returning the row. Conflicting work therefore delays the response and its cancellation ID, contrary to 05’s “returns at once” contract. Conversely, validation refusals are converted into accepted jobs without a row, although 30 §3 specifies synchronous refusal before starting the job.  
   **Fix:** separate validation, acceptance, preparing-row allocation, and admitted work. Test prompt acceptance behind a held gate, cancellation before installer work, and invalid requests leaving no job.

6. **P2: A resource-edit setup refusal loses its stable code.**  
   [store.rs:253](/Users/polarzero/silo-work/d-computers/app/SiloUI/src-tauri/engine/src/macos_computers/store.rs:253) returns `"Finish setting up the computer before changing its CPU or memory."`; [classify_refusal:645](/Users/polarzero/silo-work/d-computers/app/SiloUI/src-tauri/engine/src/macos_computers.rs:645) recognizes different setup phrases. The job consequently ends with `internal` instead of `setup_incomplete`.  
   **Fix:** classify this refusal explicitly, preferably through a typed error shared with the producer. Test the actual resource-edit refusal.

7. **P2: `forceStop` creates an unreturned durable job.**  
   The command handler at [computers.rs:804](/Users/polarzero/silo-work/d-computers/app/SiloUI/src-tauri/silod/src/methods/computers.rs:804) invokes an engine path that allocates and finishes a job, then returns only `null`. Its outcome remains unacknowledged, and its gate entry carries a job ID despite 05 specifying no job ID for commands.  
   **Fix:** provide command admission without a durable job. Test successful and refused force-stop calls for leftover outcomes.

8. **P2: Storage compatibility conversion happens during reads and misses reclaim results.**  
   [computers.rs:740](/Users/polarzero/silo-work/d-computers/app/SiloUI/src-tauri/silod/src/methods/computers.rs:740) rewrites historical `legacy` triggers to `manual` only in `storage.read`. Reclaim results serialize the original history directly, potentially violating the API trigger enum. The read-time shim also contradicts 95 §3’s launch-only migration policy.  
   **Fix:** normalize persisted history during launch, remove the shim, and validate both read and reclaim results against `silo-api`.

9. **P3: macOS resource jobs use the Linux setup namespace.**  
   [computers.rs:918](/Users/polarzero/silo-work/d-computers/app/SiloUI/src-tauri/silod/src/methods/computers.rs:918) produces `setup:<requestId>`. The 05 job-space table reserves that namespace for Linux setup and assigns `job:` to every macOS job.  
   **Fix:** allocate through `context.start_job` and update the contract/tests consistently.

The report also overstates compliance: macOS restart, dismiss-error, storage, and identities remain refused at [computers.rs:728](/Users/polarzero/silo-work/d-computers/app/SiloUI/src-tauri/silod/src/methods/computers.rs:728), despite the decided parity requirement. Q13 records missing implementation evidence, not an exemption. Remote forwarding, launch execution, and raw streams remain acknowledged integration gaps. No additional local `deviceId` misrouting was found.

The resource optimistic check correctly compares CPU, memory, and disk after queue admission and preserves disk size. Tests still need successful persistence, stale memory/disk checks, and a configuration change while waiting. The socket resource test stops at host-support refusal.

No proven new health-watch duplicate-event defect was found. Add deterministic installed-watch tests for repeated readings, discarded/unavailable reads, and lifecycle/delete interleavings between observation and delivery. Also correct the report’s Quit claim: macOS stop completion means the stop request was issued; safe Quit must observe the stopped state.

**First action:** fix the common setup publisher and fallback audience handling together, backed by a two-client regression test.