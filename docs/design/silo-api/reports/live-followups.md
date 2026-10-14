# Live follow-ups (engine/live-followups), 2026-10-14

Branch `engine/live-followups` off Silo main `e87a0669`; main had not moved. Fast-forwarded into the `microsandbox-workspaces` main (`f501d99e`). Not pushed. No VMs.

## Commits
- `1777f0b8` feat(engine): SecureToken restored for an imported computer.
- `953e9b6b` test(engine): developer tools install node and claude; template base follows their pins.
- `f212390b` test(engine): port-publish ordering.
- `a181395f` test(engine): launch migration graceful shutdown.
- `fcdfbe3a` test(engine): GitHub worker backoff on a refused item.
- `0e1c6609` test(silod): network.* routing for macOS computers.
- `f501d99e` style: drop an unneeded mut.

## 1. SecureToken after import
`personalize_import` (provision.rs), after key login with `sudo -n` is proven and before the shutdown, runs `personalize::secure_token_script()` as root over guest SSH. The script reads the account password from stdin into a shell variable (never in the script, the command or the host-side argv). It reads `sysadminctl -secureTokenStatus silo`; only if that is not ENABLED does it run `sysadminctl -secureTokenOn silo -password … -adminUser silo -adminPassword …` (the working account as its own admin, with the password Silo holds), then reads the status again and prints `SILO_SECURETOKEN=enabled|disabled|unknown`. It is idempotent. The password does appear in sysadminctl's argv inside the guest for a moment (sysadminctl's prompt form needs a tty).
If the final status is not ENABLED, the import is still marked personalized and usable, but the setup reports a failure detail ("Silo could not turn on SecureToken … otherwise ready to start"), the same pattern as the disk-shortfall message. Template copies are unaffected (dscl -passwd with the old password keeps the token).
Tests: status parsing (enabled, disabled, other user, empty), command construction (password never in script or command, status guard before `-secureTokenOn`, two status reads, base64 round trip), outcome parsing, stdin input.
**Not verified live.** Risk: `-secureTokenOn` needs an admin that already holds a token. On an imported disk nobody does, so this may fail; if the live run shows that, the fallback is a token-granting login (the account logging in at the login window) or an `fdesetup`/`dscl` route. The failure is visible, not silent.

## 2. Unit tests for the live-only fixes
Small refactors made the code testable without behaviour change:
- Port publish: `save_mapping_then_start` (ports.rs) saves, then runs the tunnel start closure. Tests: the mapping is on disk when the start runs; a failing start restores the previous mappings; a host port taken by another computer is refused before any start.
- silod routing: test `network_calls_for_a_macos_computer_go_to_the_macos_store` writes a macOS computer record, then publishes, reads network.state (macOS row merged, Linux computer still listed) and unpublishes through the real handlers.
- GitHub worker: `defer_refused` and `pass_wait` extracted. Tests: a refusal waits 300 s, not 100 ms; the saved refresh time moves out so the worker is not due; a later refresh time is kept; the OPERATION lock is taken and freed by a pass. The pass itself is still a thread loop; the lock release is proven on the lock, not by running the loop.
- Launch migration: `stop_bootstrap_guest` extracted (bootstrap.rs). Tests: graceful shutdown that releases the machine never calls the force stop; a guest that ignores it is force-stopped after the wait; a failed script is force-stopped with no shutdown; a held machine is an error; the stop error is reported after release.

## 3. Agent tools on macOS
Confirmed on main (`819367b3`): `silo-developer-tools.zsh` installs Node (tarball, linked into /usr/local/bin) and Claude Code (pinned bootstrap.sh run as the working account, linked to /usr/local/bin/claude), verifies both, and writes `nodeVersion`/`claudeVersion` into the receipt. `developer_tools::version()` hashes script + lock, and `templates::setup_version()` includes `developer_tools::setup_inputs()`, so the fingerprint bump makes the existing template (`25G83-2dd2…`) stale: it is refreshed rather than copied, and existing computers take the developer-tools retry. Existing tests covered the pins and the developer-tools fingerprint; added: the script installs and verifies node and claude, and the template base changes when either pin changes. Note for the owner: the next live run must rebuild the template (a new IPSW download unless the base image is cached).

## Gate
`cargo test --locked -p silo-engine -p silod -p silo-api --no-fail-fast`: engine 2742 passed (32 ignored), silod 278, api 31, integration tests green. `cargo +1.94.0 fmt --all --check` clean. Without the bundled Git runtime, 8 `host_push` tests fail on any checkout (environment, "prepare the bundled Git runtime"); I symlinked `src-tauri/runtime/git` from the main checkout (git-ignored) for the run. One pre-existing unused-mut warning in runtime/checkpoints tests is untouched.
