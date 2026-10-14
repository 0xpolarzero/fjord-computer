# P3 macOS proxy implementation report

**Code and build gates passed. Live guest qualification is blocked by the 60 GB disk floor.** The merge and bootstrap integration are committed; the unfinished Dev-only macOS install and its restore image were removed.

## Commits

- `9a956f07a1722c002283fb21d8ad1b67e2d0f2ec` — `merge(engine): integrate macOS provisioning parity` (merged `main` with `--no-ff`; resolved the macOS computer command overlap and fixed the guest SSH endpoint type in the merged code).
- `aec9397036d606bc3e2d3c07dc39dd6afa4f8661` — `fix(macos): stage proxy bootstrap during setup and startup migration`.

## Changes

- Provisioning stages the guest network helper, proxy CA trust, DNS/route configuration, placeholders, and persisted bootstrap identity after setup is complete. A fully provisioned copied template gets this before personalization leaves NAT; an incomplete copy stays on NAT until final setup.
- The sole old-computer conversion runs from startup after backup/configuration recovery and before lifecycle recovery or start-at-launch. Start and computer-changing operations are gated until the launch pass finishes; ordinary Start still requires persisted bootstrap state and fails closed when it is missing.
- The macOS Tauri overlay now bundles the existing MicroSandbox and Git executables along with the proxy gateway/bootstrap helpers. The original overlay replaced those base tools, which made the first debug launch show `msb is missing`; the corrected bundle loaded Silo Dev and its UI.
- Added a patch changeset and regression coverage for provisioning readiness, startup migration order, and macOS external binary packaging.

## Verification

- Full workspace command: `SILO_GITHUB_APP_SLUG=silo-test SILO_GITHUB_CLIENT_ID=test-client SILO_GITHUB_CLIENT_SECRET=test-secret CARGO_TARGET_DIR=/Users/polarzero/silo-work/p3-macos-proxy/target CARGO_BUILD_JOBS=5 cargo test --quiet --manifest-path app/SiloUI/Cargo.toml --workspace --locked` — exit 0; 2,420 passed, 0 failed, 30 ignored across 11 test binaries. The log is `target/verification/p3-macos-proxy-2-cargo-test.log`.
- Formatting: `cargo +1.94.0 fmt --manifest-path app/SiloUI/src-tauri/Cargo.toml --check` — exit 0.
- Packaging test: `node --test app/SiloUI/scripts/linux-package-tools.test.mjs` — 4 passed, 0 failed.
- Dev bundle: `SILO_GITHUB_APP_SLUG=silo-test SILO_GITHUB_CLIENT_ID=test-client SILO_GITHUB_CLIENT_SECRET=test-secret CARGO_TARGET_DIR=/Users/polarzero/silo-work/p3-macos-proxy/target CARGO_BUILD_JOBS=5 npm --prefix app/SiloUI run desktop:build:debug` — exit 0. This ran `tsc -b` and Vite and produced the exact Dev bundle listed above. Verified executable entries: `silo-ui`, `msb`, `git`, `git-lfs`, `git-remote-http`, `git-remote-https`, `silo-macos-gateway`, and `silo-network-bootstrap`.
- Build and tests used only synthetic GitHub App values. No real account, GitHub OAuth, or publishing flow ran.
- Repository worktree is clean after the two commits.

## Live qualification

The host was macOS 26.5 (25F71), arm64; Silo Dev was 0.11.1; MicroSandbox was 0.7.6 at `09df3d4b9d832adaede1fb9a198cfc660bfab8cd`.

One Dev computer was created with 8 GiB memory. During macOS installation, `df -g /` fell from 62 GB to 59 GB in 15 seconds. The live probe rules require stopping below 60 GB. I cancelled the install at that point; Silo removed the computer. I removed the restore image that this attempt downloaded. Final preflight reported 90 GB free, zero Dev macOS computer records, zero cached restore images, no Silo Dev process, and no open VM or restore-image files. No guest-level probe ran.

The requested live checks therefore remain unproven: guest System-keychain trust, default DNS, allowed-host-only substitution, revocation of an open connection, two-computer isolation, and launch migration on an existing computer. See [the probe record](../probes/p3-macos-proxy-2.md) and its sanitized host capture at `~/silo-probes/p3-macos-proxy-2/evidence/final-preflight.txt`.

To finish live qualification, rerun on a host with enough free disk to complete both the restore and guest installation while keeping at least 60 GB free, or use an approved flow that clones the existing Dev template without modifying it.
