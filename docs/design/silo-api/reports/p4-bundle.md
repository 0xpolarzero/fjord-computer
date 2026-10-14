# P4-bundle implementation report

## Result

Fjord now builds and embeds the `silod` helper from a pinned Silo checkout, signs the nested engine bundle with the Fjord signing identity and virtualization entitlement, and gates LaunchAgent registration behind the Computers page's explicit **Enable Silo Engine** action. The local arm64 app bundle and its nested signature verified. The single requested `scripts/test.sh` run stopped during test compilation; the compiler issue is fixed and `swift build --build-tests` now compiles the state-machine tests, but the test suite was not rerun.

## Implementation

- [`scripts/silod.commit`](../../../scripts/silod.commit) pins Silo at `fc0f286fb313bbc9c5addefbe171f6f23c232198`. [`scripts/build-silod.sh`](../../../scripts/build-silod.sh) reads a clean checkout from `SILO_REPO_PATH` (default `../microsandbox-workspaces`), verifies the exact commit, and builds locked `silod` with Rust 1.94. `SILO_TARGET_DIR` controls Cargo output; `UNIVERSAL=1` builds arm64 and x86_64 and combines them.
- The output is embedded at `Fjord.app/Contents/Resources/SiloEngineDistribution/Silo Engine.app`. It contains the `silod` executable, Silo's production `Info.plist`, inner LaunchAgent plist, and a production manifest whose `engineBuild` records the pinned commit. Fjord also carries the plist at `Contents/Library/LaunchAgents/org.silo.preview.engine.plist`; its `BundleProgram` points to the nested helper. This lets `SMAppService.agent(plistName:)` resolve a plist from the calling Fjord app bundle, as required by [Apple's agent API](https://developer.apple.com/documentation/servicemanagement/smappservice/agent%28plistname%3A%29).
- [`Resources/SiloEngineEntitlements.plist`](../../../Resources/SiloEngineEntitlements.plist) grants `com.apple.security.virtualization`. The nested engine bundle is signed first with the selected Fjord identity and checked for that entitlement; the outer Fjord app is then signed and deep-verified. The build does not use `codesign --deep --force` to replace the nested signature. `SILOD_PRODUCTION_CODE_REQUIREMENT` can pin the release requirement; otherwise the build derives a leaf-certificate requirement from the Fjord identity, falling back to the engine bundle identifier for ad-hoc builds.
- [`Sources/Fjord/EngineLauncher.swift`](../../../Sources/Fjord/EngineLauncher.swift) wraps `SMAppService` behind an injectable service protocol. Opening Computers only probes the shared socket and service state. Registration occurs only after the user presses Enable. The launcher surfaces `requiresApproval`, opens Login Items only after the user asks, and waits for handshake, `engine.state`, and `updates.state` before connecting the Computers model. It reads the silod owner record and process path to distinguish an engine running inside Fjord from one supplied by another bundle. A newer or equal-version shared owner is reused; an older owner or equal-version different build is left running and reported as blocked rather than starting a second engine.
- Ordinary app launches begin with an unavailable engine client. `MockEngineClient` remains limited to demo and test contexts. The Computers page and saved detail routes are gated until a real client connects.
- `.github/workflows/release.yml` checks out the recorded Silo revision, installs Rust 1.94 and both macOS Rust targets, then builds the universal app. `DEVELOPMENT.md` documents the path, pin, and signing inputs.

The direct registration flow follows Apple's documented `SMAppService.agent(plistName:)` bundle lookup and [`register()` approval behavior](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29). It follows the task's explicit request to register from Fjord and sign with Fjord's identity. P4 §5 and P2 §1.2 instead specify a canonical Silo-signed per-user bundle and shared installer. This implementation therefore keeps an inner Silo Engine app but also copies its plist into Fjord's calling bundle; it does not claim the canonical shared-installer design is complete.

## Verification

- `swift build` — passed before the final launcher refinements; `scripts/build-app.sh` subsequently rebuilt and linked the final production Fjord executable successfully.
- `swift build --build-tests` — passed after the final launcher and mock-connector changes; this compiled the full test target without executing tests.
- `scripts/test.sh` — run once, as requested; it exited during test compilation because `MockEngineConnector.connect()` omitted `return` in its success branch. That source error is fixed. The suite was not rerun, so no test execution pass is claimed. The pre-existing `test.log` was restored after the script.
- `scripts/build-app.sh` — passed for arm64. It built the nested `Silo Engine.app`, signed it, then signed and verified `build/Fjord.app`.
- `test -x build/Fjord.app/Contents/Resources/SiloEngineDistribution/Silo Engine.app/Contents/MacOS/silod` — passed.
- `plutil -lint` on the outer and inner LaunchAgent plists — passed.
- `codesign --verify --deep --strict build/Fjord.app` — passed.
- `codesign -dv --entitlements :- …/Contents/MacOS/silod` — returned `com.apple.security.virtualization=true`.
- `lipo -info` — local helper is arm64. The universal release workflow is configured, but the x86_64 cross-build was not run on this machine.
- No Fjord app was launched and no LaunchAgent was registered.

## Remaining release and lifecycle gaps

- The Silo checkout is clean at the pinned commit, but local `main` is 87 commits ahead of `origin/main`; `origin/main` does not contain this pin. The release workflow's remote checkout cannot fetch it until that Silo commit is published. No push was performed.
- The Silo scaffold report records that the shared `silo-engine-install` coordinator and save/resume handoff have not landed. When a connected engine is older than this bundle, Fjord reports the required update as blocked and preserves the existing owner. This prevents a second owner, but the P2 “newest wins” replacement transaction is not implemented here.
- The bundled engine currently contains the `silod` scaffold, plist, `Info.plist`, and manifest. P2's complete runtime distribution, installer, and release qualification are still external work.
- Local signing used the `Fjord Dev` identity, which is present in the keychain but reported by `security find-identity` as not trusted. The local signature verifies; this does not qualify a trusted or notarized release identity.

`git diff --check` passed. No live Service Management transition, cross-bundle handoff, x86_64 build, or signed Dev-harness run was performed.
