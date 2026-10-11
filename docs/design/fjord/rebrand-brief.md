# Brief: Lookout becomes Fjord Computer

## What we're doing

Lookout becomes **Fjord Computer**, by Amont Labs (amontlabs.com). It stays **one Mac app**: one download, one updater, one window, one bar. Inside it, the two halves of today's app become **tools** that each user switches on or off:

- **Triage**: the GitHub inbox and CI, which is today's Lookout part: notifications, categories, rules, inbox actions, Done.
- **Router**: one chat above all your Claude Code sessions.

Later tools will be **Diff** (changes across repos) and **Sweep** (developer disk cleanup), so the structure has to welcome a third and fourth tool. The direction is close to an agents-first OS.

Headline: **"The power without the storm."**

## Product rules

- **On first launch, pick your tools.** You choose Triage, Router or both, and can change this later in Settings. What a tool needs appears right below it as soon as it's switched on, on the same screen: GitHub sign-in under Triage, the Jev (TypeSafe) API key under Router, kept in the Keychain as today. Switching a tool off folds its fields away. One screen, super smooth, minimal and beautiful, in the app's existing look: no wizard, no extra steps. Each tool that's on adds its items to the bar, the window's sidebar, Settings and the shortcuts. A tool that's off shows nothing.
- **Each tool works alone.**
  - **Triage only:** the inbox, CI and categories all work. Actions that start a Claude session are hidden; commenting on GitHub and re-running checks still work.
  - **Router only:** no GitHub sign-in is needed. The Router simply has no Triage tools to call.
- **Together, they do more.** A GitHub event can start the right Claude session, and you can set Triage up by talking to the Router (its tools read and change categories, groups, the inbox and settings, and each change is a card you can revert). This link is the pitch, and it's what competitors such as One and AgentDock don't have. It runs only when both tools are on. Today it's spread across `InboxActions`, `ActionEditor`, `RouterLookout` and `RouterMCP`.

## The work

1. **Turn each half into a tool the app can switch on or off.** Define a small module interface: a tool contributes bar items, sidebar pages, a Settings page, shortcuts and its background work. Register Triage and Router through it. The hard part is untangling the files that mix both domains: `Store.swift`, `HubView.swift`, `HubSections.swift`, `HubController.swift` and `SettingsView.swift`.
2. **Put the Triage–Router link behind a check that both are on.** This covers the files listed above.
3. **Add the first-launch onboarding:** one screen with the tools, each tool's sign-ins and keys (GitHub, the Jev/TypeSafe API key) unfolding right below it when it's switched on. Stop requiring GitHub sign-in when only Router is on.
4. **Rename everything to Fjord Computer:**
   - the app name, `Package.swift` targets and executable;
   - the bundle ID (today `dev.polarzero.lookout` in `scripts/build-app.sh`);
   - the release workflow, tags and update feed (`.github/workflows/release.yml`);
   - the data folder (`~/Library/Application Support/Lookout`);
   - Keychain service names;
   - the Claude Code hook and the signed plugin;
   - the README, which also still describes the old session tiles and separate Router window.

   "Lookout" as a product name is gone. Triage is its successor.
5. **Write a one-off migration script for the owner's machine only.** There are no users, so no in-app migration. The script moves the data folder, the preferences domain (old bundle ID to new), the Keychain items (GitHub token, TypeSafe key), and the hook in `~/.claude/settings.json` and the plugin.
6. **Apply the identity** (see below): the app icon, and the one-colour loader for in-app loading.

## Scope and quality

- **Gate, don't redesign.** The UI and UX are well thought through: nothing gets removed, changed or added beyond what switching tools on and off, the onboarding and the rename need. A tool that's off is hidden, not reworked.
- **Don't over-engineer.** The module interface is the smallest thing that lets the bar, sidebar, Settings and shortcuts show only what's on. No plugin system, no abstractions for tools that don't exist yet.
- **Straightforward and clean, with no bloat.** Match the surrounding code. No dead code, no compatibility shims (there are no users).
- **No poor optimizations.** No work done when a tool is off (no syncing, polling or watching for it), and no slower paths introduced by the gating.

Codex reviews catch all of the above, so put every piece through one before committing.

## Identity (settled; see `docs/design/fjord/mark.html`)

- **Look in the app:** already done and committed (`Sources/Lookout/Brand.swift`, the default). It keeps the current app design, with Geist and Geist Mono bundled, neutrals mapped to the studio's ink ramp, and light and dark following the Mac live. `FJORD_THEME=dark|light|claude` pins a look. **Claude's blue stays the app's accent; fonte is not used in the app UI.**
- **The mark is "sun over water, two bands":**
  - a circle cut by a level horizon at 0.55 of its diameter;
  - the sun above, in paper on dark or ink on light;
  - then gap 0.072, band 0.2, gap 0.072, band 0.11, in fonte `#0F9AC3`.
- **Wordmark:** "fjord" in Geist Medium, with the j's dot replaced by a fonte disc.
- **App icon:**
  - default dark (paper sun on an ink tile) and default light;
  - tinted and clear variants strictly in one colour, with the shape carried only by the cuts;
  - no fonte tile, and one mark at every size, with no separate small or menu-bar drawing;
  - still needed: the macOS 26 layered icon (Icon Composer).
- **Loader, for in-app loading, always in one colour:** each part fades out one by one from the top (sun first) to a faint trace (opacity 0.1), then they come back in the same order. The cycle is 2.6 s with smoothstep fades. The reference implementation is `level()` in `mark.html`.
- **The mark never carries status colours.** Needs-you and failed stay in the app's own interface (amber and red).
- **Studio system:** `~/code/projects/amont/brand`, amontlabs.com, silo.amontlabs.com. Start from these, not generic design.

## How to work in this repo

- **Subagents:** split independent pieces across subagents (for example, one untangles `Store.swift` while another writes the migration script), but never two writers on the same files.
- **Review loops with Codex:** after each piece, send the diff to Codex (GPT-6.1 Sol, high reasoning) through the codex-bridge, fix what it finds, and run another round only while it still finds real problems; stop once it only raises minor edge cases. Ask it to check the scope and quality rules above: gating only, no over-engineering, no bloat, no poor optimizations.

- **Work in your own git worktree,** on its own branch cut from `main`, so other agents' work on `main` doesn't disturb you. Do the entire job there and commit each piece on that branch.
- **Come back only when it's ready to merge.** Then report what changed, how it was verified, and anything left open. Merge into `main` only with the owner's approval. Before asking, bring the branch up to date with `main` and make sure the tests pass.
- Make one commit per verified piece, and gate each on `swift test`. Use single test runs only, no stress loads.
- Don't run end-to-end or live-app (LCU) checks unless asked; they steal focus.
