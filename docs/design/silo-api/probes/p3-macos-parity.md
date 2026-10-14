# P3 macOS parity part 1 probe

Run date: 2026-10-14. Scope: B-19, B-24 (macOS), and B-4 from [80 §4(B)](../80-coverage-and-consistency.md). This probe tested developer tools, the guest recorder's Screen Recording grant, and Screen Sharing readiness on one disposable Silo Dev template clone. The implementation is summarized in [the part 1 report](../reports/p3-macos-parity-1.md).

## Environment and method

- Host: macOS 26.5, build 25F71, Apple Silicon.
- Guest: macOS 26.6.2, build 25G83, arm64. It was cloned from the Silo Dev template with APFS `cp -c`; the probe configured 4 CPUs and 8 GiB. The template was left unchanged.
- Silo source checkout: 0.11.1. The guest template contained Silo app 26.930.61225 and LCU 0.11.0.
- MicroSandbox: Silo pins 0.7.6 at commit `09df3d4b9d832adaede1fb9a198cfc660bfab8cd`. The custom probe harness did not call MicroSandbox.
- The VM was started by a custom ad-hoc-signed `P3Probe.app`, not the Silo Dev app. Probe sources remain in `/Users/polarzero/silo-probes/p3-macos-parity/src`; compact evidence remains in `/Users/polarzero/silo-probes/p3-macos-parity/evidence`.
- The guest already had its console account and Silo/LCU, but no active Xcode Command Line Tools selection. Its `/usr/bin/git` shim reported that developer tools were missing.
- No host privacy or security settings changed. The clone and downloaded packages were removed after the probe. The guest stopped through the harness (`vm_stopped state=0`); the final disk check showed 104 GiB available.

The retained evidence includes the VM harness (`P3Probe.swift`), the artifact fetcher, the guest setup scripts, the production-rendered developer-tools installer, and focused logs. The excerpts below omit the guest address and MAC address.

## Results

| Probe | Verdict | Result |
| --- | --- | --- |
| B-19 | PARTLY | CLT, Git, Git LFS and GitHub CLI became usable, and a C program compiled and ran. A separate probe installer exercised unattended CLT installation; the production-rendered installer ran after the CLT receipts already existed, so its cold-install branch remains unverified. No public clone or LFS transfer was attempted. |
| B-24 (macOS) | PARTLY | The guest recorder's bundle identifier received a Screen Recording TCC row with authorization value 2 and reason 4. Its signature verified and its Aqua LaunchAgent loaded. The new recorder was not run to create a movie. |
| B-4 | PARTLY | Screen Sharing's system job was loaded, and a connection to TCP 5900 received `RFB 003.889` while launchd reported `not running`, consistent with socket activation. The first readiness attempt timed out; a retry succeeded. Authentication, screen contents, input, and repeatability across boots were not tested. |

### B-19 — PARTLY

The probe fetched the five CLT packages and the pinned Git LFS and GitHub CLI archives, checked artifact sizes and SHA-256 digests, and checked each CLT package with `pkgutil --check-signature`. The package signatures reported `signed Apple Software` with the `Software Update` identity and the pinned leaf certificate. An earlier probe script then installed the five CLT packages unattended with `/usr/sbin/installer -pkg ... -target /` and verified their receipts. It also installed Git LFS and GitHub CLI.

The checked-in production script was rendered from the current guest script and lock, staged with those artifacts, and run as `/bin/zsh /private/tmp/silo-developer-tools/silo-developer-tools.zsh`. Because the earlier probe script had already installed CLT, the production script logged `Apple package receipt already matches` for each package. It verified the current receipts and completed the Git LFS and GitHub CLI installation and version checks. It did not enter its own cold `installer -pkg` branch.

The production run reported:

```text
xcode_select=/Library/Developer/CommandLineTools
git=git version 2.50.1 (Apple Git-155)
git_lfs=git-lfs/3.8.0
gh=gh version 2.102.0 (2026-09-30)
xcrun clang=/Library/Developer/CommandLineTools/usr/bin/clang
Developer tools are ready for 25G83
```

The probe compiled and ran a small C program with `xcrun clang`. A preliminary custom probe harness call failed its Git LFS version check because that harness omitted `/usr/local/bin` from its test `PATH`; after correcting the harness environment, the production installer and its non-login-shell check passed. This was a harness issue, not a production-script failure.

The Apple Software Update catalog's SHA-1 values did not match the downloaded bytes for the five CLT packages. The artifacts did match the lock's byte counts and SHA-256 hashes, and `pkgutil` verified Apple's package signature and certificate. The report therefore relies on the pinned SHA-256 and Apple signature checks, not the mismatching catalog SHA-1 values.

**Spec impact:** B-19 supports adding unattended CLT/Git/LFS provisioning to [30 §5, setup](../30-macos-computers.md). It does not validate cloning public repositories or an LFS transfer. Those network paths belong to P3-macos-proxy and remain outside this probe. Repeat on a clean guest with the production installer itself taking the cold CLT install branch.

### B-24 (macOS) — PARTLY

The probe ran the guest Computer Use setup script with `apply --approval ask`. It built and signed `SiloGuestRecorder.app`, installed its Aqua LaunchAgent, wrote the recorder's Screen Recording grant, and verified the grant row and code signature. The focused check reported:

```text
recorder_tcc_row=kTCCServiceScreenCapture|org.silo.guest-recorder|2|4
gui/<guest uid>/org.silo.guest-recorder = { ... state = not running ... }
recorder_signature=verified
```

The agent is configured with `RunAtLoad=false`, so `not running` is expected after loading. The probe did not launch it or retrieve a movie; it confirms the grant and launch configuration, not successful recording by this newly packaged identity.

After this VM run, setup was changed to defer bootstrapping the recorder agent when the Aqua launchd domain does not exist yet. The successful probe had an Aqua domain. The no-Aqua deferral is covered by the checked-in script unit assertion but was not exercised live.

**Spec impact:** This supports the TCC identity and grant mechanism in [40 §5, proof recording](../40-desktop-display-computer-use.md), with a live recording by this exact recorder identity still needed. Keep the recorder in the guest with its own TCC grant; do not infer capture success from the database row alone.

### B-4 — PARTLY

The guest setup command enabled and loaded `system/com.apple.screensharing`. A diagnostic connection to loopback port 5900 returned the RFB greeting. The final check observed:

```text
screensharing_job=loaded
screensharing_state=not running
screensharing_rfb_greeting=RFB 003.889
```

The Screen Sharing job is socket-activated, so launchd's `not running` state between connections did not mean the listener was unavailable. The first setup attempt did not return a greeting before its timeout; a retry returned one, and the later check after `launchctl bootout system/com.apple.screensharing` again observed the socket-activated greeting.

**Spec impact:** This supports the readiness rule in [30 §7, display](../30-macos-computers.md): check that the Screen Sharing job is loaded and that TCP 5900 speaks RFB, instead of requiring the daemon to stay running. It does not establish authentication, a visible desktop, input, or readiness after another boot.

## Exact probe commands and code

The retained harness and scripts are under `/Users/polarzero/silo-probes/p3-macos-parity/src`:

- `P3Probe.swift` cloned the disk and auxiliary storage from the Silo Dev template with `cp -c`, configured the VM, started it, and provided SSH access.
- `guest_developer_tools.zsh` was the initial probe installer. It used `pkgutil --check-signature`, `installer -pkg ... -target /`, `xcode-select --switch`, receipt checks, Git/LFS/gh checks, and a compile/run check.
- `run_production_developer_tools_probe.zsh` rendered and ran the checked-in `silo-developer-tools.zsh` with the checked-in lock and `setup-github.sh`, then checked `git --version`, `git lfs version`, `gh --version`, `xcode-select -p`, and the CLT receipt.
- `run_computer_use_probe.zsh` copied the checked-in guest Computer Use script, recorder Swift source, recorder metadata, and LaunchAgent plist, then ran `silo-computer-use.zsh apply --approval ask`.
- `verify_computer_use.zsh` queried the Screen Sharing launchd state, read the RFB greeting with `nc -w 1 127.0.0.1 5900`, queried the guest TCC row for `kTCCServiceScreenCapture` and `org.silo.guest-recorder`, and ran `codesign --verify --deep --strict` on the app.

The setup used placeholder-only credential helper configuration; it did not sign into GitHub, access an external account, clone a repository, or exercise the host network proxy.
