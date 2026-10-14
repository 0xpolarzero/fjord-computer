# Fjord API sync

Schema: Silo main `38dc9357` (sha256 `31abb5a1...ee2a`), regenerated with `scripts/generate-engine-client.sh --write`.

## Done
1. **Regenerated client.** The generator failed on `cpus` (uint8 in the Linux configuration, uint64 in the new `macosResources` variant, merged into one class); `swift-renderer.mjs` now keeps the widest integer format when merged properties differ. The union now shares one `expected` type, `SiloWireConfiguration`; `SiloWireConfiguration(_: ComputerConfiguration)` converts for Linux edits.
2. **macOS resource editing.** `updateResources` sends `macosResources` with `expected {cpus, memoryGiB, diskGiB}` from the displayed row, plus the new values and a request id. It stops a running computer first and checks the limits from `resourceLimits(.macos)`. The Resources panel shows steppers; "coming soon" is gone.
3. **Owner routing.** `SiloGuestClient.execGet` sends `deviceId`, which covers Triage runs and Runs on.
4. **Error codes.** `EngineErrorText` gives plain-language messages for not_running, needs_personalizing, setup_incomplete, screen_sharing_unavailable, running_limit, desktop_update_required (says to use Update desktop), permission_denied and output_too_large. They surface as `EngineClientError.coded` (socket errors) and `OperationJobError.userMessage` (job failures, receipts, run cards).
5. **Checkpoint kind.** The UI already read the `kind` field; added `kindLabel` and a test that kind, not the name suffix, decides.
6. **Mock.** The `macosResources` handler is typed and checks that the computer is stopped and that the baseline matches. It records `lastConfigurationChange`, and display-open raises `not_running`.

## Tests
New: the macOS edit wire contents, a stale baseline, error messages, job receipt mapping, checkpoint kind, `guest.exec.get` deviceId, and socket error code mapping. The old "stays disabled" test was replaced. `swift build` passes, `scripts/test.sh` passes (1730 tests), and the generator `--check` passes. Computers window shots re-rendered (`.build/shots-sync`).
