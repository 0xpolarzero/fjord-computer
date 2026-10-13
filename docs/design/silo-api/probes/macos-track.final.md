Results are in [macos.md](/Users/polarzero/code/projects/lookout/docs/design/silo-api/probes/macos.md). The VM stopped, the LaunchAgent is unregistered, and the clones and saved state were deleted; 196 GiB was available at the final check.

- B-1 — **CONFIRMED** — Serial-queue VM attached to VZVirtualMachineView on macOS 26.5.
- B-3 — **PARTLY** — Activation policy switched with the window; Dock/Cmd-Tab and login-window behavior weren’t directly observed.
- B-4 — **PARTLY** — NAT SSH/22 connected; guest Screen Sharing/5900 refused the connection.
- B-5 — **CONFIRMED** — VirtioFS mounted with bidirectional file access; no TCC prompt was observed.
- B-7 — **PARTLY** — Measured logical and reported allocated sizes; per-file private bytes weren’t established.
- B-14 — **CONFIRMED** — SFTP subsystem, MaxSessions 10, and OpenSSH 10.3p1 recorded.
- B-19 — **PARTLY** — Listener discovery, SSH forwarding, half-close, and teardown worked; Git/LFS remained inconclusive.
- B-23 — **CONFIRMED** — SSH via `launchctl asuser` reached the console user’s active GUI display.
- B-24 (macOS) — **BLOCKED** — Guest ScreenCapture TCC denied capture without prompting; no recording was retrieved.
- B-30 (macOS) — **PARTLY** — New process restored, resumed, and reconnected SSH; uptime continuity wasn’t established.

Next action: carry the remaining evidence gaps into the spec revision.