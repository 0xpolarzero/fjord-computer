Found **one P1 and eight P2 findings**. These remain in this worktree’s HEAD. Review was read-only; the report is unchanged.

1. **P1: Reversing approval during an update leaves automatic approval enabled.**  
   [guest_computer_use.rs:455](/Users/polarzero/silo-work/d-display/app/SiloUI/src-tauri/engine/src/macos_computers/guest_computer_use.rs:455)  
   With applied `ask`, request `auto`, then request `ask` while installation runs. The second request matches the old fingerprint, so it returns before queuing another update. The first worker finishes with `auto`; the guest retains it until the next Start.  
   **Fix:** reconcile the latest desired mode after every completion, including changes back to the previously applied mode. Add a barrier-controlled `ask → auto → ask` regression.

2. **P2: Approval writes overwrite concurrent record changes.**  
   [macos_computers.rs:1630](/Users/polarzero/silo-work/d-display/app/SiloUI/src-tauri/engine/src/macos_computers.rs:1630)  
   The setter clones the record, saves it outside the registry lock, then replaces the entire record. Concurrent updater completion can lose its applied fingerprint; concurrent setters can leave disk and memory disagreeing. A concurrent Delete can also finish before `save` recreates its directory.  
   **Fix:** serialize a field-specific desired-approval mutation and persistence with lifecycle changes. Test setter/completion and setter/Delete interleavings.

3. **P2: Disconnect can miss an opening viewer.**  
   [display.rs:668](/Users/polarzero/silo-work/d-display/app/SiloUI/src-tauri/silod/src/methods/display.rs:668), [socket.rs:624](/Users/polarzero/silo-work/d-display/app/SiloUI/src-tauri/silod/src/socket.rs:624)  
   Credential reads precede registry reservation. Disconnect during that read closes nothing; the surviving worker subsequently installs a viewer for the dead client. Its proxy, tunnel and capacity slot remain.  
   **Fix:** bind claim and finish to an active session lifetime, or reserve before blocking work. Test disconnect before claim. Existing generation tests cover disconnect after reservation.

4. **P2: Clipboard transfer can target the wrong computer.**  
   [display.rs:947](/Users/polarzero/silo-work/d-display/app/SiloUI/src-tauri/silod/src/methods/display.rs:947)  
   The handler checks connection ownership but never matches its stored computer/device to the supplied target. An owned viewer for B with `computerId` A transfers B’s clipboard. A remote viewer also bypasses the explicit remote-device refusal when presented under a local target.  
   **Fix:** validate the complete viewer target before transfer. Test two same-client viewers with mismatched targets.

5. **P2: Cancellation reports refusal while cancelling, and remote jobs cannot propagate cancellation.**  
   [display.rs:1074](/Users/polarzero/silo-work/d-display/app/SiloUI/src-tauri/silod/src/methods/display.rs:1074), [display.rs:375](/Users/polarzero/silo-work/d-display/app/SiloUI/src-tauri/silod/src/methods/display.rs:375)  
   Before gate admission, cancellation sets the shared flag but returns “can’t be cancelled.” Local admission later consumes that flag and cancels the job. Remote action/setup branches neither enter the gate nor observe the flag.  
   **Fix:** return success when accepting cancellation; relay remote jobs and cancellation to the owner’s durable job identity. Test before admission, while waiting/running, and remotely.

6. **P2: Linux mutations omit the canonical computer event.**  
   [desktop.rs:784](/Users/polarzero/silo-work/d-display/app/SiloUI/src-tauri/engine/src/desktop.rs:784)  
   Successful desktop actions and approval changes publish only `silo://application-state-changed` with null payload. `SilodContext` forwards it unchanged, so `computers.changed` subscribers miss these changes.  
   **Fix:** publish the canonical state projection after mutation and approval application. Add socket-level event assertions.

7. **P2: Failed native-window creation can leave an orphan window.**  
   [display.rs:1243](/Users/polarzero/silo-work/d-display/app/SiloUI/src-tauri/silod/src/methods/display.rs:1243), [display.rs:1257](/Users/polarzero/silo-work/d-display/app/SiloUI/src-tauri/silod/src/methods/display.rs:1257)  
   Activation-policy failure occurs after registry insertion without rollback. Separately, a caller timeout does not invalidate queued main-thread work, which can later create an unattached window and switch Dock activation.  
   **Fix:** roll back failed insertion and invalidate timed-out requests before window creation. Inject policy failure and delayed-main-thread execution in tests.

8. **P2, acknowledged deviation: Local clients receive guest credentials.**  
   [display.rs:333](/Users/polarzero/silo-work/d-display/app/SiloUI/src-tauri/silod/src/methods/display.rs:333)  
   `desktop.connect` returns username/password to ordinary local sessions despite spec 40’s engine-only contract. Same-user authorization does not implement that restriction.  
   **Fix:** refuse local-client calls until authenticated engine-peer routing exists; test that no credential fields escape.

9. **P2, acknowledged dependency: Separate proxies do not provide independent live viewers.**  
   [display.rs:727](/Users/polarzero/silo-work/d-display/app/SiloUI/src-tauri/silod/src/methods/display.rs:727)  
   Both proxies reach the unchanged Selkies service documented as terminating the previous primary viewer. A-28 remains unmet until the streamer admission change lands.  
   **Fix:** complete the upstream admission fix and qualify simultaneous viewers through close, resize and clipboard operations.

I found no concrete cross-client page injection or observation path: ownership checks, generated client identities, `Audience::Client`, separate cookies and separate nonce inboxes enforce those boundaries. Static inspection also found no definite AppKit lifetime violation: retained objects stay on the main thread, `releasedWhenClosed` is disabled, and the close callback retains its removed entry.

The saved test log confirms the reported passing suite; I did not rerun tests or launch an app. Remaining coverage needs both clients subscribed during isolation checks, foreign-cookie/nonce rejection, lifecycle races, and signed AppKit close/reopen and multi-window Dock checks. The socket fixture uses a nonexistent guest socket and `sleep`, so it cannot establish live streamer behavior.

**First follow-up: fix and regress the approval reversal race.**