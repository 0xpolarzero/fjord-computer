# Guest plugin presence in Desktop SSH sessions, 2026-10-15

Follow-up to `e2e-gui.md` item 3 (presence/ stayed empty). Computer: Silo Dev `e2e-relay` (started with the bundle's `msb` directly, no silod, memory 32 to 8 GiB and restored, stopped afterwards). Guest CLI: Desktop's own `~/.claude/remote/ccd-cli/2.1.295-cdb4a4da2c4c` (the sessions' registry entries say `version 2.1.295`, `entrypoint claude-desktop`); the guest's own `claude` is 2.1.287.

## Cause (CONFIRMED)
Claude Desktop syncs the Mac's local plugins into the guest (`~/.claude/remote/plugins/<id>/<hash>/`) and loads them with `--plugin-dir`. The synced copies hold only `.claude-plugin/`, `config.json` (with Mac paths: `/Users/polarzero/Library/Application Support/Fjord/relay.key`, `.../plugin-sessions`, ...) and no `hooks/`. Fjord's Mac plugin is called `fjord`, and so was the guest plugin (`fjord@fjord`). A `--plugin-dir` plugin overrides an installed one of the same name:

```
[DEBUG] Loaded inline plugin from path: fjord
[DEBUG] Plugin "fjord" from --plugin-dir overrides installed version
```

The hookless copy wins, so the guest module (`hooks/register.ts`) never loads, and nothing writes presence. The `PermissionRequest` hook is a plain settings hook, not a plugin, so it still fired.

## Evidence (same ccd-cli binary, run in the guest in `~/e2e-proj` with a synthetic API key, `--debug-file`)
- A, no `--plugin-dir`: `hooks module fjord@fjord loaded (worker ...); events: session.receive,session.start,...` and `$.fs.write (fjord): .../presence/<session> (262 bytes)`. The module works in this CLI; hooks modules and `channelsEnabled` are not involved (the plugin has no MCP or channel server; it is a hooks module only, so there is nothing to start).
- B, `--plugin-dir ~/.claude/remote/plugins/76f4e89d/a48e00241e64d7f9` (the synced Fjord copy): the two lines above, no module, presence/ empty.
- C, after renaming the guest plugin to `fjord-guest` (`fjord-guest@fjord-guest`) and the same `--plugin-dir`: `hooks module fjord-guest@fjord-guest loaded`, presence file written on session.start, renewed at turn start, `ended` on session.end. No override line.

Not captured: the exact command line of the Desktop-launched remote process (the daemon log does not record argv, and the process was gone). `--setting-sources` is therefore not checked; the user-scope plugin does load in the settings. I reproduced the Desktop shape with the synced `--plugin-dir`, not with a new Desktop session (INFERRED that the live Desktop session behaves as C; B matches the observed failure exactly).

Side observations: the guest `~/.claude/settings.json` carries lcu `mcp_tool` hooks and the `lcu-approve` skills-dir plugin from the owner's Mac setup, so settings are not purely the guest's own.

## Fix (Fjord)
- The guest plugin is `fjord-guest` in marketplace `fjord-guest` (`ClaudePlugin.guestName`, `guestID`, `guestMarketplaceJSON`; `pluginJSON(version:name:)`). The Mac plugin keeps `fjord`.
- `GuestRouterInstaller` installs and updates `fjord-guest@fjord-guest`, writes the guest names into `plugin.json` and `marketplace.json`, and on a fresh install first removes the old `fjord@fjord` plugin and `fjord` marketplace (best effort). Install version bumped to `fjord-guest-2`, so existing guests migrate on next setup.
- Test: `GuestRouterTests.guestInstallerWritesGuestOnlyPluginHookSettingsAndPrivateKey` checks the names and the legacy removal.

## Cleanup
e2e-relay stopped, memory back to 32 GiB. The guest was left with the fixed plugin installed (`fjord-guest@fjord-guest`, `fjord@fjord` removed), presence/ emptied, debug files removed. `~/.claude/settings.json` and `~/.ssh/config` on the Mac were not touched. Not done: a fresh Desktop deep-link session (needs the owner's approval panels).
