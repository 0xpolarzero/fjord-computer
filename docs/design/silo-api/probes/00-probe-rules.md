# Rules for live probes (binding for every probe track)

Context: `docs/design/silo-api/` specifies an API for Silo as an engine, with Fjord as its frontend. Read its `README.md`, `95-decisions.md` and the probe table in `80-coverage-and-consistency.md` §4 (B). Probes settle facts that the spec couldn't settle from code alone.

## Safety

- **The owner's Mac is in use.** Keep focus-stealing GUI work short. Never lock the screen, log out, sleep or reboot. Never change system or security settings (Remote Login, FileVault, firewall, privacy/TCC on the host, login items you didn't create). Never kill apps you didn't start, especially Chrome, Claude or Silo instances already running.
- **Two macOS VMs at most can run on this Mac**, across all tracks. **Each track may run at most ONE macOS VM at a time.** Only the macOS-VM and proxy tracks run one.
- **RAM is 64 GiB.** Give probe VMs at most 8 GiB each. Don't start the existing 32 GiB Linux computers unless the track says so.
- **Disk:** internal disk only; never use external drives (/Volumes/*). Check `df -g /` before anything large. Stop and report if free space falls below 60 GB. Put everything under `~/silo-probes/<track>/`, and clean up VMs and large files at the end (keep small evidence files).
- **Never modify these:**
  - Silo's source in `/Users/polarzero/code/projects/microsandbox-workspaces` (build outputs and caches are fine);
  - Silo's production data (`~/Library/Application Support/org.silo.preview`);
  - the Silo Dev template in `.../org.silo.dev/macos-templates/`. Read it and APFS-clone it (`cp -c`) only.
- **Before editing `~/.claude/settings.json` or `~/.ssh/config`:** copy it to `~/silo-probes/backup/` with a timestamp, make the smallest change, and restore it at the end.
- **Use only synthetic credentials** for secret and proxy tests. Never print real tokens.
- **Anything that would act on an external account** (GitHub OAuth, publishing): don't do it. Report it as needing the owner.

## Evidence

Write results to `docs/design/silo-api/probes/<track>.md`. For each probe ID:

- **Verdict:** CONFIRMED / REFUTED / PARTLY / BLOCKED (and why).
- **Exact commands and code used,** with probe source kept under `~/silo-probes/<track>/src`.
- **Raw output excerpts** and the OS, Silo and MicroSandbox versions.
- **What it changes in the spec:** the section and method or question.

Only report what you observed. Mark anything inferred as INFERRED.
