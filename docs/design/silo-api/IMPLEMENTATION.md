# Implementation: Silo engine and Fjord Computers

This is the orchestration tracker, kept by the coordinating agent. The spec is this folder (README → 95 → 05 → 10–70 → 80). Every implementer reads [the implementer brief](#implementer-brief) first.

## Phases and tracks

Silo repo: `/Users/polarzero/code/projects/microsandbox-workspaces`, crate `app/SiloUI/src-tauri` (`silo-ui`). Each Silo track works in its own git worktree under `~/silo-work/<track>` on branch `engine/<track>`. The coordinator reviews (Sol high) and merges into Silo `main`. Fjord tracks work in `/Users/polarzero/code/projects/lookout` on `main` directly; only one Fjord track at a time edits a given file.

### Phase 1: foundation

| Track | What | Depends on | Status |
| --- | --- | --- | --- |
| P1-engine | Pull the backend logic into a Tauri-free engine library crate (`silo-engine`) behind an `EngineContext` (paths, events, main thread, process), per 05 §2. `silo-ui` becomes a thin adapter; all existing tests pass. | — | running |
| P1-api | A `silo-api` crate holding the canonical wire types: request/response envelope, handshake, `JobId` and job progress/finished, the event envelope and catalogue, error codes. JSON Schema generation (schemars), per 05 §4.2 and #job-contract. Types and schema only, no dispatch. | — | running |
| P1-fjord-ui | Fjord: an `EngineClient` protocol plus a mock, a Computers tool skeleton (list, detail, actions) on demo data, and window shots. | — | running |

### Phase 2: the engine process

| Track | What | Depends on |
| --- | --- | --- |
| P2-silod | The `silod` binary: SMAppService LaunchAgent, AppKit run loop, macOS VMs and the engine-owned VM window (95 A-21), `engine.sock` with peer-euid check, request dispatch into `silo-engine`, the handshake. | P1-engine, P1-api |
| P2-jobs-events | Job registry with outcomes persisted until acknowledged, `operations.*`, `events.subscribe` with sequence and resync, notices retained per key. | P2-silod |
| P2-tauri-client | Silo.app talks to `silod` over the socket with the canonical names (no aliases). | P2-silod |
| P2-swift-client | Swift client generated from the schema, replacing Fjord's mock. | P1-api |

### Phase 3: domains (in parallel)

P3-guest (`guest.exec`/`guest.files`/`guest.sshAlias`) · P3-checkpoints (automatic checkpoints, retention, settings) · P3-macos-parity (files, ports, terminal/editor commands, export/import, start at launch, developer tools, queue) · P3-macos-proxy (secrets/GitHub through the FileHandle gateway) · P3-connections (routing through the local engine, revoking keys, GitHub sign-in over SSH) · P3-viewers (one viewer connection per client) · P3-lifecycle (Quit "keep running", engine update save/resume)

### Phase 4: Fjord features

Computers tool, complete · Router "Runs on" (sshConfigs, plugin and hook installed in the guest, delivery over `guest.files`) · Triage "Run in a computer" (headless runs, an automatic checkpoint first, proof recordings) · bundling `silod` and registering the LaunchAgent

## Implementer brief

1. **The spec is the authority.** Read README.md, 95-decisions.md (with §3 amendments; later overrides earlier), 05-engine-architecture.md, and the sections for your domain. When the spec and the code disagree, follow the spec and note it in your report. Where the spec leaves something open, choose the simplest option and write it down.
2. **No legacy:** no backwards compatibility, no old-name aliases, no compatibility paths. The only allowed migration runs at launch through Silo's existing `runtime_migration`. Macs only; no Linux-host code paths.
3. **Commits:** conventional commits (`feat(engine): …`, `refactor(engine): …`, `test(…)`, `docs(…)`), one per atomic, verified piece. Never push. Never commit secrets or `github-build.local.json`.
4. **Verification before each commit:**
   - Silo: `cargo test --manifest-path <worktree>/app/SiloUI/src-tauri/Cargo.toml --locked` (filtered while iterating; full before the final commit), `cargo +1.94.0 fmt --check`, and the npm typecheck, lint and test when UI code is touched (see the repo's AGENTS.md).
   - Fjord: `swift build` and `scripts/test.sh` (one test run at a time, never in loops or in parallel). For UI, the `--window-shots` renders described in lookout's CLAUDE.md.
5. **Resources:** the Mac is shared (64 GiB RAM, about 190 GB free disk). One cargo build at a time per track. Use your own `CARGO_TARGET_DIR` under `~/silo-work/<track>/target`. Don't start VMs, apps or the Claude app unless your track says so; follow `probes/00-probe-rules.md` if it does.
6. **Report:** when done, write `docs/design/silo-api/reports/<track>.md` in the lookout repo. Cover: what was built, the commits (hashes), tests run with results, deviations from the spec and why, and what the next tracks need to know.
