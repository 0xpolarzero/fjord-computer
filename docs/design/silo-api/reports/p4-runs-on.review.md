`00ffcdca` is not production-ready. Beyond the report’s declared gaps, the normal dispatcher fails guest starts and form replies, and uncertain delivery can execute the same task twice. Read-only review; no files changed or build/test suite run.

Findings, ranked by severity:

1. **P1: Guest starts open Desktop, then fail with “Not prepared.”**  
   [RouterDispatcher.swift:1417](/Users/polarzero/code/projects/lookout/Sources/Fjord/RouterDispatcher.swift:1417) passes every start result into `started()`, which requires a local `peer` and prepared delivery. Guest starts deliberately return `ready_in_claude` without either. **Fix:** represent preparation and deliverable starts separately; record successful guest preparation and skip initial delivery. The existing test calls `tools.startSession` directly and misses this dispatcher failure.

2. **P1: Retry after uncertain delivery creates a second executable message.**  
   [GuestRelayInbox.swift:63](/Users/polarzero/code/projects/lookout/Sources/Fjord/GuestRelayInbox.swift:63) handles only `exists` around message creation. A disconnect after admission, or an acknowledgement-read failure, leaves the message deliverable and its receipt `inFlight`. The ledger has no recovery consumer; [RouterFlight.swift:145](/Users/polarzero/code/projects/lookout/Sources/Fjord/RouterFlight.swift:145) submits Retry as a new turn, producing a fresh nonce. **Fix:** persist the signed payload and originating decision before admission, classify uncertain errors explicitly, and reconcile the original nonce before allowing another delivery.

3. **P1: Composer form replies write answers on This Mac.**  
   [RouterMCP.swift:940](/Users/polarzero/code/projects/lookout/Sources/Fjord/RouterMCP.swift:940) always uses `store.formBridge.dir` and local `FormWriter`, even when `pendingForm` returned a guest form. The composer reports success while the guest hook receives nothing. Card buttons use the correct guest branch, masking this failure. **Fix:** dispatch tool/composer answers through `GuestRouterRuntime.answer`, preserving the ticket and form-identity gate.

4. **P1: Guest execution state is incorrect and overwritten by the local mirror.**  
   [GuestRouterRuntime.swift:211](/Users/polarzero/code/projects/lookout/Sources/Fjord/GuestRouterRuntime.swift:211) marks every live plugin process `running`, although that property means an unfinished turn. Missing evidence leaves previous activity untouched. Meanwhile, unchanged local readers read SSH mirrors and [Agents.swift:459](/Users/polarzero/code/projects/lookout/Sources/Fjord/Agents.swift:459) replaces guest activity; local ingestion also replaces sessions. Working, completion and question state can oscillate between these sources. **Fix:** merge execution state centrally by location, derive turn state from guest transcripts, and distinguish idle, dead and inaccessible evidence. Exclude guest execution data from local ingestion.

5. **P1: Switching Router off during first installation leaves the guest enabled.**  
   [RouterMCP.swift:1280](/Users/polarzero/code/projects/lookout/Sources/Fjord/RouterMCP.swift:1280) installs before registering the runtime target. `disableAll()` therefore cannot revoke or queue that installation. The installer subsequently publishes its key and enabled marker; the later ticket check only prevents Desktop opening. **Fix:** register the installation target before mutation, serialize install/disable per location, and gate final activation on the captured Router generation.

6. **P1: Cancelled or stale form approvals can still be written.**  
   [GuestForms.swift:73](/Users/polarzero/code/projects/lookout/Sources/Fjord/GuestForms.swift:73) checks validity before awaiting `guest.account`, then writes without another check or task-cancellation check. Closing the card or switching Router off during that await still admits the old answer, including plan approval. **Fix:** recheck cancellation, Router generation, card and request identity immediately before admission; handle delayed remote admission explicitly.

7. **P2: Session matching fabricates alias evidence and does not enforce exclusive ownership.**  
   [GuestRouterRuntime.swift:114](/Users/polarzero/code/projects/lookout/Sources/Fjord/GuestRouterRuntime.swift:114) assigns every same-folder Desktop candidate the pending alias instead of decoding its actual SSH connection. Another active session at `/workspace/repo` blocks matching even on another computer. Pending starts are also reconciled independently, so two preparations can claim the same session. [GuestDesktopStart.swift:87](/Users/polarzero/code/projects/lookout/Sources/Fjord/GuestDesktopStart.swift:87) permanently rejects empty prompts and edited prefills. **Fix:** decode real Desktop SSH metadata, join through owner/computer and registry identity, claim each session once, and provide explicit selection for unmatched preparations.

8. **P2: Tagged guest projects repeatedly select a new start.**  
   [RouterDispatcher.swift:643](/Users/polarzero/code/projects/lookout/Sources/Fjord/RouterDispatcher.swift:643) still compares card/session folders directly with the controller project folder. A guest session has a different folder, so an ordinary project-tagged follow-up selects `.start`. **Fix:** use the new location-aware project matching helpers here.

9. **P2: Guest delivery and cancellation retain local availability checks.**  
   [RouterDispatcher.swift:1422](/Users/polarzero/code/projects/lookout/Sources/Fjord/RouterDispatcher.swift:1422) requires host Claude Code before reaching guest delivery; [RouterWaiting.swift:467](/Users/polarzero/code/projects/lookout/Sources/Fjord/RouterWaiting.swift:467) does the same for ready messages. The abort-capability effect at [RouterDispatcher.swift:1439](/Users/polarzero/code/projects/lookout/Sources/Fjord/RouterDispatcher.swift:1439) checks local plugin presence, making guest deliveries non-cancellable through the dispatcher. **Fix:** resolve location first and obtain guest capabilities from guest evidence.

10. **P2: Guest hook removal fails for a mixed hook entry.**  
    [GuestRouterInstaller.swift:206](/Users/polarzero/code/projects/lookout/Sources/Fjord/GuestRouterInstaller.swift:206) detects changes by counting outer entries. Removing Fjord’s command from an entry containing another command leaves that count unchanged, so settings remain unchanged while the script is deleted. **Fix:** track nested changes and commit whenever Fjord’s command was removed.

11. **P2: Settings retries can overwrite the wrong symlink target.**  
    [ClaudeSSHSettings.swift:31](/Users/polarzero/code/projects/lookout/Sources/Fjord/ClaudeSSHSettings.swift:31), the supporting shared writer, resolves the target once but rereads the current symlink on every attempt. Retargeting A→B makes a retry read B and write its modified contents into A, returning success without updating B. **Fix:** capture the target per attempt and recheck both target identity and bytes before replacement.

12. **P2: Coalesced acknowledgement hints incur the full timeout.**  
    [GuestRelayInbox.swift:106](/Users/polarzero/code/projects/lookout/Sources/Fjord/GuestRelayInbox.swift:106) rereads only when the event path exactly equals the acknowledgement file. The protocol promises coalesced folder-change hints. A valid acknowledgement accompanying a directory hint is discovered only by the final timeout read. **Fix:** reread the expected acknowledgement on every relevant subscription hint.

13. **P2: The guest hook can ignore termination while awaiting stdin.**  
    [GuestRouterInstaller.swift:274](/Users/polarzero/code/projects/lookout/Sources/Fjord/GuestRouterInstaller.swift:274) waits indefinitely for EOF, while its signal handlers suppress normal termination. A read-only subprocess reproduction with stdin held open remained alive after SIGTERM. **Fix:** bound input reading and make it cancellable, as the local hook does.

The controller SSH writer otherwise preserves unrelated settings and connections, refuses malformed JSON/types, backs up original bytes, shares serialization with the local form installer, preserves permissions, and uses temporary-file/rename replacement. Its final external check/rename window is the design’s acknowledged limitation.

The guest wrapper uses quoted guest Node/module paths and has no Fjord binary dependency. Guest signing uses the guest key and clock; the reused plugin retains HMAC verification, target binding, freshness, nonce claims, signed settings and signed aborts. B-15 proves hook invocation, not complete Fjord plugin delivery. B-16 supports guest transcript authority, which the current ingestion pipeline violates.

Missing tests include:

- Actual dispatcher guest start, composer form reply, project-tagged follow-up, guest-only delivery and cancellation.
- Accepted write with lost reply, acknowledgement failures, late/coalesced acknowledgements, and retry/relaunch without a fresh nonce.
- Interleaved local/guest snapshots, idle/live/dead transitions and Desktop quit.
- Router-off during installation, suspended-account stale approval, mixed-hook removal and exclusive session matching.
- Settings conflict exhaustion, backup/mode preservation, symlink retargeting, concurrent key/settings creation and partial installation.
- Real hook request/answer subprocess fixtures, signal/parent-death cleanup, and restore/fork key invalidation.

Precisely what the [report’s remaining-work section](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/p4-runs-on.md:33) still requires for production, in addition to these fixes:

- A generated production adapter for account, exec, file read/write/list/remove/watch and alias operations.
- Owner-grouped inventory and remote placements carrying `deviceId`.
- Guest runtime provisioning; installation currently requires Node 18+, Git and Claude already present.
- Startup client rehydration, watch reattachment and complete tri-state liveness.
- Transcript inode/size/mtime caching with replacement/shrink handling; guest background-task and fd readers; location-aware `RouterBrief`.
- Deleted-computer SSH settings and alias cleanup, including reconnect reconciliation.
- Qualification of remote-owner placement and RepoWorld/clone routing.
- Live end-to-end guest validation, a clean test-suite result, and a dedicated placement-popover screenshot.

The local branches retain their original transport paths, but unchanged This Mac behaviour has no passing regression-suite evidence, and the shared settings writer has the symlink defect above.

Fix the dispatcher’s `ready_in_claude` result handling first, with an end-to-end regression test.