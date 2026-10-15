# keychain-repair (Silo engine/keychain-repair, Fjord main)

## Silo (worktree ~/silo-work/live-final, fast-forwarded into microsandbox-workspaces main; not pushed)

Commits: `5e33aed2` (flaky tests), `1e749670` (SecureToken note), `086fb8d4` (Keychain repair).

1. **Keychain repair.** `silo_engine::credential_access`; API `silo-api::methods::credentials`; handlers in silod `services.rs`.
   - `engine.credentials.status` (query, local only): the engine's items that exist (GitHub sign-in, token ledger, personal token, secrets vault, one proxy CA per macOS computer), each `accessible | denied | failed`, plus `deniedCount`. Absent items are not listed. Never prompts.
   - `engine.credentials.repair` (command, local only): probes without prompts, and only if something is denied opens an `InteractionWindow` (RAII: allow UI, forbid again on Drop, also on error or panic, one retry). It touches each denied item on a dedicated `keychain-repair` thread, forbids prompts again, re-reads the status and reports per item `alreadyAccessible | repaired | stillDenied | failed`. One repair at a time (`busy`).
   - Everything else stays non-interactive (`credential_store::allow_interaction` is used only here).
   - Limit: `SecKeychainSetUserInteractionAllowed` is process-wide, so an unattended Keychain call that overlaps a repair could also prompt. Documented in docs/SiloUI-ENGINE.md.
   - Tests (fakes only, no real items): item list, status projection and denied count, prompts allowed only while refused items are touched, no window when nothing is denied, restored after a failed open, a panic and a failing switch-off.
2. **SecureToken.** The import setup no longer fails on a missing token. Record `secureTokenMissing`, new `note: Option<String>` on the macOS computer row (informational, separate from `detail`). The previous `secure_token_failure` plumbing is removed.
3. **Flaky tests.** Cause 1: the macOS inventory is a process-wide registry loaded from disk once, so a computer written after another test loaded it was not found. The test now holds the registry and process-gate locks and resets the inventory. Cause 2: command sessions are a process-wide table keyed by job id while every fixture registry hands out `job:1`, so two fixtures read each other's job. The two tests that start local jobs now share a test lock. The silod lib suite passed 7 of 7 consecutive runs (before: 2 of 3 failed).
4. **Gate.** `cargo test --locked -p silo-engine -p silod -p silo-api --no-fail-fast`: api 32, engine 2748 (32 ignored), silod 278 and all integration tests passed; `cargo +1.94.0 fmt --check` clean. The schema was regenerated (148 methods). silo-ui was not built or touched.

## Fjord (main)

- Commits: `27f09a58` (regenerated client; manifest pinned to Silo `086fb8d4`, 148 methods) and the feature commit after it.
- `KeychainAccess.swift`: `KeychainAccessModel`, the `KeychainAccessBanner` ("After this update, Silo's engine needs your permission to use its saved credentials." with an Allow access button and the Always Allow instruction), and a banner condition that is true when `engine.credentials.status` has denied items or any shown error is the `credential_access_denied` text. It appears on Computers and at the top of the computers settings. Pressing the button calls `engine.credentials.repair`. A declined dialog names what is still blocked. A failure is shown and retryable. The refusal error text is cleared once access works. The status is read after the engine attaches (so after an update handoff) and when settings open. An older engine without the method is quiet.
- The `credential_access_denied` message now reads as above plus "Use Allow access on the Computers page or in Settings."
- The SecureToken note shows with an info icon in the computer overview, never as a failure.
- Shots: `computers-keychain`, `computer-secure-token-note` (checked visually).
- Tests: `KeychainAccessTests` (8). `swift build` and `scripts/test.sh` once: 1915 tests passed.

## For the owner
- `scripts/silod.commit` was not bumped (still `fc0f286f`); bump it to a Silo commit with `086fb8d4` so the bundled engine has the new methods.
- Not run live (no real Keychain): the first live run should confirm the dialog appears and Always Allow clears the denied items for the ad-hoc and the Fjord Dev builds.
- CLAUDE.md still says the binary is `FjordComputer`; it is `.build/debug/Fjord`.
