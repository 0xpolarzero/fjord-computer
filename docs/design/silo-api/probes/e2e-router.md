# Router "Runs on" end to end (Fjord + silod + Linux computer + Claude Desktop SSH session), 2026-10-15

Follow-up to `e2e-gui.md` item 3 and `guest-plugin.md`. Fjord main `d6db6ec4` plus other agents' commits (`31bcd7f4`, `f879de75`) and my fix `659d849b`. Silo main `3b08abb6` (no change; the signed bundle of the previous run was reused, since its `silod` is built from that same commit). Evidence: `~/silo-probes/e2e-router/evidence/` (texts, `silod.out`); screenshots are the LCU captures quoted by path in the run's transcript. Computer: Silo Dev `e2e-relay` (memory 32 to 8 GiB, restored to 32 GiB, stopped from the Fjord UI). Fjord: the debug binary wrapped as `FjordE2E.app` (`dev.fjord.e2e`), `FJORD_SILO_SOCKET_PATH=~/.silo-dev/engine.sock`, support folder `Fjord Dev`. Claude Desktop 2.31226.1, guest CLI 2.1.295 (Desktop's `ccd-cli`), Opus 5.5.

| # | Item | Verdict |
| --- | --- | --- |
| a | Fjord installs the guest plugin `fjord-guest@fjord-guest`; presence file appears after Send | PASS (see note on dev names) |
| b | AskUserQuestion shows a live card in the Router while the turn is open | PASS after a fix (card with the form and its options) |
| c | Answering in Fjord reaches the session, which continues | PASS |
| d | A normal Router message is delivered into the guest session as the user's message | PASS |

## a. Plugin and presence (PASS)
I removed the guest's plugin, marketplace and `~/.local/share/fjord` first. Then, from Fjord's Router, I tagged the project, chose **Runs on** `e2e-relay` (guest folder prompt, `/home/silo/e2e-proj`) and sent. Fjord reached "Ready in Claude" and the guest then had (`02-guest-after-ready.txt`):
- `fjord-guest@fjord-guest`, version `fjord-guest-2.r9874620c`, user scope, enabled; marketplace `fjord-guest` from `~/.local/share/fjord/router/plugin`; hook files, `relay.key`, `presence/`, `forms/.enabled`;
- `sshConfigs` entry in the Mac's `~/.claude/settings.json` and the `Include` line in `~/.ssh/config` (restored afterwards).
After Open in Claude, "Use this SSH connection?" (already trusted) and Send in Desktop, `presence/<session>` appeared for the new session with `state live` and capabilities `inbox-v1, settings-v1, abort-v1` (`03-guest-presence-forms.txt`). The Router banner went to "Session found in Claude" (state `matched`). So the shadowing fix works end to end: the module loads in a Desktop-launched session.

Note: this repo's main moved during the run (`31bcd7f4`: debug and E2E builds get their own plugin, marketplace, hook script and sshConfigs names). Runs after my rebuild installed `fjord-guest-dev@fjord-guest-dev` and `fjord-dev-form.sh` in the guest; the later items ran on those names (presence and relay `origin.name` read `fjord-guest-dev`). I removed the older `fjord-guest@fjord-guest` copy and its hook entry from the guest so one hook ran.

## b. Live card while the turn is open (PASS after a fix)
First attempt: the card appeared ("Question", while the turn was open) but with no options: "open the session to see the options", and Fjord's `guestPendingForms` held a form with no `toolUseID`. Cause (confirmed): the guest `form-hook.mjs` rereads the transcript to find the call's `tool_use_id`; for a user row whose `message.content` is a plain string (the first prompt) `row.message.content.some` throws, the catch returns no id, so the form never got its `tool_use_id` and `pendingForm(for:)` could not match the card. Reproduced by running the hook's `transcriptState` by hand in the guest (`TypeError: ... .some is not a function`). The Mac hook (Swift) is not affected.

Fix `659d849b` (Fjord main): `blocks(row)` returns content only when it is an array; install version bumped to `fjord-guest-3`; test `guestFormHookFindsTheCallInATranscriptWhoseFirstPromptIsAPlainString` (runs the real module with node; fails without the fix, passes with it; `swift test --filter GuestRouterTests`: 36 passed). After it, the guest form carried `tool_use_id` (`04-guest-forms-after-fix.txt`) and Fjord's Router showed the card with the question "Do you prefer cats or dogs?" and its options Cats, Dogs, Other, Submit, while Desktop still showed the question open.

Observed behaviour, not a bug: a card for a session shown in the frontmost Claude window is held (`watching`) until you leave it; I had to bring Fjord to the front to get the card.

## c. Answer from Fjord (PASS)
Picked Dogs and pressed Submit in the Router card. The guest transcript shows (`05-transcript-answer.txt`): `tool_result "Your questions have been answered: \"Do you prefer cats or dogs?\"=\"Dogs\""`, then the assistant continued: "You picked dogs, which makes sense since they're loyal and always happy to see you." The card showed the answer and cleared.

## d. Normal message (PASS)
Typed "Tell the cat or dog preference question session: reply with exactly the word pong" in the Router; the Router asked "Where should this go?"; I chose the guest session. Fjord's `guestRelayDeliveries` entry reached `delivered` (signed payload) and the guest transcript has the user row (`06-transcript-relay.txt`): `origin {kind plugin, name fjord-guest-dev, asUser true}`, entrypoint `claude-desktop`, followed by the assistant reply "pong". It is the user's message, not a tool result or peer message.

## Other findings
1. **Card layout overflows the window** when the guest project label is long: the label `e2e-relay-test · silo-dev-<id> @ local/<id>:/home/silo/e2e-proj` (by design, `RouterView.routerSessionProject`) makes the Needs you card and the Working row wider than the window, so the Archive button and right edge are clipped. A `lineLimit(1)` plus middle truncation in `ProjectLabel` did not fix it (the row's layout is the cause); I reverted it. Needs a look at the card header layout.
2. **A guest project listed as a Mac project**: after the earlier run, `@e2e-proj` (`/home/silo/e2e-proj`) is offered as a Mac project (from Desktop's session metadata, "Runs on: This Mac"); the Router (Jev) routed the first message to "New session · e2e-proj" and failed with `The file "e2e-proj" doesn't exist`. Guest-folder sessions should not become Mac projects.
3. **Retry after relaunch**: "The guest file client isn't connected for this computer yet" until the Computers page was opened once after launch; the Router's Send/Retry should wait for the engine or connect it.
4. **Settings page**: the Router hook status said "Form hook not installed ... `claude plugin install fjord-dev@fjord-dev` failed: Plugin "fjord-dev" not found in marketplace" for one launch of the dev build (two dev instances had run against the same support folder at that moment).
5. **Hazards of the harness, mine**: LCU `getApp("FjordE2E")` by name launched `/silo-probes/e2e-gui/FjordE2E.app` (an older Fjord without `AppIdentity`, same bundle id as mine); I killed it. It started at 13:37 and ran about 13 minutes against the real `~/Library/Application Support/Fjord` folder (it touched `actions.json` and `forms/`, and the file `state.json` was rewritten at 13:50 while the installed Fjord also runs). Also, the first dev launch re-pointed the user-scope Claude plugin marketplace `fjord` (`~/.claude/plugins/known_marketplaces.json`) at `Fjord Dev/claude-plugin` and reinstalled `fjord@fjord` from it; I restored it: `marketplace remove fjord`, `add ~/Library/Application Support/Fjord/claude-plugin`, `install fjord@fjord`. The shell's `claude plugin list` still shows `fjord@fjord` as "Hook load failed ... hooks expected record" (the plugin uses a `modules` hooks file that this CLI version does not read; Desktop's CLI does). This was already true of the shared plugin and is not mine, but confirm that the installed Fjord's Router still delivers.
6. The previous run's `AppIdentity` change holds for state and socket; the plugin marketplace name was still shared at the time of my first launch (since changed by `31bcd7f4`).

## Cleanup
- `e2e-relay` stopped from the Fjord UI (Save and stop), memory back to 32 GiB. `silod` (pid 61948, started by me) stopped with SIGTERM; my Fjord instances stopped. `msb` of `e2e-relay` not running.
- `~/.claude/settings.json` and `~/.ssh/config` restored from `~/silo-probes/backup/claude-settings.json.20261015-133638` and `ssh-config.20261015-133638` (byte-identical). Worktree `e2e-confirm` and its branch removed (no Silo change).
- Guest left with `fjord-guest-dev@fjord-guest-dev`, the `fjord-dev-form.sh` hook, and a backup of its earlier settings (`~/.claude/settings.json.e2e-router-pre`). A guest hook process for session 1 (below) is gone with the computer stop.
- Claude Desktop sessions I created (project `e2e-proj`, SSH `e2e-relay · silo`), for the owner to archive:
  1. **Color preference question** (`local_9fb03f11-13cb-49fa-bbe9-73e0afcb81ea`, still "Awaiting input": its question was never answered; created 13:41).
  2. **Cat or dog preference question** (`local_5161f311-6a1b-41b1-832d-4804f4edf4fb`, answered, replied "pong").
  The older "Color preference question", "Cat or dog preference" and the previous run's sessions remain from `e2e-gui.md`. Fjord's Router also holds a stale card for session 1.
