# 91 — Codex's findings, verified

This file cross-checks every confirmed finding of `90-codex-independent-audit.md` (M1–M3, P1–P7, C1, D1–D7) against Silo and against the spec in this folder.

**How each finding was checked**

- Silo is at `/Users/polarzero/code/projects/microsandbox-workspaces`, HEAD `94d81937904af83faf5839e8b28b24e0e1883c8b`. Each cited Silo line was opened.
- **Code paths** below are relative to `app/SiloUI/`, as in the audit: `src-tauri/src/…` for Rust, `src-tauri/guest/…` for guest scripts, `src/…` for the UI. `docs/…` is the Silo repo's `docs/`.
- **Spec references** name the section file and the method or behaviour. They don't use line numbers, because another agent may be renaming methods while this is written.
- **Verdicts:**
  - **CONFIRMED:** the behaviour exists in Silo, the spec lacks it or contradicts it, and Codex's evidence is accurate.
  - **PARTLY:** part of the finding holds. The verdict says which part.
  - **REJECTED:** the spec already covers it, or the evidence is wrong.
- **What to add:** each CONFIRMED and PARTLY finding ends with the text to add to the spec. Where a finding needs an owner decision, it ends with a decision statement instead.

## Verdicts

| # | Verdict | One line |
|---|---|---|
| M1 | CONFIRMED | ChatGPT app version collection (gated, never waits for the storage lock, retried every 120 s) is not in the spec |
| M2 | CONFIRMED | The `runtime-grants` ledger of issued GitHub tokens, and its 30 s retirement sweep, are not in the spec |
| M3 | CONFIRMED | The private publishing cache (2 GiB budget, inherited lock, `.active` crash marker, discard rules) is not in the spec |
| P1 | CONFIRMED | The ChatGPT worker's 10 s start delay, back-off schedule, stop on a permanent failure, Retry wake, single worker and low priority are not specified |
| P2 | CONFIRMED | The log filtering rules (PEM state per stream and session, and markers for credentials) are absent from `logs.query` and `logs.export` |
| P3 | CONFIRMED | `unreadableRecords` appears in the spec, but the rules for damaged and oversized records behind it don't |
| P4 | CONFIRMED | Account preparation is one line in the spec. The migration rules (refusals, copy with conflicts, record written last) are missing |
| P5 | PARTLY | `guest.sshAlias.ensure` lacks `path` in both §50 and §70. But §80 N10 already proposes `path?`; what's missing is its rules and errors |
| P6 | CONFIRMED | `push.start` omits the LFS steps and the rule that the Git ref is published only after LFS succeeds. The spec only cites the doc range that holds them |
| P7 | CONFIRMED | The spec names `secrets::install` but not the recovery it performs |
| C1 | CONFIRMED | The code checks the bridge protocol version (5), not the release. §05 and §60 repeat a Silo doc claim that overstates the check |
| D1 | PARTLY | There is no lock or recording contract. But §40 OQ 9–10 and §80 A-8/A-9 already record both as owner decisions with options |
| D2 | PARTLY | The job, id and cancel conflict is real, but §80 N11 and A-9 already record it. Codex adds the engine-lifetime and owner-device questions |
| D3 | PARTLY | All three schema conflicts are real in §30, §50 and §70. §80 N10, N17 and N19 already resolve them as proposals, not yet applied |
| D4 | PARTLY | Real, but §50 Q1 and Q5–Q7, and §80 A-15 to A-17, already pose these decisions. Codex adds nothing beyond calling them blockers |
| D5 | PARTLY | §40 OQ 3 and §80 A-24 already ask how viewers are shared. Codex adds a concrete problem: one client's close tears down another's viewer |
| D6 | PARTLY | §60 OQ 10 and §80 A-4 already ask whether notices are replayed. The new fact is that today Silo delivers the OS notification itself |
| D7 | CONFIRMED | Revoking secrets, cleaning stopped computers' logs and repairing ports are triggered by reads. No engine schedule replaces those reads, and §80 doesn't list this |

---

## M1. ChatGPT app garbage collection — CONFIRMED

**Silo.** All cited lines check out:

- `collect_garbage`, `try_collect_garbage` and `collect_garbage_locked`: `src-tauri/src/chatgpt_app.rs:1842-1922`.
- `collect_unused` and its rationale: `:2027-2054`.
- `collect_unused_once`: `:2056-2066`.
- `COLLECTION_RETRY` = 120 s, and the `Maintenance` retry loop: `:2068-2108`.
- `collect_unused_gated`: `:2110-2128`.
- Callers, and nothing else:
  - the worker's ready hook: `:2196-2200`;
  - `start_automatic`: `:2225-2227`, itself started from `src-tauri/src/computer_use.rs:1743`.
- `docs/SiloUI-CHATGPT-APP.md`, "Behavior": lines 59-64.

One precision on Codex's wording: in this path `in_use` is empty, so collection removes every unpinned version. It runs only when no Linux computer is running at all (`collect_unused_once`, `:2056-2066`; `runtime/update_recovery.rs:176-183`).

**Spec.** §20 §4.1 and §40 `computerUse.app.*` mention the worker and the status, nothing about collection. No other spec file mentions it (searched for "garbage", "collect").

**Add to `20-checkpoints-exports-preparation.md`**, §4.1 Facts, under the ChatGPT for Linux app bullet:

> #### Engine behaviour: unused ChatGPT app versions are removed
> - **Status:** EXISTS, internal. No command, event or bridge method (`src-tauri/src/chatgpt_app.rs:2042-2054`; callers `:2199`, `:2227`).
> - **Platforms:** host-level, on every device; it protects running Linux computers.
> - **What it removes** (`collect_garbage_locked`, `chatgpt_app.rs:1875-1922`):
>   - stale `.staging-*` under the storage root and under `published/`;
>   - every `published/<version>-<debarch>` folder other than the pinned one, with its publication record;
>   - records of such versions whose folder is gone;
>   - every file in `downloads/` not named `chatgpt_<pinned version>_<arch>.deb…`.
> - **When:**
>   - at engine start, right after the first status read (`chatgpt_app.rs:2225-2227`);
>   - when the worker has published the pinned version (`:2196-2200`);
>   - `docs/SiloUI-CHATGPT-APP.md` "Behavior", lines 59-64.
> - **Preconditions, all checked inside the device-wide operation gate.** The gate is taken as a hidden try-admission, `try_device_hidden("Removing unused ChatGPT app versions")` (`chatgpt_app.rs:2110-2128`; `runtime/operation_gate.rs:915-917`).
>   - No Linux computer is running (`runtime/update_recovery.rs:176-183`). Every computer mounts the whole `published/` folder, and a running guest may still use the previous version until its next boot sync (`chatgpt_app.rs:2027-2033`; doc lines 62-64).
>   - Because the check and the deletion share the gate that every start, restore and resume takes, no computer can begin booting from a version between the inventory and the deletion (`:2029-2032`).
>   - Any other gate work in progress means the pass is skipped, not queued (`:2032-2033`).
> - **The storage lock is never awaited inside the gate.** `try_collect_garbage` takes `RootLock::try_take` and gives up while a download or an extraction holds the lock, because "waiting while holding the device-wide gate would stall every lifecycle operation and Quit" (`chatgpt_app.rs:1858-1874`, `:2034-2037`).
> - **Retry:**
>   - a skipped pass stays pending;
>   - one thread, `chatgpt-app-gc`, retries every 120 s until a pass runs;
>   - a pass skipped while the loop is ending restarts the loop (`COLLECTION_RETRY`, `Maintenance::note` / `run_retries`, `chatgpt_app.rs:2038-2054`, `:2068-2108`).
> - **Not visible to clients.** It changes neither `preparation.chatgpt.status` nor the operation queue, because the gate entry is hidden.

---

## M2. GitHub issued-token retirement ledger — CONFIRMED

**Silo.** All cited lines check out:

- The ledger:
  - `TokenLedger` and the `runtime-grants` store entry: `src-tauri/src/github.rs:1189-1216`;
  - `remember_token`: `:1217-1225`;
  - `retire_unused`: `:1230-1275`;
  - `append_ledger_token`, `retire_ledger_tokens` and `forget_ledger_tokens`: `:1278-1340`.
- `RETIREMENT_RETRY_AFTER` = 30 and `TokenRetirement`: `:2125-2143`.
- `sweep_retirement`: `:2804-2827`.
- The worker's call: `:2985-2996`.

Codex's description holds:

- Each issuance is recorded before the next request. A runtime grant whose recording fails is revoked at once (`:1914-1917`). A host push token is recorded through `begin_host_push_token` (`:2144-2154`, called at `:2316-2318`).
- Tokens still used by grants or by active pushes are kept.
- A failed ledger write is flushed before the next sweep (`:2822-2823`).

**Spec.** §50 `github.*` "What exists" → "Background work" lists catalog refresh, renewal, personal-token checks and rate limits. `github.disconnect` covers account revocation. Neither the ledger nor the retirement sweep appears anywhere in the spec (searched for "ledger", "runtime-grants", "retire").

**Add to `50-access-network-files.md`**, `github.*` "What exists", as a new bullet after "Background work":

> - **Engine behaviour: retiring issued tokens through a ledger.**
>   - **Status:** EXISTS, internal. No method.
>   - **Store:** a credential-store entry `runtime-grants` under the channel's GitHub service. It holds a JSON map from computer name to the restricted tokens issued for it (`src/github.rs:1189-1216`). Its errors:
>     - "The system credential store is unavailable.";
>     - "Stored GitHub runtime credentials are invalid.";
>     - "Cannot read GitHub runtime credentials from the system credential store.";
>     - "Cannot save GitHub runtime credentials in the system credential store.".
>   - **Record before the next request:**
>     - Every restricted token minted for a computer is appended to the ledger before Silo makes any other network request, so "a later partial failure must not lose the only copy needed for revocation" (`remember_token`, `src/github.rs:1217-1225`).
>     - If recording a runtime grant's token fails, the token is revoked at once and the issuance fails (`:1914-1917`).
>     - Recording also sets `grants_issued` in `github.json` (`:1222-1224`).
>   - **Retirement:**
>     - `retire_unused(computer)` revokes (`RevokeToken`) each of that computer's ledger tokens that is not live. It then removes the revoked ones from the ledger (`:1230-1275`, `:1295-1340`).
>     - "Live" means any of: in the computer's cached runtime profile (`runtime::scoped_cached_tokens`), in its active grants, issued and still matching the computer's current scopes, or held by a host push in progress (`active_pushes`, `:2126-2154`).
>   - **Retry, independent of clients:**
>     - The GitHub worker runs `sweep_retirement` at most every 30 s (`RETIREMENT_RETRY_AFTER`, `:2125`; `:2804-2827`; called at `:2985-2996`).
>     - A pass first saves a ledger whose earlier write failed (`LEDGER_SECRET.flush`), then retires every computer in the ledger. One computer's failure doesn't stop the others.
>     - The worker never sleeps past the next retirement time (`:2999-3006`).
>   - **Host push tokens:**
>     - A push token joins `active_pushes` before it is recorded (`begin_host_push_token`, `:2144-2154`).
>     - When the push ends, `HostPushCredential::drop` revokes the token, removes it from the ledger, marks retirement due now and wakes the worker (`:2178-2203`).
>     - A personal token is never revoked (`:2157-2158`).
>   - **Credential-store retry** also clears a blocked ledger (`retry_credential_access`, `:424-427`).

---

## M3. Private publishing-cache recovery and eviction — CONFIRMED

**Silo.** All cited lines check out in `src-tauri/src/host_push_cache.rs`:

- `MAX_BYTES` = 2 GiB: `:17`.
- Acquisition, with the `.active` check and recreation: `:92-147`.
- `discard`: `:149-155`.
- `Drop`: `:160-178`.
- `idle_lock`, `sweep` and `evict`: `:202-298`.

Use in `src-tauri/src/host_push.rs`:

- cache key and acquisition: `:1086-1087`;
- the lock fd passed to Git: `:1132`;
- discard on failure: `:1150-1156`.

One precision: the cache is discarded only when publication fails **before** the guest commit was imported into it (`if publication.is_err() && !imported`, `host_push.rs:1154`). After import it is kept across remote rejections and network failures, "so large (LFS) repositories do not re-transfer on retry" (`:1150-1153`).

**Spec.** §50 `push.start` cites `docs/SiloUI-GITHUB-IMPLEMENTATION.md` 448-528, which contains the cache rules, but the method states none of them. No spec file mentions `host_push_cache` or the publishing cache (searched).

**Add to `50-access-network-files.md`**, `push.start` Semantics:

> - **Engine behaviour: the private publishing cache.**
>   - **Status:** EXISTS, internal.
>   - **Location and key:** `<runtime home>/push-cache/<sha256(computer \0 path \0 repository)>`, private directories only (`src/host_push.rs:1086-1087`; `src/host_push_cache.rs:33-46`, `:92-95`). It holds no tokens (`docs/SiloUI-GITHUB-IMPLEMENTATION.md` 479-487).
>   - **Locks:**
>     - A short root lock serialises choosing, creating and evicting caches across processes.
>     - Each repository's `<name>.lock` is held for the whole push and inherited by the Git children (`HostGit.cache_lock_fd`, `src/host_push.rs:1132`; `src/host_push_cache.rs:1-4`, `:20-27`, `:96-106`).
>     - A second push of the same repository fails with "Another push of this repository is still using its publishing cache. Wait for it to finish." (`:100-104`).
>   - **Crash recovery:**
>     - An `.active` marker is written and synced at each acquisition (`:126-139`).
>     - If the marker is still there at the next acquisition, its process died before cleanup. Holding the repository lock proves no Git child of that process survives, so the directory is deleted and recreated (`:109-112`).
>   - **Failed publication:**
>     - A failure before the guest commit is imported into the cache discards the directory but keeps the lock (`src/host_push.rs:1150-1156`; `src/host_push_cache.rs:149-155`).
>     - After import, the cache is kept so LFS data isn't transferred again on retry (`src/host_push.rs:1150-1153`).
>   - **Release:**
>     - The `.active` marker is removed unless the cache was discarded. The lock is released explicitly, then the root is swept.
>     - Cleanup errors are ignored: "Cache cleanup must not relabel a successful remote ref update as a failed push" (`src/host_push_cache.rs:160-178`).
>   - **Budget:** 2 GiB across repositories (`:17`), enforced at every acquisition and release (`:113`, `:175-177`):
>     - a cache whose lock is held is counted but never evicted;
>     - an idle cache over the budget by itself is removed;
>     - otherwise idle caches are evicted least recently used first, by the `.last-used` mtime, until the total fits;
>     - lock files left by removed caches are deleted (`:202-298`).
>   - **Errors:**
>     - "Could not prepare the private publishing cache." (`:18`);
>     - "The publishing cache contains a symbolic link. Remove this cache before retrying." (`:181-200`).

---

## P1. Automatic ChatGPT preparation — CONFIRMED

**Silo.** All cited lines check out in `src-tauri/src/chatgpt_app/auto.rs`:

- `START_DELAY` = 10 s: `:13-14`.
- `delay_for`: 30 s, 1, 2, 5, 10, 30 min, then hourly (`:16-25`).
- `settle`:
  - stops on `retryable: false` (`:42-46`);
  - a wake resets the failure count (`:51-53`).
- One worker per process: `Slot`/`Claim` (`:59-107`) and `Wake` (`:110-136`).
- `lower_priority`: utility QoS on macOS, nice 10 on Linux (`:138-152`).

And in `src-tauri/src/chatgpt_app.rs`:

- `ensure_in_background`: `:2173-2205`.
- `retry_now`: `:2212-2222`.
- `start_automatic`: `:2223-2238`.

The doc is `docs/SiloUI-CHATGPT-APP.md`, "Automatic preparation", lines 155-180.

**Spec.** §20 §4.1 says "has its own worker and status". §20 `preparation.chatgpt.retry` says "wakes the worker". None of the schedule is specified (searched for "hourly", "backoff", "START_DELAY", "QoS").

**Add to `20-checkpoints-exports-preparation.md`**, under `preparation.chatgpt.retry`, or as its own entry next to M1's:

> #### Engine behaviour: automatic ChatGPT app preparation
> - **Status:** EXISTS. It is started by `computer_use::install` on a background thread (`src-tauri/src/computer_use.rs:1743` → `chatgpt_app::start_automatic`, `src-tauri/src/chatgpt_app.rs:2223-2238`).
> - **At engine start:**
>   1. It reads the status (the first full digest of the process happens here).
>   2. It collects unused versions (M1).
>   3. If the pinned version is published, it reconciles computer use in running computers and stops.
>   4. Otherwise it waits 10 s and starts the worker (`chatgpt_app.rs:2225-2238`; `chatgpt_app/auto.rs:13-14`).
> - **One worker per process:**
>   - An in-process slot means a second start only wakes the running worker (`auto.rs:59-107`; `chatgpt_app.rs:2177-2180`).
>   - `PREPARING` covers a second caller in the same process (`chatgpt_app.rs:1942`, `:2142-2154`).
>   - `ensure` also holds a cross-process `flock` on `<root>/.lock` (`docs/SiloUI-CHATGPT-APP.md` "Behavior", lines 26-27).
> - **Priority:** the worker thread lowers itself to utility QoS on macOS, or nice 10 on Linux. The unpacking tools inherit it (`auto.rs:138-152`; called at `chatgpt_app.rs:2185`).
> - **Schedule** (`auto::settle`, `auto.rs:27-57`):
>   - **ready:** run the ready hook once and stop. The hook applies computer use in running Linux computers and collects garbage (`chatgpt_app.rs:2196-2200`).
>   - **failure retrying can't fix:** stop. These are a hash mismatch, or a pinned version OpenAI no longer serves (`retryable: false`, `auto.rs:42-46`).
>   - **retryable failure:** network, firewall, disk space, or another run in progress. Wait, then try again: 30 s, 1 min, 2 min, 5 min, 10 min, 30 min, then hourly (`auto.rs:16-25`). The failure stays the reported status meanwhile (doc lines 168-172).
> - **Retry** (`preparation.chatgpt.retry`):
>   - It wakes a waiting worker, which resets the schedule to its first delay (`auto.rs:51-53`, `:123-135`).
>   - It starts a new worker if none runs and the app isn't ready (`chatgpt_app.rs:2212-2222`).
>   - A Retry that races a terminal failure either keeps the worker running or claims its successor (`auto.rs:64-81`).
> - **Nothing waits for it:** creation, start and restore need only the (possibly empty) `published/` folder (doc lines 175-180).

---

## P2. Log credential filtering — CONFIRMED

**Silo.** All cited lines check out:

- `Redaction`, the PEM state keyed by `(stream, execution session)`: `src-tauri/src/runtime_logs.rs:106-151`.
- Filtering happens in `scan` before indexing (`redaction.apply`, `:376`).
- Matching then runs on the filtered body (`Index::add` → `filter.matches`, `:913`).
- Context and page reads restart from the record's stored `in_pem` (`:452-456`).
- The line filter is `runtime_activity::log_text_with_pem` (`src-tauri/src/runtime_activity.rs:490-529`), with:
  - `sensitive_assignment`: `:416-431`;
  - `credential_url`: `:433-456`;
  - `sensitive_option`: `:458-484`.
- Doc: `docs/SiloUI-LOGS.md` lines 126-158.

Codex calls this "Activity filtering". The functions live in `runtime_activity.rs` but serve Logs directly.

**Spec.** §10 `logs.query` and `logs.export` list params, paging and retention, with no filtering. The only mention is "filtered like Logs" in §10 "Failure reporting fields".

**Add to `10-computers-lifecycle.md`**, `logs.query` (and referenced from `logs.export`):

> - **Sensitive-output filtering** (EXISTS; it runs in the engine before any search, context, page, Follow or export result leaves it; `docs/SiloUI-LOGS.md` lines 126-158):
>   - **Hidden lines.** Each line becomes `[Sensitive runtime output hidden]` when it does any of the following (`src-tauri/src/runtime_activity.rs:490-529`):
>     - lies inside a PEM block, from a line containing `-----begin` through the line containing `-----end`;
>     - contains a secret-looking assignment, `secret|token|key|passw|credential` followed by `:` or `=` (`:416-431`);
>     - carries a credential option: `-u`, `--user`, `--proxy-user`, or a long option with a part `password|passwd|passphrase|token|secret|key|credential(s)` (`:458-484`);
>     - contains a URL with user information, or a query parameter that is a signature (`sig`, `signature`, `x-amz-signature`, `x-goog-signature`) or matches an assignment marker (`:433-456`);
>     - contains `authorization`, `bearer `, `ghp_`, `ghs_`, `ghu_`, `ghr_`, `github_pat_`, `private key`, `environment:` or `"env"`.
>   - ANSI and other control sequences are stripped first (`strip_ansi`, `:372`).
>   - **PEM state crosses records:**
>     - It is kept per `(stream, execution session)` while scanning segments oldest first (`src-tauri/src/runtime_logs.rs:106-151`).
>     - Each indexed match stores its initial PEM state, so a page, a context window, Follow or an export that starts inside a block still hides it (`:913-925`, `:452-456`).
>     - An unterminated block stays hidden to the end of that session's retained output.
>     - The open-session table counts against the 128 MiB index budget. Exceeding it fails the search with "This search has too many matches…" instead of exposing the rest of a block (`:140-145`, `:940`).
>   - **Search runs on filtered text** (`:376`, `:913`), so searching for a hidden value finds nothing.
>   - Filtering runs after the runtime has persisted the logs. It is not a guarantee: "Review exports before sharing them" (doc lines 139, 157-158).

---

## P3. Malformed and oversized log records — CONFIRMED

**Silo.** All cited lines check out in `src-tauri/src/runtime_logs.rs`:

- `RECORD_LIMIT` = 1 MiB, `TRUNCATED_TEXT` = 64 KiB, and the truncation suffix: `:176-181`.
- `read_record`, `skip_line` and `truncate_text`: `:183-227`.
- `Decoded.estimated` / `unreadable`: `:236-242`.
- `decode`, with its placeholders: `:243-320`.
- In `scan`: oversized-line handling (`:358-368`) and the unterminated `exec` stop (`:369-372`).
- Page fields: `:48`, `:55`.
- Doc: `docs/SiloUI-LOGS.md` lines 99-106.

**Spec.** §10 `logs.query` returns `unreadableRecords?` and `timestampEstimated`, but the rules that set them aren't stated.

**Add to `10-computers-lifecycle.md`**, `logs.query`:

> - **Damaged and oversized records never fail a query or an export** (EXISTS; `src-tauri/src/runtime_logs.rs:243-320`; `docs/SiloUI-LOGS.md` lines 99-106):
>   - **Reading:** a record is read up to 1 MiB + 1 byte. The rest of an oversized line is skipped to its newline (`RECORD_LIMIT`, `:176-219`).
>   - **`exec` records** (JSON lines):
>     - Over 1 MiB → placeholder `[Execution log record over 1 MiB omitted]`.
>     - Not valid JSON, or no `d` field → placeholder `[Unreadable execution log record]`.
>     - `e: "b64"` → body `[Binary runtime output]`, a readable record.
>     - A missing `t` → the segment's file time, marked estimated (`:258-281`).
>   - **An unterminated `exec` record** is not a record. Scanning stops before it, and Follow reads it again once it is complete (`:369-372`; doc lines 84-85).
>   - **`boot-error`:** unreadable, or over the limit → placeholder `[Unreadable boot failure record]` (`:282-293`).
>   - **Console streams** (`runtime`, `kernel`):
>     - Over 1 MiB → the first 64 KiB plus ` … [record over 1 MiB truncated]`, marked unreadable (`:176-181`, `:220-227`, `:294-318`).
>     - A time is parsed from the first word. Otherwise the file time is used, marked estimated.
>     - A time parsed from `kernel` output was chosen by the guest, and is returned as `guestTimestamp` (`:306-312`).
>     - Unterminated console chunks stay searchable (`:369-370`).
>   - **Placeholders** carry `source` `system` (exec) or `runtime` (boot), and the file time, marked estimated (`:247-256`).
>   - **Page flags:** `timestampEstimated` is set when any returned record has an estimated time. `unreadableRecords` is set when any record was a placeholder or truncated (`:48`, `:55`, `:485-487`). Export coverage reports `unreadableRecords` too (doc lines 103-104).

---

## P4. Working-account preparation and legacy migration — CONFIRMED

**Silo.** All cited lines check out:

- `src-tauri/src/working_account.rs`:
  - the module doc: `:1-8`;
  - the `CHECK` script: `:15-20`;
  - the 30-minute limit: `:24-26`;
  - `prepare`: `:39-65`.
- `src-tauri/guest/working-account.py`:
  - `POLICY`, `RECORD`, `HOME`: `:22-24`;
  - `conflict`: `:64-65`;
  - `copy_home` preflight: `:124-164`;
  - `set_up`: `:223-285`, with the record written last at `:284-285`.
- Doc: `docs/SiloUI-WORKING-ACCOUNT-MIGRATION.md`, "At the first start", lines 8-29.

One correction to Codex: UID/GID collisions are **refused**, not handled: "The reserved account ID 1001 belongs to another account." (`working-account.py:238-244`).

**Spec.** §10 `computers.start` Semantics, step 3, says only "The working account is prepared…". §70 `guest.account` has the error `accountNotMigrated`, with no rule behind it.

**Add to `10-computers-lifecycle.md`**, `computers.start`, replacing step 3 with a pointer to this entry. Add the entry under "Engine behaviours without a command":

> #### Engine behaviour: working-account preparation after each boot (Linux)
> - **Status:** EXISTS (`src-tauri/src/working_account.rs:39-65`; called after boot at `runtime.rs:1248-1271`).
> - **Check:** `msb exec --user root --no-start` reads `/var/lib/silo/working-account.json` and prints one of three results (`working_account.rs:15-20`, 30 s limit):
>   - `ready`: the record equals `{"schemaVersion":1,"user":"silo","home":"/home/silo"}`;
>   - `missing`: there is no record;
>   - `unknown`: the record is anything else. The start then fails with "<name> records an account layout this version of Silo does not know. Update Silo, then start it again." (`:51-56`).
> - **Setup**, when `missing`:
>   - It runs `guest/working-account.sh` + `working-account.py` as root, as a visible gate step "Setting up the silo account in <name>", bounded by 30 min (`working_account.rs:24-26`, `:57-64`).
>   - On failure the computer is stopped again, so a running computer always has its account (`runtime.rs:1248-1271`).
> - **Refusals before any change** (`guest/working-account.py:223-249`):
>   - not root on Ubuntu 24.04;
>   - missing account tools;
>   - `/workspace` not the standard ext4 disk;
>   - both `silo` and `silo-desktop` exist;
>   - UID or GID 1001 belongs to another account;
>   - `/home/silo` is a link, not a folder, or exists without its account;
>   - an old `silo-desktop` account with an unexpected layout.
> - **Migration steps.** Each step checks what an interrupted earlier run already did (`guest/working-account.py:250-285`; doc "At the first start", lines 8-29):
>   1. Stop the managed desktop, then rename `silo-desktop` to `silo`. Otherwise create `silo` (UID/GID 1001, `/bin/bash`).
>   2. Copy `/root`, then `/home/silo-desktop`, into `/home/silo` (`copy_home`, `:124-…`):
>      - the whole merge is preflighted first;
>      - credentials are kept byte for byte;
>      - absolute home symlinks and launch scripts are relocated;
>      - root dotfiles identical to the distribution defaults are skipped, and so are sockets and FIFOs;
>      - any differing existing entry is a conflict, and the setup stops with "Home migration conflict at <path>. Preserve or move the conflicting entry and retry; legacy homes are unchanged." (`:64-65`).
>      - Nothing is deleted (doc "Nothing is deleted").
>   3. Give `silo` its home, and `/workspace` without crossing mounts or following links (`:272-274`). Install passwordless sudo and the desktop service files if the desktop is installed. Verify as `silo` that the home and `/workspace` are writable, `sudo -n` works and `sftp-server` exists (`:275-283`).
>   4. Write the record last, atomically (`:284-285`), so an interrupted setup finishes at the next boot.
> - **The record lives on the computer's disk,** so restores, forks and imports carry it (`working_account.rs:7-8`).
> - **API surface:**
>   - progress through the operation queue and lifecycle failure reporting;
>   - §70 `guest.account`'s `accountNotMigrated` is the `missing` or `unknown` state of this check.

---

## P5. Selected-folder editor handoff lacks `path` — PARTLY

**Silo.** All cited lines check out:

- The UI passes the folder: `src/features/application/components/computer-file-tree.tsx:51`, `:139` → `FolderActions` (`folder-actions.tsx:20-25`).
- The tauri `computer_action` takes `path: Option<String>` (`src-tauri/src/runtime.rs:3255-3270`).
- `editor::open`: `src-tauri/src/editor.rs:32-104`, with:
  - `validate_path`: `:154-166`;
  - `test -d` as `silo`: `:61-85`;
  - the BatchMode probe: `:88-99`.
- Remote: `guest.prepare` requires `path` and validates it the same way (`src-tauri/src/remote_access.rs:68-87`; `editor.rs:672-707`).

**Spec.**

- §50 `guest.sshAlias.ensure`: Params `computer`, `installInclude?`. The "Launchers" prose says the checks "belong in `guest.sshAlias.ensure` with an optional `path`".
- §70 `guest.sshAlias.ensure`: Params `computerId` only.
- **Already proposed:** §80 N10 gives the merged params as `{computerId, deviceId?, installInclude?, path?}`.

So the missing parameter is already caught. What's missing everywhere is the rule and the errors.

**Add to the consolidated `guest.sshAlias.ensure`** (owned by `50-access-network-files.md` per §80 N10), in the brief's format:

> - Params (add):
>   - `path?: string` — the guest folder the client will open.
>     - Default `/workspace`, as `editor::open` uses for local and remote computers (`src/editor.rs:34`, `:46`).
>     - It must be `/workspace` or `/workspace/<segments>`: at most 4,096 bytes, no control characters, no empty, `.` or `..` segment (`validate_path`, `src/editor.rs:154-166`).
> - Errors (add):
>   - "Choose a folder inside /workspace with no control characters." (`src/editor.rs:163`);
>   - "This folder is unavailable inside the computer.": `test -d <path>` failed as the working account, with a 5 s limit (`src/editor.rs:61-85`). For remote computers the owner runs the same check in `guest.prepare` (`src/editor.rs:672-707`);
>   - "Could not connect to this computer over SSH. Retry after checking that it is running.": the probe `ssh -F <config> -o BatchMode=yes -o ConnectTimeout=5 <alias> true` failed within 10 s (`src/editor.rs:88-99`).
> - Semantics (add): the path check and the probe run only when `path` is given. Without `path`, the method only writes the alias, as §70's Fjord use needs.

The last line is a design choice, not a Silo fact. Today `open` always checks, with `/workspace` as the default. Mark it as the spec's proposal, or drop it and always check.

---

## P6. Host Push LFS publication order — CONFIRMED

**Silo.** All cited lines check out:

- `publish_committed_tracking`: `src-tauri/src/host_push.rs:863-1014`.
  - Non-fast-forward check before the LFS transfer: `:948-951`.
  - Source fetch, `git lfs fetch --all silo-source refs/silo/push` over pure SSH: `:959-978`.
  - First `git lfs push`: `:980`.
  - Terminal `CANCELLED` / `CREDENTIAL_EXPIRED`: `:981-986`, constants at `:350`, `:353-354`.
  - The single upstream `lfs fetch --all origin` and retry: `:987-1002`.
  - The Git push, only after that: `:1003-1013`.
- Doc: `docs/SiloUI-GITHUB-IMPLEMENTATION.md` lines 454-470.

**Spec.** §50 `push.start` describes the claim, journal, scope, token and "The transfer fetches from the guest's upload-pack over a private OpenSSH connection". It never mentions LFS. Its Sources line cites the doc range, but the body states none of these steps.

**Add to `50-access-network-files.md`**, `push.start` Semantics:

> - **Publication order** (EXISTS; `src/host_push.rs:863-1014`; `docs/SiloUI-GITHUB-IMPLEMENTATION.md` 454-470):
>   1. **Capture.**
>      - The guest pins the confirmed commit in a temporary ref. It fails with `TARGET_CHANGED` if the branch moved or `origin` no longer names the confirmed repository.
>      - The guest's LFS media directory is exposed read-only through `git-lfs-transfer`, in an operation directory (`:1079-1124`).
>   2. **Fetch into the private cache** (M3). The fetched commit must equal the confirmed one: "The computer repository changed during export. Retry the push." (`:888-902`).
>   3. **Check the remote.** Read the remote branch. If it exists, refuse a non-fast-forward before transferring LFS: "The remote branch has commits missing from this computer. Fetch and integrate them before pushing." (`:911-951`). If it doesn't, count commits against the remote default branch.
>   4. **Fetch LFS from the source.** `git lfs fetch --all` from the guest over pure SSH, so objects referenced only by historical commits are included (`:959-978`). Its failure is not fatal by itself.
>   5. **Upload LFS.** `git lfs push origin`.
>      - Cancellation, or an expired credential, ends the push at once (`:980-986`).
>      - Any other failure allows exactly one `git lfs fetch --all origin` to recover pruned historical objects, then one more `git lfs push`. That error reports the source, upstream and first-upload results (`:987-1002`).
>      - Incomplete LFS pushes are never enabled.
>   6. **Push the ref.** A non-force `git push --porcelain origin refs/silo/push:refs/heads/<branch>`, only after Git LFS succeeded (`:1003-1013`).
>   7. **Record.** Update the guest's tracking ref to the published commit, only if the guest hasn't fetched newer data or repointed `origin` meanwhile (`:1157-1170`). This step can't be cancelled.

---

## P7. Secret startup recovery — CONFIRMED

**Silo.** `secrets::install` (`src-tauri/src/secrets.rs:903-933`) does the following:

- It sets the store path.
- On a thread it takes the module's operation lock (`OPERATION`, `:19`), then:
  - deletes from the credential store the value of every secret still marked `removing` (the legacy removal format), before any slow live update;
  - reconciles every surviving secret with non-empty `affected`;
  - releases the lock;
  - calls `schedule_revocations`;
  - emits `silo://application-state-changed`.

The lock is the secrets module's own mutex, not the device gate.

**Spec.** §50 `secrets.*` "Background" says only "`secrets::install` runs at startup". §05 §7 lists "secrets" as step 8.

**Add to `50-access-network-files.md`**, replacing the `secrets.*` "Background" bullet:

> - **Background (an engine duty). Startup recovery** (EXISTS, `src/secrets.rs:903-933`, started at `src/main.rs:305`), on its own thread, under the secrets operation lock (`OPERATION`, `src/secrets.rs:19`):
>   1. **Legacy removals first.** Any secret still marked `removing` has its value deleted from the credential store. This happens before any slow live update can wait on a computer (`:915-918`).
>   2. **Unfinished assignments.** Every other secret with a non-empty `affected` list is reconciled again: live update, or `restart-required` (`:919-925`; `reconcile`, which waits on each computer's gate and releases the global lock while it waits, `:540-646`).
>   3. **Pending revocations.** The lock is released, then the background revocation pass is scheduled (`schedule_revocations`, `:752-780`). See D7 for its retry rule.
>   4. **Notify.** A state change is emitted (`:929`), the future `secrets.changed`.

Also add to `05-engine-architecture.md` §7, step 8: "secrets (startup recovery, §50 `secrets.*` Background)".

---

## C1. Protocol equality presented as release equality — CONFIRMED

**Silo.**

- `VERSION: u32 = 5` is the "Bridge protocol version" (`src-tauri/src/remote.rs:34-36`).
- `validate_authorization` compares only `request["version"]` with `VERSION`, then the device id (`:2161-2184`).
- The application version appears only as `appVersion` in the `incompatible_version` reply (`:571-574`; `src-tauri/src/bridge_error.rs:17-24`).
- Releases sharing protocol 5 are expected to interoperate. Silo probes the owner's `capabilities` (`remote.rs:1217-1244`) and turns `unsupported_remote_operation` into "Update Silo on that device to use computer use." (`chatgpt_app.rs:2260-2268`). These paths only make sense between different releases on the same protocol.

**Spec.**

- §05 §G "Today": "Versions must match exactly (`remote.rs:2166-2178`), so 'both devices must run the same Silo version'". The quote is from `docs/SiloUI-CONNECTIONS.md` line 103, which itself overstates the code.
- §60 Open question 9: "an update on one device breaks Connections until the other device matches".

**Replace in `05-engine-architecture.md`**, §G "Today", the first bullet:

> - The bridge **protocol** version must match exactly. Today it is 5 (`src-tauri/src/remote.rs:34-36`, checked at `:2166-2178`).
>   - The check doesn't compare application releases. A mismatch is refused with `incompatible_version`, whose reply also carries `version` and `appVersion` (`remote.rs:571-574`).
>   - `docs/SiloUI-CONNECTIONS.md` line 103 says "both devices must run the same Silo version". That holds only when two releases differ in protocol version.
>   - Different releases on protocol 5 interoperate. Missing methods are found through the handshake `capabilities` (`remote.rs:1217-1244`) and reported as `unsupported_remote_operation`, for example "Update Silo on that device to use computer use." (`chatgpt_app.rs:2260-2268`).

**Replace in `60-connections-settings-services.md`**, Open question 9, the bullet on the exact match:

> - The bridge's exact **protocol** match (`remote.rs:2166-2178`) means an update that changes the protocol version breaks Connections until the other device matches. An update within protocol 5 doesn't. Its new methods are reported as unsupported by older owners.

---

## D1. Screen lock and proof recordings — PARTLY

**Holds:**

- The brief requires both (`00-brief.md` "One GUI driver at a time", "Proof").
- §40 §5 ends "No NEW methods are specified for them here".
- §70 §5 lists what Fjord needs, with no method.

Codex's Silo evidence is accurate:

- `guest_screen.rs:1-8`: only stills of Silo's own window.
- `desktop_proxy.rs:378-397`: opaque WebSocket relay.
- `docs/SiloUI-DESKTOP-VIEWER-DIRECTION.md:11-14`: no input leases.

**Already in the spec:**

- §40 OQ 9 ("Screen lock") and OQ 10 ("Recordings as proof") set out the options with sources.
- §80 A-8 and A-9 list both as owner decisions.

Calling the gap a blocker is fair, but the spec doesn't overlook it.

**Decision statement** (for §80 A-8/A-9; to be settled before §40 can specify methods):

> **D-lock. Where the one-driver lock lives.**
> - **A. Advisory engine lease** (`computerUse.lease.acquire | release | state`, holder label set by the client, released when its job ends or its client disconnects).
>   - Every client and controller reaches the engine.
>   - It can't stop Selkies input from another viewer, or LCU input in the guest, because the proxy sees opaque WebSocket bytes (`src-tauri/src/desktop_proxy.rs:378-397`).
>   - On macOS the engine owns the native window, so it can drop human input there. Setup already does this while typing into Recovery (`docs/SiloUI-MACOS-COMPUTERS.md` 324-332).
> - **B. Enforcement in the guest, or in LCU.** Blocks input for real. It needs an LCU feature and a Selkies input gate that don't exist (§40 §5).
> - **Either way:** it reverses `docs/SiloUI-DESKTOP-VIEWER-DIRECTION.md:11-14`. The decision must say which input paths obey the lock (human viewer, other agents, controllers) and how it is cleaned up after a job ends or a client disconnects.
>
> **D-record. Where proof recordings are produced.**
> - **A. Engine.**
>   - On macOS, record the engine-owned `VZVirtualMachineView` window. Silo already captures that window without Screen Recording permission (`src-tauri/src/macos_computers/guest_screen.rs:5-8`).
>   - On Linux, either decode the relayed Selkies stream, or run a recorder in the guest on display `:1`. The image installs `ffmpeg` (`guest-image/Dockerfile:55`), but capturing `:1` is unproven.
> - **B. Fjord** records its own viewer window. This doesn't work with no viewer open, while agents must work without one (`docs/SiloUI-DESKTOP-VIEWER-DIRECTION.md:175-179`).
> - **Then:** a job-scoped `start / finish / fetch` contract tied to the D2 job id.

---

## D2. Unified jobs vs the operations contract — PARTLY

**Holds:**

- §05 §E/§F give `jobId: string` and route all cancellation through `operations.cancel {jobId}`.
- §10 `operations.cancel` takes `id: u64` and treats an unknown id as success (`src-tauri/src/runtime/operation_gate.rs:1036`, `:1052-1054`).
- §70 `guest.exec.start` uses string job ids.

Codex's evidence is accurate:

- The gate id is a process-local counter: `self.next_id += 1` (`operation_gate.rs:249`). Ids restart with the process.
- Transfers cancel by `transfer_id` (`transfer.rs:1482-1496`).
- Log export cancels by a generation counter (`log_export.rs:73-78`).
- macOS work keeps its own `operation` on registry entries (`macos_computers.rs:327-331`).

**Already in the spec:** §80 N11 lists the same three facts: id type, jobs outside the gate, and the payload union. §80 A-9 makes ids for non-gate jobs an owner decision.

**Codex adds:**

- **Owner device and engine lifetime:** which engine holds the registry for remote jobs, and whether ids survive an engine restart.
- **Unknown ids:** whether `operations.cancel` of an unknown id may stay `Ok`, once ids identify long-lived `guest.exec` jobs that a client re-attaches to.

**Decision statement** (add to §80 N11):

> **D-jobs. One job registry.**
> - **Identity:** a string `jobId` minted by the engine that owns the work. A gate entry exposes its `u64` in decimal (§80 N11 fact 1). Jobs outside the gate (transfers, log export, GitHub connect, export inspection, macOS work, `guest.exec.start`) get an id from the same registry.
> - **Lifetime:** pick one.
>   - (a) Process-local, like the gate counter today (`operation_gate.rs:249`). A restarted engine reports `lost`, as §70 `guest.exec.get` already allows.
>   - (b) Persisted, like push journals (`host_push_operations.rs:96-103`). After a restart, unfinished jobs read `unknown`.
> - **Remote jobs:** the owner device mints and holds the id. A controller addresses it as `(deviceId, jobId)`, as push already does with its journalled `operationId` (§50 `push.start`).
> - **Cancel of an unknown id:** keep `Ok`, which is idempotent and matches today's gate. Or return `not_found` for registry jobs, so a client can tell "already finished" from "wrong id". The second needs retained results (§70 `guest.exec.get`).
> - **Adapters:** `files.transfer.cancel`, `logs.export.cancel`, `exports.cancel`, `exports.inspect.cancel` and `github.connect.cancel` stay as wire aliases (§80 N11 proposal). Each maps a `jobId` to its existing mechanism.

---

## D3. Shared methods with incompatible schemas — PARTLY

**Holds.** All three conflicts are real in the section files today:

- `guest.exec`: §30 takes `command` and `maxStdoutBytes` and returns `{status, stdout, stderr}`, from `CommandOutput` (`guest_access.rs:36-41`). §70 takes `argv`, `cwd`, `env`, `as` and `maxOutputBytes` and returns `exitCode` and `truncated`.
- `guest.sshAlias.ensure`: §50 vs §70, as Codex lists.
- Error codes: §70's camelCase codes against `ErrorCode` (`bridge_error.rs:4-15`).

**Already in the spec:** §80 resolves each one as a proposal:

- N19 "`guest.exec` (30 vs 70)": use §70's shape for both platforms;
- N10: one `guest.sshAlias.ensure`, owned by §50, with a union result;
- N17: codes in snake_case; new codes as a decided extension of `ErrorCode` (A-10), `internal` until then.

**Nothing new to add.** The remaining work is to apply N10, N17 and N19 to §30, §50 and §70. When applying N10, add P5's `path` rules.

---

## D4. macOS and controller credential workflows — PARTLY

**Holds:** the brief requires GitHub and secrets in Computers, and controllers on other Macs. The mechanisms are still open. Codex's evidence is accurate:

- `secrets_runtime.rs:56-58`: the msb placeholder spec;
- `macos_computers/engine.rs:485-486`: VZ NAT;
- `github.rs:2589-2600`: the loopback callback;
- `runtime.rs:13110-13132`: local Linux computers only.

**Already in the spec**, with options and what settles each:

- §50 Q1: connect from a remote or headless engine;
- §50 Q5 and Q6: GitHub and secrets in macOS guests;
- §50 Q7: secret values across devices;
- §80 A-15, A-16 and A-17.

Codex adds no fact or option. Its point is that these block Fjord's Computers tool, which §80 could state.

**Decision statement** (add the blocking note to §80 A-15 to A-17):

> **D-cred.** These three decisions block "access to GitHub and secrets" in Fjord's Computers tool for macOS computers and for controllers (`00-brief.md` lines 19, 25). They should be settled before §50 specifies `github.*` and `secrets.*` for those cases:
> - (1) GitHub connect from a headless or remote engine (§50 Q1): forward the loopback callback over the existing SSH connection, enable Device Flow on the App, or connect only where a browser runs.
> - (2) macOS guest credentials (§50 Q5/Q6): a host-side intercepting proxy for VZ NAT guests, or real restricted tokens in the guest. Real tokens drop the verified "Real bearer tokens were absent from guest environment/Git configuration" (`docs/SiloUI-GITHUB-IMPLEMENTATION.md` 206-207).
> - (3) Secret values across devices (§50 Q7): send values over the SSH bridge, or keep values on the owner and accept edits only there.

---

## D5. Linux viewer sharing between clients — PARTLY

**Holds:**

- `claim_viewer` reserves one viewer per computer (`src-tauri/src/desktop_viewer.rs:126-140`).
- Detaching is keyed by the calling window's label (`:715-729`).
- §40 `display.viewer.open` is "idempotent per computer: an existing healthy connection is returned".
- §40 `display.viewer.close {connectionId}` "drops the proxy and tunnel".

So under the spec as written, Fjord and the Tauri client opening the same computer get the same `connectionId`, and either one's close tears down the other's viewer. Codex is right that this is undefined, and the consequence is concrete.

**Already in the spec:**

- §40 OQ 3, "Several clients on one computer: share the connection or get its own?";
- §80 A-24 lists it among smaller decisions.

**Decision statement** (sharpen §40 OQ 3, and move it out of §80 A-24 because it changes `display.viewer.close`):

> **D-viewer.**
> - **A. Shared connection with per-client attachments.**
>   - `display.viewer.open` returns the computer's connection and a NEW `attachmentId` for the calling client. `close` releases that attachment. The proxy and tunnel drop when the last attachment goes, or when its client disconnects.
>   - Resize, clipboard and sound state stay per connection. The direction says extra viewers must not compete on resize or clipboard (`docs/SiloUI-DESKTOP-VIEWER-DIRECTION.md:172`), so only one attachment may resize.
> - **B. Separate connections per client.**
>   - Lift the one-per-computer reservation (`desktop_viewer.rs:126-140`), with each client getting its own tunnel and proxy.
>   - Needs a Selkies test with two clients (§40 OQ 3), and counts against the 16-viewer cap (`:135-137`).
> - **Under either option:** `close` must never end a viewer another client still uses.

---

## D6. Late clients and engine notices — PARTLY

**Holds:**

- §60 `notifications.notice` moves OS delivery and filtering to clients.
- It leaves buffering to Open question 10.
- §05 `events.subscribe` has no notice snapshot.

**Already in the spec:** §60 OQ 10 and §80 A-4 ("replay of notices fired before any client subscribes").

**The new fact, which Codex states only in passing:**

- Today nothing is lost when no window is open. `notify` emits the event **and** delivers the system notification itself (`src-tauri/src/notifications.rs:124-138`).
- The health watch runs "including while the main window is hidden" (`health_watch.rs:249-251`).
- Startup recovery raises notices before any UI may exist (`startup.rs:187-218`).

So the loss comes from the spec's own change, moving OS delivery to clients, not from Silo.

**Decision statement** (add to §60 OQ 10):

> **D-notices.**
> - **A. The engine keeps the latest notice per key.**
>   - It applies the same replacement rule as clients ("The key replaces earlier notices with the same key", §60). It drops a key on `notifications.cleared` for that computer.
>   - `events.subscribe` (or a NEW `notifications.list`) returns the retained set first.
>   - This keeps today's "nothing is lost" property without OS delivery from `silod`.
> - **B. `silod` keeps delivering system notifications itself, as Silo does today** (`notifications.rs:130-138`). This needs a check that a LaunchAgent may post UserNotifications (§60 OQ 10).
> - **C. Accept the loss.** A client reconstructs failures from state (`lifecycleFailure`, activity) only.
> - **Note:** A and B can be combined.

---

## D7. Read-triggered maintenance — CONFIRMED

**Silo.** Each cited trigger checks out:

- `read_application_state` calls `secrets::schedule_revocations` and plans stopped-log cleanup, at most hourly per stopped computer (`src-tauri/src/runtime.rs:2663-2690`; `LOG_CLEANUP_INTERVAL`, `:2700-2701`). The bridge `runtime.snapshot` calls the same function (`src-tauri/src/runtime/remote_ops.rs:6-11`).
- `revoke_secret` skips a computer whose gate is busy, "retry on a later state refresh" (`runtime.rs:13029-13060`).
- `schedule_revocations` is called only from:
  - that read (`runtime.rs:2671`);
  - `remove_secret` (`secrets.rs:870`);
  - `retry_secret` (`:893`);
  - `install` (`:928`).
  
  A stop clears that computer's records (`secrets::computer_stopped`, `secrets.rs:369-379`, called at `runtime/lifecycle_recovery.rs:214-216`). A busy computer that keeps running waits for the next read.
- `read_network_state` schedules the forward repair (`network.rs:827-836`). Its only caller is `schedule_network_reconcile` (`:729-770`). Desired rules are also reapplied after each start (§50 `network.*`).
- The health watcher uses `health_observations` → `read_application_state_with`, which runs none of these side effects (`runtime.rs:3007-3031`; `health_watch.rs:247-251`).

**Spec.**

- §10 "Engine behaviours without a command" lists "Expired log cleanup" with its read trigger.
- §50 says revocation and port repair run "on each state read" and "on reads".
- §05 replaces polling with pushed events.
- No section says what triggers these once clients stop polling, and §80 doesn't list it.

**Add to `05-engine-architecture.md`**, a new subsection in the event/polling part ("Polling → events"), with pointers from §10 "Engine behaviours without a command" and §50 `secrets.*` / `network.*`:

> #### Engine behaviour: maintenance that today runs on client reads
> Three passes run today only as side effects of a client's state read. A headless or always-on engine must trigger them itself (`00-brief.md` "Linux hosts run the engine without any UI", "An always-on host Mac").
>
> | Pass | Today's trigger | Skips when | Source |
> |---|---|---|---|
> | Pending secret revocations | `read_application_state` (also bridge `runtime.snapshot`); secret remove and retry; startup | The computer's gate is busy: "retry on a later state refresh". A stop clears that computer's records | `runtime.rs:2671`; `secrets.rs:752-780`, `:870`, `:893`, `:928`, `:369-379`; `runtime.rs:13029-13060` |
> | Expired-log cleanup of stopped computers | `read_application_state`, at most hourly per computer; a fresh log search | Its lane is busy (hidden try-lock) | `runtime.rs:2676-2701`; `runtime_logs.rs:639-657` |
> | Forward repair of published ports | `read_network_state`; desired rules are also reapplied after each start | The computer's gate is busy | `network.rs:729-770`, `:827-836`, `:973-984` |
>
> The health watch (`health_watch.rs:242-273`) reads with `read_application_state_with`, which runs none of them (`runtime.rs:3007-3031`).

**Decision statement:**

> **D-maintenance.**
> - **A. Engine timers.** Each pass runs on its own schedule, plus after any event that can unblock it (a computer's gate released, a stop). The current rate limits stay: hourly for logs, one pass at a time each.
> - **B. Hook the passes onto the health watch's loop,** which already runs headless with bounded reads (`health_watch.rs:242-273`).
> - **C. Keep the reads as triggers,** and require every client to read state on a schedule. That fails with no client connected.
> - **Note:** A and B keep today's semantics. Only C needs nothing new.
