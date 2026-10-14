# P2-silod scaffold implementation report

## Summary

Implemented the first process scaffold in `engine/p2-silod`: a macOS `silod` binary with AppKit on the initial thread, Tokio socket I/O, per-channel launch services and paths, single-owner startup checks, authenticated local sessions, protocol handshake, and `engine.state`. Other API methods return the canonical unsupported-operation error until their engine adapters land.

This follows the [Implementer brief](../IMPLEMENTATION.md#implementer-brief), [P2-silod design](../design/p2.md#1-p2-silod), [engine hosting and transport contracts](../05-engine-architecture.md#3-engine-hosting-on-macos) including [§4.2](../05-engine-architecture.md#42-what-the-engine-api-needs-on-top), and [macOS probe evidence](../probes/macos.md).

## Implementation

- Added `silod` to the Rust workspace and added the P1 `silo-api` crate at `app/SiloUI/api`, since it was not present on the `engine/integration` base. The API crate had no frozen transport version on that base. The initial scaffold uses protocol version 6, as P2 requires freezing a new version and retiring the v5 transport rather than reusing it.
- The process creates `NSApplication` on the initial thread with accessory activation, changes to regular activation while an engine window is open, and runs Tokio I/O on a worker runtime. AppKit shutdown posts the event needed for `NSApplication.run()` to return. Restart requests exit code 75 and unwind the current worker task so server and owner cleanup can finish.
- `engine.sock` is created below the channel-specific private state directory with mode 0600. The listener checks `getpeereid` immediately after accept. Framing uses the four-byte big-endian length prefix and JSON envelope, bounded frames and queues, request IDs, concurrent reply workers, and per-connection ID checks.
- The method registry implements `engine.handshake` and `engine.state`. Handshake negotiates the highest common protocol and advertises only registered methods. All other methods remain unsupported. The `EngineContext` adapter supplies channel paths and identity, bounded event publication, the AppKit main-thread runner, and process control.
- Added channel-specific LaunchAgent plists and `SMAppService` status/register/unregister/open-settings commands. Startup takes an euid-owned lock per channel, refuses a second owner, and refuses a stale lower-version or equal-version conflicting build. This is an ownership/version check; package installation, binary handoff, and rollback remain outside this scaffold.
- Bundle validation uses Security.framework static-code validation with nested-code and strict checks. Production builds fail closed unless `SILOD_PRODUCTION_CODE_REQUIREMENT` pins the release signing requirement. The repository did not contain the production designated requirement, so the release build input still needs to be supplied.

The host choices follow Apple's documented AppKit stop behavior ([`NSApplication.stop`](https://developer.apple.com/documentation/appkit/nsapplication/stop%28_%3A%29)), `SMAppService` agent registration ([agent service](https://developer.apple.com/documentation/servicemanagement/smappservice/agent%28plistname%3A%29?language=objc%2Cobjc), [register](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29)), Security.framework static-code validation ([`SecStaticCodeCheckValidity`](https://developer.apple.com/documentation/security/secstaticcodecheckvalidity%28_%3A_%3A_%3A%29?changes=__3)), and the documented peer-credential API ([`getpeereid(3)`](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/getpeereid.3.html)). The plist's Aqua/Interactive hosting follows the macOS probe; conditional crash relaunch and live Service Management transitions still require signed Dev-harness qualification.

## Verification

- `cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --check` — passed.
- `cargo +1.94.0 test --manifest-path app/SiloUI/src-tauri/Cargo.toml --package silod --locked` — passed: 24 unit tests and 1 integration test, including framing, mocked peer-euid rejection, dispatcher, worker restart, and a temporary-socket handshake with two sequential state requests.
- `cargo +1.94.0 test --manifest-path app/SiloUI/src-tauri/Cargo.toml --workspace --locked` — passed with synthetic GitHub App test settings permitted by the release guide: 60 engine, 2,229 UI, and 25 silod tests passed; 30 UI tests were ignored.
- `git diff --check` — passed.

Tests used temporary directories and a temporary Unix socket. They did not register a LaunchAgent, launch a signed app bundle, exercise AppKit's live run loop, or touch Silo production data. The full workspace test covers the test host and fixtures; it does not prove service installation, two-device behavior, or release readiness.

## Remaining integration work

- Supply the production signing requirement through the release build environment and qualify the canonical signed bundle.
- Add an explicit macOS CI job for `cargo test -p silod --locked`. The current workspace `default-members` excludes `silod`; that setting and CI workflow were left unchanged to keep this patch within the requested workspace-only scope.
- Wire the remaining dispatcher methods, engine startup/recovery, lifecycle shutdown, event subscriptions, and package installer/handoff after the extraction and installer tracks land.
- Qualify AppKit activation transitions, LaunchAgent crash-restart policy, service approval/revocation, and restart behavior in the signed Dev harness described by P2 and the probe.
