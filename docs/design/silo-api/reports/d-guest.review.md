Read-only review complete. The report and repository are unchanged. Findings below are ranked by severity; paths are relative to `app/SiloUI/src-tauri/`.

1. **P1 — Linux execution without stdin bypasses streaming and memory limits.**  
   `engine/src/guest/target.rs:231` adds `--stream` only when stdin is present. The pinned MicroSandbox CLI otherwise buffers stdout and stderr in unbounded vectors until exit. Ordinary `guest.exec.start` therefore produces no live output, and bounded exec can exhaust host memory before Silo enforces its stdout cap.  
   **Fix:** always pass `--stream`, adding `--no-stdin` when appropriate. Test against the real CLI or a fake that reproduces its buffering behavior.

2. **P1 — Cancellation loses the process group when the primary command exits first.**  
   `engine/src/guest/helpers/exec.pl:47` deletes the group record immediately after waiting for the primary child. Descendants can remain alive. `helpers/control.pl:34` treats the missing record as successful termination, and `guest/session.rs:317` discards termination failures before reporting cancellation.  
   **Fix:** retain verifiable group state through confirmed group cleanup and propagate failed termination. Cover a primary command that exits while descendants remain.

3. **P1 — Path aliases defeat `expectedSha256` serialization and lose updates.**  
   `engine/src/guest/files.rs:156` locks the literal path. `/dir/settings.json` and `/dir/./settings.json` acquire different locks, then both can validate the old hash before `helpers/files.pl:164` independently renames their replacements. Both calls can succeed while one update disappears. The report’s claim that CAS is exact for engine writers is false.  
   **Fix:** serialize by resolved destination identity inside the guest and pin the parent directory. Add a synchronized concurrent-write test using path aliases. Explicitly define the remaining limitation against non-cooperating writers.

4. **P2 — macOS environment names can select an unintended command.**  
   `engine/src/guest/exec.rs:72` accepts names containing spaces and leading dashes; `guest/target.rs:65` places assignments after `/usr/bin/env` without `--`. A name such as `-S /usr/bin/printf injected #` is interpreted as an option and bypasses the supervisor. A harmless host probe confirmed this parsing behavior.  
   **Fix:** use `/usr/bin/env --` and validate environment names consistently. Test option-like names separately from shell quoting.

5. **P2 — Output-drain waits escape deadlines and later cancellation.**  
   `engine/src/guest/process.rs:123` stops checking the deadline once the host child exits, then joins writer/readers without a deadline at lines 147–155. `guest/session.rs:427` similarly samples cancellation once before an unbounded reader join. Inherited descriptors held open by descendants can leave these waits unresolved.  
   **Fix:** supervise process exit and pipe completion together, with a live cancellation flag and bounded cleanup. Test cancellation after process exit but before pipe EOF.

6. **P2 — Watch success precedes watcher readiness.**  
   `engine/src/guest/watch.rs:83` returns after spawning the transport; `helpers/files.pl:190` suppresses changes during its first scan. A client can subscribe, re-read, then write before that scan, and receive no event. The report’s suggested re-read does not close this gap. Existing tests hide it with startup sleeps.  
   **Fix:** return success only after the watcher establishes its baseline and is armed. Test an immediate write after the response without sleeps.

7. **P2 — Watch polling has unbounded directory-dependent cost.**  
   `engine/src/guest/helpers/files.pl:183` sorts and stats every entry every 200 ms, then retains full signatures at lines 185–193. The 32-folder limit bounds neither entry count nor memory; subscribers duplicate the work. This contradicts the specified Linux inotify adapter.  
   **Fix:** implement the specified notification adapter, bound resources, and test large directories, rename/coalescing, initialization failures, and overflow recovery.

8. **P2 — Valid macOS exit code 255 becomes a transport failure.**  
   `engine/src/guest/target.rs:274` classifies every SSH status 255 as `not_running`. A guest program can legitimately exit 255, causing bounded exec to fail and an exec job to become `lost`.  
   **Fix:** record complete supervised exit status through the control channel and distinguish recorded guest exits from SSH failures. Test both cases.

9. **P2 — Replay can retain old chunks while silently dropping newer ones.**  
   `engine/src/guest/session.rs:294` skips chunks larger than `retainOutputBytes` without evicting older chunks. The ring ceases to represent a contiguous suffix, and `firstRetainedSeq` does not expose the missing tail.  
   **Fix:** define oversized-chunk retention explicitly and preserve a contiguous suffix or explicit gap information. Test a small budget with an oversized middle and final chunk.

10. **P3 — Exec lifecycle cleanup and domain validation are incomplete.**  
    `engine/src/guest/session.rs:594` accepts registry jobs without checking their method, so another domain’s completed job produces a fabricated exec state. Also, `session.rs:656` defines `forget_finished`, but `silod/src/dispatcher.rs:242` acknowledges outcomes without calling it; replay remains allocated until a later launch triggers pruning.  
    **Fix:** reject non-exec jobs and connect acknowledgement to replay cleanup. Add cross-domain lookup and acknowledgement tests.

No ordinary shell injection was found in the Perl file helper: arguments follow `--`, opens use three arguments, and list/watch records use NUL delimiters. Final-component removal uses `unlink`, so a symlink replacement does not delete its referent. Parent traversal and temporary commits remain pathname based; shared-writable-parent race tests are missing.

Exec input/get have no client ownership checks, and output is broadcast. The supplied spec does not establish private exec ownership: same-user clients are trusted, and sources other than setup are broadcast. Treat this as shared access policy, not an established security defect.

Verification used source/spec inspection and harmless `env` probes. No builds, test suites, apps, or guests were started.

**Next action:** fix unconditional Linux streaming first, then verify caps and live output through the pinned runtime.