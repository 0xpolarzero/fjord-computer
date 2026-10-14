# live-fixes (engine/live-fixes)

Commit `99465a6b`, fast-forwarded into Silo main (main had not moved; no merge needed). Not pushed.

## Built

1. **No Keychain UI, ever.** New `silo_engine::credential_store`. `forbid_interaction()` calls `SecKeychainSetUserInteractionAllowed(false)`; silod calls it first thing in `run_appkit`, so every Keychain call of the process (keyring uses the legacy SecKeychain API) fails with errSecInteractionNotAllowed instead of showing a dialog. `describe()` maps OSStatus -25293, -25308 and -128 (reached through keyring's `PlatformFailure` / `NoStorageAccess`, downcast to security-framework 2.11, added as an aliased engine dependency) to one stable message containing `credential_access_denied`. Applied to every Keychain read, write and delete in `github.rs` (account, runtime-grants ledger), `github_personal_token.rs`, `secrets.rs` and `macos_computers/proxy_ca.rs`.
2. **Typed error.** `silo_api::ErrorCode::CredentialAccessDenied` (`credential_access_denied`); schema regenerated. The silod dispatcher upgrades an `internal` error whose message carries the marker (both `DispatchError::internal` and `error_response`), so a client can show "Allow Silo's engine to use its saved sign-in". Client generators (Fjord's Swift client) need a regeneration to know the new code.
3. **Unattended paths skip and retry.** The proxy migration thread now runs through `drive_proxy_bootstrap_migration`: macOS Start opens after the first pass whatever its result; a pass refused by the Keychain is logged and retried every 15 minutes (idempotent per computer); other failures are reported once.
4. **LSUIElement.** Removed from `Info.development.plist` and `Info.production.plist`; both local (`build_desktop.py`) and release (`package-macos-release.py`) packaging copy these through `embed_engine.py`. silod still sets accessory at runtime, and if AppKit refuses it, it logs and continues instead of exiting.
5. **Stable signing.** `build_desktop.py` had no identity variable (everything was ad hoc `-`), so I added `SILO_ENGINE_SIGNING_IDENTITY` to `embed_engine.codesign_engine` (default `-`, so release is unchanged unless set). Documented in `docs/SiloUI-ENGINE.md` ("Signing the dev silod with a stable identity"), including how to seal a hand-assembled bundle and the one-time Always Allow.

## Tests (all green)

- `cargo test --locked -p silo-engine -p silod -p silo-api --no-fail-fast`: engine 2708 passed, silod 245, api 30, integration tests passing. `cargo fmt --all --check` clean.
- New: credential_store (status set, stable message, refusal vs other failures via constructed keyring errors, interaction really forbidden after `forbid_interaction`); silod migration tests (runs once and completes and opens Start; a refusal skips, opens Start and retries until done; a refusal stops when asked, other failures do not retry); dispatcher test for the new code; `test_embed_engine` (no LSUIElement in either channel or the embedded bundle; signing identity default and env override).
- Script tests `test_embed_engine`, `test_macos_release`, `test_desktop_release`: OK. silo-ui was not built (not touched).

## Notes

- Not run live (no VMs, apps or real Keychain). The unit tests cannot trigger a real Keychain refusal; the live rerun should confirm that `SecKeychainSetUserInteractionAllowed(false)` yields `credential_access_denied` for the ad-hoc silod on the real `org.silo.dev.github` item.
- Because Keychain UI is now forbidden in the whole silod, a user-initiated GitHub sign-in over silod also fails fast on a denied item. Approval must happen with a stable identity (or Keychain Access) rather than through a dialog.
- Not covered: the bundle template for a launchd-started silod without LSUIElement briefly shows as a regular app before the accessory call; untested live.
