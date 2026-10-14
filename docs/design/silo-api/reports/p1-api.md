# P1-api implementation report

## Built

Added the standalone `silo-api` crate at `app/SiloUI/api`. It contains serde and schemars types only; it has no Tauri dependency, dispatcher, or engine logic.

The crate defines:

- Request and response envelopes, handshake parameters/results with a protocol range and method capabilities, and the stable error object.
- The 23 snake_case error codes: the 8 existing codes and the pending guest, file, exec, and macOS codes listed by the spec.
- The six validated `JobId` spaces, source-tagged job progress with per-source data, job completion and lookup types, and the acknowledge method params.
- The sequenced event envelope and all 26 events in 05 §4.2 D.
- A typed method registry for all 146 methods in 80 §3, including kind, params type, and result type. Domain types are grouped under `methods::*`.
- Schemars 2020-12 JSON Schema at `app/SiloUI/api/schema/silo-api.schema.json`. The schema root includes all method param/result unions and registry metadata (`x-silo-methods`) plus the method-specific job completion catalogue (`x-silo-job-results`). A test compares the committed schema byte-for-byte to a fresh generation.

Types that mirror Silo Rust types include source file citations in their doc comments. Where the canonical API adds platform discriminators or replaces name references with IDs, the comments call that out.

## Commits

- `f5cb77b3 feat(api): add standalone wire contract crate`
- `70abe9f5 feat(api): add canonical method and event contracts`
- `57a0a6f7 feat(api): generate checked-in contract schema`

## Verification

Commands ran from `/Users/polarzero/silo-work/p1-api`. Cargo build, test, clippy, and schema-generation commands used `CARGO_TARGET_DIR=/Users/polarzero/silo-work/p1-api/target`; `cargo fmt` is target-independent.

- `cargo test --manifest-path app/SiloUI/api/Cargo.toml` — passed, 13 unit tests; 0 doc tests.
- `cargo clippy --manifest-path app/SiloUI/api/Cargo.toml --all-targets -- -D warnings` — passed.
- `cargo +1.94.0 fmt --manifest-path app/SiloUI/api/Cargo.toml -- --check` — passed.
- `cargo run --manifest-path app/SiloUI/api/Cargo.toml --example generate_schema` — passed; generated schema matches the committed file.

The crate was tested standalone. No VM, app, or live computer state was used.

## Spec gaps and choices

- `operations.job.finished.result` remains an untagged JSON value because its type depends on the job-starting method. The schema lists all 29 terminal result mappings separately. The spec leaves the macOS result shape unresolved for the new adapters called out by Q13 / 80 B-34, including configuration change/retry, restart, identity configuration, and `computerUse.setup`; 20 §1.2.5 also leaves the new macOS `checkpoints.abandonRestore` result open. The result catalogue records sourced branches and the report does not claim those adapters are resolved.
- 05 §4.2 D describes `checkpoints.changed` only as “those results” and does not define an exact wrapper or union. Its event payload is `serde_json::Value` pending that shape.
- 50 §2 leaves `computerOperations[].diagnosticDetails` unspecified, so it is `serde_json::Value`.
- 30 §6 fixes the clipboard read discriminator but leaves the rest of its payload open. The proposed read type uses `{kind:"text", text}` and `{kind:"image", mime, bytes}`, alongside `empty` and `too-large`. The spec does not define a JSON binary encoding; `Vec<u8>` serializes as a JSON integer array. `clipboard.write` declares no result shape, so its result is `null`.
- 50 does not fix the successful `sshAccess.connection` response when `download:true`. The type is `Option<String>` to preserve the current source's nullable result and its command-string result for `download:false`.
- `migration.preUpgradeBackup.delete` and `migration.preUpgradeBackup.acknowledgeNotice` do not define result payloads; they use `null`.
- 05's `settings.changed` row says the snapshot is “without the draft,” while 60 §2.1 explicitly says the API snapshot's `onboardingDraft` is always `null`. The type follows the detailed 60 contract and includes `onboardingDraft: null`.
- 05 requires update progress to preserve the current `updates::Snapshot`, which has `installStatus`; 60 §5.1 excludes `installStatus` from the method/event snapshot. The crate therefore has a source-shaped `UpdateProgressData` with `installStatus` and a separate method/event `UpdateSnapshot` without it.
- 05 defines macOS job progress as `computerId` while the current `MacosComputer` source row names the field `id`. The job projection follows the explicit 05 contract and uses `computerId`.
- Byte fields for guest exec and guest files use `Vec<u8>` and therefore JSON integer arrays. The spec names bytes but does not select a JSON encoding.

## Handoff

The crate remains self-contained. When the engine Cargo workspace is ready, add `../api` as a member from `app/SiloUI/src-tauri` and add `silo-api = { path = "../api" }` to the engine crate. Keep `app/SiloUI/api/Cargo.toml` so this crate remains independently buildable.

P2 can use the public method unions, event envelope, and job types directly. The crate defines contracts only; dispatch, event sequencing, job persistence, and durable `job:<n>` allocation remain engine work. The durable job ID and recovery questions remain probe B-37 in the spec.
