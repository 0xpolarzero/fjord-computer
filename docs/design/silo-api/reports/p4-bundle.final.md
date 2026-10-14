Implemented and committed:

- `dc9813d7` `feat: bundle and launch the shared Silo engine`
- `fadb9f03` `docs: report P4 engine bundle implementation`

[`build-app.sh`](/Users/polarzero/code/projects/lookout/scripts/build-app.sh) now builds pinned `silod`, embeds its engine app and LaunchAgent plists, and signs it with Fjord’s identity and virtualization entitlement. The final arm64 bundle passed deep signature verification; `codesign -dv --entitlements :-` showed `com.apple.security.virtualization=true`. The launcher registers only after the user selects **Enable**. Its plist is in Fjord’s calling bundle, consistent with [Apple’s SMAppService agent API](https://developer.apple.com/documentation/servicemanagement/smappservice/agent%28plistname%3A%29).

**Verification:** `swift build` passed; `swift build --build-tests` compiled the test target. The single `scripts/test.sh` run failed during compilation because the mock connector lacked a `return`; I fixed that error but did not rerun the suite, so test execution is unverified. No app was launched and no agent was registered.

Two release gaps remain: the pinned Silo commit is 87 commits ahead of `origin/main`, so the release workflow cannot check it out until it is published; and the shared installer/save-resume handoff is not available. Fjord detects an older running engine and blocks an update to avoid starting a second owner, so full “newest wins” replacement is not implemented.

Details are in the [P4 bundle report](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/p4-bundle.md). Next action: publish the pinned Silo commit so the release workflow can resolve it.