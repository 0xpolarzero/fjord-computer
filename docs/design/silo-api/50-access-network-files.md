# 50 — Access, network and files

Domains: `github.*`, `push.*`, `secrets.*`, `network.*`, `sshAccess.*`, `guest.*` (with the `editor.*` / `terminal.*` question), `files.*`.

## Conventions in this section

**Host scope (95 §3, Linux hosts dropped).** All owner engines, controller engines and Fjord clients run on Macs only. “Both” in a method's Platforms means Linux computers and macOS computers on those Mac hosts. Linux guest images, desktop services, MicroSandbox, credential substitution and guest SSH remain in scope. Linux engine packages, Secret Service custody, AppImage launch helpers, Linux application launchers and Linux host webviews are retired source evidence, with no API branch or new engine updates (95 §3).


- **Paths.** `src/…` is `app/SiloUI/src-tauri/src/…`, `guest/…` is `app/SiloUI/src-tauri/guest/…` and `ui/…` is `app/SiloUI/src/…` in the Silo repo at `94d81937`. `docs/…` are Silo docs. `brief` is `docs/design/silo-api/00-brief.md` in this repo.
- **Computer reference.** Today's Tauri commands take a local computer *name*, or `silo-remote:<deviceId>:<computerId>` for a computer on another device (`src/remote_access.rs:8-19`). Bridge methods take `computerId` and resolve it on the owner (`src/remote_access.rs:26-28`). In the API every per-computer method takes `computerId` + `deviceId?` (10's `ComputerRef`, flattened; absent `deviceId` = this engine), and device-level methods take `deviceId?` (80 §2 N16). The historical `silo-remote:` target string is not retained as an engine input or compatibility route; clients use canonical IDs (95 §3). NEW records and wire references use `computerId`; there is no runtime name-key fallback or compatibility migration (95 §3 overrides the A-11/A-13 conversion default). Any conversion required to reach this version runs once at launch through `runtime_migration` (20 `migration.*`; 95 §3). Current name-key evidence: `src/github.rs:1630-1634`, `src/github.rs:1189-1216`, `src/runtime.rs:13117-13125`. Historical type examples below show the previous keys; the API changes them explicitly.
- **Jobs.** Long methods (Kind `job`) follow the one job contract of 05 §4.2 E/F ([job contract](05-engine-architecture.md#job-contract)): they return `{jobId}` at once, report progress on `operations.job.progress`, end with `operations.job.finished`, and cancel through `operations.cancel {jobId}`. NEW terminal outcomes are saved to disk, survive engine restarts and are removed after a client acknowledges showing them through `operations.job.acknowledge` (95 §3 Job results, overriding A-25). Interrupted running work is not promised to resume; B-37 qualifies recovery.
- **macOS queue admission (NEW, justified by 95 A-31 and §3 Queue).** Mutating macOS work waits its operation turn, appears as “Waiting…” with Cancel, and is not refused merely because another operation or transfer is running (10 operations queue; 95 §3). Read methods and established raw streams retain their sourced query/stream role. Cancellation and durable terminal outcomes follow 05's common contract.
- **Remote routing baseline.** Today Tauri methods receiving a `silo-remote:` target forward to the owner over the Connections bridge. The NEW canonical contract takes IDs through the local engine, with no old target parser (95 A-3; 95 §3). That is why one API method usually maps to one Tauri command plus one bridge method. Change methods on the bridge carry an `operationId` and a `startWithinMs` and are journalled, so a lost reply never replays them (`src/remote.rs:2249-2275`). Bridge errors are `BridgeError { code, message }` with `code` in `update_in_progress | unsupported_remote_operation | cancelled | already_queued | busy | not_found | incompatible_version | internal` (serialized snake_case, `src/bridge_error.rs:4-24`). Local Tauri commands return plain `String` errors. The messages quoted below are the ones in the code.
- **Main-window checks.** Many commands refuse any window but `main` (for example `src/github.rs:3011-3018`, `src/secrets.rs:782-788`, `src/ssh_connection.rs:129-131`, `src/transfer.rs:1346`). That is Tauri's window-permission model. In the engine it becomes client authorization (`engine.*` section), so it isn't repeated per method.
- **Events.** Today GitHub, secrets and push changes are announced by the generic `silo://application-state-changed` (for example `src/github.rs:266,820,3069`, `src/secrets.rs:531,849,869,777`, `src/host_push_operations.rs:224`). The domain events named below (`github.changed`, `secrets.changed`, `push.changed`, `network.changed`, `editor.includeNotice.changed`) are the names of 05's [event catalogue](05-engine-architecture.md#event-catalogue) (05 §4.2 D; 80 §2 N15). NEW events carry the new read state plus sequence number; buffers are bounded and clients re-read after a gap or reconnect (justified by 95 A-4; 05 event catalogue). Remote subscriptions use a Stream-class bridge through the controller's local engine (95 A-3/A-4).

**No legacy contract (95 §3).** Historical Tauri and bridge names in Sources and Coverage identify today's implementation only. Both clients call the canonical methods; no old bridge method names, retired operations, old SSH-name aliases or runtime name-key compatibility paths are served. Only the existing `runtime_migration` launch mechanism may convert state to this version (20 `migration.*`).

---

## github.*

### What exists

- **Connection: native PKCE through a loopback callback, no Silo server.** `connect` binds `127.0.0.1:0` (`src/github.rs:2589-2600`). It builds `https://github.com/login/oauth/authorize` with `client_id`, `redirect_uri=http://127.0.0.1:<port>/github/callback`, a random `state` and an S256 `code_challenge` (`src/github.rs:2601-2618`). It opens that URL in the browser chosen in Settings (`src/github.rs:2556-2574`, through `applications::open_browser`, `src/applications.rs:41`). It then waits up to 300 s for the callback (`src/github.rs:2620-2652`) and answers it with a plain-text page (`src/github.rs:2637-2642`). The callback must be a single `GET /github/callback` with exactly one matching `state` and one `code` (`src/github.rs:2474-2514`).
- **Exchange, then the App installation check.** The code is exchanged, and `/user` and the installation catalog are read (`src/github.rs:2664-2680`). When the App isn't installed, Silo opens `https://github.com/apps/<slug>/installations/new` and polls every 3 s for up to 300 s (`src/github.rs:2681-2706`). Then it stores the credential and records the account (`src/github.rs:2710-2768`, `record_connection` `src/github.rs:2783-2798`). It revokes any replaced credential (`src/github.rs:2769-2773`) and brings the main window forward (`src/github.rs:2775-2778`).
- **Which parts need a browser or UI.**
  - Two browser pages: the OAuth authorize page and, when needed, the App installation page. Both are opened by the engine process today.
  - Today the callback is plain HTTP to `127.0.0.1` on the owner. NEW: the controller's local engine carries this callback over the existing Connections SSH connection so its browser can authorize the owner (justified by 95 A-17; callback: `src/github.rs:2589-2600`; Stream bridge precedent: `src/remote.rs:2106-2120`).
  - `reopen_github_authorization` reopens the pending URL that is kept in `AUTHORIZATION` (`src/github.rs:145-164, 3076-3088`).
  - `manage_github_repositories` opens the App installation page (`src/github.rs:3090-3105`).
  - Raising the main window after the connect (`src/github.rs:2775-2778`) is UI-only.
  - Everything else (exchange, storage, catalog, grants) is engine work.
- **Credentials.**
  - On supported Mac hosts, the user credential is kept in the Keychain under the channel's GitHub service (`src/channel.rs:83-87`; 95 §3). The historical Secret Service route is retired (95 §3). Public snapshots never read the store. They read only a process-local observation (`docs/SiloUI-GITHUB-IMPLEMENTATION.md` "Live edits and failures", 94-100; `src/github.rs:431-471`).
  - The personal token is a separate store entry, `personal-token` (`src/github_personal_token.rs:19-25`).
- **Per-computer policy, saved in `github.json`.** The fields are `computer`, `identity {name,email,apply}`, `repositoryMode: "selected"|"all"`, `repositories[{repository, allowPushes}]`, `allRepositoriesAllowChanges` and `authenticationMethod: "oauth"|"token"` (validation in `src/github.rs:1607-1696`; type in `ui/desktop/production-source.ts:53-58`).
  - Read-only is the default: "Default to read-only; **Allow GitHub changes** covers repository Git/API writes" (`docs/SiloUI-GITHUB-IMPLEMENTATION.md` "Behavior and scope", 13-17).
  - A successful connect turns access on (`src/github.rs:2789`). An explicit disable persists (same doc, 13-15).
- **Restricted tokens injected by the msb proxy.**
  - Every Linux computer is created with `--secret SILO_GITHUB:passthrough=*@github.com,api.github.com,uploads.github.com` and `--env GH_TOKEN=$MSB_SILO_GITHUB` (`src/runtime.rs:5626-5635`; spec `src/secrets_runtime.rs:56-58`).
  - The host mints narrow per-owner read/write tokens (`RuntimeGrant`, `src/github.rs:1699-1712`; scopes `src/github.rs:1734-1811`) and sends a versioned profile with `msb modify` (`apply_github_policy`, `src/runtime.rs:2430-2470`; version 1 is OAuth and version 2 is the personal token).
  - The patched proxy substitutes "only scoped credentials to the exact Authorization placeholder under verified TLS" (`docs/SiloUI-GITHUB-IMPLEMENTATION.md` 46-50; personal token: `docs/SiloUI-GITHUB-PERSONAL-TOKENS.md` "Credential boundaries", 39-44).
  - A profile change closes existing proxy connections without a reboot (implementation doc 71-73).
- **The guest credential helper.** `guest/setup-github.sh:10-28` installs `/usr/local/libexec/silo-github-credential`. For `https://github.com` it answers `username=x-access-token` and `password=$MSB_SILO_GITHUB`, the placeholder and never a real token. It registers the helper system-wide and runs `git lfs install --system`. `gh` gets `GH_TOKEN=$MSB_SILO_GITHUB` from the computer's environment (`src/runtime.rs:5632-5633`).
- **GitHub App configuration at build time.**
  - `SILO_GITHUB_CLIENT_ID`, `SILO_GITHUB_CLIENT_SECRET` and `SILO_GITHUB_APP_SLUG` are compile-time values (`src/github.rs:269-271`). `build.rs` reads them from `app/SiloUI/github-build.local.json` or the environment and fails the build when they're missing (`app/SiloUI/src-tauri/build.rs:1-15`; `docs/SiloUI-GITHUB-IMPLEMENTATION.md` "GitHub App and build configuration", 106-131).
  - The App is ID `4605731` with callback `http://127.0.0.1/github/callback`. Device Flow is disabled and only repository permissions are granted (same doc, 108-115).
  - **For the engine: these become `silod` build inputs. No client needs them.**
- **Background work (an engine duty).** `github::install` starts the worker (`src/main.rs:306`, `src/github.rs:2831`).
  - It refreshes the catalog every five minutes for connected, enabled accounts (implementation doc 74-77) and renews tokens.
  - It re-validates a saved personal token at startup and every five minutes, retrying after 30 s on failure (`docs/SiloUI-GITHUB-PERSONAL-TOKENS.md` 22-25).
  - It honours rate limits, with at most five automatic retries (implementation doc 79-86).
- **Engine behaviour: retiring issued tokens through a ledger.**
  - **Status:** EXISTS, internal. No method (`src/github.rs:1217-1277`, `src/github.rs:2985-2996`).
  - **Store:** a credential-store entry `runtime-grants` under the channel's GitHub service. It holds a JSON map from computer name to the restricted tokens issued for it (`src/github.rs:1189-1216`). Its errors (`src/github.rs:1189-1216`):
    - "The system credential store is unavailable.";
    - "Stored GitHub runtime credentials are invalid.";
    - "Cannot read GitHub runtime credentials from the system credential store.";
    - "Cannot save GitHub runtime credentials in the system credential store.".
  - **Record before the next request:**
    - Every restricted token minted for a computer is appended to the ledger before Silo makes any other network request, so "a later partial failure must not lose the only copy needed for revocation" (`remember_token`, `src/github.rs:1217-1225`).
    - If recording a runtime grant's token fails, Silo attempts to revoke the token at once and the issuance fails (`src/github.rs:1914-1917`).
    - Recording also sets `grants_issued` in `github.json` (`src/github.rs:1222-1224`).
  - **Retirement:**
    - `retire_unused(computer)` revokes (`RevokeToken`) each of that computer's ledger tokens that is not live. It then removes the revoked ones from the ledger (`src/github.rs:1230-1275`, `src/github.rs:1295-1340`).
    - "Live" means any of: in the computer's cached runtime profile (`runtime::scoped_cached_tokens`), in its active grants, issued and still matching the computer's current scopes, or held by a host push in progress (`src/github.rs:1230-1277`; `active_pushes`, `src/github.rs:2126-2154`).
  - **Retry, independent of clients:**
    - The GitHub worker runs `sweep_retirement` when due and schedules its next pass 30 s later; a completed host push can make a pass due sooner (`RETIREMENT_RETRY_AFTER`, `src/github.rs:2125`; `src/github.rs:2135-2137`, `src/github.rs:2804-2827`; called at `src/github.rs:2985-2996`).
    - A pass first saves a ledger whose earlier write failed (`LEDGER_SECRET.flush`), then retires every computer in the ledger. One computer's failure doesn't stop the others (`src/github.rs:2804-2827`, `src/github.rs:2985-2996`).
    - The next retirement deadline limits the worker's sleep, subject to its 100 ms minimum (`src/github.rs:96`, `src/github.rs:2999-3006`).
  - **Host push tokens:**
    - A push token joins `active_pushes` before it is recorded (`begin_host_push_token`, `src/github.rs:2144-2154`).
    - When the push ends, `HostPushCredential::drop` attempts revocation, removes the token from the ledger only after confirmed revocation, marks retirement due now and wakes the worker (`src/github.rs:2178-2210`).
    - A personal token is never revoked (`src/github.rs:2157-2158`).
  - **Credential-store retry** also clears a blocked ledger (`retry_credential_access`, `src/github.rs:424-427`).
- **Scope today: local computers only.** Policies are keyed by local computer name (`src/github.rs:1630-1634`), and no bridge method exists for GitHub (`src/remote.rs:236-271`). A controller sees the owner's GitHub state only inside that owner's `runtime.snapshot` (`src/runtime.rs:2867-2871`, served by `src/runtime/remote_ops.rs:6-11`).

### GitHubState (the result type of every github.* method)

The current keys of `public_snapshot` are (`src/github.rs:1171-1188`), checked against `ui/desktop/production-source.ts:41-64`:

- `policyRevision: u64`: below 2^53 (`src/github.rs:473-482`).
- `personalToken: {state: "connected"|"disconnected", saved: bool, account?: string, message?: string}` (`src/github_personal_token.rs:35-41, 270-285`).
- `state: "disconnected"|"connecting"|"connected"`.
- `account: string|null`.
- `accessEnabled: bool`.
- `deviceIdentity: {name, email}|null`: the host's Git and Jujutsu author (`src/device_identity.rs:13-17`).
- `repositoryCatalog: string[]` (`owner/name`).
- `repositoryCatalogStatus: {status:"available"} | {status:"unavailable", message, canRetry}`.
- `computers: Policy[]`. NEW API policy row field `computerId: string` replaces current `computer: string`, justified by 95 A-11; current stored keys: `src/github.rs:1630-1634`. The array key `computers` stays unchanged.
- `computerOperations: [{computer, status: "applying"|"succeeded"|"failed", message, canRetry?, diagnosticDetails?}]`.
- NEW API `computerOperations[].computerId: string` replaces the name-keyed `computer` reference, justified by 95 A-11; existing public row source: `src/github.rs:1171-1188`.
- **NEW field `pendingAuthorizationUrl: string|null`.** It is the URL the connect is waiting on: the authorize URL or the App install URL (`src/github.rs:2612-2619, 2686-2690`), today kept only in `AUTHORIZATION` (`src/github.rs:2559-2574`). Required because the engine may have no UI to open a browser (brief:12) and must expose everything but drawing UI (brief:14). The client opens it.

### github.state
- Kind: query
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19). Host-level methods apply to either kind.
- Status: EXTENDED. NEW pendingAuthorizationUrl and remote owner access (95 A-14/A-16/A-17/A-22). Existing behavior: (tauri `read_github_state`, `src/github.rs:3031-3036`). Also embedded as `github` in `read_application_state` and the bridge `runtime.snapshot` (`src/runtime.rs:2867-2871`).
- Params: none. **NEW for remote:** `deviceId?: string`, so a controller can read an owner's state directly. It is required by "controllers on other Macs" and the always-on host (brief:25), and by "access to GitHub and secrets" in the Computers tool (brief:19).
- Result: `GitHubState`.
- Errors: "GitHub state could not be read." (`src/github.rs:3035`).
- Semantics: it never opens the credential store. While the store hasn't answered yet, it reports "Waiting for access to the system credential store." with `canRetry:false` (`src/github.rs:1154-1169`). Computers waiting for a pending restore are left out of `computerOperations` (`src/github.rs:1141-1152`).
- Sources: as cited.

- Host scope: account custody and authorization run on the owner Mac; guest proxy policy is specified by `github.configuration.*` and `secrets.save`.
- Remote contract: NEW (justified by 95 A-3/A-14/A-16). `deviceId?: string` routes through the local engine to the owner; absent means local owner. Write-only credential values use that SSH connection and remain stored on the selected owner (95 §1–2; existing custody: `docs/SiloUI-SECRETS.md:3-7`).

### github.connect
- Kind: job (today a blocking command that returns once the browser flow ends, up to about 10 min: 300 s callback plus 300 s App install, `src/github.rs:2620, 2691`)
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19). Host-level methods apply to either kind.
- Status: EXTENDED. NEW client-owned browser/callback relay, durable job outcomes and remote owner access (95 A-14/A-16/A-17/A-22; 95 §3 Job results). Existing behavior: (tauri `connect_github`, `src/github.rs:3037-3052`; flow `src/github.rs:2576-2781`). Job wrapper and `pendingAuthorizationUrl` are NEW, justified by 95 A-17/A-22 and §3 Job results (overriding A-25).
- Params: none. NEW: `deviceId?: string` selects the owner through the local engine (95 A-3/A-14/A-17). Browser launching belongs to the client: it opens `pendingAuthorizationUrl`; the engine never launches a browser (95 A-22).
- Result: `{jobId}` (`job:<n>`, 05 §4.2 E). `operations.job.finished.result`: `GitHubState` (`state:"connected"`). NEW: the engine saves the terminal outcome to disk, retains it across restarts, and removes it after a client acknowledges showing it through `operations.job.acknowledge` (95 §3 Job results, overriding A-25; 05 job contract). This does not guarantee resumption of an interrupted running process; recovery of that case remains B-37.
- Progress/events: no progress source and no gate entry (GitHub connect never enters the gate, 05 §4.2 E). `state:"connecting"` in `GitHubState` while it waits (`src/github.rs:2582`). `github.changed` fires on start and at the end (`src/github.rs:2585, 257-266`).
- Cancel: `operations.cancel {jobId}` (05 §4.2 F), routed to today's `cancel_github_connection`; the job ends with `error.code: "cancelled"`.
- Errors (today's command errors; they end the job in `operations.job.finished.error`, 05 §4.2 E item 5): "GitHub connection cancelled.", "GitHub connection timed out. Try again.", "GitHub authorization was declined.", "Invalid GitHub authorization response.", "GitHub repository authorization timed out. Connect again after authorizing the App.", "GitHub App is not configured in this build.", "Cannot start the GitHub callback listener." (`src/github.rs:2474-2706`).
- Semantics:
  - One flow at a time (`CONNECTION_FLOW`, `src/github.rs:3047`).
  - Only the exchange and the storage steps hold the network lock (`src/github.rs:2660-2662`).
  - The owner keeps the existing PKCE verifier, state check and credential exchange (`src/github.rs:2474-2514, 2601-2618, 2664-2680`). For a remote owner Mac without a screen (95 A-17; 95 §3), the controller's local engine establishes the callback route over the existing SSH connection before exposing `pendingAuthorizationUrl`; the browser's loopback request is carried to the owner's callback listener (NEW, justified by 95 A-17). Only this connect job's listener is forwarded, and it closes on completion/cancellation. Existing loopback and Stream bridge seams are `src/github.rs:2589-2600` and `src/remote.rs:2106-2120`; callback port reservation, multiplexed framing and GitHub acceptance remain B-25. The NEW `github.connect.callback` Stream route is restricted to this active job; it is not a general port relay.
  - A reconnect detaches old grants from every OAuth-mode computer and never reuses them (`src/github.rs:2726-2756`).
  - A failure after the exchange revokes the new credential (`Unstored`, `src/github.rs:2669-2671`; doc 39-42).
- Sources: `docs/SiloUI-GITHUB-IMPLEMENTATION.md` "Native implementation" 25-56, "GitHub App and build configuration" 106-148.

- Host scope: account custody and authorization run on the owner Mac; guest proxy policy is specified by `github.configuration.*` and `secrets.save`.
- Remote contract: NEW (justified by 95 A-3/A-14/A-16). `deviceId?: string` routes through the local engine to the owner; absent means local owner. Write-only credential values use that SSH connection and remain stored on the selected owner (95 §1–2; existing custody: `docs/SiloUI-SECRETS.md:3-7`).

### github.connect.callback (engine-to-engine)
- Kind: stream (raw HTTP request/response bytes over the existing Connections SSH transport).
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); host-level callback listener.
- Status: NEW (justified by 95 A-17: controller browser callback reaches an owner Mac without a screen (95 §3); 95 §1). Builds on the existing PKCE loopback listener (`src/github.rs:2589-2618`) and Stream bridge dispatch (`src/remote.rs:2106-2120`), not a second OAuth flow.
- Params (NEW): `jobId: string` — the active owner's GitHub connect job identifies the only permitted callback listener; `deviceId?: string` — route through the controller's local engine (95 A-3/A-17; 05 job contract). No host, path or port supplied by a client is accepted.
- Result: raw callback HTTP bytes and the owner's existing response (`src/github.rs:2637-2642`). The owner's matching state/code validation remains authoritative (`src/github.rs:2474-2514`).
- Progress/events: connect completion is still `operations.job.finished`; this transport adds no job (05 job contract; 95 A-17).
- Errors: existing `not_found` for no active job/listener and `cancelled` after cancellation (`src/bridge_error.rs:4-24`); existing OAuth refusal/timeout remains on `github.connect` (`src/github.rs:2474-2706`). Exact callback listener-bind/transport codes require B-25.
- Semantics (NEW, 95 A-17): local engine binds the browser-facing loopback listener before publishing the authorization URL and relays only its active connect job's callback through this Stream method. Completion, cancellation and SSH loss tear down the listener/stream. Preserve the existing PKCE verifier and exchange on the owner (`src/github.rs:2601-2618, 2664-2680`). The installed Connections key forbids SSH port forwarding (`src/remote.rs:25-29, 876-898`), so reuse the restricted bridge Stream path rather than generic SSH forwarding. Port reservation, URL/redirect consistency and GitHub round-trip acceptance remain B-25.
- Sources: 95 A-17; code cited above. This route is NEW, not an existing supported callback bridge method.


### github.connect.reopen
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19).
- Kind: command
- Status: EXTENDED. NEW pending URL result for client launching and remote owner access (95 A-14/A-16/A-22). Existing behavior: (tauri `reopen_github_authorization`, `src/github.rs:3076-3088`). NEW behavior: returns the pending URL for the client to open, without an engine-side browser launch (justified by 95 A-22).
- Params: `deviceId?: string` (NEW, 95 A-14). Result (NEW, 95 A-22): `{url: string}`.
- Errors: those of `PendingAuthorization::url` (`src/github.rs:145-164`) and "Cannot reopen GitHub authorization.".

- Host scope: account custody and authorization run on the owner Mac; guest proxy policy is specified by `github.configuration.*` and `secrets.save`.
- Remote contract: NEW (justified by 95 A-3/A-14/A-16). `deviceId?: string` routes through the local engine to the owner; absent means local owner. Write-only credential values use that SSH connection and remain stored on the selected owner (95 §1–2; existing custody: `docs/SiloUI-SECRETS.md:3-7`).

### github.repositories.manage
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19).
- Kind: command
- Status: EXTENDED. NEW URL result for client launching and remote owner access (95 A-14/A-16/A-22). Existing behavior: (tauri `manage_github_repositories`, `src/github.rs:3090-3105`). NEW behavior: returns `https://github.com/apps/<slug>/installations/new` for client launching (justified by 95 A-22).
- Params: none. Result: today none. NEW: `{url}`, so a client can open it (brief:12,14).
- Errors: "GitHub App is not configured in this build.", "Invalid GitHub App slug." (`src/github.rs:3094-3097`).

- Host scope: account custody and authorization run on the owner Mac; guest proxy policy is specified by `github.configuration.*` and `secrets.save`.
- Remote contract: NEW (justified by 95 A-3/A-14/A-16). `deviceId?: string` routes through the local engine to the owner; absent means local owner. Write-only credential values use that SSH connection and remain stored on the selected owner (95 §1–2; existing custody: `docs/SiloUI-SECRETS.md:3-7`).

### github.repositories.refresh
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19).
- Kind: command
- Status: EXTENDED. NEW remote owner access and macOS computer policy reconciliation (95 A-14/A-16/A-19). Existing behavior: (tauri `refresh_github_repositories`, `src/github.rs:3107-3139`)
- Params: none. Result: `GitHubState`.
- Semantics:
  - It retries credential-store access (`src/github.rs:424-430, 3113`) and reloads the catalog.
  - A changed catalog marks every computer pending. It narrows grants immediately and schedules the worker in 500 ms (`src/github.rs:3118-3135`).
  - It resets only safe operations and keeps server-imposed waits ("Live edits and failures", doc 83-86).

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).
- Remote contract: NEW (justified by 95 A-3/A-14/A-16). `deviceId?: string` routes through the local engine to the owner; absent means local owner. Write-only credential values use that SSH connection and remain stored on the selected owner (95 §1–2; existing custody: `docs/SiloUI-SECRETS.md:3-7`).

### github.disconnect
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19).
- Kind: command
- Status: EXTENDED. NEW remote owner control and macOS credential-proxy detachment (95 A-14/A-16/A-19). Existing behavior: (tauri `disconnect_github`, `src/github.rs:3140-3166`)
- Params: none. Result: `GitHubState`.
- Semantics:
  - It persists `accessEnabled=false` and `disconnectPending=true` and detaches every computer, then the worker revokes on GitHub (`src/github.rs:3153-3161`).
  - Only `bad_refresh_token` lets the disconnect finish without revocation. Other OAuth errors keep revocation pending (doc 144-148).
  - The account cache is cleared only after the credential is deleted (doc 279-287).

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).
- Remote contract: NEW (justified by 95 A-3/A-14/A-16). `deviceId?: string` routes through the local engine to the owner; absent means local owner. Write-only credential values use that SSH connection and remain stored on the selected owner (95 §1–2; existing custody: `docs/SiloUI-SECRETS.md:3-7`).

### github.access.set
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19).
- Kind: command
- Status: EXTENDED. NEW remote owner control and macOS credential-proxy reconciliation (95 A-14/A-16/A-19). Existing behavior: (tauri `set_github_access_enabled`, `src/github.rs:3167-3197`)
- Params: `enabled: bool`. Result: `GitHubState`.
- Semantics: idempotent (it returns the snapshot when nothing changes, `src/github.rs:3183-3185`). Otherwise it bumps the revision, marks every computer pending and narrows (`src/github.rs:3186-3192`). It runs in intent order (`INTENTS`, `src/github.rs:167-256`).

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).
- Remote contract: NEW (justified by 95 A-3/A-14/A-16). `deviceId?: string` routes through the local engine to the owner; absent means local owner. Write-only credential values use that SSH connection and remain stored on the selected owner (95 §1–2; existing custody: `docs/SiloUI-SECRETS.md:3-7`).

### github.configuration.save
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19).
- Kind: command
- Status: EXTENDED. NEW macOS credential-proxy policy application and remote owner control (95 A-14/A-16/A-19). Existing behavior: (tauri `save_github_configuration`, `src/github.rs:3323-3384`)
- Params: `configuration: {computers: Policy[], baseRevision: u64|null}`. `computers` holds only the computers the caller changed (`src/github.rs:3323-3326`). `accessEnabled` is ignored. `Policy.computer` is the local computer name today. NEW API `Policy.computerId: string` replaces it; records use IDs without runtime name-key fallback (95 §3; NEW justified by 95 A-11/A-13 as amended; existing validation: `src/github.rs:1630-1634`).
- Result: `GitHubState`.
- Errors:
  - The validation messages in `src/github.rs:1607-1696`, for example "Choose selected or all repositories.", "Invalid repository policy." and "Too many computer policies." (more than 64).
  - "GitHub settings for {name} changed while you were editing them. …" (`src/github.rs:3272-3276`).
  - "Connect a personal token before selecting it." and "Connect GitHub OAuth before selecting it." (`src/github.rs:3198-3217`).
- Semantics:
  - Patches apply per computer; computers that aren't listed keep their choices (`src/github.rs:3249-3322`).
  - Additions and write enablement are combined for 500 ms. Removals detach locally before any network work (doc "Live edits and failures" 64-73).
  - A failed narrow marks the changed computers `failed`, `canRetry:true` (`src/github.rs:3368-3379`).
  - The personal-token mode uses the token's full permissions. Repository controls are kept but ignored (`docs/SiloUI-GITHUB-PERSONAL-TOKENS.md` 13-18).

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).
- Remote contract: NEW (justified by 95 A-3/A-14/A-16). `deviceId?: string` routes through the local engine to the owner; absent means local owner. Write-only credential values use that SSH connection and remain stored on the selected owner (95 §1–2; existing custody: `docs/SiloUI-SECRETS.md:3-7`).

### github.configuration.retry
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19).
- Kind: command
- Status: EXTENDED. NEW macOS credential-proxy reconciliation and remote owner control (95 A-14/A-16/A-19). Existing behavior: (tauri `retry_github_configuration`, `src/github.rs:3404-3430`)
- Params: NEW `computerId?: string` (none means every computer), justified by 95 A-11; it replaces the saved local-name key (`src/github.rs:1630-1634`). Result: `GitHubState`.
- Semantics: resets the retry gates (`src/github.rs:3418-3422`), re-marks access and identity pending (`src/github.rs:3385-3402`) and wakes the worker immediately.

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).
- Remote contract: NEW (justified by 95 A-3/A-14/A-16). `deviceId?: string` routes through the local engine to the owner; absent means local owner. Write-only credential values use that SSH connection and remain stored on the selected owner (95 §1–2; existing custody: `docs/SiloUI-SECRETS.md:3-7`).

### github.personalToken.save
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19).
- Kind: command
- Status: EXTENDED. NEW remote owner credential management (95 A-14/A-16). Existing behavior: (tauri `github::personal_token::save_github_personal_token`, `src/github_personal_token.rs:316-351`)
- Params: `token: string`. It is write-only and never returned (`docs/SiloUI-GITHUB-PERSONAL-TOKENS.md` 29-37).
- Result: `GitHubState`.
- Errors:
  - "Enter a valid GitHub personal access token." (empty, more than 4096 bytes or any character outside `[A-Za-z0-9_]`, `src/github_personal_token.rs:51-66`).
  - The `/user` validation failure.
  - "Cannot save GitHub token in the system credential store.".
- Semantics: validated with `/user` before it is stored. Store first, then publish `connected` (`src/github_personal_token.rs:306-350`).

- Host scope: account custody and authorization run on the owner Mac; guest proxy policy is specified by `github.configuration.*` and `secrets.save`.
- Remote contract: NEW (justified by 95 A-3/A-14/A-16). `deviceId?: string` routes through the local engine to the owner; absent means local owner. Write-only credential values use that SSH connection and remain stored on the selected owner (95 §1–2; existing custody: `docs/SiloUI-SECRETS.md:3-7`).

### github.personalToken.remove
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19).
- Kind: command
- Status: EXTENDED. NEW remote owner credential management (95 A-14/A-16). Existing behavior: (tauri `github::personal_token::remove_github_personal_token`, `src/github_personal_token.rs:353-375`)
- Params: none. Result: `GitHubState`.
- Semantics: detaches before deleting, so a storage failure can't leave access attached (`src/github_personal_token.rs:361-364`). It doesn't revoke the token on GitHub (`docs/SiloUI-GITHUB-PERSONAL-TOKENS.md` 19-21).

- Host scope: account custody and authorization run on the owner Mac; guest proxy policy is specified by `github.configuration.*` and `secrets.save`.
- Remote contract: NEW (justified by 95 A-3/A-14/A-16). `deviceId?: string` routes through the local engine to the owner; absent means local owner. Write-only credential values use that SSH connection and remain stored on the selected owner (95 §1–2; existing custody: `docs/SiloUI-SECRETS.md:3-7`).

### github.changed (event)
- Kind: subscription
- Status: EXTENDED (NEW state payload and sequence number required by 95 A-4; 95 §2). Existing event source: EXISTS as `silo://application-state-changed` emitted by `save` (`src/github.rs:818-821`), the connect guard (`src/github.rs:257-266`), the observation publisher (`src/github.rs:433-442`) and others. The name is 05's event catalogue (05 §4.2 D).
- Payload (NEW, justified by 95 A-4): new state (GitHubState) plus sequence number. Bounded subscriber buffering; after a gap or reconnect re-read the domain query (95 §2; 05 event catalogue).

---

## push.*

Host Push publishes a computer's committed branch from the host. The computer's own GitHub access stays read-only, and guest hooks and config never run on the host (`docs/SiloUI-GITHUB-IMPLEMENTATION.md` "Standard host publishing implementation", 448-503).

### push.repositories
- Kind: query
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19). Host-level methods apply to either kind.
- Status: EXTENDED. NEW macOS guest repository discovery adapter (95 A-19; Q9–Q10). Existing behavior, embedded. Every fresh, running computer row of `read_application_state(refreshRepositories?)` carries `repositories` (`src/runtime.rs:2826-2858`; `src/runtime.rs:2664-2690`). The bridge `runtime.snapshot` takes `refreshRepositories` (`src/runtime/remote_ops.rs:6-11`; controller `src/remote.rs:1467-1478`). If `computers.list` carries `repositories`, this is the same data. The method is named here so push has a complete surface.
- Params: `computerId`, `deviceId?`, `refresh?: bool`.
- Result: `[{path, branch, ahead, behind, dirty, head: string|null, repository: "owner/name"|null}]` (`src/host_push.rs:314-340`).
- Semantics:
  - It scans `/workspace` for `.git`, skipping dependency trees, with no entry-count cutoff (`src/host_push.rs:290-301`).
  - It is single-flight and cached per computer (`src/host_push.rs:226-289`). Without `refresh`, it returns the last result while a scan runs.
  - Discovery runs `--no-start`, so it never boots a computer (doc 538-541).

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).

### push.start
- Kind: job (the client picks the push `operationId`)
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19). Host-level methods apply to either kind.
- Status: EXTENDED. NEW durable outcome acknowledgement and macOS guest publication adapter/queue (95 §3 Job results/Queue; 95 A-19). Existing behavior: (tauri `host_push_operations::start_repository_push`, `src/host_push_operations.rs:402-434`; bridge `repository.push.start`, `src/remote.rs:260`, dispatched at `src/remote_access.rs:126-128` to `start_remote`, `src/host_push_operations.rs:389-401`)
- Params: `computerId`, `deviceId?`, `repositoryPath: string`, `operationId: uuid`, `target: {repository: "owner/name", branch, commit}` (`PushTarget`, `src/host_push.rs:185-207`). `operationId` is the push's domain id, not the bridge's transport `operationId` (05 §4.1, §4.2 E item 2).
- Result: `{jobId}` (`push:<operationId>`, 05 §4.2 E). `operations.job.finished.result`: the final `PushOperation = {operationId, computer, repositoryPath, status: "pushing"|"succeeded"|"failed"|"unknown", commitCount, target, message?}` (`src/host_push_operations.rs:157, 218`; `src/host_push.rs:1272-1300`). A client that missed `finished` can re-read `push.status`; the terminal job outcome also follows durable retention and acknowledgement (95 §3 Job results; 05 job contract).
- Progress/events: `operations.job.progress` with `source: "push"`, `data` = the `PushOperation` while `status: "pushing"` (05 §4.2 E item 4). `push.changed` also fires (today `silo://application-state-changed`, `src/host_push.rs:1219, 1241`; `src/host_push_operations.rs:224`).
- Cancel: `operations.cancel {jobId}` (05 §4.2 F), which goes to its gate entry; that entry opts in (`src/host_push.rs:786-791`).
- Errors:
  - Returned as a `failed` result, not as an error, so a preparation failure can't be mistaken for a lost reply (`src/host_push_operations.rs:358-368`). Under the job contract `failed` and `unknown` stay data in `operations.job.finished.result`; `error` is set only where today's command errors (05 §4.2 E item 5).
  - "Invalid GitHub repository for this push." / "Invalid branch for this push." / "Invalid commit for this push." (`src/host_push.rs:190-206`).
  - "This computer is not allowed to push to this repository." (`src/github.rs:2339-2358`).
  - "Enable GitHub access before pushing." (`src/github.rs:2255-2257`).
  - "The repository changed after you confirmed the push. …" (`src/host_push.rs:208-209`).
  - For journal capacity, the 10,000 and 16 MiB messages (`src/host_push_operations.rs:38-39, 154-156`).
  - An older remote device: "Update Silo on the remote device before pushing." (`src/host_push_operations.rs:419`).
- Semantics:
  - The claim is persisted in `repository-push-operations.json` before dispatch, so a retry of a lost reply never starts a second job. A duplicate click returns the existing job (`src/host_push_operations.rs:128-168, 189-227`), so the same `push:<operationId>` (05 §4.2 E item 2).
  - A process restart turns a `pushing` job into `unknown` (`src/host_push_operations.rs:96-103`).
  - The push needs `allowPushes` on the repository, or `all` with `allRepositoriesAllowChanges` (`src/github.rs:2339-2358`). It uses a token scoped to `contents: write` on that one repository, minted from an account credential renewed to last at least 30 min, or the personal token (`src/github.rs:2212-2236, 2239-2324`).
  - The transfer fetches from the guest's upload-pack over a private OpenSSH connection (`src/host_push_transport.rs:29`; doc 454-470).
  - **Publication order** (EXISTS; `src/host_push.rs:863-1014`; `docs/SiloUI-GITHUB-IMPLEMENTATION.md` 454-470):
    1. **Capture.**
       - The guest pins the confirmed commit in a temporary ref. It fails with `TARGET_CHANGED` if the branch moved or `origin` no longer names the confirmed repository (`src/host_push.rs:1091-1124`).
       - The guest's LFS media directory is exposed read-only through `git-lfs-transfer`, in an operation directory (`src/host_push.rs:1079-1124`; `docs/SiloUI-GITHUB-IMPLEMENTATION.md` "Standard host publishing implementation", 458-463).
    2. **Fetch into the private publishing cache** (engine behaviour below). The fetched commit must equal the confirmed one: "The computer repository changed during export. Retry the push." (`src/host_push.rs:888-902`).
    3. **Check the remote.** Read the remote branch. If it exists, refuse a non-fast-forward before transferring LFS: "The remote branch has commits missing from this computer. Fetch and integrate them before pushing." (`src/host_push.rs:911-951`). If it doesn't, count commits against the remote default branch.
    4. **Fetch LFS from the source.** `git lfs fetch --all` from the guest over pure SSH, so objects referenced only by historical commits are included (`src/host_push.rs:959-978`). Its failure is not fatal by itself (`src/host_push.rs:963-980`).
    5. **Upload LFS.** `git lfs push origin refs/silo/push` (`src/host_push.rs:980`).
       - Cancellation, or an expired credential, ends the push at once (`src/host_push.rs:980-986`).
       - Any other failure allows exactly one `git lfs fetch --all origin` to recover pruned historical objects, then one more `git lfs push`. That error reports the source, upstream and first-upload results (`src/host_push.rs:987-1002`).
       - Incomplete LFS pushes are never enabled (`src/host_push.rs:987-989`).
    6. **Push the ref.** A non-force `git push --porcelain origin refs/silo/push:refs/heads/<branch>`, only after Git LFS succeeded (`src/host_push.rs:1003-1013`).
    7. **Record.** Update the guest's tracking ref to the published commit, only if the guest hasn't fetched newer data or repointed `origin` meanwhile (`src/host_push.rs:1157-1170`). This step can't be cancelled (`src/host_push.rs:1160-1171`).

  - **Engine behaviour: the private publishing cache.**
    - **Status:** EXISTS, internal (`src/host_push_cache.rs:29-31`, `src/host_push.rs:1086-1087`).
    - **Location and key:** `<runtime home>/push-cache/<sha256(computer \0 path \0 repository)>`, private directories only (`src/host_push.rs:1086-1087`; `src/host_push_cache.rs:33-46`, `src/host_push_cache.rs:92-95`). It holds no tokens (`docs/SiloUI-GITHUB-IMPLEMENTATION.md` 479-487).
    - **Locks:**
      - A short root lock serialises choosing, creating and evicting caches across processes (`src/host_push_cache.rs:1-4`, `src/host_push_cache.rs:66-85`).
      - Each repository's `<name>.lock` is held for the whole push and inherited by the Git children (`HostGit.cache_lock_fd`, `src/host_push.rs:1132`; `src/host_push_cache.rs:1-4`, `src/host_push_cache.rs:20-27`, `src/host_push_cache.rs:96-106`).
      - A second push of the same repository fails with "Another push of this repository is still using its publishing cache. Wait for it to finish." (`src/host_push_cache.rs:100-104`).
    - **Crash recovery:**
      - An `.active` marker is written and synced at each acquisition (`src/host_push_cache.rs:126-139`).
      - If the marker is still there at the next acquisition, its process died before cleanup. Holding the repository lock proves no Git child of that process survives, so the directory is deleted and recreated (`src/host_push_cache.rs:109-112`).
    - **Failed publication:**
      - A failure before the guest commit is imported into the cache discards the directory but keeps the lock (`src/host_push.rs:1150-1156`; `src/host_push_cache.rs:149-155`).
      - After import, the cache is kept across remote rejections and network failures to avoid retransferring large LFS repositories on retry (`src/host_push.rs:1152-1153`).
    - **Release:**
      - The `.active` marker is removed unless the cache was discarded. The lock is released explicitly, then the root is swept (`src/host_push_cache.rs:162-178`).
      - Cleanup errors are ignored: "Cache cleanup must not relabel a successful remote ref update as a failed push" (`src/host_push_cache.rs:160-178`).
    - **Budget:** 2 GiB across repositories (`src/host_push_cache.rs:17`), swept at every acquisition and release (`src/host_push_cache.rs:113`, `src/host_push_cache.rs:175-177`); eviction rules (`src/host_push_cache.rs:202-298`):
      - a cache whose lock is held is counted when its size can be read, but never evicted; a concurrent mutation that prevents sizing skips it for that pass;
      - an idle cache over the budget by itself is removed;
      - otherwise idle caches are evicted least recently used first, by the `.last-used` mtime, until the total fits;
      - lock files left by removed caches are deleted (`src/host_push_cache.rs:202-298`).
    - **Errors:**
      - "Could not prepare the private publishing cache." (`src/host_push_cache.rs:18`);
      - "The publishing cache contains a symbolic link. Remove this cache before retrying." (`src/host_push_cache.rs:181-200`).
- Sources: `docs/SiloUI-GITHUB-IMPLEMENTATION.md` 448-528.

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).

### push.status
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19).
- Kind: query
- Status: EXISTS (renamed) (tauri `repository_push_status`, `src/host_push_operations.rs:435-456`; bridge `repository.push.status`, `src/remote.rs:259`, `src/remote_access.rs:129-134`)
- Params: `computerId`, `deviceId?`, `repositoryPath`, `operationId`. Result: `PushOperation | null` (`src/host_push_operations.rs:257-276`). It is the domain read for a `push:` job whose `operations.job.finished` a client missed (05 §4.2 E item 5).
- Errors: "Push operation identifier belongs to another repository." (`src/host_push_operations.rs:272-274`).

- macOS scope: the persisted push journal read is platform-independent (`src/host_push_operations.rs:257-276`); macOS publication is the NEW part of `push.start`.

### push.dismiss
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19).
- Kind: command
- Status: EXTENDED. NEW macOS queue admission for this mutating operation (95 A-31; 95 §3 Queue). Existing behavior: (tauri `host_push::dismiss_repository_push`, `src/host_push.rs:69-91`; bridge `repository.dismiss`, `src/remote.rs:262`, `src/remote_access.rs:135-143`)
- Params: `computerId`, `deviceId?`, `repositoryPath`. Result: none.
- Semantics:
  - It marks every non-`pushing` job of that repository as dismissed (`src/host_push_operations.rs:343-357`). It can't cancel an active push (`docs/SiloUI-TERMINAL-HANDOFF.md` 34-37).
  - It is also the UI's "I've checked GitHub" acknowledgement of an `unknown` result before a separate retry (doc 497-499; `ui/features/application/components/repository-push-feedback.tsx:82`).

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).


### push.changed (event)
- Kind: subscription
- Status: EXTENDED (NEW state payload and sequence number required by 95 A-4; 95 §2). Existing event source: EXISTS as `silo://application-state-changed` (`src/host_push.rs:92, 1219, 1241`; `src/host_push_operations.rs:224`). Push operations also travel inside the app state as `repositoryPushOperations` (`src/runtime.rs:2832-2834`). The name is 05's event catalogue (05 §4.2 D).
- Payload (NEW, justified by 95 A-4): new state (push.status and push.repositories results) plus sequence number. Bounded subscriber buffering; after a gap or reconnect re-read the domain query (95 §2; 05 event catalogue).

---

## secrets.*

### What exists

- **Storage.** Values live in the Mac host Keychain; the historical Linux-host Secret Service route is retired (95 §3). `secrets.json` holds only names, value references, assignments, allowed hosts, pending state, errors and activity. Values are never returned (`docs/SiloUI-SECRETS.md` 3-13; types `src/secrets.rs:60-95`).
- **Placeholders and the passthrough proxy.**
  - MicroSandbox gets host env-source references. The guest sees the placeholder `$MSB_<NAME>` in the named variable (`docs/SiloUI-SECRETS.md` 41-47; opaque source names `src/secrets_runtime.rs:59-66`).
  - TLS interception applies only to destinations that match an assigned secret's allowed hosts (doc 49-62).
  - The computer needs `network.tls.enabled`, otherwise "This computer does not have secure HTTPS secret handling enabled. Recreate it before assigning secrets." (`src/secrets_runtime.rs:263-271`).
- **Allowed hosts.** Allowed are exact lowercase hosts, `*.domain`, or `*` (`src/secrets.rs:456-472`). The engine accepts `*` without any acknowledgement. The "Confirm access to any HTTPS destination." check exists only in the UI (`ui/features/application/model/secret-configuration.ts:53`; checkbox `ui/features/application/components/secret-editor.tsx:122`). See Q8.
- **Live updates, and when a restart is needed.**
  - Changed values and domains apply live. A new variable on a running computer waits for the next boot (`docs/SiloUI-SECRETS.md` 41-47; plan `src/secrets_runtime.rs:106-…`, apply `src/secrets_runtime.rs:242-282`).
  - Such a secret shows `state:"restart-required"` with `pendingComputers` (`src/secrets.rs:243-255`). Silo never restarts a computer on its own (doc 43-44).
- **Pending revocations.**
  - Remove first journals `{secretId, generation, name, computer}` for every computer that may hold it, then deletes the value and drops the secret from the list (`src/secrets.rs:78-85, 647-688`).
  - A background pass on each state read clears a record on a confirmed absence, a stop, a deletion or a verified restart (`src/secrets.rs:735-780`; `src/runtime.rs:13031-13108`; doc 15-39). The engine scheduling decision is in 05 §4.2, "Engine behaviour: maintenance that today runs on client reads".
  - The affected computer row carries `pendingSecretRevocations` (`src/runtime.rs:619`) with the warning "May still have access to GITHUB_TOKEN until it restarts" (doc 27-30).
- **Scope today: local computers only.** The check says "Secrets can only be assigned to local Silo computers." (`src/runtime.rs:13110-13132`). Connections keep secrets on "This device" (`docs/SiloUI-CONNECTIONS.md` 14). Revocations for remote rows run on the owner (`docs/SiloUI-SECRETS.md` 23-24).
- **Background (an engine duty). Startup recovery** (EXISTS, `src/secrets.rs:903-933`, started at `src/main.rs:305`), on its own thread, under the secrets operation lock (`OPERATION`, `src/secrets.rs:19`):
  1. **Legacy removals first.** Silo attempts to delete the credential-store value of every secret still marked `removing`, ignoring removal errors in this startup pass. This happens before any slow live update can wait on a computer (`src/secrets.rs:915-918`).
  2. **Unfinished assignments.** Every other secret with a non-empty `affected` list is reconciled again: live update, or `restart-required` (`src/secrets.rs:919-925`; `reconcile`, which waits on each computer's gate and releases the global lock while it waits, `src/secrets.rs:524-646`).
  3. **Pending revocations.** The lock is released, then the background revocation pass is scheduled (`schedule_revocations`, `src/secrets.rs:752-780`). Today its retry trigger is a state refresh (`src/secrets.rs:754-755`). NEW: an engine timer schedules revocation retries without a client read (justified by 95 A-26; 05 §4.2).
  4. **Notify.** A state change is emitted (`src/secrets.rs:929`), mapped to `secrets.changed` by 05's [event catalogue](05-engine-architecture.md#event-catalogue).

### Secret (the public row)
`{id, name, computers: string[], allowedDomains: string[], state: "active"|"applying"|"restart-required", pendingComputers: string[], removing: bool, error: string|null}` (`src/secrets.rs:243-255`; `ui/desktop/production-source.ts:72-76`). NEW API `computerIds: string[]` and `pendingComputerIds: string[]` replace `computers` and `pendingComputers`, justified by 95 A-11; these identify the same assigned/pending owner inventory rows across rename and macOS parity. Other public fields and write-only value custody remain as sourced above.

### secrets.list
- Kind: query
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19). Host-level methods apply to either kind.
- Status: EXTENDED. NEW remote owner secret-policy access (95 A-14/A-16). Existing behavior: (tauri `read_secrets_state`, `src/secrets.rs:789-795`). Also `secrets` in the app state (`src/runtime.rs:561`).
- Params: none. NEW for remote: `deviceId?`, required by brief:19 ("access to GitHub and secrets") and brief:25 (always-on host managed from other Macs).
- Result: `Secret[]`.
- Semantics: document I/O runs off the async pool (doc 69-74).

- Host scope: account custody and authorization run on the owner Mac; guest proxy policy is specified by `github.configuration.*` and `secrets.save`.
- Remote contract: NEW (justified by 95 A-3/A-14/A-16). `deviceId?: string` routes through the local engine to the owner; absent means local owner. Write-only credential values use that SSH connection and remain stored on the selected owner (95 §1–2; existing custody: `docs/SiloUI-SECRETS.md:3-7`).

### secrets.save
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19).
- Kind: command (it can wait minutes on each computer's gate; `src/secrets.rs:535-539`, `src/runtime.rs:12964-12967`)
- Status: EXTENDED. NEW macOS host-proxy policy application, explicit wildcard acknowledgement and remote owner control (95 A-15/A-16/A-19; B-27). Existing behavior: (tauri `save_secret`, `src/secrets.rs:796-856`)
- Params: `request: {operation: "add"|"edit", id?: string, name: string, value?: string, computers: string[], allowedDomains: string[]}` (`src/secrets.rs:96-105`). `value` is write-only and required on `add`. NEW `computerIds: string[]` replaces the name-keyed `computers` list, justified by 95 A-11; there is no runtime name-key fallback. Any conversion is launch-only through 20 `migration.*` (95 §3; current assignments: `src/runtime.rs:13117-13125`). NEW `allowAnyDestination?: bool` is required to be `true` when `allowedDomains` contains `*` (justified by 95 A-16, Secrets wildcard; existing wildcard acceptance: `src/secrets.rs:457`). The engine rejects an unacknowledged wildcard before storing/reconciling anything. NEW `deviceId?: string` selects the owner through the local engine, with secret values sent only through the user's own SSH connection and stored on that owner (95 A-3/A-14/A-16; current custody: `docs/SiloUI-SECRETS.md:3-7`).
- Result: `Secret[]`.
- Errors (`src/secrets.rs:473-521`):
  - "Choose a valid, unreserved secret name." (names match `[A-Za-z_][A-Za-z0-9_]*`, are at most 128 bytes and aren't reserved, `src/secrets.rs:437-455`).
  - "Secret names cannot change. …", "A secret with this name already exists.", "Enter a secret value.", "Secret values must contain between 1 and 65536 bytes without null characters.", "Select computers and valid allowed domains." (1-100 computers, 1-100 domains).
  - "Cannot access secrets in the system credential store. Unlock it and retry." (`src/secrets.rs:58-59`).
- Semantics:
  - The value is stored before its reference is published (doc 12-13).
  - It reconciles each affected computer under that computer's gate, releasing the global lock while it waits (`src/secrets.rs:540-646`).
  - A save that loses a race records "Secret settings changed during this update. Retry to verify the latest settings." (`src/secrets.rs:595-605`).

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).
- Remote contract: NEW (justified by 95 A-3/A-14/A-16). `deviceId?: string` routes through the local engine to the owner; absent means local owner. Write-only credential values use that SSH connection and remain stored on the selected owner (95 §1–2; existing custody: `docs/SiloUI-SECRETS.md:3-7`).

### secrets.remove
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19).
- Kind: command
- Status: EXTENDED. NEW macOS host-proxy revocation and remote owner control (95 A-15/A-16/A-19; B-27). Existing behavior: (tauri `remove_secret`, `src/secrets.rs:857-875`)
- Params: `id`. Result: `Secret[]`.
- Semantics: returns without waiting for any computer. Revocation continues in the background (doc 15-21). A store failure leaves a retryable tombstone that is left out of boot material (`src/secrets.rs:647-688`).

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).
- Remote contract: NEW (justified by 95 A-3/A-14/A-16). `deviceId?: string` routes through the local engine to the owner; absent means local owner. Write-only credential values use that SSH connection and remain stored on the selected owner (95 §1–2; existing custody: `docs/SiloUI-SECRETS.md:3-7`).

### secrets.retry
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19).
- Kind: command
- Status: EXTENDED. NEW macOS host-proxy reconciliation and remote owner control (95 A-15/A-16/A-19; B-27). Existing behavior: (tauri `retry_secret`, `src/secrets.rs:876-902`)
- Params: `id`. Result: `Secret[]`.
- Semantics: for a `removing` secret, it retries the store deletion. Otherwise it reconciles again (`src/secrets.rs:887-896`).

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).
- Remote contract: NEW (justified by 95 A-3/A-14/A-16). `deviceId?: string` routes through the local engine to the owner; absent means local owner. Write-only credential values use that SSH connection and remain stored on the selected owner (95 §1–2; existing custody: `docs/SiloUI-SECRETS.md:3-7`).

### secrets.changed (event)
- Kind: subscription
- Status: EXTENDED (NEW state payload and sequence number required by 95 A-4; 95 §2). Existing event source: EXISTS as `silo://application-state-changed` (`src/secrets.rs:531, 777, 849, 869, 929`). The name is 05's event catalogue (05 §4.2 D).
- Payload (NEW, justified by 95 A-4): new state (Secret[]) plus sequence number. Bounded subscriber buffering; after a gap or reconnect re-read the domain query (95 §2; 05 event catalogue).

---

## network.*

### What exists

- **Discovered listeners.** Silo reads the guest's `/proc/net/tcp` and `/proc/net/tcp6` through `msb exec --no-start` (`src/network.rs:238-259`). It keeps `LISTEN` (`0A`) rows and marks IPv6-only or guest-loopback sockets as not reachable through the IPv4 publisher (`src/network.rs:194-237`). Discovered rows have `configured:false, state:"unpublished"` (`src/network.rs:479, 549`).
- **Publishing.**
  - The patched PortPublisher control socket offers `ports_list`, `port_add`, `port_remove` and `port_probe`. It binds `127.0.0.1` only, and "reachable" needs a direct guest TCP handshake (`docs/SiloUI-NETWORK-PLAN.md` 14-19, 98-103; `src/network.rs:657-725`).
  - Desired mappings are kept in `network.json`. They are reapplied after each start (`src/network.rs:973-984`) and repaired in the background on reads (`src/network.rs:729-770`).
  - At most 128 published ports per computer and 4096 saved mappings (`src/network.rs:43, 877-892`).
- **`.localhost` hostnames.** `computer_host(name, id)` gives `<sanitised-name>-<first 8 hex of id>.localhost` (`src/network.rs:82-114`). Website URLs are `<scheme>://<host>:<hostPort>` (`src/network.rs:116-119`). Rationale and the browser check: `docs/SiloUI-MANAGED-SSH.md` "Published websites" 77-111; Safari before macOS 26 can't resolve these names (`docs/SiloUI-NETWORK-PLAN.md` 49-61).
- **Computers on another device.**
  - The controller owns loopback `ssh -L` tunnels through the owner's `guest.ssh` stream with `purpose:"port"`. Tunnel intents are reopened on the same local port (`src/remote_network.rs:1-8, 437-527`; `src/remote.rs:753-807`).
  - The `-L` destination is the guest's interface address on the guest port (`docs/SiloUI-CONNECTIONS.md` 85-92).
  - Unpublishing on the owner ends matching streams immediately (`src/remote.rs:2792-2803`, called at `src/network.rs:937-938`).
  - At most 128 tunnels (`src/remote_network.rs:146`).

### NetworkState
`{computers: [{computer, computerId? (bridge only, src/remote_network.rs:200-219), host?: "<label>.localhost", error: string|null, ports: [{port, hostPort: u16|null, configuredHostPort: u16|null, scheme: "http"|"https"|null, state: "reachable"|"waiting"|"unpublished"|"unknown", configured: bool, message: string|null}]}]}` (`src/network.rs:59-80, 120-123`; `ui/desktop/production-source.ts:255-261`). For a remote device, `computer` is projected to `silo-remote:<device>:<id>` and `hostPort` to the local tunnel port (`src/remote_network.rs:311-…`).

### network.state
- Kind: query
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19). Host-level methods apply to either kind.
- Status: EXTENDED. NEW autonomous port-repair timer and macOS port discovery adapter (95 A-26/A-19). Existing behavior: (tauri `read_network_state`, `src/network.rs:826-840`; tauri `remote_network_state(deviceId)`, `src/remote_network.rs:650-655`; bridge `network.state`, `src/remote.rs:256`, `src/remote_access.rs:88`, owner side `src/remote_network.rs:152-198`)
- Params: `deviceId?: string`. Result: `NetworkState`.
- Semantics:
  - The read itself only observes: no gate, no publishing. It also schedules forward repair in the background, under a hidden computer gate, skipping busy computers (`src/network.rs:729-770`, `src/network.rs:828-836`). Computers are read three at a time (`src/network.rs:782-802`). NEW: repair also runs on the engine's own timer, independent of client reads (justified by 95 A-26; 05 §4.2).
  - The owner caches its answer for 2 s for polling controllers (`src/remote_network.rs:149-181`).
  - A remote read also reopens dead tunnels in the background (`src/remote_network.rs:221-251, 529-543`).

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).

### network.publish
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19).
- Kind: command
- Status: EXTENDED. NEW macOS published-port transport and queue admission (95 A-19/A-31; 95 §3 Queue; Q11). Existing behavior: (tauri `save_network_port`, `src/network.rs:841-899`; `remote_save_network_port`, `src/remote_network.rs:656-695`; bridge `network.publish`, `src/remote.rs:257`, `src/remote_access.rs:89-107`)
- Params: `computerId`, `deviceId?`, `port: u16 (guest, ≠0)`, `hostPort?: u16 (≠0; local only, or the controller's local tunnel port for remote)`, `scheme?: "http"|"https"` (absent means TCP) (`src/network.rs:131-139`).
- Result: `NetworkState`.
- Errors: "Enter a port from 1 to 65535 and a supported protocol.", "This computer already has 128 published ports.", "Too many saved ports. Remove an unused port first." (`src/network.rs:131-139, 877-892`). Remote: "The remote computer port is not available yet. …" (`src/remote_network.rs:686`), "This local port is already in use." (`src/remote_network.rs:443-444`).
- Semantics:
  - Under the computer gate (`PortPublish`, `src/network.rs:856-863`). An explicit port conflict keeps the previous mapping (`docs/SiloUI-NETWORK-PLAN.md` 15-17).
  - The bridge publishes on the owner with an automatic host port, and the controller then opens its own tunnel (`src/remote_access.rs:99-105`; `src/remote_network.rs:672-690`).
  - A computer created before the runtime extension needs one restart (`docs/SiloUI-NETWORK-PLAN.md` 24-25).

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).

### network.unpublish
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19).
- Kind: command
- Status: EXTENDED. NEW macOS published-port transport cleanup and queue admission (95 A-19/A-31; 95 §3 Queue; Q11). Existing behavior: (tauri `remove_network_port`, `src/network.rs:900-943`; `remote_remove_network_port`, `src/remote_network.rs:708-728`; bridge `network.unpublish`, `src/remote.rs:258`, `src/remote_access.rs:108-123`)
- Params: `computerId`, `deviceId?`, `port`. Result: `NetworkState`.
- Semantics: the removal intent is persisted before the live listener is touched (`src/network.rs:926-936`). It revokes other devices' streams for that port (`src/network.rs:937-938`). Removing on one controller removes it for every controller (`src/remote_access.rs:109-110`).

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).

### network.open
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19).
- Kind: command
- Status: EXTENDED. NEW browser URL result for client launching and macOS port adapter (95 A-22/A-19). Existing behavior: (tauri `open_network_port`, `src/network.rs:944-971`; `remote_open_network_port`, `src/remote_network.rs:729-762`). It rechecks that the port is `reachable` and is a website, returns the browser URL to the client instead of opening a browser (NEW, justified by 95 A-22).
- Params: `computerId`, `deviceId?`, `port`. Client launching only; no `launch` flag (95 A-22).
- Result: today none. NEW: `{url}`. Required because browser launching belongs to the Mac client (95 A-22; 95 §3).
- Errors: "This service is not reachable.", "This TCP service is not configured as a website." / "This port is not a website.", "This service is not connected." (`src/network.rs:957-963`; `src/remote_network.rs:748-756`).

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).

### network.changed (event)
- Kind: subscription
- Status: EXTENDED (NEW state payload and sequence number required by 95 A-4; 95 §2). Existing event source: EXISTS (`silo://network-state-changed`, emitted at `src/network.rs:822`, `src/remote_network.rs:541`, and after SSH access saves at `src/ssh_access.rs:667, 963`; listened to at `ui/desktop/production-source.ts:1082`). The name is 05's event catalogue (05 §4.2 D).
- Payload (NEW, justified by 95 A-4): new state (network.state and sshAccess.state results) plus sequence number. Bounded subscriber buffering; after a gap or reconnect re-read the domain query (95 §2; 05 event catalogue).

---

## sshAccess.*

Managed SSH: a listener on a host port per computer, for any SSH client.

### What exists

- Each enabled computer gets `msb ssh serve NAME --no-start --no-inactivity-timeout --exit-on-stdin-close --authorized-keys <isolated store> --expected-machine-id <id> --host <IPv4> --port <port>`, on loopback plus an optional selected LAN interface (`docs/SiloUI-MANAGED-SSH.md` "Ownership and persistence" 151-166; `src/ssh_access.rs:221-295`).
- **Loopback versus LAN.**
  - `bindAddress` is `127.0.0.1` or one specific IPv4 address of an interface that is up; wildcards are refused (`src/ssh_access.rs:117-148, 876-879`). Addresses come from `getifaddrs` (`src/ssh_access.rs:172-206`).
  - "Ordinary service port forwarding remains loopback only", and Silo doesn't touch the firewall (doc 37-41).
  - The UI confirmation before allowing other devices (doc 29-31) is UI-only.
- **Managed keys.** `ssh/managed-clients/<computerId>` holds the generated key, which is replaced after a disable (`src/ssh_access.rs:687-694, 911-926`). Every authorized key of the listener (the managed key, controller keys and keys the user added) is written to `ssh/managed-access/<id>.authorized_keys` (`src/ssh_access.rs:222-230`). Turning access off revokes managed and controller keys and keeps keys the user added (`src/ssh_access.rs:851-864`; doc 46-52, 137-147).
- **`authorize_controller`.** A controller sends its own Ed25519 public key plus its `controllerId`. The owner adds `<key> silo-controller:<controllerId>`, replacing that controller's earlier key, and returns `{port, address, user}`. Private keys never cross devices (`src/ssh_access.rs:749-796`; doc 192-212).
- **Reconcile.** After lifecycle changes, and every 15 s while any access is enabled (`src/ssh_access.rs:550-568`; doc 174-190). Started at `src/main.rs:342` and closed on quit at `src/main.rs:365`.

### SshAccessState
`{computers: [{computer, computerId, enabled, port, bindAddress, keys: string[], state: "disabled"|"waiting"|"listening"|"error", message: string|null, fingerprint: string|null ("SHA256:…"), deviceName, addresses: string[], user: "silo"}]}` (`src/ssh_access.rs:31-51, 570-625`). For a remote device, `computer` is projected to `silo-remote:<device>:<id>` (`src/remote_ssh_access.rs:8-25`).

### sshAccess.state
- Kind: query
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19). Host-level methods apply to either kind.
- Status: EXTENDED. NEW macOS managed guest-access state adapter (95 A-19; Q13 / 80 C-7). Existing behavior: (tauri `read_ssh_access_state`, `src/ssh_access.rs:626-639`; `remote_ssh_access_state(deviceId)`, `src/remote_ssh_access.rs:39-49`; bridge `ssh.access.state`, `src/remote.rs:250`, owner `src/ssh_access.rs:939-954`)
- Params: `deviceId?`. Result: `SshAccessState`.
- Semantics: observation only. Any repair is scheduled in the background (`src/ssh_access.rs:628-635`).

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).

### sshAccess.save
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19).
- Kind: command
- Status: EXTENDED. NEW macOS key/listener configuration and queue admission (95 A-19/A-31; 95 §3 Queue; Q13 / 80 C-7). Existing behavior: (tauri `save_ssh_access`, `src/ssh_access.rs:640-672`; `remote_save_ssh_access`, `src/remote_ssh_access.rs:50-77`; bridge `ssh.access.save` with `{computerId, settings}`, `src/remote.rs:252`, `src/ssh_access.rs:931-936, 983-989`)
- Params: `computerId`, `deviceId?`, `enabled: bool`, `port: u16`, `bindAddress: string`, `keys?: string[]` (`Settings`, `src/ssh_access.rs:674-682`). If `keys` is absent, the owner's latest list is kept. An explicit list replaces it (doc 137-142).
- Result: `SshAccessState`.
- Errors (`src/ssh_access.rs:117-160, 810-929`): "Enter a port from 1 to 65535.", "Choose 127.0.0.1 or a specific network interface address. Wildcard bindings are not allowed.", "Choose an active network interface address.", "Use at most 128 authorized keys.", "Paste one Ed25519 public key per entry.", "This public key is already authorized.", "Another computer already uses this SSH port. Choose a different port.", "No SSH port is available.", "Could not identify the previous SSH connection key. …", "This computer no longer exists on its device. Refresh SSH access.".
- Semantics:
  - Device-scope gate (`src/ssh_access.rs:652-654`). The first enable on port 2222 picks the next free port (`src/ssh_access.rs:887-892`).
  - Changes close live sessions before they commit (`src/ssh_access.rs:907-909`).
  - Enabled doesn't mean listening: a stopped computer waits for its next start (doc 43-45).
  - Emits `network.changed` (today `silo://network-state-changed`, `src/ssh_access.rs:667, 962-964`).

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).

### sshAccess.connection
- Kind: command
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19). Host-level methods apply to either kind.
- Status: EXTENDED. NEW macOS managed-access key authorization/connection adapter (95 A-19; Q13 / 80 C-7). Existing behavior: (tauri `ssh_connection`, `src/ssh_connection.rs:119-182`; for a remote computer it calls bridge `ssh.access.connection`, `src/remote.rs:251`, served by `authorize_controller`, `src/ssh_access.rs:972-977`)
- Params:
  - `computerId`, `deviceId?` (today: the local name, or `deviceId` + `computerId`).
  - `network?: bool`. `true` requires a LAN address; `false` forces `127.0.0.1` (`src/ssh_connection.rs:37-54`).
  - `download: bool`.
- Result:
  - `download:false` returns `"ssh -i '<key path>' -o IdentitiesOnly=yes -p <port> <user>@<address>"` (`src/ssh_connection.rs:20-35`).
  - `download:true` opens a native save dialog and writes the key with mode 0600 (`src/ssh_connection.rs:173-179`). The dialog is UI-only. NEW for the API: `destination?: path` replaces the dialog, required because the Mac client owns native dialogs (95 A-22; 95 §3).
- Errors: "Enable SSH access first.", "Enable SSH from other devices first.", "Enable access from other devices to connect to this remote computer.", "Update Silo on both devices to connect over SSH." (`src/ssh_access.rs:730, 762`; `src/ssh_connection.rs:43-52, 146-148`).
- Semantics:
  - A local call reads the owner's managed private key, on this device only (`src/ssh_access.rs:719-747`).
  - A remote call creates this device's own key under `ssh/remote-clients/<device>-<computer>` and sends only the public key (`src/ssh_connection.rs:56-83, 135-149`).
  - Keys for a device are deleted when that device is removed (`src/ssh_connection.rs:94-117`, called at `src/remote.rs:453`).

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).

---

## guest.*

`guest.*` here covers the access plumbing: the owner-side key authorization and the raw SSH stream, the per-computer SSH aliases, and the transport entry points those aliases call. Guest command execution and programmatic file access (`guest.exec*`, `guest.files.*`) are 70 §2.1.

### guest.prepare
- Kind: command (bridge, owner side)
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19). Host-level methods apply to either kind.
- Status: EXTENDED. NEW macOS guest-key authorization adapter and queue admission (95 A-19/A-31; 95 §3 Queue). Existing behavior: (bridge `guest.prepare`, `src/remote.rs:254`, `src/remote_access.rs:68-87`; controller `remote_access::prepare`, `src/remote_access.rs:265-291`)
- Params: `computerId`, `publicKey` (Ed25519 only, `src/editor.rs:654-671`), `path` (`/workspace[/…]`, `src/editor.rs:154-166`), `accountProtocol: 1`, `forwarding?: bool`.
- Result: `{hostPublicKey, user, guestAddress: ip|null}`. `guestAddress` is set when `forwarding` is true. It is read in the guest with a UDP-connect probe (`src/remote_access.rs:238-263`).
- Errors: "Start <name> first." (`src/terminal.rs:72-74`), "This folder is unavailable inside the computer.", "Expected an Ed25519 public key." / "Invalid Ed25519 public key." (`src/editor.rs:654-707`).
- Semantics:
  - It waits on the computer's gate (`src/remote_access.rs:184-195`).
  - It appends the key to the runtime's `ssh/authorized_keys`, which the editor transport shares, and creates the computer's host key if it is missing (`src/editor.rs:673-729`).
  - Called by every controller transport: editor, terminal, files, published-port tunnels and desktop (`src/editor.rs:755-797`; callers `src/editor.rs:1228`, `src/terminal.rs:79`, `src/editor.rs:546` for `src/transfer.rs:1331`, `src/remote_network.rs:518`, `src/desktop_viewer.rs:274`).

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).

### guest.ssh
- Kind: stream (raw SSH bytes to the guest's `msb ssh serve --stdio`)
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19). Host-level methods apply to either kind.
- Status: EXTENDED. NEW macOS guest SSH stream adapter (95 A-19). Existing behavior: (bridge `guest.ssh`, `Access::Stream`, `src/remote.rs:255`; served before request dispatch at `src/remote.rs:2106-2120`; spawn `src/remote_access.rs:197-226`)
- Params: `computerId`, `purpose?: "port"`, `port?: u16`. No purpose means an interactive stream (editor, terminal, files, desktop). `purpose:"port"` requires `port` in 1..=65535 (`src/remote.rs:2725-2747`).
- Semantics:
  - It never starts a computer (`--no-start`, `src/remote_access.rs:213-220`).
  - Streams live outside the operation queue (`src/remote_access.rs:201-203`). They count against a 192-stream budget (`src/remote.rs:3377-3391`).
  - Port streams are registered so an unpublish revokes them (`src/remote.rs:2749-2803`).
- Local equivalent: the ProxyCommand `msb ssh serve <name> --stdio --no-start --no-inactivity-timeout` with `MSB_HOME`/`MSB_PATH`/`MSB_LIBKRUNFW_PATH` (`src/editor.rs:807-839`).

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).

### Transport entry points (the ProxyCommand targets)
- Status: EXISTS for the retained Mac-host transport; historical CLI mode sources are `src/main.rs:97-104`:
  - `--remote-guest <deviceId> <computerId> [port]` opens `guest.ssh` on the owner and copies stdio (`src/remote.rs:1802-1860`).
  - Retired source evidence: `--msb-ssh-serve <runtime home> <name>` is the AppImage transport helper (`src/editor.rs:862-902`; `docs/SiloUI-EDITOR-HANDOFF.md:41`). It is removed from the engine, not retained for Mac-host Linux guests (95 §3). Their local transport is the direct `msb ssh serve` path already cited under `guest.ssh`.
- The retained Mac-host remote transport must stay callable by a plain `ssh` ProxyCommand that any client (VS Code, Zed, `sftp`, the Claude desktop app) runs. Which executable and path they live on after the split is Q3.

### guest.sshAlias.ensure
The editor's SSH config generation, exposed on its own. This is the single method for 50 and 70 (80 §2 N10); 70 §1.3 gives Fjord's use of it.
- Kind: command
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19). Host-level methods apply to either kind.
- Status: EXTENDED. NEW installInclude:false option/result, ID-keyed generated records and macOS guest adapter (95 A-11/A-13/A-19 as amended by 95 §3). Existing behavior: Tauri `computer_action` action=`open-editor` (`src/runtime.rs:3263-3270`) calls the alias generation inside `open-editor` (`src/editor.rs:409-421, 1222-1234`). Exposing the existing alias generation separately is extraction; the additions are named in Status. Required by the Router's "Runs on": "Claude desktop app sessions running inside a computer over SSH. Fjord writes the SSH connection" (brief:21). The Claude desktop app's `sshConfigs[].sshHost` accepts "a host alias from ~/.ssh/config" (`/Applications/Claude.app/Contents/Resources/app.asar`, Claude 2.31226.1: the settings schema at byte offset 1001149, inside `.vite/build/file-index-worker/fileIndexWorker.js`; its fields are `id`, `name`, `sshHost`, `sshPort?`, `sshIdentityFile?`, `startDirectory?`). The desktop app's own reader keeps only `id`, `name`, `sshHost`, `sshPort` and `sshIdentityFile`, from the managed and user settings tiers (`.vite/build/index.chunk-NSocLvQH.js`, byte offsets 19177682 and 19178306).
- Params: `computerId`, `deviceId?`, `installInclude?: bool` (NEW option, default `true`; today both local and remote editor preparation always install the Include, `src/editor.rs:409-420`, `src/editor.rs:1222-1233`).
  - `path?: string` — the Linux guest folder the client will open. Default `/workspace`, for both local and remote editor handoffs (`src/editor.rs:32-47`).
  - The Linux path must be `/workspace` or `/workspace/<segments>`, at most 4,096 bytes, with no ASCII control characters and no empty, `.` or `..` segment (`src/editor.rs:154-166`). macOS Files/working-folder parity is decided (95 A-19), but folder roots are unsourced and remain Q14; these Linux rules do not establish a macOS `/workspace`.
- Result (NEW type `GuestSshAlias`):
  - `alias`: what an SSH client names; for Fjord's SSH deep links it must contain only letters, digits, `.`, `_`, `:` and `-` (70 §1.1, "Open an SSH session from a link"). Today's name-based format is below (`src/editor.rs:581-586`).
  - `user`: the guest login.
  - `home`: the guest account's home, to build guest paths (70 §1.3).
  - `configPath`: the file holding the `Host` entry.
  - `includeLine`: the `Include` that makes it visible to `~/.ssh/config`.
  - `includeInstalled: bool`. With `installInclude:true`, success means `true`; an unsafe or unwritable Include target fails the method, as both editor preparation paths propagate `install_include` errors today (`src/editor.rs:409-420`, `src/editor.rs:1222-1233`, `src/editor.rs:460-505`). **NEW option semantics:** with `installInclude:false`, skip installation and report whether the line already exists; `false` then means the client or user must add `includeLine` to use the alias without `-F`. This option serves clients that use `configPath` directly (80 §2 N10; `src/terminal.rs:76-93`). It never converts an attempted installation failure into a successful result. (50's earlier `manualIncludeRequired` is `!includeInstalled`, so it is dropped, 80 §2 N10.)
  - Each field is justified by what an external client needs: the Claude app takes a host alias; a client that passes `-F` (as the remote terminal does, `src/terminal.rs:76-93`) needs `configPath`.
- Errors (wire codes per 80 §2 N17):
  - "OpenSSH is required to … Install your system's OpenSSH client and retry." (`src/editor.rs:136-152`): 70's `open_ssh_missing`.
  - The manual-Include message, containing the exact Include line to add (`src/editor.rs:443-448`, `src/editor.rs:496-504`): 70's `include_not_writable`. This is a failure when `installInclude:true`, not an `includeInstalled:false` result.
  - "Choose a folder inside /workspace with no control characters." (`src/editor.rs:154-166`).
  - "This folder is unavailable inside the computer.": `test -d <path>` failed as `silo`; its guest timeout is 5 s and the host call limit is 8 s (`src/editor.rs:61-85`). For remote Linux computers the owner checks the same path in `guest.prepare` (`src/remote_access.rs:68-87`, `src/editor.rs:673-707`).
  - "Could not connect to this computer over SSH. Retry after checking that it is running.": the local probe `ssh -F <config> -o BatchMode=yes -o ConnectTimeout=5 <alias> true` failed within its 10 s host limit (`src/editor.rs:88-99`).
  - "Start <name> first.": 70's `not_running`.
  - These codes are NEW, justified by 95 A-10: add stable snake_case refusals and guest/file codes to `ErrorCode` and its fixtures. Today they become `internal` (`src/bridge_error.rs:104-108`); 70 defines the new code mapping.
- **Path and handoff checks.** The extracted alias-writing helpers do not perform all `open-editor` checks (`src/editor.rs:409-420`, `src/editor.rs:1222-1233`). The extracted API method preserves the Linux editor handoff's path validation and guest-directory check even when `path` is omitted, using `/workspace` as today (`src/editor.rs:32-85`). It preserves today's local BatchMode probe (`src/editor.rs:88-99`); remote preparation uses the owner check through `guest.prepare` (`src/remote_access.rs:68-87`).
- **Repeat calls and transport.** Re-running rewrites the same generated file (`src/editor.rs:586-595`, `:755-797`). It never starts a stopped computer (`--no-start`, `src/editor.rs:836`) and retains `ForwardAgent no` and `ForwardX11 no` (`src/editor.rs:593`). These are the semantics used by Fjord's alias flow (70 §1.3).
- Alias key: today's alias is name-based (`silo-<hash>-<name>`, below). NEW: key SSH aliases, generated config files and known-host references by `computerId` (justified by 95 A-11/A-13 as amended by 95 §3). There are no old-name SSH aliases or runtime conversion/fallback paths; any necessary conversion runs at launch through 20 `migration.*`. The exact alias spelling and stable installed helper path remain packaging/probe work (Q3; B-22).
- **Historical implementation evidence, not the NEW entry format (95 §3):**
  - **Local Linux computer.**
    - File: `<runtime home>/ssh/<name>.conf`. The runtime home is the alias `~/.silo[-dev]/<12 hex of sha256(<storage>/microsandbox)>` (`src/runtime.rs:805-806, 852-857`; `src/channel.rs:75-81`).
    - Alias: `silo-<runtime-home basename>-<name>` (`src/editor.rs:581-586`). The source also preserves older names (`src/editor.rs:598-621`); the new engine does not retain that branch (95 §3).
    - Entry (`src/editor.rs:593`):
      ```
      Host silo-<hash>-<name>
        HostName silo-<hash>-<name>
        User <guest user>
        IdentityFile "<runtime home>/ssh/silo_ed25519"
        IdentitiesOnly yes
        IdentityAgent none
        ForwardAgent no
        ForwardX11 no
        UserKnownHostsFile "<runtime home>/ssh/<name>.known_hosts"
        StrictHostKeyChecking yes
        BatchMode yes
        ProxyCommand '/usr/bin/env' 'MSB_HOME=…' 'MSB_PATH=…' 'MSB_LIBKRUNFW_PATH=…' '<msb>' 'ssh' 'serve' '<name>' '--stdio' '--no-start' '--no-inactivity-timeout'

      Host *
      ```
    - The trailing `Host *` closes the block so the included file can't capture later configuration.
  - **Keys and known_hosts.**
    - The client key is `<runtime home>/ssh/silo_ed25519`. It is created with `ssh-keygen -t ed25519 -N ""` and the channel product name as comment, and repaired to mode 0600 (`src/editor.rs:337-360`; doc 21-27).
    - Its public key is appended once to `<runtime home>/ssh/authorized_keys` (`src/editor.rs:564-576`).
    - The host key is `<runtime home>/sandboxes/<name>/ssh/host_ed25519`, pinned as `<alias> <host public key>` in the per-computer `known_hosts` (`src/editor.rs:577-590`).
  - **Computer on another device.** The client key is `~/.silo[-dev]/desktop-remote/ssh/<deviceId>.key`. The alias is `silo-remote-<deviceId>-<computerId>` (`silo-dev-remote` for Dev, `src/channel.rs:110-112`). The config is `…/desktop-remote/ssh/<deviceId>-<computerId>.conf`, with the same directives, `User` from `guest.prepare`, and `ProxyCommand '<Silo executable>' '--remote-guest' '<deviceId>' '<computerId>'` (`src/editor.rs:755-797, 841-860`). Published-port tunnels use a separate `…-port-<port>.conf` (`src/editor.rs:787-793`).
  - **Include handling.**
    - `Include "<root with \ [ ] ? * escaped>/*.conf"` is prepended once to `~/.ssh/config` (`src/editor.rs:423-436, 460-505`).
    - Links (stow, chezmoi) are followed when they point to a folder or file this account owns, and the file is replaced atomically.
    - Otherwise the error names the exact line to add (`src/editor.rs:443-448`; doc 21). Only the startup repair records that line for `editor.includeNotice` (`src/editor.rs:1163-1168, 1080-1127`); `open-editor` just returns the error.
    - Private transports (`transfer`, `desktop`, push) never touch `~/.ssh/config` (`src/editor.rs:522-552`).
  - **Current-config repair (engine duty).** Generated entries are repointed at the current runtime and executable as needed; old-name alias preservation and runtime migration branches are excluded by 95 §3. Existing repair source: `src/editor.rs:1141-1220`, started at `src/main.rs:343`; `docs/SiloUI-EDITOR-HANDOFF.md` 119-127.

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).

### guest.sshAlias.remove
- Kind: command
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19). Host-level methods apply to either kind.
- Status: NEW (no generated-alias removal implementation in `src/editor.rs:409-505, 1141-1235`; those paths create/install/repair entries) (justified by 95 A-13/A-19 as amended by 95 §3). Required by the Router “Runs on” SSH connection (00-brief.md §What was decided; 70 §1.3): `guest.sshAlias.ensure` writes a generated entry into the user's SSH configuration (`src/editor.rs:409-421`); removing the computer's client connection needs to remove that entry too.
- Params: `computerId: string`, `deviceId?: string` (10 §0.2, flattened).
- Result: none.
- Semantics (NEW): idempotent. Removes the computer's generated `*.conf`. Removes the generated `Include` only when no entry is left. This is the one definition; 70 §1.3 records Fjord's use.

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).

### editor.includeNotice
- Platforms: Mac host; this reads the host SSH Include notice, independently of guest kind.
- Kind: query
- Status: EXISTS (renamed) (tauri `editor::read_editor_include_notice`, `src/editor.rs:1108-1127`)
- Params: none. Result: `string|null`, the `Include` line the user must add, rechecked against the file on every read (`src/editor.rs:1103-1106`).
- Kept as its own query for the Tauri editor flow, because it is the existing command (80 §2 N10). It reports the startup repair notice; an explicit `guest.sshAlias.ensure` installation failure remains a method error (`src/editor.rs:409-420`, `src/editor.rs:1222-1233`).


### editor.includeNotice.changed (event)
- Kind: subscription
- Status: EXTENDED (NEW state payload and sequence number required by 95 A-4; 95 §2). Existing event source: EXISTS (`silo://editor-include-changed`, `src/editor.rs:1084, 1097-1101`). The name is 05's event catalogue (05 §4.2 D).
- Payload (NEW, justified by 95 A-4): new state (editor.includeNotice result) plus sequence number. Bounded subscriber buffering; after a gap or reconnect re-read the domain query (95 §2; 05 event catalogue).

### terminal.command
- Kind: query
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19). Host-level methods apply to either kind.
- Status: EXTENDED. Existing Tauri `computer_action` action=`open-terminal` (`src/runtime.rs:3263-3270`) builds the command through `terminal::command` (`src/terminal.rs:19-48`, remote `:76-93`). NEW: return the launch command to the client rather than launching a terminal, plus macOS guest adaptation (95 A-22/A-19).
- Params: `computerId`, `deviceId?`.
- Result (NEW): `{argv: string[]}`.
  - Local: `/usr/bin/env MSB_HOME=… MSB_PATH=… MSB_LIBKRUNFW_PATH=… <msb> exec <name> --user silo --env USER=silo --env LOGNAME=silo --no-start --workdir /workspace --tty` (`src/terminal.rs:28-46`; `docs/SiloUI-TERMINAL-HANDOFF.md` 7-15).
  - Remote: `/usr/bin/ssh -F <config> -t <alias>` (`src/terminal.rs:81-91`).
- Errors: "Start <name> first.", "Choose a local Silo computer." (`src/terminal.rs:49-103`).

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).

### editor.command
- Kind: command (prepares the local SSH alias/workspace and returns a launch command).
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS platform extension is NEW, justified by 95 A-19.
- Status: EXTENDED. Existing Tauri `computer_action` action=`open-editor` (`src/runtime.rs:3263-3270`) constructs the launch through `editor::open` (`src/editor.rs:32-104`, `editor_launch` `:187-208`). NEW: return editor commands for client launching and add the macOS guest adapter (95 A-22/A-19).
- Params: `computerId: string`, `deviceId?: string`, `path?: string` — same validated guest path as `guest.sshAlias.ensure`; Linux default is `/workspace` (`src/editor.rs:32-47, 154-166`). The macOS path/default is unsourced, Q14 / 80 C-7.
- Result (NEW type, justified by 95 A-22): `{argv: string[]}` — executable plus arguments from existing command construction: Zed receives its SSH URI; VS Code receives `--profile <channel profile> <workspace file>` (`src/editor.rs:187-208`; command prefix type: `src/applications/launch.rs:13-19`). These are for execution on the calling Mac client's device (95 §3); Mac editor CLI discovery is `src/applications/macos.rs:17-40`, with no Linux-host launcher branch.
- Progress/events: no new job or event; alias Include preparation uses existing `editor.includeNotice` where relevant (`src/editor.rs:1080-1127`).
- Errors: the same OpenSSH, path and SSH-probe refusals as `guest.sshAlias.ensure`; unavailable/unsupported editor refusals come from `src/applications.rs:120-142` and `src/applications/launch.rs:21-22`. Stable code mapping is NEW (95 A-10; 70 errors).
- Semantics: execute on the controller's local engine even for a remote computer (95 A-3/A-22). It prepares/checks the guest alias and working folder, selects the editor from that local device's settings, and writes the VS Code workspace when required (`src/editor.rs:32-104, 211-260`). It returns argv and does not launch the editor; the client performs the launch (95 A-22). macOS guest-path integration still requires Q14 / 80 C-7.
- Sources: 95 A-22/A-19; existing preparation and command construction cited above.

### Launchers: UI-only, not in the API
The rule: everything that runs a desktop application, or shows a dialog, on the device where the user sits is UI-only. Keys, `authorized_keys`, `known_hosts`, the `.conf` entries, the `Include` and ProxyCommand repair are the engine's.
- **`computer_action` with `action: "open-editor" | "open-terminal"`** (`src/runtime.rs:3255-3276`) dispatches to `editor::open` (`src/editor.rs:32-104`) and `terminal::open` (`src/terminal.rs:75-103`).
  - The Mac client launches the editor with the engine-returned command, including the VS Code profile/workspace or Zed `ssh://` URI (`src/editor.rs:168-292`; 95 A-22). The controller's local engine prepares the SSH alias and VS Code workspace through `editor.command`; it launches no editor (95 A-22). Terminal and iTerm command files (`src/terminal.rs:105-146`; `src/applications/macos.rs:731-744`), Ghostty through `osascript` (`src/applications/macos.rs:721-730`) all run in the Mac client (95 A-22; 95 §3). The Linux-host terminal arguments (`src/terminal.rs:147-159`) are retired source evidence with no launcher branch (95 §3).
  - "editor and terminal applications always launch locally" (`src/remote_access.rs:1-2`). For remote computers too, "Terminals and editors launch on the controlling device" (`docs/SiloUI-CONNECTIONS.md` 12).
  - These are UI-only launchers built on `editor.command`, `guest.sshAlias.ensure` and `terminal.command` (95 A-22). The pre-launch checks they do (the folder exists in the guest, `src/editor.rs:61-85`; a BatchMode probe, `src/editor.rs:88-99`) belong in `guest.sshAlias.ensure` with an optional `path`, which `guest.prepare` already checks for remote computers.
- **`applications::list_applications`** (`src/applications.rs:186-218`) discovers the terminals, editors and browsers installed on the UI's device. It is UI-only for the same reason. The chosen paths are settings (`settings.*` section).
- **`applications::choose_application`** (`src/applications.rs:221-…`) is a native file dialog: UI-only.
- **`open_browser`** (`src/applications.rs:41`), used by GitHub and network, is UI-only. Those methods expose URLs instead (NEW, above).

### The Claude desktop app alias (NEW, Fjord)
- Requirement: brief:21 (Fjord writes the SSH connection for "Runs on") and brief:20 (one long-lived dev computer, usually macOS).
- What the engine gives: `guest.sshAlias.ensure`, and `guest.sshAlias.remove` when the computer goes (70 §1.3). Fjord then writes `{id, name, sshHost: <alias>}` into `sshConfigs` in `~/.claude/settings.json` (schema: `/Applications/Claude.app/Contents/Resources/app.asar` byte offset 1001149; the desktop app reads `sshConfigs` from the user tier, whose file is `settings.json` in `$CLAUDE_CONFIG_DIR` or `~/.claude`, `.vite/build/index.chunk-Cyt2WTko.js` functions `jj` and `Ij`, and `.vite/build/index.chunk-NSocLvQH.js` at byte offset 19177682). Writing the Claude settings file is Fjord's job, not the engine's.
- Nothing new is needed in the entry format: the alias already carries `User`, `IdentityFile`, the pinned `known_hosts` and the `ProxyCommand`. The first-party Linux session honored `Include` and `ProxyCommand`; `IdentityAgent none`, pinned host keys and forwarding restrictions worked. Desktop overrode alias `BatchMode yes` with `no`. Use `ssh_folder` in the deeplink for the folder; `sshConfigs.startDirectory` is not supported by this evidence ([linux.md §B-11](probes/linux.md#b-11--claude-desktop-ssh-alias)). macOS alias integration and first-party credential/plugin details remain OPEN in Q4/B-11.

---

## files.*

### What exists

- **Listing.** One level at a time under `/workspace`, folders first, 200 entries per page, with snapshot IDs for paging. The limits are 20,000 entries, 1 MiB of output and 64 snapshots with a 120 s TTL (`docs/SiloUI-FILES.md` "Loading and refresh" 11-24; `src/files.rs:14-75`). It runs with `--no-start` (doc 36-40).
- **Transfer.**
  - System `/usr/bin/sftp -b` through the managed SSH config and ProxyCommand (`editor::private_computer_transport(…, "transfer")`, `src/transfer.rs:1316-1339`; `src/editor.rs:540-552`). Local computers use `msb ssh serve`; remote computers use `--remote-guest` (`src/editor.rs:807-860`). **There is no separate bridge method for transfers.**
  - Roots are `/workspace` and `/home/silo/Downloads` (`src/transfer.rs:156-162`).
  - Limits: 4 GiB per file, 8 GiB and 100 files per upload, one transfer at a time in today's Linux source (`src/transfer.rs:38-73, 1083-1132`). NEW macOS admission queues competing transfers with “Waiting…” and Cancel (95 A-31; 95 §3 Queue).
  - Uploads publish through `.<name>.silo-part-<id>` and a rename. Downloads are bounded by size and free space (`docs/SiloUI-FILES.md` "Rules" 75-158).
- **Gaps** ("No content editor, deletion, folder transfer, recursive search or automatic boot is included", `docs/SiloUI-FILES.md` 5-7):
  - no delete;
  - no folder transfer;
  - no macOS computers ("Terminal, editor, Files, network ports, GitHub, secrets, working account | None", `docs/SiloUI-MACOS-COMPUTERS.md` "Not covered yet" 500).

### files.list
- Kind: query
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19). Host-level methods apply to either kind.
- Status: EXTENDED. NEW macOS filesystem-root/listing adapter (95 A-19; Q14 / 80 C-7). Existing behavior: (tauri `list_computer_directory`, `src/files.rs:139-197`; bridge `files.list`, `src/remote.rs:253`, `src/remote_access.rs:50-67`). It stays the Files page's method; 70's `guest.files.list` (any readable path, unpaged, both kinds) is a separate programmatic method (80 §2 N12).
- Params: `computerId`, `deviceId?`, `path: "/workspace[/…]"` (`src/files.rs:67-75`), `offset: multiple of 200, ≤ 20000`, `snapshotId?: string` (required when `offset > 0`).
- Result: `{entries: [{name, path, kind: "folder"|"file"|"symlink"}], nextOffset: number|null, snapshotId}` (`src/files.rs:20-33, 106-114`).
- Errors: "Invalid folder request.", "Start this computer to browse its files.", "Folder listing expired. Refresh this folder.", "This folder is too large to list.", "This folder no longer exists.", "Permission denied.", "This folder cannot be browsed.", "Could not load this folder.", "Computer no longer exists.", and for a remote computer "The remote device returned an invalid folder listing." (`src/files.rs:17-19, 76-84, 147-186`).
- Semantics: no gate; available during operations (`src/remote_access.rs:51-52`).

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).

### files.upload
- Kind: job (identified by the client's `transferId`)
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19). Host-level methods apply to either kind.
- Status: EXTENDED. NEW durable job outcomes, caller authorization replacing the window check, explicit client paths and macOS SFTP/queue adapter (95 A-19/A-33; 95 §3 Job results/Queue). Existing behavior: (tauri `upload_files`, `src/transfer.rs:1371-1427`)
- Params:
  - `transferId: [A-Za-z0-9_-]{1,64}` (`src/transfer.rs:1100-1106`), `computerId`, `deviceId?`, `directory` (inside a root), `conflict: "ask"|"replace"|"keepBoth"` (`src/transfer.rs:75-81`).
  - `selection: token`. This one-time token from the native picker or a drop is valid for 10 min and bound to its window (`src/transfer.rs:72, 1204-1263`; doc 146-155).
  - **NEW: `paths: string[]`** as an alternative to `selection`, for a native client that already holds the paths. Fjord installs "its plugin and hook in the guest" (brief:21) and has no picker in that flow. NEW `origin: "client"|"viewer"` and `connectionId?: string` distinguish a viewer drop (justified by 95 A-33); `origin:"viewer"` requires a viewer connection owned by the authorized caller, and the engine resolves its Downloads directory and rejects every other destination. macOS Downloads resolution remains Q14; it is not the Linux path.
- Result: `{jobId}` (`transfer:<transferId>`, 05 §4.2 E). `operations.job.finished.result`: `UploadOutcome = {status: "conflict", names} | {status: "done", names} | {status: "cancelled"}` (`src/transfer.rs:83-94`). NEW: the engine saves the terminal outcome to disk, retains it across restarts, and removes it after a client acknowledges showing it through `operations.job.acknowledge` (95 §3 Job results, overriding A-25; 05 job contract). This does not guarantee resumption of an interrupted running process; recovery of that case remains B-37.
- Progress/events: `operations.job.progress` with `source: "transfer"`, `data` = `transfer::Progress` with every field (see [Transfer progress](#transfer-progress-operationsjobprogress-source-transfer)).
- Cancel: `operations.cancel {jobId}` (05 §4.2 F), routed to today's `cancel_transfer(transferId)`; the Tauri client also calls `operations.cancel` directly (95 §3). Today a cancelled transfer returns `{status: "cancelled"}` as data, not an error (`src/transfer.rs:83-101`). 05 §4.2 E item 5 and F preserve that data outcome in `operations.job.finished.result`; `error.code: "cancelled"` applies only when today’s command returns cancellation as an error.
- Errors (today's command errors; they end the job in `operations.job.finished.error`, 05 §4.2 E item 5): "Silo can only upload to the workspace or the Downloads folder.", "This window can only upload to the Downloads folder.", Linux source admission refusal "Another file transfer is still running." (macOS instead queues competing work under 95 §3 Queue), "Silo is installing an update. Try again after it restarts.", "Start this computer to transfer files." (`src/transfer.rs:53, 1113-1117, 1384-1390`).
- Semantics:
  - `ask` sends nothing when a name already exists, and the selection survives that answer (`src/transfer.rs:1419`).
  - Viewer drops only go to Downloads, enforced by the engine using the caller-owned viewer connection (NEW, justified by 95 A-33). Today the backend uses the Tauri window label (`src/transfer.rs:1387-1390`). They always keep both because the viewer sends `conflict: "keepBoth"` (`ui/desktop/viewer-file-drop.tsx:54`; doc 92-94); the backend doesn't enforce that.

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).

### files.upload.choose
- Status: EXISTS (tauri `choose_upload_files`, `src/transfer.rs:1341-1369`). It is a native dialog: **UI-only**, not in the API. Clients without a webview pass `paths` (above).

### files.download
- Platforms: Linux and macOS computers; Mac hosts only (95 §3); macOS extension NEW (95 A-19).
- Kind: job
- Status: EXTENDED. NEW durable job outcomes, client-selected destination and macOS SFTP/queue adapter (95 A-19/A-22; 95 §3 Job results/Queue). Existing behavior: (tauri `download_file`, `src/transfer.rs:1429-1480`)
- Params: `transferId`, `computerId`, `deviceId?`, `path` (a regular file inside a root). **NEW: `destination?: path`.** Today the backend opens a save dialog (`src/transfer.rs:1460-1468`). The Mac client owns that dialog (95 A-22; 95 §3), and Fjord needs proof recordings (brief:23), which are made inside the computer.
- Result: `{jobId}` (`transfer:<transferId>`, 05 §4.2 E). `operations.job.finished.result`: `DownloadOutcome = {status: "done", path} | {status: "cancelled"}` (`src/transfer.rs:96-101`). NEW: the engine saves the terminal outcome to disk, retains it across restarts, and removes it after a client acknowledges showing it through `operations.job.acknowledge` (95 §3 Job results, overriding A-25; 05 job contract). This does not guarantee resumption of an interrupted running process; recovery of that case remains B-37.
- Progress/events: `operations.job.progress` with `source: "transfer"` (as `files.upload`).
- Cancel: `operations.cancel {jobId}` (05 §4.2 F); the Tauri client also calls `operations.cancel` directly (95 §3). The `{status: "cancelled"}` note of `files.upload` applies.
- Errors (they end the job in `operations.job.finished.error`, 05 §4.2 E item 5): "Silo can only download files from the workspace or the Downloads folder.", the size and free-space messages (`src/transfer.rs:59-66, 1440-1444`).

- macOS addition: NEW (justified by 95 A-19 and A-31 / §3 Queue: parity and queued work rather than busy admission). The macOS sections below cite B-14 guest SFTP, B-19 discovery/tunneling and missing tooling, and B-27 proxy evidence. NEW tools provisioning is in 30; default proxy DNS/lifecycle and keys/listeners/roots remain OPEN (Q5–Q6/Q9/Q13–Q14; C-7).


### Transfer progress (`operations.job.progress`, source `transfer`)
- Not an event of its own: `files.transfer.progress` is `operations.job.progress {jobId: "transfer:<transferId>", computerId?, source: "transfer", data}` (05 §4.2 E item 4; 80 §2 N11, N15).
- Status: EXISTS (`silo://transfer-progress`, `src/transfer.rs:37, 1397-1399, 1448-1450`), broadcast as today (05 §4.2 E item 4).
- `data` = `transfer::Progress`, every field kept: `{id, computer, direction: "upload"|"download", state: "transferring"|"done"|"failed"|"cancelled", name, fileIndex, fileCount, bytesDone, bytesTotal}` (`src/transfer.rs:103-115`; `ui/features/application/model/file-transfer.ts:18-28`).

### Viewer drag and drop events
`silo://viewer-drag` and `silo://viewer-drop` (`src/transfer.rs:70-71, 1282-1300`) are sent only to the viewer shell window that received a native drop. **UI-only**, not in the API. The resulting upload is `files.upload` to Downloads.

---

## Remote control of GitHub and secrets (NEW)

Today a controller can't change another device's GitHub or secrets (above). Fjord needs an "always-on host Mac, and controllers on other Macs" (brief:25) and "access to GitHub and secrets" in the Computers tool (brief:19).

**DECIDED (95 A-14/A-16):** every GitHub and secrets method is remotely manageable, and write-only secret values travel over the user's own SSH connection to the owner credential store (95 §1). Clients call their local engine with `deviceId?`; it routes to the owner (95 A-3).

The remote extensions are NEW, justified by 95 A-14/A-16. They add same-name bridge methods to the existing journalled `Access::Change` path (`src/remote.rs:2249-2275`), while reads use Read and pushed subscriptions use Stream (95 A-4; current classification: `src/remote.rs:226-234`). GitHub callback transport is NEW under `github.connect` (95 A-17; B-25), rather than requiring a screen on the owner.

---

## GitHub and secrets on macOS computers

**Requirement for every item in this section and the three that follow:**
- `docs/SiloUI-MACOS-COMPUTERS.md` "Not covered yet": "Terminal, editor, Files, network ports, GitHub, secrets, working account | None. These use the Linux guest bridge over SSH, which macOS computers do not have" (line 500).
- Fjord's dev computer is "usually macOS" (brief:20), and its Computers tool needs GitHub and secrets (brief:19).

What macOS computers already have, as the base for each mechanism:
- A guest account `silo` with Remote Login and a per-computer Ed25519 key in `macos-computers/<id>/guest-access/` (`docs/SiloUI-MACOS-COMPUTERS.md` "Provisioning for computer use" 303-322, 401-403; `src/macos_computers/guest_access.rs:4-5, 123-126`).
- SSH from the owner with `-F /dev/null`, `IdentitiesOnly`, `StrictHostKeyChecking=accept-new`, a per-computer `known_hosts` and `HostKeyAlias=silo-<id>` (`src/macos_computers/guest_access.rs:1-6, 323-356`).
- The guest's address comes from the newest `/var/db/dhcpd_leases` entry for its MAC address (`src/macos_computers/guest_access.rs:24, 255-265`).
- Networking is `VZNATNetworkDeviceAttachment` (`src/macos_computers/engine.rs:485-486`). The NAT address is "reachable only from the owner" (`docs/SiloUI-MACOS-COMPUTERS.md` 440-444).
- macOS computers have IDs, not entries in `computers.json` (`docs/SiloUI-MACOS-COMPUTERS.md` 78-80). Policies and assignments keyed by Linux name (`src/github.rs:1630-1634`; `src/runtime.rs:13117-13125`) need the computer key from `computers.*` (`computerId`, 80 §2 N16); NEW stored policies/assignments use `computerId` without name-key fallback; any required conversion is launch-only through 20 `migration.*` (95 §3; source keys above).

| Method | macOS computer |
| --- | --- |
| `github.state`, `.connect`, `.connect.reopen`, `.repositories.manage`, `.repositories.refresh`, `.disconnect`, `.access.set`, `.personalToken.*` | NEW (justified by 95 A-19). for macOS rows; the account side is host-level and unchanged |
| `github.configuration.save` / `.retry` | NEW (justified by 95 A-19): the same `Policy` for a macOS computer. **Route chosen by 95 A-15; qualification B-27.** Linux puts restricted tokens behind the msb TLS proxy placeholder (`src/secrets_runtime.rs:56-58`; implementation doc 46-50). the current macOS engine uses VZ NAT without this proxy (`src/macos_computers/engine.rs:485-486`); the NEW host gateway route is specified below |
| Guest credential helper | NEW (justified by 95 A-19): the `setup-github.sh` helper returns the placeholder `$MSB_SILO_GITHUB` (`guest/setup-github.sh:23`), which only the msb proxy replaces. Depends on Q5 |
| `secrets.list` / `.save` / `.remove` / `.retry` | NEW (justified by 95 A-19). for macOS assignments. **NEW host gateway route below (95 A-15; B-27)**, preserving the Linux behavior (placeholders and interception are msb's, `docs/SiloUI-SECRETS.md` 41-62) |
| `push.repositories` / `.start` / `.status` / `.dismiss` | NEW (justified by 95 A-19): the host fetches from the guest's upload-pack over OpenSSH (implementation doc 454-457). A macOS guest has sshd and a key (above). The template has no working Git/LFS, so NEW developer-tools provisioning is required (30 §Developer-tools provisioning; [macos.md Follow-up §B-19](probes/macos.md#b-19--settled-for-template-tooling)). Discovery roots remain Q9/C-7 (Linux scans `/workspace`, `src/host_push.rs:303-311`) |

### macOS host credential-proxy route (engine-internal, NEW)

- Status: NEW (justified by 95 A-15; 95 §1 and [92 §2–4](92-macos-proxy-research.md)). No new client method: `github.configuration.*` and `secrets.*` own policy changes.
- Platforms: macOS computers; the owner engine hosts per-computer network/proxy state (95 A-15).
- Contract: agents receive placeholders, with the same scoped GitHub selector and destination-restricted secret substitution as Linux (`src/secrets_runtime.rs:56-58, 104-131`; `guest/setup-github.sh:23`; network patch `patches/microsandbox-silo-network-0.7.6.patch:1677, 1941`). Allowed servers still receive the real value and can reflect it back, the documented secrecy boundary (`docs/SiloUI-SECRETS.md:76`; 95 A-15).
- Qualified prototype mechanism (NEW production integration): `VZFileHandleNetworkDeviceAttachment` → `AF_UNIX/SOCK_DGRAM` socketpair → Rust gateway → patched MicroSandbox `SmoltcpNetwork::take_backend()`. The gateway removes the 12-byte virtio-net header on guest frames, feeds the public frame backend and sends engine frames back through the FileHandle; the patched network engine owns DNS bindings, TLS interception, secret policy and live updates. This compiled at the pinned MicroSandbox revision/patch without a separate TLS-proxy fallback. Silo's current `VZNATNetworkDeviceAttachment` remains source behavior, not this adapter ([proxy.md §Adapter and commands](probes/proxy.md#adapter-and-commands), [§Scope and versions](probes/proxy.md#scope-and-versions); `src/macos_computers/engine.rs:485-486`).
- Guest interface/route/DNS bootstrap is NEW: the prototype used a boot LaunchDaemon with `networksetup`, `ifconfig en0` and `route`; `networksetup` preferences alone did not bring up the interface. Guest A used `172.30.0.2/30` through gateway/DNS `172.30.0.1`, B used `172.30.0.6/30` through `172.30.0.5`. These are probe addresses, not API defaults. Production address allocation, boot readiness and resolver integration require implementation qualification ([proxy.md §Adapter and commands](probes/proxy.md#adapter-and-commands)).
- **DNS remainder:** guest default `dig` timed out. Explicit `dig @<engine-gateway> allowed.test A` succeeded and populated the patch's host/name binding; subsequent HTTPS requests used `curl --resolve` with that hostname/SNI. This proves a controlled DNS/substitution path, not normal guest resolver behavior. Default resolver integration is OPEN before ordinary guest networking can be claimed ([proxy.md §Results](probes/proxy.md#results)).
- Guest CA trust: root setup must deliver the per-computer engine CA and run `security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain <guest-ca.pem>`. The probe installed the CA into the guest System keychain and verified its fingerprint; root-finalization delivery remains NEW integration at `src/macos_computers/offline_setup.rs:675-710` ([proxy.md §Adapter and commands](probes/proxy.md#adapter-and-commands)). Keep the CA private key on the host (95 A-15; the prototype used separate engine CAs).
- **Qualified secret behavior:** allowed-host placeholder substitution, non-allowed-host passthrough and revocation of an active TLS relay passed. After `REVOKE`, the engine logged policy-change connection closure, guest curl exited 52, and upstream could not write the held response. Two guests tested sequentially with separate network instances/subnets/CAs/secrets received only their own secret. Simultaneous guests were not tested ([proxy.md §Results](probes/proxy.md#results)).
- **Measured cost, three 10 MiB samples:** Apple NAT median first byte 24.562 ms / total 122.440 ms / 85.64 MB/s; FileHandle + patched engine 29.814 ms / 244.955 ms / 42.81 MB/s. The frame path added 5.252 ms to first byte and approximately doubled total transfer time, halving throughput in this test. NAT used its resolver; FileHandle required `--resolve`, so this is a bounded comparison, not a general throughput guarantee ([proxy.md §NAT comparison](probes/proxy.md#nat-comparison)).
- **PARTLY B-27:** the adapter and controlled secret/CA paths are viable. Default DNS, production secret lifecycle/GitHub selector integration, root-finalization CA delivery, concurrent isolation and gateway lifecycle/restart cleanup remain OPEN. No client method is added ([proxy.md §Spec impact and remaining seam](probes/proxy.md#spec-impact-and-remaining-seam)).

## Network on macOS computers

| Method | macOS computer |
| --- | --- |
| `network.state` (discovered listeners) | NEW (justified by 95 A-19). Use guest SSH `lsof -nP -iTCP -sTCP:LISTEN`; the probe also qualified `netstat -anv -p tcp` LISTEN output without `/proc` ([macos.md §B-19](probes/macos.md#b-19--partly)). API parsing/result adaptation remains implementation work; Linux's `/proc/net/tcp` reader is `src/network.rs:238-259` |
| `network.publish` / `.unpublish` | NEW (justified by 95 A-19). Use an owner OpenSSH `-N -L 127.0.0.1:<hostPort>:127.0.0.1:<guestPort>` tunnel through guest sshd, which also reaches guest-loopback listeners. B-19 sent 16 bytes, half-closed the writer, received `EOF:16`, and verified tunnel/listener teardown ([macos.md §B-19](probes/macos.md#b-19--partly)). Production port/key/readiness ownership remains C-7; no general direct-NAT TCP relay was qualified |
| `network.open`, `.localhost` hosts | NEW (justified by 95 A-19). `computer_host(name, id)` (`src/network.rs:89-114`) applies unchanged once a macOS computer has a name and ID |
| Controllers | NEW (justified by 95 A-19). `guest.ssh` with `purpose:"port"` for macOS computers (below) |

## SSH access, guest access and files on macOS computers

| Method | macOS computer |
| --- | --- |
| `guest.sshAlias.ensure` / `.remove` | NEW (justified by 95 A-19). Required by brief:20-21. A `Host` entry would carry `User silo`, the computer's key and its `known_hosts`. The guest's NAT address comes from DHCP and can change (`src/macos_computers/guest_access.rs:255-265`), so a fixed `HostName` is fragile. The other option is a ProxyCommand to an engine entry point that connects to port 22 of the current NAT address, as `macos.display.stream` does for port 5900 (`docs/SiloUI-MACOS-COMPUTERS.md` 440-444; `src/macos_computers/remote_display.rs:84-97`). The ProxyCommand relay is the choice (70 §1.3; 80 §2 N10; Q12) |
| `guest.ssh` | NEW (justified by 95 A-19). for macOS computers: an owner-side relay to the guest's port 22, the same shape as `macos.display.stream` (`src/macos_remote.rs:100`). Needed for controllers on other Macs (brief:25) |
| `guest.prepare` | NEW (justified by 95 A-19). for macOS: authorize a controller's public key in the guest account's `~/.ssh/authorized_keys`. Linux authorizes it in msb's key store (`src/editor.rs:708-723`). This is also where 30 §7's macOS key authorization (`{computerId, publicKey}`) lives; its alias and ProxyCommand result is `guest.sshAlias.ensure` (80 §2 N8). Q13 |
| `terminal.command` | NEW (justified by 95 A-19): `ssh -F <config> -t <alias>`, as for remote Linux computers (`src/terminal.rs:81-91`) |
| `sshAccess.*` | NEW (justified by 95 A-19), with the same meaning as on Linux (80 §2 N8). For Linux computers on a Mac host, the owner runs a per-computer `msb ssh serve` listener (`src/ssh_access.rs:221-295`). For macOS computers, the guest runs its own sshd, reachable only from the owner. A loopback or LAN listener would need an owner relay, and managed keys would go to the guest's `authorized_keys`. Q13 |
| `files.list` | NEW (justified by 95 A-19). Linux runs a guest script through `msb exec` (`src/files.rs:199-256`). macOS would go over SSH like the clipboard (`docs/SiloUI-MACOS-COMPUTERS.md` 381-391). Roots: Q14 |
| `files.upload` / `.download` | NEW (justified by 95 A-19): `sftp` with the computer's key. Guest `sshd -T` confirms `subsystem sftp /usr/libexec/sftp-server`, `maxsessions 10`, and OpenSSH 10.3p1 / LibreSSL 3.3.6 ([macos.md §B-14](probes/macos.md#b-14--confirmed)); Files roots remain Q14/C-7. Silo already copies into macOS guests with `scp` and that key (`src/macos_computers/guest_access.rs:375-390, 573`) |

---

## Coverage table

| Item | Kind | API method | Notes |
| --- | --- | --- | --- |
| `github::read_github_state` (`src/github.rs:3031`) | tauri | `github.state` | |
| `github::connect_github` (`src/github.rs:3037`) | tauri | `github.connect` | job `job:<n>` (05 §4.2 E); `pendingAuthorizationUrl` NEW |
| `github::cancel_github_connection` (`src/github.rs:3053`) | tauri | `operations.cancel` | `jobId` = the running GitHub connect job; no old wire method (95 §3; 05 §4.2 F) |
| `github::reopen_github_authorization` (`src/github.rs:3076`) | tauri | `github.connect.reopen` | browser launch belongs to the Mac client (95 A-22; 95 §3) |
| `github::manage_github_repositories` (`src/github.rs:3090`) | tauri | `github.repositories.manage` | returns `{url}` NEW |
| `github::refresh_github_repositories` (`src/github.rs:3107`) | tauri | `github.repositories.refresh` | |
| `github::disconnect_github` (`src/github.rs:3140`) | tauri | `github.disconnect` | |
| `github::set_github_access_enabled` (`src/github.rs:3167`) | tauri | `github.access.set` | |
| `github::save_github_configuration` (`src/github.rs:3327`) | tauri | `github.configuration.save` | |
| `github::retry_github_configuration` (`src/github.rs:3404`) | tauri | `github.configuration.retry` | |
| `github::personal_token::save_github_personal_token` (`src/github_personal_token.rs:316`) | tauri | `github.personalToken.save` | |
| `github::personal_token::remove_github_personal_token` (`src/github_personal_token.rs:353`) | tauri | `github.personalToken.remove` | |
| `host_push_operations::start_repository_push` (`src/host_push_operations.rs:402`) | tauri | `push.start` | job `push:<operationId>` (05 §4.2 E) |
| `host_push_operations::repository_push_status` (`src/host_push_operations.rs:435`) | tauri | `push.status` | |
| `host_push::dismiss_repository_push` (`src/host_push.rs:69`) | tauri | `push.dismiss` | |
| `read_application_state` → `repositories` (`src/runtime.rs:2826-2858`) | tauri (embedded) | `push.repositories` | shared with `computers.*` |
| `secrets::read_secrets_state` (`src/secrets.rs:789`) | tauri | `secrets.list` | |
| `secrets::save_secret` (`src/secrets.rs:796`) | tauri | `secrets.save` | |
| `secrets::remove_secret` (`src/secrets.rs:857`) | tauri | `secrets.remove` | |
| `secrets::retry_secret` (`src/secrets.rs:876`) | tauri | `secrets.retry` | |
| `network::read_network_state` (`src/network.rs:826`) | tauri | `network.state` | |
| `network::save_network_port` (`src/network.rs:841`) | tauri | `network.publish` | |
| `network::remove_network_port` (`src/network.rs:900`) | tauri | `network.unpublish` | |
| `network::open_network_port` (`src/network.rs:944`) | tauri | `network.open` | returns `{url}` NEW |
| `remote_network::remote_network_state` (`src/remote_network.rs:650`) | tauri | `network.state` (`deviceId`) | |
| `remote_network::remote_save_network_port` (`src/remote_network.rs:656`) | tauri | `network.publish` (remote computer) | |
| `remote_network::remote_remove_network_port` (`src/remote_network.rs:709`) | tauri | `network.unpublish` (remote computer) | |
| `remote_network::remote_open_network_port` (`src/remote_network.rs:729`) | tauri | `network.open` (remote computer) | |
| `ssh_access::read_ssh_access_state` (`src/ssh_access.rs:626`) | tauri | `sshAccess.state` | |
| `ssh_access::save_ssh_access` (`src/ssh_access.rs:640`) | tauri | `sshAccess.save` | |
| `ssh_connection::ssh_connection` (`src/ssh_connection.rs:119`) | tauri | `sshAccess.connection` | save dialog → `destination` NEW |
| `remote_ssh_access::remote_ssh_access_state` (`src/remote_ssh_access.rs:39`) | tauri | `sshAccess.state` (`deviceId`) | |
| `remote_ssh_access::remote_save_ssh_access` (`src/remote_ssh_access.rs:50`) | tauri | `sshAccess.save` (remote computer) | |
| `editor::read_editor_include_notice` (`src/editor.rs:1111`) | tauri | `editor.includeNotice` | |
| `computer_action` action=`open-editor` (`src/runtime.rs:3263-3270`) | tauri | UI-only, not in API | launcher on the UI's device, built on `editor.command` and `guest.sshAlias.ensure` (95 A-22; `src/editor.rs:32-104, 187-208`) |
| `computer_action` action=`open-terminal` (`src/runtime.rs:3263-3268`) | tauri | UI-only, not in API | launcher on the UI's device, built on `terminal.command` (`src/remote_access.rs:1-2`) |
| `applications::list_applications` (`src/applications.rs:186`) | tauri | UI-only, not in API | discovers apps on the UI's device |
| `applications::choose_application` (`src/applications.rs:221`) | tauri | UI-only, not in API | native file dialog |
| `files::list_computer_directory` (`src/files.rs:139`) | tauri | `files.list` | |
| `transfer::choose_upload_files` (`src/transfer.rs:1341`) | tauri | UI-only, not in API | native picker; `files.upload` gets `paths` NEW |
| `transfer::upload_files` (`src/transfer.rs:1371`) | tauri | `files.upload` | job `transfer:<transferId>` (05 §4.2 E); `paths` NEW |
| `transfer::download_file` (`src/transfer.rs:1429`) | tauri | `files.download` | job `transfer:<transferId>` (05 §4.2 E); `destination` NEW |
| `transfer::cancel_transfer` (`src/transfer.rs:1482`) | tauri | `operations.cancel` | `jobId` = `transfer:<transferId>`; no old wire method (95 §3; 05 §4.2 F) |
| `silo://network-state-changed` | event | `network.changed` | also emitted by SSH access saves; NEW state and sequence payload (95 A-4) |
| `silo://transfer-progress` (`src/transfer.rs:37`) | event | `operations.job.progress` | `source: "transfer"`, `data` = `transfer::Progress` (05 §4.2 E) |
| `silo://editor-include-changed` (`src/editor.rs:1084`) | event | `editor.includeNotice.changed` | NEW state and sequence payload (95 A-4) |
| `silo://viewer-drag`, `silo://viewer-drop` (`src/transfer.rs:70-71`) | event | UI-only, not in API | sent to one viewer shell window only |
| `silo://application-state-changed` from GitHub (`src/github.rs:257-266, 433-442, 818-821`) | event | `github.changed` | 05 §4.2 D lists every emit site; NEW state and sequence payload (95 A-4) |
| `silo://application-state-changed` from secrets (`src/secrets.rs:531, 777, 849, 869, 929`) | event | `secrets.changed` | NEW state and sequence payload (95 A-4) |
| `silo://application-state-changed` from push (`src/host_push.rs:92, 1219, 1241`; `src/host_push_operations.rs:224`) | event | `push.changed` | NEW state and sequence payload (95 A-4) |
| `ssh.access.state` (`src/remote.rs:250`) | bridge | `sshAccess.state` | |
| `ssh.access.connection` (`src/remote.rs:251`) | bridge | `sshAccess.connection` (owner side: `authorize_controller`) | |
| `ssh.access.save` (`src/remote.rs:252`) | bridge | `sshAccess.save` | |
| `files.list` (`src/remote.rs:253`) | bridge | `files.list` | |
| `guest.prepare` (`src/remote.rs:254`) | bridge | `guest.prepare` | macOS part NEW, also hosts 30 §7's key authorization (80 §2 N8) |
| `guest.ssh` (`src/remote.rs:255`) | bridge (stream) | `guest.ssh` | `purpose:"port"` |
| `network.state` (`src/remote.rs:256`) | bridge | `network.state` | |
| `network.publish` (`src/remote.rs:257`) | bridge | `network.publish` | |
| `network.unpublish` (`src/remote.rs:258`) | bridge | `network.unpublish` | |
| `repository.push.status` (`src/remote.rs:259`) | bridge | `push.status` | |
| `repository.push.start` (`src/remote.rs:260`) | bridge | `push.start` | job `push:<operationId>` |
| `repository.push` (`src/remote.rs:261`) | bridge | removed, no API route (95 §3; source already unserved: `src/remote_access.rs:124-125, 180`) | 80 §5 B-6 |
| `repository.dismiss` (`src/remote.rs:262`) | bridge | `push.dismiss` | |
| `--remote-guest` (`src/main.rs:97-104`) | CLI | not an API method: ProxyCommand transport entry for `guest.ssh` (80 §1.6) | Q3 |
| `--msb-ssh-serve` (`src/main.rs:97-104`) | CLI | retired AppImage transport; no engine entry or API route (95 §3; 80 §1.6) | Q3 |
| NEW `editor.command` (95 A-22) | extracted command | `editor.command` | client launches returned argv; macOS path probe Q14 / 80 C-7 |
| NEW `github.connect.callback` (95 A-17) | bridge (stream) | `github.connect.callback` | owner callback only; B-25 |
| Background: GitHub worker (`src/main.rs:306`), secrets install (`src/main.rs:305`), SSH monitor (`src/main.rs:342`), editor transport repair (`src/main.rs:343`), tunnel, transfer and listener shutdown (`src/main.rs:365-367`) | lifecycle | engine duties, no method | |

## Open questions

- D-cred. **DECIDED (95 A-15/A-16/A-17):** use the macOS host placeholder proxy, carry GitHub callbacks over SSH and allow remote secret edits over the user's own SSH connection (95 §1). Proxy qualification remains B-27; callback validation remains B-25.
- Q1. **DECIDED (95 A-17):** the controller browser signs in and the callback is carried over the existing SSH connection (95 §1; `github.connect`). Owner PKCE callback remains `src/github.rs:2589-2618`; end-to-end validation is B-25.
- Q2. **DECIDED (95 A-4):** events carry new state and sequence number, bounded buffers and re-read after gaps/reconnect (95 §2; 05 event catalogue).
- Q3. **DECIDED (95 A-1):** Fjord is the maintained product and one engine serves both apps (95 §1). Existing ProxyCommand modes remain engine transport entry points (`src/editor.rs:807-860`; `src/main.rs:97-104`). Stable installed helper path/bundle arbitration is not specified by 95 and remains B-22.
- **Q4. PARTLY B-11:** first-party Desktop connected to Linux through Silo's Include/ProxyCommand with `IdentityAgent none`, host-key pinning and forced-off forwarding. Desktop set `BatchMode no`; the alias remained `yes`. The working folder came from deeplink `ssh_folder=/home/silo`, not `sshConfigs.startDirectory`. macOS Desktop alias integration, credential propagation and remote plugin-hook copying remain OPEN ([linux.md §B-11](probes/linux.md#b-11--claude-desktop-ssh-alias); 70 OQ1).

- Q5. **DECIDED (95 A-15):** macOS uses a host proxy and placeholders; recommended VZ file-handle gateway route is NEW above (95 §1; 92 §2–4). PARTLY B-27 qualifies the FileHandle/gateway/patched-SmoltcpNetwork adapter, controlled substitution/revocation/isolation and CA trust above; default guest DNS and production lifecycle/GitHub integration remain OPEN ([proxy.md §Spec impact and remaining seam](probes/proxy.md#spec-impact-and-remaining-seam)). This is NEW Silo integration.
- Q6. **DECIDED (95 A-15):** general secrets use the same macOS host placeholder-proxy route as GitHub (95 §1; 92 §2–4); B-27 partially qualifies the adapter/secret behavior; default DNS and production lifecycle remain OPEN ([proxy.md §Results](probes/proxy.md#results)).
- Q7. **DECIDED (95 A-16):** secret values may cross the user's own SSH connection and are stored in the selected owner's credential store (95 §1; current custody: `docs/SiloUI-SECRETS.md:3-7`).
- Q8. **DECIDED (95 A-16):** `secrets.save` requires `allowAnyDestination:true` for `*` (95 §2, Secrets wildcard); existing UI-only acknowledgement and backend acceptance are `ui/features/application/model/secret-configuration.ts:53`, `src/secrets.rs:457`.
- **Q9. B-19 tooling SETTLED:** the template has no working Git, Git LFS or Xcode command-line tools; NEW provisioning is specified in 30 before dev readiness (95 A-19; [macos.md Follow-up §B-19](probes/macos.md#b-19--settled-for-template-tooling)). Workspace/Git roots remain research C-7; post-provision clone/LFS/Host Push validation remains implementation work (B-34).
- **Q10. B-19 discovery SETTLED:** `lsof -nP -iTCP -sTCP:LISTEN` and `netstat -anv -p tcp` worked over guest SSH (§Network on macOS computers; [macos.md §B-19](probes/macos.md#b-19--partly)).
- **Q11. B-19 tunnel mechanism SETTLED:** OpenSSH `ssh -L` reached a guest-loopback listener, preserved write-half-close and tore down cleanly. Use this mechanism for the NEW publisher; production ownership/recovery remains C-7 ([macos.md §B-19](probes/macos.md#b-19--partly)).

- Q12. **DECIDED (95 A-13):** managed SSH aliases use `computerId`; no old-name aliases or runtime migration/fallback paths (95 §3 overrides the original A-13 conversion default); the ProxyCommand engine relay remains the prior chosen design (80 §2 N10; `src/macos_computers/guest_access.rs:255-265, 348-350`).
- Q13. **DECIDED (95 A-13/A-19):** key aliases by `computerId` and provide managed SSH parity (95 §1–2). 95 does not specify the guest/controller key lifecycle or managed listener mechanism. *Remaining probe (80 C-7):* validate the guest's `authorized_keys` integration and owner-side loopback/LAN relay before defining its implementation; current root finalization writes the initial owner key (`src/macos_computers/offline_setup.rs:675-710`).
- Q14. **DECIDED (95 A-19):** files and editor access apply to macOS in this API version (95 §1). B-14 confirms guest SFTP, MaxSessions 10 and OpenSSH 10.3p1 ([macos.md §B-14](probes/macos.md#b-14--confirmed)). *Remaining research:* define Files roots (80 C-7); `/Users/silo` is sourced (`docs/SiloUI-MACOS-COMPUTERS.md:303-306`), but no macOS `/workspace` or Downloads root is established. 95 does not choose roots.
- Q15. **DECIDED (95 A-19):** macOS receives the Linux Files feature set (95 §1). Programmatic folder/delete access remains `guest.files.*` (80 §2 N12; 70 §2.1); Linux Files-page folder transfer/delete is absent (`docs/SiloUI-FILES.md:5-7`). 95 does not expand that Files-page contract.
- **Q16. Where `push.repositories` lives.** Resolved: 10 §1.4 retains `repositories` on each computer row, owned by `push.*`, and this section §push.repositories defines the domain query. This preserves today’s enrichment (`src/runtime.rs:2835-2865`) without defining a second method (80 §2 N20).
