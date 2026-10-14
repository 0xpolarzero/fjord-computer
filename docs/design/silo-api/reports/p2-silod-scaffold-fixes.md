# P2 silod scaffold fixes

Fixed all four findings in `p2-silod-scaffold.review.md` on Silo branch `engine/p2-silod`.

## Changes

- Initialize `silo_engine::channel` from the validated engine manifest before resolving channel paths. A subprocess regression checks production and development global channels against the context identity.
- Treat `AlreadyExists` from concurrent state-directory creation as a race winner. Re-read metadata, require an euid-owned directory, set mode `0700`, and verify it. A barrier-synchronized two-process test makes both starts observe a missing directory before either creates it, then verifies both reach ownership arbitration and exactly one acquires the lease.
- Sync the Connections state directory after publishing `config.json` and removing its temporary name. Propagate directory-sync failures. The regression verifies publication and cleanup precede the sync and that its failure prevents returning the identity.
- Add optional typed `error.diagnostics` to the canonical API and generated JSON Schema. Incompatible handshakes now report `engineProtocolRange`, `clientProtocolRange`, `engineAppVersion`, and optional `clientAppVersion`; the engine version comes from `EngineIdentity`. The protocol diagnostics reflect the engine's currently supported `PROTOCOL_VERSION` range.

Each regression failed against the original behavior: development startup reported `Production`; simultaneous creation returned `AlreadyExists` before arbitration; identity publication returned without invoking directory sync; and incompatible handshakes had no diagnostics object. All regressions pass after the fixes.

## Commits

- `9fa42b50` `fix(silod): initialize engine channel from manifest`
- `347ed299` `fix(silod): tolerate concurrent state directory creation`
- `41bc45ac` `fix(silod): sync identity directory after publication`
- `81f51766` `fix(silod): report engine and client handshake diagnostics`

## Verification

- `CARGO_TARGET_DIR=/Users/polarzero/silo-work/p2-silod/target cargo +1.94.0 test --manifest-path app/SiloUI/src-tauri/Cargo.toml -p silod --locked` — passed: 30 unit tests and 1 handshake integration test.
- `CARGO_TARGET_DIR=/Users/polarzero/silo-work/p2-silod/target cargo +1.94.0 test --manifest-path app/SiloUI/src-tauri/Cargo.toml --workspace --locked --quiet` — passed with the documented synthetic GitHub build configuration: 2,229 UI tests passed, 30 ignored; 60 engine tests and 30 silod tests passed; integration tests passed.
- `CARGO_TARGET_DIR=/Users/polarzero/silo-work/p2-silod/target cargo +1.94.0 test --manifest-path app/SiloUI/api/Cargo.toml --locked` — passed: 27 API tests, including schema equality.
- `cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --check` — passed.
- `cargo +1.94.0 fmt --manifest-path app/SiloUI/api/Cargo.toml --check` — passed.
- `git diff --check` — passed.

No spec deviations. Tests used temporary fixture homes; no app or LaunchAgent was launched. The generated API schema is committed with the Rust wire types. Client tracks can read the optional `error.diagnostics` object when presenting incompatible-version details.
