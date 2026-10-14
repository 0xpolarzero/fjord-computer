Implemented P2-swift-client and committed the generated schema client, Computers model migration, socket transport, tests, and report.

- `swift build` passed on the clean committed snapshot. `scripts/test.sh` passed **1,608 tests across 161 suites**, including the new socket and schema fixture tests.
- The shared working tree contains unfinished Router/Guest changes outside this track. I left them untouched and ran final verification on a temporary archive of committed `main`; the report records the earlier shared-tree build failure.
- Socket selection is opt-in with `--socket-client`; MockEngineClient remains the default. The protocol range defaults provisionally to `1...1` until Silo settles the version.
- Commits: `dec12a9a`, `8adc0265`, `38b5ddff`, `dacfc17f`, `9e49d2a8`, `46d69283`, `cd139334`.

[Implementation report](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/p2-swift-client.md)