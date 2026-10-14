**Do not merge as-is.** I found 8 P1 defects that reject valid payloads or lose required semantics, plus 5 lower-severity contract mismatches.

1. **P1: Log flags have incompatible types.** [logs.rs:56](/Users/polarzero/silo-work/p1-api/app/SiloUI/api/src/methods/logs.rs:56) makes `unreadableRecords` an integer; line 75 makes `guestTimestamp` a string. Both are boolean flags in native `runtime_logs.rs` and the TS contract. **Fix:** use booleans with the source’s default-false and omission behavior.

2. **P1: Storage timestamps become strings.** [storage.rs:33](/Users/polarzero/silo-work/p1-api/app/SiloUI/api/src/methods/storage.rs:33) declares `lastTrimAt` as `Option<String>`; line 41 declares history `at` as `String`. Native `runtime/storage.rs` and TS use numeric epoch seconds. **Fix:** use `Option<u64>` and `u64`.

3. **P1: Passing dependency checks cannot decode.** [device.rs:27](/Users/polarzero/silo-work/p1-api/app/SiloUI/api/src/methods/device.rs:27) requires a string `remediation`. Native `dependencies.rs:89` uses `Option<String>` and passing checks emit `null`. **Fix:** make it nullable and preserve explicit-null serialization.

4. **P1: Pending-restore fields use snake_case.** [checkpoints.rs:90](/Users/polarzero/silo-work/p1-api/app/SiloUI/api/src/methods/checkpoints.rs:90) lacks enum field renaming, producing `checkpoint_id` and `source_computer`. Spec 20 §1.1 and both native restore types require `checkpointId` and `sourceComputer`. **Fix:** add `rename_all_fields = "camelCase"`.

5. **P1: GitHub retry state uses the wrong field name.** [github.rs:163](/Users/polarzero/silo-work/p1-api/app/SiloUI/api/src/methods/github.rs:163) renames variants but leaves `can_retry` unchanged. Spec 50, native `github.rs:1187`, and TS require `canRetry`. Unavailable-catalog snapshots therefore fail decoding. **Fix:** rename enum fields to camelCase.

6. **P1: Resize results use the wrong names.** [macos.rs:14](/Users/polarzero/silo-work/p1-api/app/SiloUI/api/src/methods/macos.rs:14) returns `{width,height}` instead of `{widthPx,heightPx}`, required by spec 30 and native `macos_remote.rs:93`. **Fix:** use `width_px`/`height_px`; also restore the specified `u64` request dimensions at line 13.

7. **P1: Valid desktop statuses cannot decode.** [desktop.rs:58](/Users/polarzero/silo-work/p1-api/app/SiloUI/api/src/methods/desktop.rs:58) requires string `sessionState` and `streamState`; spec 40 and native projection permit `null`. **Fix:** use nullable component-state types. Also change `display` at line 55 from arbitrary JSON to the specified nullable string.

8. **P1: Conditional file writes lose explicit-null semantics.** [guest.rs:136](/Users/polarzero/silo-work/p1-api/app/SiloUI/api/src/methods/guest.rs:136) collapses omitted and null `expectedSha256`, then omits both when serializing. Spec 70 defines null as “the file must not exist.” **Fix:** use presence-aware nullable serialization/deserialization, following the existing settings patch implementation.

9. **P2: Force-stop omits its remote result.** [registry.rs:68](/Users/polarzero/silo-work/p1-api/app/SiloUI/api/src/methods/registry.rs:68) registers only `()`. Spec 10 and native `macos_remote.rs:79–82` allow remote `MacosComputersState`. **Fix:** model the null/state result alternatives.

10. **P2: Clipboard discriminator is misspelled.** [clipboard.rs:12](/Users/polarzero/silo-work/p1-api/app/SiloUI/api/src/methods/clipboard.rs:12) serializes `TooLarge` as `"toolarge"`. Spec 30 requires `"too-large"`. **Fix:** use kebab-case or an explicit variant rename.

11. **P2: Handshake capabilities reject compatible extensions.** [transport.rs:72](/Users/polarzero/silo-work/p1-api/app/SiloUI/api/src/transport.rs:72) uses `Vec<MethodName>` instead of the specified `string[]`. A compatible newer engine advertising an unfamiliar method breaks the entire handshake, including generated Swift decoding. **Fix:** use `Vec<String>`.

12. **P2: Computer-use state omits macOS receipt fields.** [computer_use.rs:37](/Users/polarzero/silo-work/p1-api/app/SiloUI/api/src/methods/computer_use.rs:37) contains the Linux projection but lacks `schemaVersion`, `chatgptVersion`, and `at`. Spec 40’s macOS result and 30 §10 explicitly include these receipt fields. **Fix:** model the macOS projection with its sourced names and nullable-until-read behavior.

13. **P3: Migration stage is unnecessarily nullable.** [migration.rs:15](/Users/polarzero/silo-work/p1-api/app/SiloUI/api/src/methods/migration.rs:15) uses `Option<String>` where native `runtime_migration.rs:85` requires `String`. This generates incorrect Swift optionality. **Fix:** use `String`.

Coverage checks passed: **all 146 method names and kinds, all 26 events, all seven progress projections**, and the specified decimal `job:` format. The schema has 294 definitions and 509 references, with none unresolved. Its faulty payload definitions follow the Rust defects above.

Read-only verification ran the existing compiled test binary: **13 passed**. I did not rebuild or generate a Swift client; the worktree remains unchanged.

**Safe to merge after these fixes are verified.** Fix the contracts, regenerate the schema, and add source-shaped fixtures covering the reported failures before merging.