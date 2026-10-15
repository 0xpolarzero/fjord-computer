# Live macOS qualification, final run (engine/live-final)

Run date 2026-10-14 to 15. Host macOS 26.5 (25F71), arm64, 64 GiB. Guest macOS 26.6.2 (25G83). MicroSandbox 0.7.6. Silo branch `engine/live-final` off main `f501d99e`; one fix commit `a94924d2`, fast-forwarded into the `microsandbox-workspaces` main. Not pushed. Evidence: `~/silo-probes/live-final/evidence/` (numbered logs, `silod.out`, `cargo-test.log`); probe sources: `~/silo-probes/live-final/src/` (`eng.py`/`lib.py` engine.sock client, `t_*.py`, `hand.py`, `sign.sh`, `startsilod.sh`, `startiso.sh`).

Setup. silod ran as a plain process (not a LaunchAgent) from a hand-assembled `Silo Dev.engine.app` (the e2e bundle's msb, git, libkrunfw and resources; silod, `silo-macos-gateway` and `silo-network-bootstrap` built from this branch). Every Mach-O and the bundle were signed with the stable identity `Fjord Dev` (hardened runtime, hypervisor / virtualization entitlements): designated requirement `identifier "org.silo.dev.engine" and certificate leaf = H"93aa9415..."`. No Keychain dialog appeared and none was answered. Synthetic credentials only. Two bundles were used for the handoff: engineVersion 0.1.1 and a rebuilt silod with engineVersion 0.1.2 (manifest `live-final-newer-development`).

## Verdicts

| # | Item | Verdict |
| --- | --- | --- |
| 1 | Template rebuild from the IPSW; node, claude, git, git-lfs in the guest | PASS |
| 2 | Proxy 1b: substitution only to the allowed host; live revocation on an open connection | PASS (with a public echo, not a local one: see the note; the existing vault item was refused, reported below) |
| 3 | Archive round trip on the final build, SecureToken restore after import | PARTLY. Export, import, personalization, marker, volume ownership, developer tools, proxy: PASS. SecureToken restore: FAIL (the new code runs, `sysadminctl -secureTokenOn` is refused; no admin holds a token). One bug found and fixed: that failure aborted the rest of the setup. |
| 4 | Handoff to a newer silod (prepare, swap, new silod, computer resumes, uptime continues) | PASS only after the owner-side Keychain step (see 5); without it the newer silod could not resume the computer (FAIL as a stable-identity promise) |
| 5 | Keychain access stays granted across a rebuild of silod with the same identity | FAIL: each build is refused its predecessor's items, because of the Keychain partition list (cdhash), not the signing identity |

Gate: `cargo test --locked -p silo-engine -p silod -p silo-api`: api 31, engine 2743 passed (32 ignored), silod 278 passed in 2 of 4 runs; the other two runs each failed one test of the shared silod fixture (`methods::access::tests::network_calls_for_a_macos_computer_go_to_the_macos_store`, and once `methods::guest::tests::an_owner_serves_a_controllers_command_as_its_own_job_with_replayable_output`). Both pass alone; the first one is the test added by `0e1c6609` and reads the process-wide `RUNTIME_HOST` fixture, so it depends on test order (a flake that predates this run; not fixed). `cargo +1.94.0 fmt --all --check` clean. `evidence/cargo-test.log`.

## 1. Template rebuild

The existing template `25G83-2dd244051a124c53-...` was stale (developer tools now include node and the Claude CLI). `computers.create` (macos, 4 CPU, 8 GiB, 40 GiB) on a silod from this branch downloaded the IPSW (18 GB, about 5 min), installed, set up and finished at about 15 minutes. The old template was removed by Silo; the new one is `25G83-4014150a1bcfa7b8-89b9692006544ead` (`template.json`: setupVersion `4014150a1bcfa7b8`, computerUseVersion `89b9692006544ead`). Evidence: `01-create-qa-main.txt`, `10-tools.txt`.

```
sw_vers: 26.6.2 (25G83) arm64, user silo
git version 2.50.1 (Apple Git-155)      /usr/bin/git
git-lfs/3.8.0 (GitHub; darwin arm64)    /usr/local/bin/git-lfs
v24.21.0 (node)  npm 11.19.0            /usr/local/bin/node, npm
2.1.287 (Claude Code)                   /usr/local/bin/claude -> /Users/silo/.local/bin/claude
gh 2.102.0, xcode-select -p = /Library/Developer/CommandLineTools
```

A computer copied from it started in 21 to 24 s; the setup of a copy takes about 80 s.

Disk. The free space went from 88 GB to 35 GB at the lowest during the rebuild (IPSW plus install) and recovered to 54 GB when Silo deleted the IPSW. Nothing was cancelled.

## 2. Proxy 1b

Vault. With an engine signed `Fjord Dev` against the real login keychain, `secrets.save` still returned `credential_access_denied` ("Allow Silo's engine to use its saved sign-in in the macOS Keychain."), and no dialog (`20-vault-denied.txt`). The refused item is the one the previous run named, made by an older ad-hoc build: service `org.silo.dev.secrets`, account `values` (the GitHub item is `org.silo.dev.github`). I did not read, change or delete it. The owner can add access in Keychain Access (Get Info, Access Control, add the `Silo Dev.engine` app and choose Always Allow), or delete the item.

Isolated scope. Then the substitution test ran in a separate HOME (`~/silo-probes/live-final/home`): its own `Library/Application Support/org.silo.dev`, its own `~/.silo-dev` socket, a template cloned with `cp -c`, and its own empty-password keychain made with `security create-keychain` and set as that HOME's default. The vault and the per-computer CA were then created fresh by the `Fjord Dev` silod (`51-iso-vault.txt`).

Local echo. A local HTTPS echo is not reachable by design. The gateway applies the `Public` egress group only (`NetworkPolicy::from_profiles([Public])`), which excludes loopback, private and host addresses, and DNS refuses rebinding names (`21-proxy-1b.txt`): from the guest `curl http://localtest.me:8099/` is "Could not resolve host", and `http://<LAN address>:8099/` and `http://host.microsandbox.internal:8099/` are "Couldn't connect". So the echo hosts were public ones, with only a synthetic value (`synthetic-secret-AAAA1111`) leaving the Mac, and only toward the allowed host.

Substitution (secret `ECHO_KEY`, allowed domain `httpbin.org`; in the guest `ECHO_KEY=$MSB_ECHO_KEY`, a placeholder):

```
curl https://httpbin.org/headers      -H "X-Api-Key: $ECHO_KEY"  ->  "X-Api-Key": "synthetic-secret-AAAA1111"
curl https://postman-echo.com/headers -H "X-Api-Key: $ECHO_KEY"  ->  "x-api-key":"$MSB_ECHO_KEY"
curl https://httpbingo.org/headers    -H "X-Api-Key: $ECHO_KEY"  ->  "X-Api-Key": ["$MSB_ECHO_KEY"]
curl http://httpbin.org/headers (port 80) -> curl: (52) Empty reply from server
```

PASS: substituted only for the allowed host; the placeholder stays for other hosts; plain HTTP is not served.

Live revocation (`22-proxy-revocation.txt`): a guest Python process opened one HTTPS connection to httpbin.org (substituted, status 200), the host called `secrets.remove`, and the next request on the same connection failed with `RemoteDisconnected` (the policy update closes previous connections). A new connection then sent `"X-Api-Key": "$MSB_ECHO_KEY"`, and `ECHO_KEY` was gone from the guest environment. PASS.

## 3. Archive round trip

The disk is the limit on this Mac. An export of a 40 GiB macOS computer stages about 22 GB in the local data folder, and the archive is 23 GB (23,040,783,446 bytes); an import writes about 40 GB for the computer. With 53 GB free the first export attempt was cancelled by my guard at the 30 GB floor, and the first import was cancelled at 29 GB. Both then ran with the archive on the external volume `/Volumes/ModelVault` (the export destination) and, for the import only, `macos-computers` temporarily replaced by a symlink to that volume (put back at the end). The engine accepted both. Evidence: `30-archive.txt`, `30-archive-run.txt`, `31-archive-import.txt`, `32-import-personalize.txt`, `33-run.txt`, `34-token-investigation.txt`, `35-imported-computer-checks.txt`.

- Export of the stopped computer `qa-main` (SecureToken ENABLED, Owners Enabled, marker file): 804 s, "Verified export file", lowest local free 33 GB.
- Import as `qa-imp`: 268 s. The computer arrives needing personalization (`needsPersonalizing: true`). `macos.setup.retry` personalized it (offline password rewrite, key login with `sudo -n`, status 0).
- Marker file intact. `diskutil info`: Owners Enabled on `/` and `/System/Volumes/Data`. Developer tools present (git, node v24.21.0, claude 2.1.287). The network bootstrap receipt `status: ready`, proxy CA trusted, `https example.com: 200`.
- SecureToken after import: DISABLED. The engine's new step ran (`secure token: status 0; stdout: SILO_SECURETOKEN=disabled`). Why: `sysadminctl -secureTokenOn silo ... -adminUser silo` fails with "setSecureTokenAuthorizationEnabled error ... Code=5101 ... credentials are not authorized" (in the guest, by hand) and with "Operation is not permitted without secure token unlock" when the password is wrong: no user on the imported disk holds a token, and `-secureTokenOn` needs one that does. The disk still has the cryptographic user record (`diskutil apfs listCryptoUsers`: `F2F955EB-...`, the same GUID as `silo`'s GeneratedUID, Volume Owner: Yes), but it is wrapped by the source computer's password, which is not in the archive. `dscl . authonly`, `sudo -u silo` and root do not grant a token. INFERRED: the remaining ways to get one are a login-window login with the password typed (macOS grants the first token to the first login when none exists), or keeping the source's password for the imported account instead of rewriting it offline. Both are design decisions, not small fixes; see "To decide".
- Bug found and fixed (`a94924d2`): the SecureToken failure returned straight out of `personalize_import`, before the developer tools, computer use and the network bootstrap steps and before `imported = false`. The first retry therefore ended "failed", the detail said "It is otherwise ready to start", and Start refused it (`needs_personalizing`); only a second Retry setup finished it, silently. The failure is now returned after the other steps. Test: `only_a_missing_secure_token_is_reported_after_an_import_is_finished`. Live check on the fixed silod (`36-reimport-fixed.txt`, `37-retry-fixed.txt`, `38-start-after-token-failure.txt`): a fresh import (256 s), one Retry setup of 212 s that ran every step, `setupComplete: true`, the SecureToken message as the detail, and `computers.start` worked (19 s; node, claude, marker, `https example.com: 200`).

## 4. Handoff to a newer silod

Old silod: engineVersion 0.1.1. New silod: a rebuilt binary, engineVersion 0.1.2 (`engine-owner.json` shows `0.1.2`, `live-final-newer-development`), signed the same way. On a running computer: a heartbeat process writing the time each second, and a marker file. Evidence: `40-handoff-newer.txt`, `40-handoff-poll.txt`, `41-diag-copy-path.txt`, `42-handoff-newer-iso.txt`.

- Without any Keychain step (real login keychain, `qa-main`): `engine.update.prepare` worked (3 s, "resuming": the computer), `engine.shutdown {reason: update, stopComputers: false}`, the new silod started and could not resume: `silod: the macOS network migration was skipped, the Keychain asked for approval: qa-main: Allow Silo's engine to use its saved sign-in in the macOS Keychain. (credential_access_denied)`. The computer stayed `stopped` with `updatePending: true` for the whole 2-minute poll. FAIL.
- The old binary at a copied path (same cdhash) resumed it in 20 s (`41-diag-copy-path.txt`). So the path does not matter; the binary does.
- With the new build's cdhash added to the items' partition list (what the owner's Always Allow does; in the isolated keychain, with `security set-generic-password-partition-list`): prepare 3 s, shutdown, the old silod exited in 1 s, the new silod resumed the computer within about 20 s of starting. After: the marker is intact, the heartbeat process is alive (`etime` continues), `uptime` goes "up 2 mins" before to "up 3 mins" after (one pause gap in the heartbeat), no reboot, `https example.com: 200` through the new silod's proxy bootstrap. PASS.

## 5. Keychain across a rebuild with the same identity

FAIL. A silod rebuilt and re-signed with `Fjord Dev` (different cdhash) is refused every item the earlier build created: the per-computer CA (`org.silo.dev.proxy-ca`, account `computer:<id>`) and the secrets vault (`org.silo.dev.secrets`, `values`). A manifest-only change plus re-sign (same silod source) is refused too; an identical binary at a different path is allowed. Reproduced in the isolated keychain (`51-iso-vault.txt`, `52-iso-keychain-acl.txt`):

```
list (NEWER silod, rebuilt binary same identity): ... "error": "qa-iso: Allow Silo's engine to use its saved sign-in in the macOS Keychain. (credential_access_denied)"
```

Cause (from `security dump-keychain -a` on that keychain, no secret values): each item has two relevant ACL entries. The application entry names `identifier "org.silo.dev.engine" and certificate leaf = H"93aa9415..."` (OK for any build), but a second entry `partition_id` holds `cdhash:392d766b...`, the creating build. A binary signed by a self-signed identity has no Team ID, so its partition is its own cdhash and a new build is outside the list. Reproduced with a stand-alone tool signed with the same identifier and identity: read status -25293. Setting the list to `unsigned:` or empty denies everyone; there is no wildcard. A tool made the same way but with the legacy ACL in a keychain made on the command line did not get the partition entry, which is why a small test tool did not show it. What does survive: the same binary (same cdhash). What would survive rebuilds: a Team ID (an Apple Development or Developer ID certificate; the one in the keychain, `Apple Development: Antton Lepretre (5AX422UKJV)`, is expired, so renewing it would give `teamid:` partitions); or the owner's Always Allow after each rebuild.

## To decide or know

1. A stable self-signed identity does not keep Keychain access across rebuilds (items 4 and 5). Use a certificate with a Team ID, or accept one Always Allow per rebuild, or run the dev engine from a binary that is not rebuilt. Production (Developer ID) gets `teamid:` and is not affected.
2. SecureToken after import cannot be restored by the engine today (item 3). Options: retain the source's password in the archive so the import does not rewrite it (the token survives, but the archive then carries a secret); a login-window login at first start (needs display input); or accept the loss (an imported computer cannot enable FileVault or change the password the token way) and drop the failure message, since every import now ends "failed" with it.
3. Local echo servers cannot be reached from a macOS computer (public-only egress). Probes need a public echo host.
4. Disk. A macOS archive round trip needs about 90 GB of headroom beyond the 30 GB floor. `computers.delete` moves computers to the Trash, which keeps their blocks; the Trash of this user (not readable from here) probably holds the earlier probes' computers, plus mine (below). Emptying it, which I did not do, would recover that space.
5. The `silod` test flake above.

## Deviations and mistakes

- One macOS VM at a time was not held for about 70 s: the isolated computer `qa-iso` was created (its setup boots a VM) while `qa-main` was still running; `qa-main` was stopped right after.
- External volume `/Volumes/ModelVault` (the owner's) was used for the archive (23 GB) and the imported computers; a first attempt to copy the template there (12 minutes) was discarded unused. Everything of mine on it was removed except what computers.delete left in its Trash.
- A `security dump-keychain` on the real login keychain and an add of a test item there were refused by the permission layer; I did not retry them. The dumps above are of the isolated keychain only.
- The first `qa-main` export was cancelled by my disk guard; the leftover staging was cleaned by Silo.

## Cleanup

All VMs stopped. Probe computers `qa-main` (real data), `qa-imp`, `qa-imp2` moved to the Trash with `computers.delete` (the last two sit in the external volume's Trash; the owner can empty them); `qa-iso` and its isolated HOME removed with the scratch folder. silod stopped; `~/.silo-dev` left as found. The new template `25G83-4014150a1bcfa7b8-...` is kept in `org.silo.dev/macos-templates`. `macos-computers` is a plain directory again. Archive deleted from the external volume. Bundles, the newer silod, the gateway and helper build output and `~/silo-work/live-final/target` deleted. The worktree `~/silo-work/live-final` and its branch are kept; `git merge --ff-only engine/live-final` done in `microsandbox-workspaces` (main is now `a94924d2`), not pushed.
