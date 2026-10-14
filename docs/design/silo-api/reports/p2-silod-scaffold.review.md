Found four P2 issues in `9a7a4cc8`. No P0/P1 defect demonstrated. This was a read-only source review; I did not rerun tests or launch an app.

1. **P2: Dev startup leaves the engine’s global channel set to production.**  
   [app.rs:33](/Users/polarzero/silo-work/p2-silod/app/SiloUI/src-tauri/silod/src/app.rs:33) derives paths from the manifest but never calls `silo_engine::channel::init`. Consequently, `channel::current()` returns production while the context identity says development. P2 §1.2 explicitly requires initialization from the validated `channelIdentifier`. Current scaffold methods do not use that global, so production-data access is not demonstrated.  
   **Fix:** initialize the channel immediately after manifest validation. Add subprocess tests asserting global channel and context identity agree for both builds.

2. **P2: Simultaneous cold starts can fail before ownership arbitration.**  
   [paths.rs:96](/Users/polarzero/silo-work/p2-silod/app/SiloUI/src-tauri/silod/src/paths.rs:96) checks for absence and then calls `create_dir`. Two processes can both observe absence; the second receives `AlreadyExists` and exits 1 before reaching `flock`. That violates the clean duplicate-owner exit and triggers the plist’s failure-restart policy.  
   **Fix:** accept `AlreadyExists`, then validate and secure the resulting directory. Add synchronized child-process starts against a fresh fixture HOME.

3. **P2: Device identity publication lacks directory durability.**  
   [identity.rs:108](/Users/polarzero/silo-work/p2-silod/app/SiloUI/src-tauri/silod/src/identity.rs:108) publishes `config.json` by hard link and removes the temporary name, but never syncs the containing directory. Syncing the temporary file does not durably commit those directory changes. A host crash can lose the published identity and generate a different `deviceId` next launch. Existing `remote.rs::save_config_in` syncs its directory.  
   **Fix:** sync the directory after publication and cleanup, before returning the identity; propagate failure.

4. **P2: Incompatible handshake diagnostics report the client version as `appVersion`.**  
   [dispatcher.rs:333](/Users/polarzero/silo-work/p2-silod/app/SiloUI/src-tauri/silod/src/dispatcher.rs:333) uses `client.version` for `appVersion` and omits the engine release version. P2 §1.6 and architecture §4.2 require engine protocol/application-version diagnostics. The caller cannot identify the incompatible engine release from this response.  
   **Fix:** include the engine identity’s version and clearly distinguish engine/client protocol ranges and application versions. Any structured diagnostic fields must live in the shared canonical API/schema. Test deliberately different engine and client versions.

The remaining checks found these limits:

- **Socket security:** peer euid is checked immediately after accept; lookup failure and mismatch close the connection. Modes, stale-socket checks and inode-based cleanup follow the intended policy. However, pathname checks followed by chmod/open/unlink are not fully race-safe, and `O_NOFOLLOW` does not protect ancestors. No cross-user exploit was demonstrated under a private HOME. Add replacement-inode, ancestor-symlink, foreign-owner and descriptor-inheritance tests.
- **Framing:** the length prefix, 4 MiB cap, connection-wide ID uniqueness, highest-overlap negotiation and capability filtering match the design. [handshake.rs:35](/Users/polarzero/silo-work/p2-silod/app/SiloUI/src-tauri/silod/tests/handshake.rs:35) tests sequential requests only. Add overlapping requests with forced reverse completion, slow-writer backpressure and capacity exhaustion.
- **AppKit and activation:** no present-scaffold deadlock was demonstrated. `WindowPolicy` has no production caller, and [app.rs:283](/Users/polarzero/silo-work/p2-silod/app/SiloUI/src-tauri/silod/src/app.rs:283) directly edits its counter. The report overstates working activation switching. Qualify actual main-thread scheduling, two-window/last-close transitions, duplicate callbacks, setter failure and shutdown/restart cleanup in the signed Dev harness.
- **LaunchAgent and ownership:** plist keys match P2, including Aqua, Interactive and conditional KeepAlive. `AssociatedBundleIdentifiers` is optional. Live lock losers exit before identity/socket changes; newer-engine handoff is explicitly deferred to the installer. Simultaneous ownership and crash/restart behavior remain unproved.
- **CI:** [Cargo.toml:12](/Users/polarzero/silo-work/p2-silod/app/SiloUI/src-tauri/Cargo.toml:12) excludes `silod` from default members, so ordinary CI does not run its tests. Add an explicit macOS `cargo test -p silod --locked` step.

Fix channel initialization first.