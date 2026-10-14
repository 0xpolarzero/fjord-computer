# P2 dispatch keystone

Silo branch: `engine/p2-dispatch` from `main@17e6d50b`  
Silo commit: `bd7c7c2754b9a3e98b659b579b1a58108c844e66` (`refactor(silod): dispatch methods through domain handlers`)

## Built

- Added the six per-domain handler modules under `silod/src/methods/` and routed domain methods through them after the existing core engine, event, operation, and notification arms.
- Added `HandlerContext` with access to `EngineContext`, the silod context, lazy job-registry access, the sequenced event bus, and negotiated client identity. It also provides typed parameter decoding, durable job allocation or domain-ID acceptance returning `JobStartResult { jobId }`, and mappings from engine bridge and registry errors to `silo-api` error codes.
- Kept the handshake capability list at the same nine built-in methods. All canonical API methods can reach dispatch; methods that a domain handler does not implement still return the same unsupported error.
- Added a registry-wide routing test. It checks that each of the 137 domain methods has exactly one domain owner, and that the nine built-in methods do not overlap a domain owner.

The implementation follows 95 §3's canonical-only rule and the 05 `#job-contract`. The 80 §3 unified method index is the reference for the full API registry. No spec/code disagreement affected this dispatch-only change.

## Handler contract for domain tracks

Use this exact async signature in each domain module:

```rust
pub async fn handle(
    method: silo_api::methods::MethodName,
    params: &serde_json::Value,
    context: &crate::methods::HandlerContext,
) -> Option<
    Result<
        crate::dispatcher::HandlerOutput,
        crate::dispatcher::DispatchError,
    >,
>
```

Return `None` when the module does not own `method`. Return `Some(Err(...))` or `Some(Ok(...))` when it owns the method. The current scaffolds return `Some(Err(unsupported))` for owned methods until their implementation lands. Keep each module's `owns` predicate aligned with its assigned prefixes; the registry-wide test catches gaps and overlaps when the canonical API changes.

`HandlerContext` exposes `engine_context()`, `silod_context()`, `job_registry()`, `event_bus()`, `client_identity()`, and `client_id()`. Decode request params with `decode_params::<silo_api::...Params>(params)`. Use `start_job(method)` for engine-allocated `job:` IDs or `start_job_with_id(method, job_id)` when the domain owns the job identity. Both return the canonical `JobStartResult` containing `jobId`. Successful handlers return `HandlerOutput { value, event_barrier }`.

## Verification

- `cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --check` — passed.
- `cargo +1.94.0 check --manifest-path app/SiloUI/Cargo.toml --locked -p silod` — passed.
- Focused `every_domain_method_routes_to_exactly_one_domain_module` test — passed.
- `cargo +1.94.0 test --manifest-path app/SiloUI/Cargo.toml --workspace --locked` — passed: 2,465 passed, 30 ignored, 0 failed. Local native-test configuration used the documented synthetic GitHub values. Output is in the ignored Silo target directory at `target/verification/p2-dispatch-cargo-test.log`.

No app or VM was launched. The tests used local test fixtures; no live computer state was exercised. Cargo tests left an untracked SQLite registry fixture in the engine crate directory; it was removed after the run.

## Next tracks

Implement the owned methods in each module while preserving the signature above and using the shared context helpers. `computers`, `checkpoints`, `guest`, `access`, `display`, and `services` own the prefixes requested for P2 dispatch. The core still owns `engine.handshake`, `engine.state`, `events.*`, `operations.*`, and `notifications.list`.
