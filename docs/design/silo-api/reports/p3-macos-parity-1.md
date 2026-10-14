# P3 macOS parity part 1 implementation

Date: 2026-10-14. Worktree: `/Users/polarzero/silo-work/p3-macos-parity`, branch `engine/p3-macos-parity`. Implementation commit: `bff33a6ccc7ec9704aa30bb69c9f19e2da066aea` (`feat(engine): add macOS provisioning and resource parity`).

This change implements the provisioning, computer-use setup, startup, queue, and CPU/memory portions of [P3-macos-parity](../design/p3-b.md), under the [Implementer brief](../IMPLEMENTATION.md) and decisions [A-19, A-31, and A-12](../95-decisions.md). It does not complete the full macOS parity track or the canonical job/events migration.

## Shipped in this part

| Scope | Implementation |
| --- | --- |
| Developer tools | Added a versioned macOS setup step for Xcode Command Line Tools (CLT), Git, Git LFS and GitHub CLI. Host-side downloads check size and SHA-256 before guest transfer. The guest checks each Apple package's signature and pinned certificate, installs CLT unattended, selects the developer directory, installs versioned LFS/gh binaries, verifies versions, and writes a receipt. The script, lock, and shared GitHub setup helper contribute to the setup fingerprint and template fingerprint. Retry setup re-runs this step if its fingerprint is stale. |
| Screen Recording | Added a guest ScreenCaptureKit recorder app and Aqua LaunchAgent. Computer Use setup grants `kTCCServiceScreenCapture` to the recorder's own bundle identifier and updates the ScreenCapture approvals ledger. If SSH setup runs before the account has an Aqua launchd domain, setup leaves the LaunchAgent for launchd to load at the next GUI login. |
| Screen Sharing | Setup grants the required TCC rows to Apple's Screen Sharing components, enables and loads the system job, then checks that port 5900 returns an RFB greeting. The local display path independently peeks at and validates the greeting without consuming bytes needed by the viewer. Readiness accepts the socket-activated `not running` launchd state when the RFB server answers. |
| Start at launch | macOS computer IDs now remain in the shared startup selection and use the existing startup coordinator. Unit tests cover preserving and starting selected local macOS IDs. |
| Operation queue | macOS configuration/setup and computer actions enter the shared `OperationGate`; conflicts wait in the queue and a queued waiter can be cancelled. Setup publishes `SettingUp` only after queue admission and reads the current saved record after admission. |
| CPU and memory | The UI edits CPU and memory for an installed, fully set up, stopped computer. The operation checks the current expected values after admission, refuses an unfinished restore or pending saved memory, persists only CPU/memory, and applies the saved values on next start. Disk size stays fixed. The form says changes apply at next start and keeps its original expected values if a newer snapshot arrives while it is open. |

The changeset is `app/SiloUI/.changeset/p3-macos-parity.md` in the Silo worktree. The live probe's bounded evidence is in [p3-macos-parity.md](../probes/p3-macos-parity.md).

## Source and licensing

The installer fetches CLT packages from Apple's public Software Update CDN when setup runs. It does not bundle or mirror those Apple packages. Each download is checked against the lock's byte count and SHA-256; each package is checked with Apple's package-signature verification and a pinned leaf-certificate hash. Git LFS and GitHub CLI come from their upstream release artifacts and are pinned by size and SHA-256.

Apple's [Command Line Tools installation documentation](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools/) identifies CLT as a separate install in `/Library/Developer/CommandLineTools`, distinct from full Xcode. The [Xcode and Apple SDKs Agreement](https://images.apple.com/legal/sla/docs/xcode.pdf) §2.2.A permits a reasonable number of installations on Apple-branded computers owned or controlled by the licensee for internal development. Applying that clause to this owner's controlled macOS VM is an inference. This implementation makes no claim that the agreement permits packaging or redistribution of Apple binaries to third parties. Full Xcode workflows remain unsupported; CLT does not include every full-Xcode tool such as `xcodebuild`.

During the live probe, the Apple catalog SHA-1 values did not match the five downloaded CLT packages. The lock uses measured byte counts and SHA-256 values, and the probe verified Apple's package signatures and pinned signer. The implementation does not rely on those mismatching catalog SHA-1 values. Upstream release references: [Git LFS 3.8.0](https://github.com/git-lfs/git-lfs/releases/tag/v3.8.0) and [GitHub CLI 2.102.0](https://github.com/cli/cli/releases/tag/v2.102.0).

## Verification

Commands ran in the specified worktree. Rust tests used the documented synthetic GitHub App configuration and `CARGO_TARGET_DIR=/Users/polarzero/silo-work/p3-macos-parity/target`, `CARGO_BUILD_JOBS=5`.

```text
cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --check                  PASS
SILO_GITHUB_APP_SLUG=<synthetic> SILO_GITHUB_CLIENT_ID=<synthetic> SILO_GITHUB_CLIENT_SECRET=<synthetic> CARGO_TARGET_DIR=/Users/polarzero/silo-work/p3-macos-parity/target CARGO_BUILD_JOBS=5 cargo test -q --manifest-path app/SiloUI/Cargo.toml --workspace --locked  PASS
npm --prefix app/SiloUI run typecheck                                                  PASS
npm --prefix app/SiloUI run lint                                                       PASS, with six existing warnings in unchanged files
npm --prefix app/SiloUI test                                                          PASS, 266 files and 2,770 tests
git diff --check                                                                      PASS
zsh -n app/SiloUI/src-tauri/guest/macos/silo-computer-use.zsh                          PASS
zsh -n app/SiloUI/src-tauri/guest/macos/silo-developer-tools.zsh                       PASS
```

The final full Rust workspace run passed 2,261 tests in the main engine suite, 69 and 30 in the additional suites, and the remaining zero/one-test targets; 30 tests were ignored. This final run includes regression tests for queued setup failure and cancellation preserving a preceding Start state. An earlier full run had an unrelated process-timeout in `dependencies::tests::version_probe_accepts_the_output_limit_and_rejects_overflow_on_either_stream`; that test passed in isolation and the final full workspace run passed. Lint's six warnings are in unchanged files.

The live macOS probe validates selected guest behavior on a disposable template clone; it is not a Silo app build or a packaged-app test. The probe and setup details, initial failures, limits, and cleanup are recorded separately in [the probe report](../probes/p3-macos-parity.md).

## Integration still required

The queue integration here uses the existing Tauri command path and in-process `OperationGate`. The API design expects durable canonical jobs and job outcomes, including macOS setup and configuration jobs. The P2 jobs/events work is being implemented on another track; this branch does not add durable macOS job IDs, `get`/`cancel`/`ack` semantics, or the canonical macOS `computers.configuration.change` payload. The current resource action still carries its legacy optimistic `expected` snapshot. Integrate the macOS operations with the P2 job/events seam before claiming API-level A-19 full parity.

P3-macos-proxy owns GitHub, secrets, repository clone, and LFS-over-proxy behavior. This part only provisions the GitHub CLI and shared credential helper; the probe used placeholder configuration and did not authenticate or contact an external account. The other Linux-parity methods named in A-19 remain outside this implementation part.

No optimized or debug app bundle was built after these edits. The report therefore establishes unit/frontend behavior and one disposable-VM probe, not packaged-app installation, full screen-sharing interaction, or release readiness.
