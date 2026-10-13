# Linux computer probes

Run on 2026-10-13 against Silo commit `94d81937904af83faf5839e8b28b24e0e1883c8b`.

## Environment and cleanup

- Host: macOS 26.5 (25F71), arm64; OpenSSH 10.2p1.
- Runtime: Silo Dev 0.11.1 debug bundle; bundled MicroSandbox CLI 0.7.6.
- Guest: Ubuntu 24.04, Linux `6.12.109`, aarch64. Claude Code Desktop remote CLI: `2.1.295-cdb4a4da2c4c`.
- Used only `e2e-relay`. Lowered startup memory to 8 GiB for the probes; restored startup memory to 32 GiB. The ceiling is 48 GiB, matching Silo's new-computer default; the original ceiling was not captured separately before lowering. Silo Dev stopped the guest. Final `msb list` showed both `e2e-relay` and `workspace-1` stopped.
- Restored host `~/.ssh/config` and `~/.claude/settings.json` byte-for-byte from `~/silo-probes/backup/` timestamped backups. Restored the guest Claude settings, removed the probe plugin and temporary hook logs. Deleted the synthetic secret from the Silo Dev Keychain and metadata; a name-only revocation for stopped `e2e-relay` remains pending until its next start.
- Closed the Silo Dev viewer and quit the Silo Dev debug app. The existing Claude app window was already open; the probe SSH session is a session in that window, not a separate window. The local WKWebView fixture server was stopped. Removed the compiled harness binaries and Python cache; source and small evidence files remain under `~/silo-probes/linux/`.
- Silo Dev initially reported a missing LCU 0.9.4 mount. The probe used `src/repair-stale-lcu-mount.sh` to hardlink the existing 0.11.0 archive into that empty mount directory. One raw `msb restart` attempt stopped the guest and then failed because Silo's `SILO_GITHUB` input was absent; Silo Dev restarted the guest successfully. No GitHub config or credential values were printed.

## Verdicts

| Probe | Verdict | Result |
| --- | --- | --- |
| B-11 | **CONFIRMED** | First-party Claude Desktop connected through Silo's Include and `ProxyCommand`; `IdentityAgent none`, host key checking, and forced-off forwarding worked. |
| B-12 | **CONFIRMED** | Killing only the session's ProxyCommand bridge left the guest Claude server and command alive; Desktop reconnected and received the command result. |
| B-13 | **CONFIRMED** | `/home/silo` is executable overlay storage with about 98 GiB free. |
| B-15 | **PARTLY** | The user-scope plugin loaded and a SessionStart hook ran in direct guest CLI; no PermissionRequest or plugin callback was observed in a Desktop SSH turn. |
| B-16 | **PARTLY** | Found both SSH transcript copies, guest session metadata, and Desktop's `local_` session ID; live tail freshness and a Linux background-task directory remain unverified. |
| B-17 | **PARTLY** | `msb exec` inherited the secret placeholder and CA path. `claude -p` reached an HTTPS endpoint and got 401, but no proxy substitution log proved the destination or token substitution. |
| B-18 | **PARTLY** | A local WKWebView fixture confirmed all-frame injection, HttpOnly behavior, H.264/Opus, attachment cancellation, clipboard rejection, and two-view survival; the harness could not use Silo's private proxy cookie. |
| B-20 (Linux) | **CONFIRMED** | Inotify `close_write` p95 was 0.321 ms versus 32.291 ms for a 30 ms poll over 40 samples. |
| B-21 | **REFUTED** | The fixture's second view survived the first closing, but Silo's current viewer registry returns the same viewer for a second attach to the same computer, contrary to A-28's separate-client requirement. |
| B-24 (Linux) | **CONFIRMED** | Guest `ffmpeg` captured display `:1.0` to a 1440×900 JPEG with the Silo Xauthority file. |
| B-32 | **PARTLY** | Current stdout-overflow and timeout errors were reproduced. Numeric defaults below are INFERRED candidates; current `run_capped` defines neither a default nor a maximum. |

## Evidence by probe

### B-11 — Claude Desktop SSH alias

**Spec:** 50 Q4, 70 OQ1, and 80 §4(B) B-11. The probe tests the `editor.*` SSH alias handoff and the first-party Claude Desktop SSH behavior, including the `startDirectory` caveat.

Silo generated alias `silo-c19a79dc92d3-e2e-relay` and this Include line:

```sshconfig
Include "/Users/polarzero/.silo-dev/c19a79dc92d3/ssh/*.conf"
```

The per-computer file `~/.silo-dev/c19a79dc92d3/ssh/e2e-relay.conf` contained:

```sshconfig
Host silo-c19a79dc92d3-e2e-relay
  HostName silo-c19a79dc92d3-e2e-relay
  User silo
  IdentityFile "/Users/polarzero/.silo-dev/c19a79dc92d3/ssh/silo_ed25519"
  IdentitiesOnly yes
  IdentityAgent none
  ForwardAgent no
  ForwardX11 no
  UserKnownHostsFile "/Users/polarzero/.silo-dev/c19a79dc92d3/ssh/e2e-relay.known_hosts"
  StrictHostKeyChecking yes
  BatchMode yes
  ProxyCommand '/usr/bin/env' 'MSB_HOME=/Users/polarzero/.silo-dev/c19a79dc92d3' 'MSB_PATH=/Users/polarzero/code/projects/microsandbox-workspaces/app/SiloUI/src-tauri/target/debug/bundle/macos/Silo Dev.app/Contents/MacOS/msb' 'MSB_LIBKRUNFW_PATH=/Users/polarzero/code/projects/microsandbox-workspaces/app/SiloUI/src-tauri/target/debug/bundle/macos/Silo Dev.app/Contents/Frameworks/libkrunfw.5.dylib' '/Users/polarzero/code/projects/microsandbox-workspaces/app/SiloUI/src-tauri/target/debug/bundle/macos/Silo Dev.app/Contents/MacOS/msb' 'ssh' 'serve' 'e2e-relay' '--stdio' '--no-start' '--no-inactivity-timeout'
```

`ssh -G` resolved `BatchMode yes`, `IdentityAgent none`, `IdentitiesOnly yes`, strict host-key checking, and the Silo ProxyCommand. A first-party Claude Code Desktop session opened with `claude://code/new?ssh_host=<alias>&ssh_folder=/home/silo&q=<prompt>`, connected as `silo`, ran `uname -a`, and asked the harmless AskUserQuestion prompt. Claude Desktop's SSH child used system OpenSSH; its command disabled `ForwardAgent`, `ForwardX11`, `Tunnel`, `LocalForward`, `RemoteForward`, `DynamicForward`, `GSSAPIDelegateCredentials`, `LocalCommand`, and `RemoteCommand`. Desktop's own child overrides `BatchMode` to `no`; the alias itself remains `yes`. `IdentityAgent none` was accepted. The guest working directory was `/home/silo`; `sshConfigs.startDirectory` remains unsupported/dropped, so this does not establish that field.

Claude Code was installed at `/home/silo/.claude/remote/ccd-cli/2.1.295-cdb4a4da2c4c`. The guest kernel returned `Linux e2e-relay 6.12.109 #1 SMP Fri Jul 24 13:01:52 WAT 2026 aarch64 aarch64 aarch64 GNU/Linux`.

**Commands/source:** `src/add-claude-ssh-config.py`, `src/open-claude-probe-deeplink.py`, `src/guest-claude-inspect.sh`; alias generation in Silo `app/SiloUI/src-tauri/src/editor.rs:423-435,581-595,807-838`. Host config restored from backup afterward.

### B-12 — ProxyCommand disconnect

**Spec:** 70 OQ2 and 80 §4(B) B-12; checks `msb ssh serve` connection loss and Claude process survival.

Desktop started `sleep 45; echo B12_DONE` in the SSH session. I terminated ProxyCommand bridge PID 78239, the child of OpenSSH PID 78238; I left the separate Zed bridge untouched. Guest Claude server PID 1088 and sleep PID 1651 remained alive. Desktop opened a new bridge, reconnected, and the local transcript recorded `B12_DONE` with exit code 0.

**Evidence:** `~/silo-probes/linux/session-proxy-disconnect.out`, `session-artifacts.out`. Session ID: `fdbb7e45-e80b-494d-8edb-b209fb775f86`.

### B-13 — Guest home mount and space

**Spec:** 70 OQ3 and 80 §4(B) B-13; this supplies Linux guest filesystem facts for Claude remote files.

`findmnt -T /home/silo` reported the root `overlay` mount with `rw,relatime`; `noexec` was absent. `df -h /home/silo` reported 99G total, 488M used, 98G available (1%).

**Commands/source:** `src/guest-linux-probes.sh`. Raw excerpt: `guest-linux-probes-success.out`.

### B-15 — Guest PermissionRequest hook and user plugin

**Spec:** 30 OQ2, 70 OQ5/OQ6, and 80 §4(B) B-15; tests whether guest user-scope hooks/plugins load in a Desktop SSH session.

Installed a minimal `PermissionRequest` hook in guest `~/.claude/settings.json` and a user-scope plugin under `~/.claude/skills/linux-probe`. Claude Code validated the plugin manifest and `ccd-cli plugin list` reported the plugin loaded at user scope. The SessionStart hook log received two entries from a direct guest `claude -p` run (B-17), not from the Desktop SSH session. PermissionRequest was not observed. The prepared Desktop SSH prompt could not be sent: Claude's UI controls repeatedly routed to the folder selector. Therefore the probe does not establish hook invocation or callback order in Desktop SSH.

**Commands/source:** `src/install-claude-probe-hooks.sh`, `src/user-scope-plugin/`, `install-claude-probe-hooks.out`, `src/open-claude-hook-probe-deeplink.py`. Guest settings were restored and the plugin/log removed.

### B-16 — Transcripts, session metadata, and task folders

**Spec:** 70 OQ8/OQ9/OQ10 and 80 §4(B) B-16; checks transcript paths and freshness, `local_` identity, and Linux background-task directories.

For session `fdbb7e45-e80b-494d-8edb-b209fb775f86`:

- Local transcript: `~/.claude/projects/ssh-fdbb7e45-e80b-494d-8edb-b209fb775f86/fdbb7e45-e80b-494d-8edb-b209fb775f86.jsonl` (301,283 bytes, 66 lines).
- Guest transcript: `/home/silo/.claude/projects/-home-silo/fdbb7e45-e80b-494d-8edb-b209fb775f86.jsonl`.
- Guest metadata: `/home/silo/.claude/sessions/1140.json`; it held `hostSessionId=local_862b7be9-b9e6-4bc6-ab70-eb3889c891fb`, `sessionId=fdbb7e45-e80b-494d-8edb-b209fb775f86`, and PID 1140.
- Desktop metadata used the same `local_862b7be9-b9e6-4bc6-ab70-eb3889c891fb` prefix in `/Users/polarzero/Library/Application Support/Claude/claude-code-sessions/614646e1-7dcc-48b2-932b-4540f6777775/31cc40fe-facd-4f3c-a29c-70fac76115b4/local_862b7be9-b9e6-4bc6-ab70-eb3889c891fb.json`.
- Guest `/tmp/claude-1001` existed. No task directory was identified, and both transcript copies were not tailed concurrently during a live turn; freshness and task location remain open.

**Commands/source:** `src/inspect-sessions.py`, `src/guest-claude-inspect.sh`, `session-artifacts.out`, `guest-claude-inspect.out`.

### B-17 — OAuth placeholder, TLS CA, and `msb exec`

**Spec:** 70 OQ11/OQ12 and 80 §4(B) B-17; distinguishes environment inheritance from HTTPS destination substitution.

Added a synthetic `CLAUDE_CODE_OAUTH_TOKEN` secret restricted to `api.anthropic.com`, restarted `e2e-relay` through Silo Dev to apply it, and ran the checks through the bundled `msb exec --no-start`. Values were never printed. Sanitized guest environment:

```text
CLAUDE_CODE_OAUTH_TOKEN: present=true placeholder=true
ANTHROPIC_AUTH_TOKEN: present=false
ANTHROPIC_API_KEY: present=false
NODE_EXTRA_CA_CERTS: set=true exists=true path=/.msb/tls/ca.pem
SILO_SECRET_* env count=0
```

`claude -p` with a harmless exact-response prompt exited 1, produced 70 bytes, and returned an unauthorized response without a TLS or network error. This shows the request reached an HTTPS endpoint, but it does not prove that the proxy substituted the placeholder at `api.anthropic.com`: no per-destination substitution log was available. Result: PARTLY.

**Evidence:** `b17-sanitized.out`; environment and secret placeholder implementation in `app/SiloUI/src-tauri/src/secrets_runtime.rs:55,237` and `runtime.rs:1487`. After stopping the guest, the synthetic value was deleted from the Silo Dev Keychain and record; a name-only revocation for `e2e-relay` remains pending until its next start.

### B-18 — WKWebView security and media checks

**Spec:** 40 OQ2 and 80 §4(B) B-18; checks all-frame injection, HttpOnly cookies, WebCodecs, downloads, and clipboard/paste behavior.

The requested harness was compiled from `~/silo-probes/linux/src/wkwebview-probe.swift` and loaded Silo's `desktop_viewer_bridge.js` against a local Selkies-like fixture. Output:

```json
{"client_2_survived_client_1_close":true,"clipboard_read_result":"NotAllowedError","download_denied":true,"httponly_cookie":true,"iframe_injected":true,"js_can_see_cookie":false,"main_frame_injected":true,"mode":"local-fixture","paste_prompt_suppressed_by_bridge":true,"webcodecs_h264":true,"webcodecs_opus":true}
```

This confirms the macOS WebKit APIs and Silo bridge script against the fixture. It does not exercise the live Silo proxy: its random URL token and HttpOnly cookie are held inside Silo's native webview, and the external harness had no supported way to obtain them. The bridge rejects page clipboard reads with `NotAllowedError`; this suppresses a page-originated paste request, but the native toolbar's paste confirmation was not exercised. Silo source uses `.incognito(true)`, `on_download` false, all-frame injection, and an HttpOnly proxy cookie (`desktop_viewer.rs:633-667`; proxy port/token creation at `desktop_proxy.rs:481-507`). Verdict: PARTLY.

**Source:** `src/wkwebview-fixture.py`, `src/wkwebview-probe.swift`, `wkwebview-local-fixture.out`; Silo `app/SiloUI/src-tauri/src/desktop_viewer.rs` and `desktop_proxy.rs`.

### B-20 — Linux inotify against 30 ms polling

**Spec:** 70 OQ14 and 80 §4(B) B-20; measures event delivery against Fjord's acknowledgment poll.

The guest ran 40 `IN_CLOSE_WRITE` samples. Inotify median/p95/max was 0.135/0.321/0.630 ms. The 30 ms file poll median/p95/max was 29.909/32.291/34.523 ms.

**Commands/source:** `src/inotify-30ms.py`; raw output `inotify-30ms.out`. This is a guest local-file measurement, not an engine/API end-to-end measurement.

### B-21 — Two viewer clients

**Spec:** 40 OQ3, 95 A-28, and 80 §4(B) B-21; A-28 requires one viewer connection per client and independent close.

Two nonpersistent WKWebViews against the local fixture were opened. After closing client one, client two fetched `/health` successfully (`client_2_survived_client_1_close=true`). That does not qualify two Silo clients: Silo `desktop_viewer.rs:126-139` reserves one viewer per computer and returns `ViewerClaim::Existing` for another attach; its test at `:1210-1219` asserts both opens use one entry. Current Silo therefore cannot supply A-28's independent same-computer viewer connections. Resize and clipboard ownership across two real Silo clients were not measured.

**Source:** local harness/output above; `desktop_viewer.rs:120-139,364-380,1210-1219`.

### B-24 — Linux ffmpeg screen capture

**Spec:** Linux part of 40 OQ10 and 80 §4(B) B-24; this does not test the macOS recording path.

`ffmpeg` 6.1.1-3ubuntu5 captured display `:1.0` with `DISPLAY=:1.0` and `XAUTHORITY=/run/silo-desktop/user/Xauthority`. It wrote a 27,075-byte JPEG, 1440×900. A first attempt without the Xauthority failed with X11 authorization; the Silo-owned guest authority succeeded.

**Command/source:** `src/guest-linux-probes.sh`; output `guest-linux-probes-success.out`.

### B-32 — `run_capped` overflow and timeout

**Spec:** 30 OQ12, 70 OQ15, 95 A-37, and 80 §4(B) B-32; preserves stdout overflow as an error and uses jobs for long runs.

Silo's current macOS `guest_access::run_capped` accepts `max_stdout: Option<usize>` and a caller-provided `Duration`; it defines no default or maximum. The stdout drain reads at most `limit + 1` bytes, then kills and waits for the SSH child and returns `The command in the computer printed too much.` The timeout loop checks every 50 ms, kills and waits, then returns `The command in the computer took too long.` Stderr is drained without a cap (`guest_access.rs:465-483,632-665,668-692`). Linux `guest.exec` is NEW, so this is not a live Linux API test.

The existing focused Rust tests passed against Silo's source:

```text
cargo test --bin silo-ui macos_computers::guest_access::tests::output_beyond_the_allowance_stops_the_command -- --exact
test result: ok. 1 passed; 0 failed
cargo test --bin silo-ui macos_computers::guest_access::tests::commands_report_output_status_and_timeouts -- --exact
test result: ok. 1 passed; 0 failed
```

A disposable reproduction at `src/run-capped-repro.rs` tested exact-cap output, one-byte overflow followed by a sleeping child, and child timeout. It accepted exact caps of 262,144 and 786,432 bytes; both overflows returned the existing error in 56 ms. A requested 250 ms timeout returned the existing timeout error in 264 ms.

**INFERRED candidate limits, not current Silo behavior:** default stdout cap 256 KiB, maximum 768 KiB, default timeout 30 s, maximum bounded timeout 180 s. The 768 KiB maximum serializes to at most about 3 MiB if the byte result uses a JSON integer array, under the current 4 MiB bridge frame limit (`remote.rs:37`) with some envelope room. The 180 s maximum matches Silo's current `MUTATION_TIMEOUT` (`runtime.rs:44-47`); long runs use `guest.exec.start` per A-37. The default cap and 30 s default are engineering candidates only: no real guest-output or latency corpus was measured. The uncapped stderr drain can still exceed the bridge frame limit, so B-32 does not settle stderr bounds.

**Evidence:** `src/run-capped-repro.rs`, `run-capped-repro.out`; implementation `app/SiloUI/src-tauri/src/macos_computers/guest_access.rs:465-483,632-692`.

## Follow-up

Follow-up run on 2026-10-13 used the same host and guest versions recorded above. The VM memory allocation was 8 GiB during these probes. The recorded original allocation was 32 GiB with a 48 GiB ceiling; CPU allocation and ceiling were 8 and 12, and the workspace and runtime disks were 120 and 100 GiB.

| Probe | Verdict | Result |
| --- | --- | --- |
| B-15 | **CONFIRMED** | A guest `PermissionRequest` hook fired for `AskUserQuestion` in a Claude Code Desktop SSH session. `SessionStart` arrived 5.090583211 seconds earlier. |
| B-16 | **PARTLY** | During a foreground turn, the local transcript copy updated about 1.1 seconds after the guest copy, then kept a fresh mtime but stayed 1,168 bytes smaller through the turn and after completion. |
| B-17 | **CONFIRMED** | The allowed Anthropic endpoint returned `invalid x-api-key` for the synthetic value; the non-allowed echo host returned the placeholder unchanged. The `Authorization` rewrite was not isolated from `x-api-key`. |
| B-18 | **CONFIRMED** | The WKWebView harness loaded the live Silo proxy at HTTP 200 with its real HttpOnly cookie and Silo bridge script. |

### B-15: PermissionRequest in Claude Code Desktop SSH

**Method:** Saved guest `/home/silo/.claude/settings.json`, added a recorder for `SessionStart` and a `PermissionRequest` hook matched to `AskUserQuestion`, then opened a Claude Code Desktop session with `claude://code/new?ssh_host=<alias>&ssh_folder=/home/silo&q=<prompt>`. The prompt asked, “Should I continue the Linux probe or stop now?” with `Continue` and `Stop` options. The probe operator selected `Continue` in the Claude app.

**Raw event excerpt:**

```json
{
  "SessionStart": {
    "received_at_unix_ns": 1791913113923476013,
    "source": "startup",
    "cwd": "/home/silo"
  },
  "PermissionRequest": {
    "received_at_unix_ns": 1791913119014059224,
    "hook_event_name": "PermissionRequest",
    "tool_name": "AskUserQuestion",
    "permission_mode": "auto",
    "cwd": "/home/silo",
    "session_id": "a312eb49-c0b4-4d49-9f03-4a9dea99a247",
    "transcript_path": "/home/silo/.claude/projects/-home-silo/a312eb49-c0b4-4d49-9f03-4a9dea99a247.jsonl",
    "tool_input": {
      "questions": [{
        "question": "Should I continue the Linux probe or stop now?",
        "header": "Linux probe",
        "options": [
          {"label": "Continue", "description": "Continue the Linux probe."},
          {"label": "Stop", "description": "Stop the Linux probe now."}
        ],
        "multiSelect": false
      }]
    }
  }
}
```

`PermissionRequest` followed `SessionStart` by 5.090583211 seconds. This confirms the hook runs before the Desktop SSH session presents `AskUserQuestion` to the user.

**Source and evidence:** `src/b15-install-guest-hooks.sh`, `src/b15-hook-recorder.py`, `src/open-claude-b15-deeplink.py`, and `b15-live-guest-observation-1.out`. The guest settings were restored byte-for-byte to SHA-256 `0e205d43dcac92334b9c7cacd528ec018ec4407f81c9804358bfb8e6a34f2399`, mode 600. The temporary hook and log were removed.

### B-16: Live transcript freshness and background task output

**Method:** In a Claude Code Desktop SSH session, ran `sleep 45; printf 'B16_ACTIVE_TURN_SENTINEL\n'` in the foreground. Sampled the local `ssh-<id>` transcript and guest transcript once per second while the UI showed the shell command running.

For session `4bcb263b-077b-430c-9a36-d46f6d2647a1`:

- Guest: `/home/silo/.claude/projects/-home-silo/4bcb263b-077b-430c-9a36-d46f6d2647a1.jsonl`
- Local: `~/.claude/projects/ssh-4bcb263b-077b-430c-9a36-d46f6d2647a1/4bcb263b-077b-430c-9a36-d46f6d2647a1.jsonl`
- At the paired stat, guest mtime was `1791915032220617127` ns and size was 279,666 bytes. Local mtime was `1791915032233766285` ns and size was 278,498 bytes. Local mtime was 13,149,158 ns newer, while its size lagged by 1,168 bytes.
- At the first sample, the guest had advanced to 278,498 bytes while the local copy was still 267,800 bytes. About 1.1 seconds later the local copy reached 278,498 bytes. It remained 1,168 bytes behind through the remaining samples and after the command completed.

The timestamp is fresh after the mirror updates, but the local transcript was not byte-complete at the observed point. No byte-for-byte comparison was made. Verdict remains PARTLY.

The background task output for the prior Desktop session was in `/tmp/claude-1001/-home-silo/a312eb49-c0b4-4d49-9f03-4a9dea99a247/tasks/bfz22fjh5.output`. It contained `B16_BACKGROUND_SENTINEL` and `[exited with code 0]`. The sanitized copy is `b16-background-task.out`.

**Source and evidence:** `src/b16-watch-foreground-turn.sh`, `b16-live-foreground-turn.out`, `b16-live-foreground-precise.out`, and `b16-background-task.out`.

### B-17: Allowed-host substitution to api.anthropic.com

**Method:** Created the Silo Dev secret `B17_SYNTHETIC_TOKEN`, assigned it to `e2e-relay`, and allowed only `api.anthropic.com`. The guest environment contained a `$MSB_...` placeholder. The synthetic value was never printed or saved in evidence.

An Authorization-only request to `GET /v1/organizations/me` returned HTTP 401 with `x-api-key header is required`. A repeat with both headers returned the same response. Anthropic's current reference documents `X-Api-Key` for that endpoint, so neither response tested bearer substitution. The final test sent `POST /v1/messages` from the guest with the placeholder in both `Authorization: Bearer ...` and `x-api-key`. Anthropic returned HTTP 401 `authentication_error` with the sanitized message `invalid x-api-key`. The non-allowed request to `https://postman-echo.com/headers` returned the placeholder unchanged (`echo_saw_placeholder=true`).

By the requested invalid-key criterion, substitution to the allowed API host is CONFIRMED. The API's rejection is based on `x-api-key`, so this does not independently prove rewriting inside the `Authorization` value. See Anthropic's [Messages API reference](https://docs.anthropic.com/en/api/messages) and [Get Current Organization reference](https://docs.anthropic.com/en/api/admin-api/organization/get-me).

**Command/source:** `src/b17-request-guest.sh`, run through the bundled `msb exec --no-start --stream e2e-relay -- bash -s`. Sanitized outputs are `b17-authorization-only.out`, `b17-auth-header-pair.out`, and `b17-messages-api.out`. The secret was removed from Silo Dev; because the guest was stopped, Silo may apply the name-only revocation on its next start.

### B-18: Live Silo desktop proxy in WKWebView

Opened `e2e-relay`'s real Silo desktop viewer. Its proxy URL was `http://127.0.0.1:58476/`; its HttpOnly cookie name was `silo_desktop_58476`. The cookie value was read through Safari Web Inspector, passed through a temporary loopback-only file, and never printed. The temporary file was removed after the harness run.

Compiled and ran `src/wkwebview-probe.swift` in `live-silo` mode with the real URL, cookie name, cookie file, and Silo `desktop_viewer_bridge.js`. Result:

```json
{"clipboard_read_result":"NotAllowedError","download_denied":false,"js_can_see_cookie":false,"main_document_host":"127.0.0.1","main_document_status":200,"main_frame_injected":true,"mode":"live-silo","page_title":"Selkies","real_selkires_page":true,"webcodecs_h264":true,"webcodecs_opus":true}
```

The harness became the new primary client and the original Silo viewer displayed `Connection Terminated: a new primary client connected connection killed`. I closed that probe viewer afterward. This live mode did not request a download, so `download_denied=false` is not a download test. Source and sanitized result: `src/wkwebview-probe.swift`, `b18-live-silo.out`.

### Follow-up cleanup

Restored e2e-relay to 8 CPUs, 12 CPU ceiling, 32 GiB memory, 48 GiB memory ceiling, 120 GiB workspace disk, and 100 GiB runtime disk. The computer is stopped. Removed the synthetic secret value and record from Silo Dev. Since e2e-relay was stopped, guest-side name-only revocation takes effect on its next start; it was not restarted after removal. Restored host `~/.ssh/config` to SHA-256 `8b1b30a0dd9c0386a4dadb13ec0a4c99bb1da5f5c7d66412feff7b6ca2ecb17c` and `~/.claude/settings.json` to `34fe9bc5e2ca3bcb58e011c491fdac8d8de6a14c1b97d6ed9b562ac6ce29cb96`; both matched the backups in `linux-config-backup-20261013T173115Z.json` and `linux-followup-config-backup-20261013T180443Z.json`. The original guest settings hash and mode are recorded under B-15.

PID 73000 was absent at the final process check. The B-15, first-run `Linux probe system info`, and B-16 foreground probe sessions were archived in Claude Desktop. Their SSH control masters were exited; no probe `ccd-ssh` or `msb` process remained. I cancelled the pending `Trust this workspace?` prompt for `/home/silo` and did not grant broader workspace access. Claude Desktop still lists the pre-existing idle `Fjord cloud deployment strategy` session and its fork; both were left untouched for the owner to review.

## Connections

**Preflight:** Silo Dev's Connections switch was off. Its computer list contained two local Linux computers, `workspace-1` and `e2e-relay`, and zero computers on other devices. No macOS computer name existed in that inventory, so B-10's duplicate-name condition had no target. The Connections page also listed an existing offline `devbox` device with a missing remote bridge; that connection was left unchanged. Remote Login was already on per the user's instruction.

`~/.ssh/authorized_keys` did not exist before this section and remains absent. Its backup is `~/silo-probes/backup/authorized_keys-20261013T175730Z.absent`. No Silo SSH key was registered and no forced command ran. Silo Dev's channel source selects `silo-remote-dev` as its bridge name, while the production channel selects `silo-remote` (`app/SiloUI/src-tauri/src/channel.rs`). The requested production-named forced command has not been tested against the Development build.

| Probe | Verdict | Result |
| --- | --- | --- |
| B-22 | **NOT RUN** | Connections remains off. No key, handshake, bundle-copy update test, or forced command was installed or run. |
| B-10 | **NOT RUN** | No macOS computer exists in the Silo Dev inventory. Remote upsert creation-wait behavior was not measured. |
| B-28 | **NOT RUN** | No device connection or key was created for removal. Key retention and established-session survival remain unmeasured. |

These live probes require enabling Connections and adding a forced SSH command, which grants local management access. The computer-use confirmation policy requires a fresh action-time confirmation for that access change. I stopped before enabling Connections. Source inspection only shows that the current remote upsert path in `app/SiloUI/src-tauri/src/runtime/remote_ops.rs` applies configuration with progress; it is not a live wait-behavior result.

## Connections (run 2)

**Run:** 2026-10-13. macOS 26.5 (build 25F71); Silo Dev 0.11.1, source commit `94d81937`; bundled MicroSandbox `msb 0.7.6` (the locked MicroSandbox crates are also 0.7.6 at revision `09df3d4b9d832adaede1fb9a198cfc660bfab8cd`). Remote Login was already on and was not changed. Preflight confirmed Connections off, `~/.ssh/authorized_keys` absent (empty backup sentinel `~/silo-probes/backup/authorized_keys-20261013T175730Z.absent`), and `~/.local/bin/silo-remote` linked to the production release app. The probe created a synthetic Ed25519 key and installed one restricted line:

```text
restrict,command="exec ~/.local/bin/silo-remote --remote-bridge" ssh-ed25519 [probe key] Silo Dev remote management
```

The fingerprint was `SHA256:0jFCIl1vvm1eEjHll+nNLnMxdXJiApmXLWbLp/LSFBY`. Source, exact probe requests, and small output captures are under `~/silo-probes/connections/`; probe helpers are in its `src/` directory. The frame helper follows `remote.rs`: a four-byte big-endian JSON length followed by the JSON request; bridge replies start with `\0SILO-BRIDGE-REPLY\n` and then a length-prefixed JSON frame.

| Probe | Verdict | Result |
| --- | --- | --- |
| B-22 | **PARTLY** | The pre-update forced-command handshake authenticated but exited 1 with `Invalid argument (os error 22)` and no reply frame. After copying and relaunching from the new bundle path, the same installed key completed a v5 handshake with exit 0. The post-update reconnect is confirmed; a successful pre-update baseline was not established. |
| B-10 | **BLOCKED** | The colliding 2 CPU / 4 GiB `runtime.upsert` and guarded `runtime.delete` both exited 1 with `Invalid argument (os error 22)` before a framed response. Follow-up Silo and MicroSandbox inventories showed only the two original computers, with the original `workspace-1` ID unchanged. Creation-preparation wait behavior was not measured. |
| B-28 | **PARTLY** | Removing the saved offline `devbox` entry through Settings left the probe key line intact and an already-open authenticated localhost SSH bridge session alive. Because `devbox` had no working bridge, that session was to localhost and not a live session to the removed device; remote-side key revocation was not observed. |

### B-22 — Forced command after bundle replacement

With Connections on, the first SSH request used the probe key and original debug app path. OpenSSH reported public-key authentication and the forced-command key option, then the helper exited 1 with `Invalid argument (os error 22)`; there was no framed response. I copied `Silo Dev.app` under `~/silo-probes/connections/update/`, pointed `~/.local/bin/silo-remote` at the copied `Contents/MacOS/silo-ui`, quit the probe-started instance, and relaunched Silo Dev from that copy. Silo's Development `silo-remote-dev` link also pointed at the copied executable after launch. The pre-installed key then completed the v5 handshake through the source-style exec request. The reply named `polarzero-MBP`, returned device ID `2ece5fc1-4668-4589-b9e2-9befd1f6c7cb`, advertised `runtime.upsert` and `runtime.delete`, and had `sshExit: 0` with zero skipped stdout bytes. The authorized key was not reinstalled between bundle paths.

**Raw excerpts:** `baseline-handshake-debug.txt` ends with `Exit status 1`; `post-update-ssh-handshake-silo-command.txt` contains the successful reply. `ssh-handshake-diagnostic.json` is a second successful post-update handshake capture. The no-command shell request also failed; Silo's source transport sends an exec request, so the result above uses the Silo-style command.

```text
Authenticated to localhost ([::1]:22) using "publickey".
Remote: /Users/polarzero/.ssh/authorized_keys:1: key options: command
Invalid argument (os error 22)
debug1: Exit status 1

post-update reply: version=5, name=polarzero-MBP,
deviceId=2ece5fc1-4668-4589-b9e2-9befd1f6c7cb, sshExit=0,
skippedStdoutBytes=0
```

**Spec effect:** B-22 (05 OQ2; 60 OQ1) gets a successful post-replacement reconnect with a pre-installed key when the forced-command link is repointed to the new bundle. The failed original-path baseline means the full before/after path comparison remains qualified.

### B-10 — Duplicate-name remote upsert and wait

Before the request, `runtime.configuration` returned two Linux computers, `workspace-1` and `e2e-relay`; both were stopped in the UI. No macOS computer existed. The request used a new UUID (`5f557457-f72f-4031-af47-9191c0ba2484`), the colliding name `workspace-1`, 2 CPUs, 4 GiB memory, 10 GiB workspace storage, and 10 GiB runtime storage. Two SSH attempts reused that candidate ID and each ended in about 0.18 seconds with no reply frame and `Invalid argument (os error 22)`. A local-stdio bridge diagnostic of the same upsert produced the same error in 0.077 seconds. The guarded `runtime.delete` was also attempted through SSH; it failed in 0.182 seconds with the same error. A fresh SSH `runtime.configuration` returned exactly the two original IDs and names, with the candidate ID absent. The bundled MicroSandbox inventory listed exactly `e2e-relay` and `workspace-1`, both `Stopped`; inspecting `workspace-1` returned its original `silo.machine-id` (`96b9e3e6-c716-493c-aa99-8c1f49c5768b`).

This does **not** show that remote upsert waited for or skipped preparation: the bridge returned no framed result. No additional runtime remained, the existing name retained its original runtime ID, and no candidate appeared in the saved configuration. The delete request did not return a framed result either. Captures: `b10-upsert-params.json`, `b10-upsert-attempt-2-summary.json`, `b10-local-diagnostic-summary.json`, `b10-delete-summary.json`, `runtime-configuration-after-b10.json`, and `b10-runtime-list-summary.json` (the raw list and inspect responses are alongside it).

```text
runtime.upsert: elapsedSeconds=0.183, bridgeProbeExit=1
SSH stderr: Invalid argument (os error 22)
runtime.delete: wasPresentBeforeDelete=false, elapsedSeconds=0.182,
bridgeProbeExit=1
MicroSandbox list: e2e-relay Stopped; workspace-1 Stopped
workspace-1 silo.machine-id: 96b9e3e6-c716-493c-aa99-8c1f49c5768b
```

**Spec effect:** B-10 (10 Q7) remains open for the remote creation-wait measurement and maintainers' intent on cross-kind name reservation. This run provides no live evidence for either question.

### B-28 — Controller removal, key retention, and open session

The Connections page contained one saved device, `devbox`, marked offline with “Silo's remote bridge is missing on the other device.” I opened an authenticated SSH session to localhost using the probe key and forced bridge exec command, without sending a frame, and left its input open. I then clicked **Remove connection to devbox** in Settings → Connections. The device row disappeared. After that removal, the SSH process was still present and the authorized key file still contained its sole restricted probe line with the same fingerprint. I closed the probe SSH session after recording survival.

This is a limited live result: the removed `devbox` was offline, while the kept-open session was the separate localhost probe connection. It confirms the controller removed its saved device record without deleting this Mac's probe key line or terminating that independent authenticated session. It does not confirm whether removal revokes the matching key on a connected peer, which B-28 and 95 A-36 still require.

```text
Connections after removal: no devbox row; Connect device… remains.
authorized_keys: exists=true, lineCount=1, restricted probe line=true
SSH after removal: PID 43459 still running the forced bridge exec command
```

**Spec effect:** B-28 (60 §connections.devices.remove/keys.revoke; 95 A-36) remains open for a connected-peer revocation test, retry/offline refusal, and reconnect race. Today's controller-side removal and established-session evidence is limited to the state above.

### Revert verification

After the probes, I turned Connections off in Silo Dev and verified `~/.silo-dev/desktop-remote/config.json` had `enabled: false` and zero saved device entries. The requested `devbox` removal remains in the controller; no other saved connection remains. I removed the newly created `~/.ssh/authorized_keys`; the earlier empty backup sentinel confirms it did not exist before the run. The original `~/.ssh` directory remains mode 700. I restored `~/.local/bin/silo-remote` to its exact preflight target, removed the probe-created `~/.local/bin/silo-remote-dev` link, removed the private and public probe key files and `known_hosts`, and deleted the copied app bundle. Silo Dev (including the earlier PID 11741 and the copied-app process) and the test SSH session were absent at final process check. Final free space was 192 GB. The checks and guarded cleanup are recorded in `src/revert_probe.py`.
