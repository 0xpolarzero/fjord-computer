Appended [Connections (run 2)](/Users/polarzero/code/projects/lookout/docs/design/silo-api/probes/linux.md:291).

- **B-22 — PARTLY:** The pre-update handshake authenticated but failed with `EINVAL`; after the bundle copy and relaunch, the same key completed a v5 handshake.
- **B-10 — BLOCKED:** Upsert and delete returned `EINVAL` without a framed response. Silo and MicroSandbox inventories showed only the original stopped computers; the preparation wait was not measured.
- **B-28 — PARTLY:** Removing offline `devbox` left the probe key line and a separate localhost SSH session intact. No connected peer was available to verify remote key revocation.

**Revert checklist**

- [x] Connections off; `authorized_keys` absent, as confirmed by the pre-run backup sentinel.
- [x] Probe key pair and host key file removed.
- [x] Original `silo-remote` link restored; probe-created `silo-remote-dev` link and copied app removed.
- [x] Silo Dev and the test SSH session quit; original Linux computers remain stopped.
- [x] Remote Login unchanged.

The requested `devbox` controller entry remains removed. Next: resolve the bridge `EINVAL` before repeating B-10’s wait probe.