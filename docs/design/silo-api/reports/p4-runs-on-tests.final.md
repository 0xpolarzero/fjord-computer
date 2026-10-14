Found the two affected suites:

- `RouterMCP` failed when shared guest runtime state sent a form operation through the wrong store or client.
- `GuestRouterTests` hung because the stale approval test waited on an account-entry continuation that the runtime race left untriggered.

I isolated the runtime per test tools instance, fixed the relay fixtures, and replaced polling and timed waits in both suites with completion signals. The diagnosis and fix are in [p4-runs-on-tests.md](/Users/polarzero/code/projects/lookout/docs/design/silo-api/reports/p4-runs-on-tests.md).

Verification passed: `RouterMCP` (46 tests), `GuestRouterTests` (34 tests), and one `scripts/test.sh` run: `✔ Test run with 1658 tests in 162 suites passed after 47.569 seconds.`

Committed as `f0c95ffd` (`fix(router): isolate guest runtime and remove test timing waits`). I staged only the eight task files and restored the pre-existing untracked `test.log`; unrelated working tree changes remain uncommitted.