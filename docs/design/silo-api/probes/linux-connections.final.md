Appended **Follow-up** and **Connections** to [linux.md](/Users/polarzero/code/projects/lookout/docs/design/silo-api/probes/linux.md:181). The sections have balanced Markdown fences and no trailing whitespace.

- **B-15 — CONFIRMED:** The guest’s `PermissionRequest` hook fired for `AskUserQuestion`; it arrived 5.09 seconds after `SessionStart`.
- **B-16 — PARTLY:** The local transcript copy lagged by about 1.1 seconds, then had a newer mtime while remaining 1,168 bytes smaller. Background-task output was in the guest’s `/tmp/claude-1001/.../tasks/` directory.
- **B-17 — CONFIRMED, with a limit:** Anthropic returned `invalid x-api-key` for the synthetic token, while the non-allowed echo host returned the placeholder unchanged. Because the request included the placeholder in both `Authorization` and `x-api-key`, it did not isolate rewriting of `Authorization`; Anthropic documents the API key requirement in its [Messages API reference](https://docs.anthropic.com/en/api/messages).
- **B-18 — CONFIRMED:** The WKWebView harness loaded the live Silo viewer through its proxy with the real cookie and bridge script; the page returned HTTP 200.
- **B-22 — NOT RUN:** Connections stayed off; no key, forced command, handshake, or bundle-path update test was run.
- **B-10 — NOT RUN:** Silo Dev had no macOS computer to duplicate, and remote creation-wait behavior was not measured.
- **B-28 — NOT RUN:** No device key was created or removed, so key retention and established-session survival were not measured.

Cleanup restored e2e-relay’s memory to 32 GiB and left it stopped. Connections is off; `authorized_keys` remains absent as it was before the probe. The saved SSH and Claude settings matched their backups, PID 73000 was absent, and no probe process remained. Claude Desktop still lists the pre-existing idle **Fjord cloud deployment strategy** session and its fork for the owner to review.

The computer-use policy requires fresh action-time confirmation before enabling Connections and installing a forced SSH management entry. Reply **“Confirm Connections probe”** and I’ll run the remaining Connections work, then turn Connections off and restore the original `authorized_keys` state.