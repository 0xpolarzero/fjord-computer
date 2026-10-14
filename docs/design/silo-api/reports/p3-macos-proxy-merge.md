# P3 macOS proxy merge into Silo main

Silo `main` fast-forwarded to `6ab2c975` (branch `engine/p3-macos-proxy`).

## Commits
- `4407bce3` merge(engine): integrate jobs, events and dispatch into macOS proxy (`git merge --no-ff main`, main at `bd7c7c27`).
- `6ab2c975` style(engine): format merged jobs and dispatch code (`cargo fmt --all`; main's engine and silod files were not formatted under `cargo +1.94.0 fmt --all`, though the `silo-ui`-only check the brief names passed).

## Conflict
Only `macos_computers.rs`, in `perform` and `start`.
- `start` took main's job-accepting lifecycle (`accept_loaded_lifecycle_job`, `admit_macos_job`, queued re-validation) and keeps the proxy's `ensure_proxy_bootstrap_migration_ready()` right after `require_supported()`.
- `perform` took main's per-action gating. The proxy's blanket launch-migration gate (everything except Stop/ForceStop) is kept: `with_macos_computer_operation` already calls it, and I added it explicitly to the `Delete` and `Setup` arms. `start_at_launch` still gates too.
- Provisioning and startup hooks merged without conflicts.

## Gate
- `cargo test --workspace --locked` from `app/SiloUI`, with the synthetic GitHub env values and `CARGO_TARGET_DIR=…/p3-macos-proxy/target`, `CARGO_BUILD_JOBS=4`: all pass, 0 failed. The engine binary ran 2348 passed and 30 ignored; the other binaries had 27, 71, 41, 1, 1 and 1 passed.
- `cargo +1.94.0 fmt --all --check`: clean after the style commit. The style commit is format-only; after it I re-ran `cargo build --workspace --tests --locked` (green) but not the full test run.
- No VMs or apps started. Live qualification (still pending, see p3-macos-proxy-2.md) remains a separate task.

## Next
Macos parity part 2 had not landed on main (main was at `bd7c7c27` when I merged), so no retry was needed. Anything merging later must merge main (now `6ab2c975`) first.
