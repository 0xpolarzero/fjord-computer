Implemented and committed the mock-backed Runs on flow on `main`.

- `00ffcdca feat(router): add guest Runs on sessions`
- `75cda324 docs(router): report P4 Runs on implementation boundaries`

The work adds persisted project placement, Claude SSH settings management, guest hook/plugin installation, guest forms and relay helpers, and Desktop deep-link preparation with pending-session matching. **Production use is not ready:** the generated guest client adapter is not connected, multi-owner placement is unsupported, and several guest lifecycle readers and reconnection paths remain incomplete. Details are in the [P4 report](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/p4-runs-on.md).

`swift build --disable-sandbox` passed. The single `scripts/test.sh` invocation stopped before test compilation because manifest sandboxing failed with `sandbox-exec: sandbox_apply: Operation not permitted`; I did not rerun it. Earlier focused test work also lacked a clean pass after concurrent Silo client test changes. Offscreen shots captured the Router shell, but not the Runs on menu; no live guest session was started.

Unrelated concurrent Silo client changes remain uncommitted and untouched. Next action: connect the generated guest adapter and validate one saved project in a disposable Linux guest.