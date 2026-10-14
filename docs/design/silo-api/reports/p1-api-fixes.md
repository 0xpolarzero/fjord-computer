# P1 API fixes

Commit: `7a0591f9` (`fix(api): align wire types with native contracts`)

The P1 API crate now matches the cited native wire shapes and the canonical spec. The schema was regenerated at `app/SiloUI/api/schema/silo-api.schema.json`. Twelve findings required code changes. Finding 9 is contradicted by the newer canonical spec, so its requested legacy result was not added; a regression test locks the specified `null` result. Each review item was checked against its cited source and has focused serde or schema coverage below.

## Findings

1. **Log flags and default omission.** `runtime_logs.rs::Entry` and `Page` use boolean `guest_timestamp`, `unsupported`, and `unreadable_records` fields with default-false omission; the native test `guest_console_timestamps_are_labelled` verifies the emitted boolean. Changed `LogEntry` and `LogPage` to the same representation. `log_flags_and_optional_page_values_match_native_serde_shapes` round-trips true flags, verifies false flags stay omitted, and checks that the schema exposes nonnullable booleans.

2. **Storage timestamps.** `runtime/storage.rs::ReclaimEntry.at` and `StorageState.last_trim_at` are Unix seconds stored as `u64`. Changed them to `u64`/`Option<u64>`. `storage_timestamps_are_numeric_and_nullable_outputs_stay_present` round-trips the native numeric shape and rejects an ISO string.

3. **Dependency remediation.** `dependencies.rs::DependencyCheck.remediation` is `Option<String>`; `pass()` sets it to `None`, which serializes as explicit `null`. Changed the API field accordingly. `passing_dependency_check_preserves_null_remediation` verifies the source-shaped payload.

4. **Pending restore names.** Linux and macOS native `PendingRestore` structs use `rename_all = "camelCase"`; the Linux source test emits `checkpointId` and the macOS source uses the same spelling. Added `rename_all_fields = "camelCase"`. `pending_restore_variants_use_native_camel_case_fields` round-trips both platform shapes.

5. **GitHub catalog retry field.** `github.rs::public_snapshot` emits `canRetry`; native tests assert that field on unavailable catalogs. Added camelCase renaming for enum variant fields. `unavailable_github_catalog_uses_camel_case_retry_field` round-trips the unavailable shape.

6. **Display resize fields and widths.** `macos_remote.rs::parse_resize` accepts `widthPx` and `heightPx` as `u64`; dispatch returns those names with the clamped dimensions. Changed resize parameters to `u64` and the result fields to `width_px`/`height_px`. `macos_resize_uses_pixel_names_and_native_integer_widths` checks both shapes and accepts a request above `u32::MAX`.

7. **Desktop nullable fields.** `desktop.rs::component_state` accepts `null` for `sessionState`/`streamState`; `public_status` projects nullable `display`, `version`, `user`, and `backend` values. Changed component states and display to nullable strings, and preserved explicit nulls for the other nullable projected fields. `desktop_status_accepts_nullable_component_and_display_fields` checks null round-tripping and rejects a non-string display object.

8. **Guest file expected hash.** The canonical request shape in `70-fjord-needs.md` §2.1 defines `expectedSha256?: string | null`, where `null` means the file must not exist. There is no existing Rust guest-file write implementation in the cited Silo source; the spec is the authority for this new API contract. Modeled it as `Option<Option<String>>` with presence-aware deserialization. `expected_sha256_distinguishes_omitted_null_and_string` covers all three states.

9. **Force-stop result.** The old `macos_remote.rs::dispatch("macos.action")` returns a `MacosComputersState`, which is the evidence behind the review claim. The implementer brief makes the canonical spec authoritative, however: `30-macos-computers.md` §4 says `computers.forceStop` returns none and retires the old `macos.action` result path. Kept the canonical unit result (`null`) and added `force_stop_uses_canonical_null_result_without_retired_remote_snapshot` to lock that contract. Returning the legacy state here would violate the newer spec.

10. **Clipboard discriminator.** The native clipboard status enum uses kebab-case, and `30-macos-computers.md` §6 specifies the read kind `too-large`. Changed `ClipboardContent` to kebab-case. `clipboard_too_large_discriminator_is_kebab_case` asserts the exact tagged value.

11. **Handshake capabilities.** Native `remote.rs::capabilities()` advertises strings, and its consumer collects `Vec<String>`. Changed `HandshakeResult.capabilities` from `Vec<MethodName>` to `Vec<String>` so newer peers can advertise unknown capabilities. `handshake_capabilities_accept_unrecognized_strings` round-trips an extension capability.

12. **Computer-use receipt fields.** The macOS guest receipt writer emits `schemaVersion`, `state`, `reason`, `chatgptVersion`, `lcuVersion`, `approval`, and RFC 3339 `at`. Spec 40 §4 says receipt-derived fields stay null until read. Added `schema_version`, `chatgpt_version`, and `at`, and made `state` nullable. `computer_use_state_round_trips_macos_receipt_and_unread_state` checks a receipt and the pre-read null state.

13. **Migration stage.** `runtime_migration::MigrationState.stage` is a `String`, initialized to `Ready` or `Checking existing computers`. Changed the API field to `String`. `migration_stage_is_a_required_native_string` round-trips the source shape and rejects `null`.

## Whole-crate scan

- Audited tagged and untagged enums with struct variants. The other multiword variant fields already use `rename_all_fields = "camelCase"`; remaining variant fields are single-word names or have explicit serde renames.
- Matched explicit-null versus omitted behavior for source projections. In addition to the findings, `LogPage` cursor/boundary options and `StorageState`/`ReclaimEntry` nullable values now serialize as `null`, matching native `Option` fields without skip attributes. `DesktopStatus` version, user, display, and backend also preserve the explicit nulls emitted by `desktop.rs`. The log and storage round-trip tests cover these cases.
- Audited timestamp types. Storage uses numeric epoch seconds and is fixed above; log timestamps remain strings as in `runtime_logs.rs`. Checkpoint `createdAt` intentionally remains an ISO string because the API spec defines the UI contract and the Linux adapter converts its internal numeric timestamp at the boundary.
- Audited kebab-case values against source/spec labels. `ClipboardContent` was the mismatch; other kebab-case status/reason enums already match their native source or canonical discriminator.
- The current Tauri storage loader can synthesize `trigger: "legacy"` from an old `lastTrimAt` record (`runtime/storage.rs::load`). The canonical plan says to normalize that historical value at launch through `runtime_migration` (10 §Q13; 95 §3), not expose a legacy API variant. The engine track must complete that launch normalization before `storage.read` can return this shape to canonical clients.

## Verification

All commands ran against this worktree with `CARGO_TARGET_DIR=/Users/polarzero/silo-work/p1-api/target` where Cargo builds were involved.

- `cargo run --manifest-path app/SiloUI/api/Cargo.toml --example generate_schema` — regenerated the schema.
- `cargo test --manifest-path app/SiloUI/api/Cargo.toml --locked` — 26 unit tests passed; 0 doc tests failed.
- `cargo clippy --manifest-path app/SiloUI/api/Cargo.toml --locked --all-targets -- -D warnings` — passed.
- `cargo fmt --manifest-path app/SiloUI/api/Cargo.toml --check` — passed.

These are API crate tests using serde payload fixtures based on native structs/tests and the cited spec; no app or live computer was launched. The P2 Swift client should regenerate from the updated schema and model `expectedSha256` as absent, null, or a string. Its storage tests should also cover that launch normalization removes the temporary native `legacy` trigger before returning API state.
