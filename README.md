# Fjord Computer

The power without the storm.

Fjord Computer, by [Amont Labs](https://amontlabs.com), is one Mac app for working with GitHub and Claude Code: a slim bar against the edge of the screen that opens, on hover, into what needs you, and a window behind it. What it does comes from **tools** you switch on or off:

- **Triage**: your GitHub inbox and CI. Pull requests, issues and workflows sorted into categories by your rules, with banners, actions and Done.
- **Router**: one chat above all your Claude Code sessions. What they ask, what they finished, what is still working, and one place to answer them.

Each works alone. Triage alone hides the actions that would start a Claude session; the Router alone needs no GitHub sign-in. Together they do more: an inbox action can start the right Claude session, and you can set Triage up by talking to the Router.

## Install

Grab the latest zip from [Releases](https://github.com/0xpolarzero/fjord-computer/releases), move **Fjord Computer.app** to `/Applications`, then clear the quarantine once (the app isn't notarized yet):

    xattr -dr com.apple.quarantine "/Applications/Fjord Computer.app"

Requires macOS 14+. The first launch opens the window on one screen to pick your tools; what each needs unfolds under it as you switch it on (GitHub's sign-in under Triage, an optional TypeSafe key under the Router). Settings → Tools changes them later.

After that the app updates itself: it checks in the background (shortly after launch, every hour and on wake), downloads and verifies a new release, then shows a small restart icon on the bar; hover it for what it is, click to restart into the new version. Right-click it, or Tab to the ⋯ menu beside it, for the release notes or to skip that version. Settings → Updates shows your version, checks on demand and turns the background check off. An update is only installed if its checksum matches and it's signed by the same certificate as the app you're running.

## Build & run

    ./scripts/build-app.sh && open "build/Fjord Computer.app"

GitHub auth comes from `gh auth token`, or a token pasted in Settings, stored in the Keychain. The TypeSafe (Jev) key is optional and kept in the Keychain too.

## Using it

### The bar and the window

- **The bar**: flush against a screen edge (drag it to any edge of any screen; along the top or bottom it lays out horizontally). It shows only what the tools that are on add: Triage's categories, each its symbol with what is unread on its corner (grouped in folders, which fold), the Router's cell with its open cards, then a gear. Hover any of them for its panel beside the bar: a category's list, the Router's latest cards and what is working, or the controls (when the inbox was last updated with a refresh, Open window, Settings). Click one to open the window there; the bar leaves the edge while the window is in front. Right-click the bar for the window, the Router, Settings, Inbox Categories, Check for Updates and Quit.
- **The window**: one window, a sidebar on the left (it folds to an icon rail, View → Collapse Sidebar): the inbox's categories and Done, the Router, Settings. Go → ⌘1–9 jumps to them, ⌘[ and ⌘] go back and forward. `⌃⌥L` opens or closes it from anywhere (a lone modifier tap like right ⌘ works too); every shortcut is customizable in Settings → Shortcuts.
- **Settings**: Tools (both switches), then each tool's own sections (GitHub, Notifications, Claude), Shortcuts, Updates and General (launch at login, centring the bar on its edge). A tool's sections and shortcuts show only while it is on.

### Triage

- **Categories**: the inbox is the categories you make. Each has a name, an SF Symbol (picked by Jev from the name as you type, with a TypeSafe key), a colour, rules, and whether it notifies. Their order is their priority: the first category whose rule matches a thing keeps it. Hide one like a table column: it stops notifying and leaves the bar, and still collects. A new inbox starts with **My repos** (the PRs and issues in repos you own); a **CI** category (failing workflows on your repos' default branch, its editor taking only repos) can be added. Edit them on the Inbox Categories page (the pencil by the sidebar's Inbox label).
- **Rules**: a sentence, such as *PRs by me in Repos I contribute to, when any of: new review by Maintainers, checks failing*. Kinds are PRs, issues and workflows; people and repos can be `@login`, `owner/repo`, `owner/*`, Repos I own, Repos I contribute to, Bots, Maintainers, teams, or named groups you save and reuse. Conditions cover new comments, reviews, commits and mentions (since Done, your last review or your last comment), review state, checks, conflicts, labels, drafts and inactivity.
- **Rows**: hover one to mark it seen, mark it Done, or open it on GitHub; click it to open it. In the window, keys act on the picked row (↑↓ or hover): Return opens, Space toggles seen, ⌫ marks Done or takes it back (⌘Z for 30 s), ⌥Space marks all seen, ⌘R refreshes.
- **Done**: what you acknowledged. A thing comes back from Done when something new matches.
- **Actions**: a category can act by itself when a thing comes in (or on each new fact): comment on GitHub, re-run the failed jobs, or, with the Router on, send your prompt to the Router with the thing attached: it goes to a Claude session working in a local clone of the repo, or a new one there, and when the Router isn't sure where, it asks you.
- **Jev's labels (optional)**: with a TypeSafe key and Settings → Claude → "Let Jev label new comments" on, new comments are labeled (asks you, to do, FYI, noise) and review requests rated. Labels only highlight or dim rows; your rules alone decide what is in a category and what notifies.
- **Extras**: banners per category, snooze, launch at login.

### Router

The Router needs the Claude desktop app: it reads its sessions (and `~/.claude/projects` for what a working session is doing, Claude Code's task list in `/private/tmp/claude-<uid>` for what it left running). These files aren't a public API: if a Claude update changes them, the Router says so and Triage keeps working.

- **Cards**: a session asks a question, wants a plan approved, finished its turn, got stuck or waits on something. A card stays open until it's addressed (you replied, answered it, or marked it by hand); opening its session in Claude leaves it open. Banners come for what needs you. `⌃⌥R` opens the Router from anywhere.
- **The page**: **Now** (what needs you, what's worth a look, what waits and what is working, in sections that fold) and **History** (your conversation with the Router and the cards already addressed), side by side in a wide window. A question's options are answered on its card; Open in Claude jumps to the session.
- **The chat**: reply to a card, type `@` to tag a project, or tell the Router what to pass on and to which session. Rules first, then Jev (with a TypeSafe key) pick where a message goes; it forwards your words as they are, answers forms or starts a new session, and says what it did in one line. When it can't tell which session you mean, it asks. It never acts on GitHub and has no tools to edit files or run commands.
- **Waiting sessions**: when a session's turn ends waiting on something the app can see finish (CI in your inbox, another session's turn), the Router shows it ready to continue; Settings → Claude can send the nudge on its own (needs a TypeSafe key).
- **Optional**: session icons picked by Jev (about $0.0002 a session), the style the Router writes its explanations in (Claude Haiku, through Claude Code), muted folders whose sessions it ignores.
- **Claude Code setup**: switching the Router on adds a form hook (`~/.claude/hooks/fjord-form.sh`, registered in `~/.claude/settings.json`, which is backed up first) so forms can be answered from the app, and installs a small signed Claude Code plugin (`fjord@fjord`) so your words arrive in a session as your own message, not as a note from another session. Sessions already open pick it up once restarted (or after `/reload-plugins`). Switching the Router off removes both.

### Triage and the Router together

With both on, an inbox action can start the right Claude session, and the Router can read and change Triage: ask it to make a category, adjust a rule or a group, mark things Done or change a setting. Each change shows as a card in its history, with Open and Revert. Switch either tool off and the link goes quiet; what each holds is kept for when it's back.

## Releasing

Push a version tag; the `Release` workflow tests, builds a universal app and publishes `FjordComputer-<version>.zip` (and its `.sha256`) to GitHub Releases:

    git tag v0.2.0 && git push origin v0.2.0

The `Test` workflow runs the same tests (`scripts/test.sh`, on the same runner) on every push to `main`, so a test that fails only there shows up before a release.

Releases are signed with one self-signed certificate, so macOS keeps the app's Accessibility access across updates and the updater can check a release is ours. Set it up once:

1. In Keychain Access: Certificate Assistant → Create a Certificate, identity type *Self-Signed Root*, certificate type *Code Signing*, named as `build-app.sh` expects (its default identity, or set `SIGN_IDENTITY`).
2. Export it with its private key as a `.p12` (with a password), then add two repository secrets: `SIGNING_CERT_P12` (`base64 -i cert.p12 | pbcopy`) and `SIGNING_CERT_PASSWORD`.
3. Keep the `.p12` safe: a release signed with another certificate isn't installed by existing apps, and everyone has to update by hand once.

`build-app.sh` signs local builds with the same certificate when it's in your keychain (ad hoc otherwise, which macOS treats as a new app on every build).

## Dev flags

    .build/debug/FjordComputer --demo [scenario] [--open] [--edge left|right|top|bottom]   # mock data, Triage on (the Router too in its scenarios), nothing saved
    #   scenarios: busy botsOnly allClear snoozed error empty agents (the plain sets), and one per state that empties a list or
    #   breaks the sync: signedOut inboxFailed rateLimited contributionsEmpty botChatterEmpty doneEmpty firstSync syncFault
    #   inboxMany hiddenCategory jev sections noCI allPassing manyCI ciRunning updateAvailable updateDownloading updateReady
    #   router routerOff
    .build/debug/FjordComputer --claude [--watch]                     # what the Router reads of Claude; --watch prints live changes
    .build/debug/FjordComputer --playground                           # the bar on a fake desktop, demo data, every edge
    .build/debug/FjordComputer --playground-shots <dir> [name...]     # render the bar's states as PNGs, offscreen: every edge, every
    #   demo scenario, Reduce Motion / Increase Contrast / Differentiate variants and a 1280x720 screen; shot names are
    #   <edge>-<state> (right-open, top-rest-signed-out...), and only those containing one of the names given are rendered
    .build/debug/FjordComputer --window                               # the window alone, on demo data
    .build/debug/FjordComputer --window-shots <dir>                   # render the window's pages as PNGs, offscreen
    FJORD_THEME=dark|light|claude .build/debug/FjordComputer          # pins the look: Fjord light or dark, or Claude's own (default: Fjord, following the Mac's appearance live)
    "build/Fjord Computer.app/Contents/MacOS/FjordComputer" --update 0.1.0   # pretend to be 0.1.0: check, download and verify the latest release
    .build/debug/FjordComputer --check owner/repo                     # headless live sync of one repo, prints the inbox
    .build/debug/FjordComputer --check-inbox                          # headless live sync with sample categories, prints every entry
    scripts/idle-cpu.sh                                               # release build's CPU at rest and kept open, on the demo data (puts the bar on screen for minutes)
    scripts/test.sh                                                   # swift test as CI runs it, output in test.log

`scripts/migrate-to-fjord.sh` is a one-off for the owner's machine (moves Lookout's data, preferences, Keychain items and Claude Code setup over); it isn't for users.

Global shortcut actions run before their callback returns. Carbon hot keys target `GetApplicationEventTarget()`, which this app dispatches through the [main-thread application event loop](https://developer.apple.com/library/archive/documentation/General/Conceptual/Devpedia-CocoaApp/MainEventLoop.html); AppKit [guarantees that local and global event monitors run on the main thread](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html). [MainActor.assumeIsolated](https://developer.apple.com/documentation/swift/mainactor/assumeisolated(_:file:line:)) verifies the executor before performing the action synchronously. Mouse-button shortcuts still defer their handler to leave the CGEvent tap callback before window work.

State: `~/Library/Application Support/Fjord Computer/state.json`.
