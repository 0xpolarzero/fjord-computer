import AppKit
import Foundation
import SwiftUI

/// `--demo [scenario]`: fake data for trying the UI without touching GitHub or the saved state.
@MainActor
enum Demo {
    /// `busy` to `agents` are the plain `--demo` sets. The rest are the states that empty a list or break the sync, each on
    /// top of the `agents` data (the bar with everything on it) unless noted, so a shot shows the state in a realistic bar.
    enum Scenario: String, CaseIterable {
        case busy, botsOnly, allClear, snoozed, error, empty, agents
        // Inbox and sync causes.
        case signedOut, inboxFailed, rateLimited, contributionsEmpty, botChatterEmpty, doneEmpty, firstSync, syncFault
        // An inbox longer than any list shows; a category hidden.
        case inboxMany, hiddenCategory
        // CI.
        case noCI, allPassing, manyCI, ciRunning
        // The update tile.
        case updateAvailable, updateDownloading, updateReady
        // The Router: cards of each kind (a question with its form) and a chat with receipts; and the Router switched off.
        case router, routerOff
    }

    static func populate(_ store: Store, _ scenario: Scenario = .busy) {
        store.persists = false
        let now = Date()
        store.me = GHUser(login: "0xpolarzero", avatarUrl: URL(string: "https://avatars.githubusercontent.com/u/0?v=4"), type: "User")
        store.tokenSource = .ghCLI
        store.lastSync = now.addingTimeInterval(-20)
        store.rateRemaining = 4812
        inbox(store, now)

        switch scenario {
        case .busy:
            break
        case .botsOnly:
            nothingForYou(store)
            empty(store, category: "Contributions")
            empty(store, category: "Reviews for you")
            passing(store)
        case .allClear:
            for entry in store.entries where !entry.isDone { store.things[entry.id] = nil }
            passing(store)
        case .snoozed:
            store.settings.snoozeUntil = Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: now)
                .map { $0 > now ? $0 : now.addingTimeInterval(3600) }
        case .error:
            store.rateRemaining = 312
            let ci = "workflow:0xpolarzero/lookout:\(ciWorkflowID)@main"
            store.things[ci]?.checks = .failing
            store.things[ci]?.failingJobs = ["test (macos-15)"]
            store.things[ci]?.title = "Drag the pill from anywhere"
        case .agents:
            agents(store, now)
        case .empty:
            store.things = [:]
        case .signedOut:
            agents(store, now)
            store.me = nil
            store.tokenSource = nil
            store.lastSync = nil
            store.rateRemaining = nil
            store.authError = "No GitHub token found"
        case .inboxFailed:
            agents(store, now)
            store.inboxError = "Something went wrong with GitHub's search (HTTP 502)"
        case .rateLimited:
            agents(store, now)
            store.rateRemaining = 0
        case .contributionsEmpty:
            // Nothing on your PRs, CI healthy, the other categories still unread: all caught up here.
            agents(store, now)
            nothingForYou(store)
            empty(store, category: "Contributions")
            passing(store)
        case .botChatterEmpty:
            agents(store, now)
            empty(store, category: "Bot chatter")
        case .doneEmpty:
            agents(store, now)
            store.marks = [:]
        case .hiddenCategory:
            // Bot chatter hidden: collecting, with no icon in the bar and no tab.
            agents(store, now)
            if let id = store.categories.first(where: { $0.name == "Bot chatter" })?.id { store.setHidden(id, true) }
        case .firstSync:
            agents(store, now)
            store.lastSync = nil
            store.isSyncing = true
            store.things = [:]
            store.rateRemaining = nil
        case .syncFault:
            // Several poll intervals old: the sync status reads "Not syncing".
            agents(store, now)
            store.lastSync = now.addingTimeInterval(-3600)
        case .inboxMany:
            agents(store, now)
            let titles = ["Cache the avatar lookups", "Dark mode for the Settings window", "Snooze until Monday", "Open the right repo on click",
                          "Hide read items after a day", "Keyboard shortcut for Mark all read", "Tab order in the footer", "Menu bar icon option",
                          "Group by repository", "Notifications repeat after wake", "Sort Done by repository", "Search inside snippets"]
            let me = person("0xpolarzero")
            for (index, title) in titles.enumerated() {
                let n = 30 + index
                let reviewer = person(["kylef", "mattt", "allevato"][index % 3])
                let thing = Thing(id: "pr:0xpolarzero/lookout#\(n)", kind: .pr, repo: "0xpolarzero/lookout", number: n, title: title,
                                  url: URL(string: "https://github.com/0xpolarzero/lookout/pull/\(n)")!, author: me,
                                  createdAt: now.addingTimeInterval(-86400),
                                  updatedAt: now.addingTimeInterval(-Double(130 + index * 40) * 60),
                                  comments: [ThingComment(id: "many-\(n)", author: reviewer, at: now.addingTimeInterval(-Double(130 + index * 40) * 60),
                                                          snippet: "Looks good, one nit.")],
                                  checks: .passing, greptileScore: 3 + index % 3)
                store.things[thing.id] = thing
            }
        case .noCI:
            agents(store, now)
            store.things = store.things.filter { $0.value.kind != .workflow }
        case .allPassing:
            agents(store, now)
            passing(store)
        case .manyCI:
            agents(store, now)
            manyCI(store, now)
        case .ciRunning:
            // Nothing failing: what was running stays running.
            agents(store, now)
            for key in store.things.keys where store.things[key]?.checks == .failing && store.things[key]?.kind == .workflow {
                store.things[key]?.checks = .pending
            }
        case .updateAvailable:
            agents(store, now)
            store.updater.preview(.available, version: "0.5.0")
        case .updateDownloading:
            agents(store, now)
            store.updater.preview(.downloading, version: "0.5.0", fraction: 0.42)
        case .updateReady:
            agents(store, now)
            store.updater.preview(.ready, version: "0.5.0")
        case .router:
            agents(store, now)
            router(store, now)
        case .routerOff:
            agents(store, now)
        }
    }

    /// The Router on, over the `agents` sessions: the one that asks is stopped on its question (whose form Lookout holds),
    /// a plan and a stuck turn wait, a turn is done, older cards are addressed; a short chat with what the Router did.
    private static func router(_ store: Store, _ now: Date) {
        let lcu = blockedAgentID
        store.claudeSessions[lcu]?.running = true
        store.claudeSessions[lcu]?.cliID = "cli-demo-lcu"
        store.claudeActivity[lcu] = ClaudeActivity(text: "Should updates install silently, or ask first each time?",
                                                   since: now.addingTimeInterval(-120), waitsForYou: true, tool: "AskUserQuestion",
                                                   toolUseID: "toolu_demo_lcu")
        let question = "Should updates install silently, or ask first each time?"
        store.pendingForms["cli-demo-lcu"] = PendingForm(
            id: "cli-demo-lcu-1-1", cliSessionID: "cli-demo-lcu", transcriptPath: "",
            questions: [PendingForm.Question(question: question, header: "Updates", multiSelect: false, options: [
                PendingForm.Option(label: "Install silently", description: "Download and install in the background"),
                PendingForm.Option(label: "Ask first", description: "Show a prompt before each update"),
            ])],
            createdAt: now.addingTimeInterval(-60), pid: 0, toolUseID: "toolu_demo_lcu")
        // The Linux sandbox's plan, held the same way: its card shows it, to approve or send back.
        let linux = "local_demo-linux"
        store.claudeSessions[linux]?.cliID = "cli-demo-linux"
        store.pendingForms["cli-demo-linux"] = PendingForm(
            id: "cli-demo-linux-1-1", cliSessionID: "cli-demo-linux", transcriptPath: "", questions: [],
            createdAt: now.addingTimeInterval(-540), pid: 0, toolUseID: "toolu_demo_linux", plan: """
            # Run the JavaScript sandbox in a Firecracker microVM on Linux

            1. Add a `firecracker` backend next to the macOS one, behind the same `Sandbox` protocol.
            2. Boot a minimal kernel and rootfs with the JS runtime baked in; talk to it over vsock.
            3. Run the existing sandbox tests against both backends in CI (Linux runner with KVM).
            """)
        func card(_ session: String, _ kind: RouterCard.Kind, _ text: String, minutes: Double, addressed: RouterCard.Addressed? = nil)
            -> RouterCard {
            let s = store.claudeSessions[session]
            let at = now.addingTimeInterval(-minutes * 60)
            // Ids as the feed makes them: a wait by when it began, a turn by its number.
            let id = kind.isTurn ? "\(session)#t\(s?.completedTurns ?? 0)" : "\(session)#w\(RouterFeed.Stamp.ms(at))"
            return RouterCard(id: id, sessionID: session, kind: kind,
                              title: s?.title ?? session, folder: s?.folder, text: text, createdAt: at,
                              addressedAt: addressed == nil ? nil : at.addingTimeInterval(120), addressedBy: addressed)
        }
        var state = RouterState()
        state.enabled = true
        state.enabledAt = now.addingTimeInterval(-86400)
        state.cards = [
            card("local_demo-transfer", .done, "Transfer is done; both remotes point at the new org.", minutes: 12, addressed: .router),
            card("local_demo-games", .question, "Single-player immersion or online squads?", minutes: 30, addressed: .answered),
            card("local_demo-ci", .done, "Fixed the flaky sandbox test; **CI is green** on the branch.", minutes: 4),
            card("local_demo-linux", .plan, "Run the JavaScript sandbox in a Firecracker microVM on Linux", minutes: 9),
            card("local_demo-calc", .stuck, "Can't reach the staging database: the VPN is down.", minutes: 6),
            card(lcu, .question, question, minutes: 2),
        ]
        state.cards[state.cards.count - 1].toolUseID = "toolu_demo_lcu"
        if let i = state.cards.firstIndex(where: { $0.sessionID == linux }) { state.cards[i].toolUseID = "toolu_demo_linux" }
        // The question is the wait the session is on now, so its form shows on its card.
        state.waits[lcu] = state.cards.last?.waitMs
        state.chat = [
            RouterMessage(role: .you, text: "what needs me?", date: now.addingTimeInterval(-300)),
            RouterMessage(role: .router, text: "**3 need you**: *LCU update notifications* asks how updates install; the Linux "
                          + "sandbox has a plan to approve; *Calculator display reading* is stuck on the VPN.\nDone: CI failure diagnosis.",
                          date: now.addingTimeInterval(-290)),
            RouterMessage(role: .you, text: "transfer: remove the old remote", date: now.addingTimeInterval(-200)),
            RouterMessage(role: .receipt, text: "→ Repository ownership transfer setup: Remove the old remote.",
                          date: now.addingTimeInterval(-195), sessionID: "local_demo-transfer",
                          original: "transfer: remove the old remote"),
            RouterMessage(role: .peer, text: "Removed `old-origin`; only the new org's remote is left. I also checked the branch "
                          + "protection rules on the new org: `main` requires one review and passing checks, as before. The deploy key "
                          + "was carried over, and the webhook for CI now points at the new repository. Two open PRs still target the "
                          + "old fork; I left them alone.", date: now.addingTimeInterval(-60), sessionID: "local_demo-transfer"),
            RouterMessage(role: .you, text: "start a session to bump the version", date: now.addingTimeInterval(-30),
                          projects: ["/Users/me/code/lookout"]),
            RouterMessage(role: .receipt, text: "Cancelled before sending", date: now.addingTimeInterval(-28)),
            RouterMessage(role: .automated, text: "⚡ Contributions: Address what https://github.com/ziglang/zig/pull/1 is waiting on.\n\n"
                          + "Context, from the “Contributions” category of the Lookout inbox:\n- Title: Warm pool\n- Local clones of ziglang/zig, to choose from: `/Users/me/code/zig`",
                          date: now.addingTimeInterval(-20), source: "Contributions"),
            RouterMessage(role: .error, text: "SendMessage to Game recommendations: not delivered (the session isn't open in Claude)",
                          date: now.addingTimeInterval(-10), sessionID: "local_demo-games"),
        ] + lookoutChanges(store, now)
        // The decision log behind the same story: what you said and what the Router did with it.
        func entry(_ minutes: Double, _ trigger: RouterDecision.Trigger, _ intent: String, _ done: [RouterDecision.Done],
                   outcome: RouterDecision.Outcome = .done) -> RouterDecision {
            var d = RouterDecision(at: now.addingTimeInterval(-minutes * 60), trigger: trigger, decision: .init(intent: intent), outcome: outcome)
            for item in done {
                switch item {
                case .changed: d.add(item)
                case .sent: d.add(item, session: "local_demo-transfer")
                default: d.add(item)
                }
            }
            return d
        }
        let changes = state.chat.compactMap(\.change)
        state.decisions = [
            entry(3.3, .you("transfer: remove the old remote"), "reply",
                  [.sent(to: "Repository ownership transfer setup", text: "Remove the old remote.", original: "transfer: remove the old remote")]),
            entry(0.5, .you("start a session to bump the version"), "start", [.failed("Cancelled")]),
            entry(0.3, .action(category: "Contributions", thing: "ziglang/zig#1", actionID: "demo", runID: nil), "action",
                  [.started(session: nil, project: "zig", model: nil, effort: nil)]),
            entry(9, .you("add a category for my contributions that need a look, and snooze banners for an hour"), "change",
                  changes.prefix(2).map { .changed($0.id) }),
            entry(3, .you("mark the bot chatter done, and mute reviews for you"), "change",
                  changes.dropFirst(2).map { .changed($0.id) }, outcome: .done),
        ]
        if let last = state.decisions.indices.last, changes.last?.isReverted == true {
            state.decisions[last].outcome = .reverted
        }
        store.router = state
    }

    /// The Router changing Lookout itself: what the user asked, and a card for each change (one taken back).
    private static func lookoutChanges(_ store: Store, _ now: Date) -> [RouterMessage] {
        let look = InboxCategory(
            name: "Needs a look", symbol: "eye", color: .aqua,
            rules: [Rule(scope: Scope(kind: .pr, by: Pick(include: [.maintainers], except: [.bots]), in: Pick(include: [.contributed])),
                         match: .any,
                         conditions: [.checks([.failing]), .unresolvedThreads(startedBy: nil, lastReplyBy: nil),
                                      .newReview(by: Pick(include: [.maintainers]), since: .myLastReview)],
                         createdAt: now)],
            actions: ActionList([CategoryAction.make(.askRouter(prompt: "Look at it and tell me what is left"))]))
        let reviews = store.categories.first { $0.name == "Reviews for you" }
        var quiet = reviews
        quiet?.notifies = false
        quiet?.hidden = true
        func message(_ title: String, _ patch: LookoutChange.Patch, minutes: Double, reverted: Bool = false) -> RouterMessage {
            var change = LookoutChange(date: now.addingTimeInterval(-minutes * 60), title: title, patch: patch)
            if reverted {
                change.revertedAt = now.addingTimeInterval(-60)
                change.revertNote = "Reverted"
            }
            return RouterMessage(role: .change, text: title, date: change.date, change: change)
        }
        let doneThings = store.entries.prefix(3).map { EntryChange(thing: $0.id, before: nil, after: EntryMarks(doneAt: now)) }
        var out = [
            RouterMessage(role: .you, text: "add a category for my contributions that need a look, and snooze banners for an hour",
                          date: now.addingTimeInterval(-9 * 60)),
            message(LookoutChange.title(forCategory: nil, look), .category(index: 1, before: nil, after: look), minutes: 8),
            message("Changed snooze to 1 hour",
                    .setting(key: "snooze", before: .date(nil), after: .date(now.addingTimeInterval(3600))), minutes: 8),
            RouterMessage(role: .you, text: "mark the bot chatter done, and mute reviews for you", date: now.addingTimeInterval(-3 * 60)),
            message("Marked \(doneThings.count) done", .marks(state: "done", doneThings), minutes: 2),
        ]
        if let reviews, let quiet {
            out.append(message(LookoutChange.title(forCategory: reviews, quiet), .category(index: 1, before: reviews, after: quiet),
                               minutes: 2, reverted: true))
        }
        return out
    }

    /// Only the bots' things and the finished ones left: nothing is for you.
    private static func nothingForYou(_ store: Store) {
        for category in ["Contributions", "Reviews for you"] { empty(store, category: category) }
    }

    // MARK: Inbox

    /// The demo's categories, in their order: ids fixed, so a shot can name them.
    private static func categories(ciRepos: [String]) -> [InboxCategory] {
        func id(_ n: Int) -> UUID { UUID(uuidString: "00000000-0000-0000-0000-00000000000\(n)")! }
        let longAgo = Date().addingTimeInterval(-60 * 86400)
        // What needs you on your own PRs: Greptile short of 5, threads still open, someone else having the last word,
        // a review that decides, conflicts.
        let contributions = InboxCategory(
            id: id(1), name: "Contributions", symbol: "hammer", color: .violet,
            rules: [Rule(scope: Scope(kind: .pr, by: Pick(include: [.me]), in: Pick(include: [.contributed])),
                         match: .any,
                         conditions: [.greptileBelow(5), .unresolvedThreads(startedBy: nil, lastReplyBy: nil),
                                      .lastComment(by: Pick(except: [.me])), .changesRequested(by: Pick()), .approved(by: Pick()),
                                      .hasConflicts],
                         createdAt: longAgo)])
        let reviews = InboxCategory(
            id: id(2), name: "Reviews for you", symbol: "eye.circle", color: .amber,
            rules: [Rule(scope: Scope(kind: .pr, to: Pick(include: [.me]), toRoles: [.reviewRequested]), createdAt: longAgo)])
        let bots = InboxCategory(
            id: id(3), name: "Bot chatter", symbol: "cpu", color: .gray,
            rules: [Rule(scope: Scope(kind: .pr, in: Pick(include: [.involved])), match: .any,
                         conditions: [.newComment(by: Pick(include: [.bots]))], createdAt: longAgo)],
            notifies: false)
        var ci = InboxStore.defaultCategories[0]
        ci.id = id(4)
        ci.rules = [Rule(scope: Scope(kind: .workflow, in: Pick(include: ciRepos.map { .repo($0) })), conditions: [.workflow([.failing])],
                         createdAt: longAgo)]
        return [contributions, reviews, bots, ci]
    }

    /// GitHub's ids for the demo's workflows (a workflow thing is `workflow:<repo>:<id>@<branch>`).
    private static let ciWorkflowID = 1001
    private static let workflowIDs = ["CI": ciWorkflowID, "Sandbox tests": 1002, "Release": 1003]

    private static let ciRepoNames = ["0xpolarzero/lookout", "apple/swift-format", "ziglang/zig", "amontlabs/lcu",
                                      "superradcompany/microsandbox"]

    /// The inbox on the demo data: things fetched from GitHub, in the categories above, some seen, some done.
    private static func inbox(_ store: Store, _ now: Date) {
        store.categories = categories(ciRepos: ciRepoNames)
        store.contributedRepos = ["ziglang/zig", "apple/swift-format", "0xpolarzero/lookout", "amontlabs/lcu"]
        let me = person("0xpolarzero")
        var things: [Thing] = []

        func pr(_ repo: String, _ n: Int, _ title: String, by author: Person, minutes: Double, greptile: Int? = nil,
                checks: CheckState? = .passing, requested: [String] = [], assignees: [String] = [], mentioned: [String] = [],
                status: ThingStatus = .open, conflicts: Bool = false, comments: [ThingComment] = [], reviews: [ThingReview] = [],
                threads: [ThingThread] = []) -> Thing {
            Thing(id: "pr:\(repo)#\(n)", kind: .pr, repo: repo, number: n, title: title,
                  url: URL(string: "https://github.com/\(repo)/pull/\(n)")!, author: author, status: status,
                  assignees: assignees, requestedReviewers: requested, mentioned: mentioned,
                  createdAt: now.addingTimeInterval(-86400 * 3), updatedAt: now.addingTimeInterval(-minutes * 60),
                  comments: comments, reviews: reviews, threads: threads, checks: checks, hasConflicts: conflicts,
                  greptileScore: greptile)
        }
        func comment(_ key: String, _ author: Person, _ text: String, minutes: Double, mentions: [String] = []) -> ThingComment {
            ThingComment(id: key, author: author, at: now.addingTimeInterval(-minutes * 60), snippet: text, mentions: mentions)
        }
        func thread(_ key: String, by: Person, reply: Person, minutes: Double, path: String, _ text: String,
                    resolved: Bool = false) -> ThingThread {
            ThingThread(id: key, isResolved: resolved, startedBy: by, lastReplyBy: reply, lastReplyID: key + "-r",
                        lastReplyAt: now.addingTimeInterval(-minutes * 60), path: path, snippet: text)
        }

        // Contributions: your PRs.
        let toks = person("toksdotdev", assoc: .collaborator)
        let andrew = person("andrewrk", assoc: .owner)
        let allevato = person("allevato", assoc: .member)
        let greptile = person("greptile-apps[bot]", bot: true)
        things.append(pr("0xpolarzero/lookout", 15, "Add GitHub Enterprise host setting", by: me, minutes: 12, greptile: 4,
                         comments: [comment("c15-1", greptile, "Confidence 4/5: one path still uses the fixed host.", minutes: 95),
                                    comment("c15-2", toks, "Can the host be validated before we save it?", minutes: 12)],
                         threads: [thread("t15-1", by: toks, reply: toks, minutes: 12, path: "Sources/Lookout/GitHub.swift",
                                          "Can the host be validated before we save it?"),
                                   thread("t15-2", by: toks, reply: me, minutes: 80, path: "Sources/Lookout/SettingsView.swift",
                                          "Placeholder text says github.com.")]))
        things.append(pr("ziglang/zig", 21877, "std.Io: add vectored reads to File", by: me, minutes: 3, greptile: 3, checks: .pending,
                         comments: [comment("c21877-1", andrew, "This should take the buffer by slice instead.", minutes: 3)],
                         reviews: [ThingReview(id: "r21877-1", author: andrew, state: .changesRequested,
                                               at: now.addingTimeInterval(-180))],
                         threads: [thread("t21877-1", by: andrew, reply: andrew, minutes: 3, path: "lib/std/Io/File.zig",
                                          "This should take the buffer by slice instead.")]))
        things.append(pr("apple/swift-format", 1042, "Respect trailing comma config in collection literals", by: me, minutes: 18,
                         greptile: 5,
                         comments: [comment("c1042-1", allevato, "Thanks! Could you add a test for the nested array case?", minutes: 18)],
                         reviews: [ThingReview(id: "r1042-1", author: allevato, state: .approved, at: now.addingTimeInterval(-1100))]))
        things.append(pr("amontlabs/lcu", 31, "Bump the Swift tools version", by: me, minutes: 240, greptile: 5, checks: .failing,
                         conflicts: true))

        // Reviews for you: asked of you.
        let ahoppen = person("ahoppen", assoc: .member)
        let mlugg = person("mlugg", assoc: .collaborator)
        let cbrewster = person("cbrewster")
        things.append(pr("apple/swift-format", 1051, "Add --lines option to format a range", by: ahoppen, minutes: 65,
                         requested: ["0xpolarzero"]))
        things.append(pr("ziglang/zig", 21840, "Sema: fix comptime int overflow in @shlExact", by: mlugg, minutes: 1500,
                         requested: ["0xpolarzero"]))
        things.append(pr("superradcompany/microsandbox", 412, "Mount host directories read-only", by: cbrewster, minutes: 400,
                         checks: .pending, requested: ["0xpolarzero"], status: .draft))

        // Bot chatter: PRs of others you're in, where a bot spoke.
        let kylef = person("kylef")
        let vercel = person("vercel[bot]", bot: true)
        let rabbit = person("coderabbitai[bot]", bot: true)
        let codecov = person("codecov[bot]", bot: true)
        things.append(pr("0xpolarzero/lookout", 14, "Group notifications by repo", by: kylef, minutes: 6, assignees: ["0xpolarzero"],
                         comments: [comment("c14-1", vercel, "Deployment ready. Preview: lookout-git-group.vercel.app", minutes: 6)]))
        things.append(pr("apple/swift-format", 1047, "Fix a crash on an empty file", by: allevato, minutes: 22, mentioned: ["0xpolarzero"],
                         comments: [comment("c1047-1", rabbit, "Consider extracting this into a helper.", minutes: 22),
                                    comment("c1047-2", codecov, "Coverage 87.2% (+0.4%) compared to base.", minutes: 25)]))
        things.append(pr("ziglang/zig", 21901, "Linker: skip empty sections", by: person("squeek502"), minutes: 700,
                         assignees: ["0xpolarzero"],
                         comments: [comment("c21901-1", person("github-actions[bot]", bot: true), "Benchmarks are within noise.",
                                            minutes: 700)]))

        // CI: workflows, the failing ones in the category.
        func workflow(_ repo: String, _ name: String, branch: String = "main", state: CheckState, title: String, minutes: Double,
                      jobs: [String] = []) -> Thing {
            Thing(id: "workflow:\(repo):\(workflowIDs[name] ?? 1000)@\(branch)", kind: .workflow, repo: repo, number: nil, title: title,
                  url: URL(string: "https://github.com/\(repo)/actions")!, createdAt: now.addingTimeInterval(-minutes * 60),
                  updatedAt: now.addingTimeInterval(-minutes * 60), checks: state, workflowName: name, branch: branch,
                  failingJobs: jobs)
        }
        things.append(workflow("apple/swift-format", "CI", state: .failing, title: "Respect trailing comma config (#1042)", minutes: 45,
                               jobs: ["Linux / build", "Windows / test"]))
        things.append(workflow("superradcompany/microsandbox", "Sandbox tests", state: .failing,
                               title: "Mount host directories read-only (#412)", minutes: 380, jobs: ["Linux / integration"]))
        things.append(workflow("0xpolarzero/lookout", "CI", state: .passing, title: "Compact, draggable repo cards", minutes: 25))
        things.append(workflow("ziglang/zig", "CI", branch: "master", state: .pending, title: "std.Io: add vectored reads to File",
                               minutes: 4))
        things.append(workflow("amontlabs/lcu", "Release", state: .passing, title: "Release 0.4.2", minutes: 1440))

        store.things = Dictionary(uniqueKeysWithValues: things.map { ($0.id, $0) })
        store.marks = [:]
        // Some seen; some done (they come back when something new happens).
        for entry in store.entries {
            switch entry.id {
            case "pr:ziglang/zig#21877", "pr:apple/swift-format#1047": store.markSeen(entry)
            case "pr:ziglang/zig#21840", "pr:ziglang/zig#21901": store.markDone(entry)
            default: break
            }
        }
        CategoriesDemo.seedActions(store, categories: CategoriesDemo.demoActions)
    }

    private static func person(_ login: String, bot: Bool = false, assoc: Association = .none) -> Person {
        Person(login: login, isBot: bot, association: assoc,
               avatar: URL(string: "https://github.com/\(login.replacingOccurrences(of: "[bot]", with: "")).png"))
    }

    /// Takes the open things of a category away: nothing for you there.
    private static func empty(_ store: Store, category name: String) {
        guard let id = store.categories.first(where: { $0.name == name })?.id else { return }
        let gone = Set(store.entries.filter { $0.categoryID == id && !$0.isDone }.map(\.id))
        store.things = store.things.filter { !gone.contains($0.key) }
    }

    /// Every CI repo green.
    private static func passing(_ store: Store) {
        for key in store.things.keys where store.things[key]?.kind == .workflow { store.things[key]?.checks = .passing }
    }

    /// 15 repositories with CI: nine failing, two running, four passing; more than the list shows.
    private static func manyCI(_ store: Store, _ now: Date) {
        let names = ["0xpolarzero/lookout", "apple/swift-format", "ziglang/zig", "amontlabs/lcu", "e2b-dev/runtime",
                     "superradcompany/microsandbox", "apple/swift-argument-parser", "pointfreeco/swift-composable-architecture",
                     "vapor/vapor", "swiftlang/swift-package-manager", "tuist/tuist", "realm/SwiftLint", "Alamofire/Alamofire",
                     "hummingbird-project/hummingbird", "apple/swift-nio"]
        store.categories = categories(ciRepos: names)
        let failing: [String: [String]] = [
            "apple/swift-format": ["Linux / build", "Windows / test"], "vapor/vapor": ["Unit tests (5.10)"],
            "tuist/tuist": ["Acceptance"], "realm/SwiftLint": ["Plugin tests"], "Alamofire/Alamofire": ["macOS", "tvOS"],
            "swiftlang/swift-package-manager": ["Build"], "pointfreeco/swift-composable-architecture": ["Library evolution"],
            "e2b-dev/runtime": ["Integration"], "amontlabs/lcu": ["Desktop"],
        ]
        let running: Set<String> = ["ziglang/zig", "apple/swift-nio"]
        store.things = store.things.filter { $0.value.kind != .workflow }
        for (index, name) in names.enumerated() {
            let state: CheckState = failing[name] != nil ? .failing : running.contains(name) ? .pending : .passing
            let thing = Thing(id: "workflow:\(name):\(ciWorkflowID)@main", kind: .workflow, repo: name, number: nil, title: "Commit headline \(index + 1)",
                              url: URL(string: "https://github.com/\(name)/actions")!,
                              createdAt: now.addingTimeInterval(-Double(index + 1) * 2300),
                              updatedAt: now.addingTimeInterval(-Double(index + 1) * 2300), checks: state, workflowName: "CI",
                              branch: "main", failingJobs: failing[name] ?? [])
            store.things[thing.id] = thing
        }
    }

    static let blockedAgentID = "local_demo-lcu"

    /// A session as the Claude app reports it: a finished turn with a summary, or (`running`) mid-turn.
    private static func session(_ id: String, _ title: String, _ folder: String?, minutes: Double, turns: Int = 4,
                                blocked: Bool = false, detail: String = "", running: Bool = false) -> ClaudeSession {
        let at = Date().addingTimeInterval(-minutes * 60)
        return ClaudeSession(id: id, title: title, folder: folder.map { "/Users/me/code/\($0)" }, completedTurns: turns,
                             lastActivity: at, lastFocused: at.addingTimeInterval(-600), lastUserMessage: at.addingTimeInterval(-90),
                             summary: running ? nil : ClaudeSession.Summary(blocked: blocked, detail: detail), running: running)
    }

    /// A session and how Lookout lists it: read or not, with the label or icon it was given.
    private struct Listed {
        var session: ClaudeSession
        var unread = false
        var label: String?
        var icon: String?

        init(_ session: ClaudeSession, unread: Bool = false, label: String? = nil, icon: String? = nil) {
            self.session = session
            self.unread = unread
            self.label = label
            self.icon = icon
        }
    }

    /// The Router's reading of Claude's sessions, on, with these sessions. `colors` pins each project's colour; the others get the
    /// least used one, in listing order. `unlisted` are known to the app but without an entry: only found by search.
    private static func sessions(_ store: Store, _ now: Date, _ listed: [Listed], activity: [String: ClaudeActivity] = [:],
                                 tasks: [String: [ClaudeTask]] = [:], colors: [String: Int] = [:],
                                 unlisted: [ClaudeSession] = []) {
        store.claudeSessions = Dictionary(uniqueKeysWithValues: (listed.map(\.session) + unlisted).map { ($0.id, $0) })
        store.claudeLink = .ok
        store.claudeActivity = activity
        store.claudeTasks = tasks
        var state = AgentsState()
        state.folderColors = colors
        for folder in listed.compactMap(\.session.folder) { state.assignColor(folder) }
        state.enabled = true
        state.enabledAt = now.addingTimeInterval(-86400)
        state.seeded = true
        state.iconsEnabled = true
        state.entries = listed.map { l in
            AgentEntry(id: l.session.id, label: l.label, unread: l.unread, seen: l.session.activity,
                       focusedAt: l.session.lastFocused, icon: l.icon)
        }
        store.agents = state
    }

    /// The sessions in every state: a waiting one, a working one, finished ones (unread and read), new activity.
    static func agents(_ store: Store, _ now: Date) {
        let listed = [
            Listed(session(blockedAgentID, "LCU update notifications", "lcu", minutes: 2, blocked: true,
                           detail: "Should updates install silently, or ask first each time?"), unread: true, icon: "bell.badge"),
            Listed(session("local_demo-ci", "CI failure diagnosis", "microsandbox", minutes: 4,
                           detail: "Fixed the flaky sandbox test; CI is green on the branch."), unread: true, icon: "ladybug"),
            Listed(session("local_demo-lookout", "Agent completion notifications", "lookout", minutes: 1, running: true)),
            Listed(session("local_demo-transfer", "Repository ownership transfer setup", "microsandbox", minutes: 180,
                           detail: "Transfer is done; both remotes point at the new org."), icon: "key"),
            Listed(session("local_demo-linux", "LCU JavaScript sandbox on Linux", "microsandbox", minutes: 1500,
                           detail: "Sandbox runs on Linux; two follow-ups listed."), label: "\u{1F427}"),
            Listed(session("local_demo-calc", "Calculator display reading", "lcu-research", minutes: 1,
                           detail: "The display reads 1,234.5; the screenshot is attached."), unread: true),
            Listed(session("local_demo-games", "Game recommendations", nil, minutes: 25,
                           detail: "Single-player immersion or online squads?")),
        ]
        let hidden = session("local_demo-storage", "Sandbox storage directory customization", "microsandbox", minutes: 2900,
                             detail: "Storage path is configurable through the CLI and the env.")
        sessions(store, now, listed, activity: ["local_demo-lookout": ClaudeActivity(text: "Running swift test", since: now.addingTimeInterval(-20))],
                 tasks: ["local_demo-ci": [
                    ClaudeTask(id: "a1", kind: .agent, title: "Review the sandbox changes", since: now.addingTimeInterval(-190),
                               activity: ClaudeActivity(text: "Reading sandbox.rs", since: now.addingTimeInterval(-5))),
                    ClaudeTask(id: "a2", kind: .agent, title: "Check the other CI jobs", since: now.addingTimeInterval(-70),
                               activity: ClaudeActivity(text: "Thinking", since: now.addingTimeInterval(-2))),
                    ClaudeTask(id: "b1", kind: .command, title: "Run the full test suite", since: now.addingTimeInterval(-370)),
                 ]],
                 colors: ["/Users/me/code/lcu": 0, "/Users/me/code/microsandbox": 1, "/Users/me/code/lookout": 2,
                          "/Users/me/code/lcu-research": 3],
                 unlisted: [hidden])
    }

}

/// `--check owner/repo`: headless refresh against live GitHub, prints what the inbox would contain for the repo's PRs, issues
/// and workflows.
@MainActor
enum Check {
    static func run(store: Store, repo: String) {
        store.persists = false
        Task {
            await store.authenticate()
            print("auth:", store.me?.login ?? "nil", store.tokenSource?.rawValue ?? "", store.authError ?? "")
            let scope = Pick<RepoRef>(include: [.repo(repo)])
            store.categories = [
                InboxCategory(name: "PRs", symbol: "arrow.triangle.pull", color: .violet,
                              rules: [Rule(scope: Scope(kind: .pr, in: scope), createdAt: .distantPast)]),
                InboxCategory(name: "Issues", symbol: "smallcircle.filled.circle", color: .green,
                              rules: [Rule(scope: Scope(kind: .issue, in: scope), createdAt: .distantPast)]),
                InboxCategory(name: "CI", symbol: "xmark.seal", color: .red,
                              rules: [Rule(scope: Scope(kind: .workflow, in: scope), conditions: [.workflow([.failing, .pending, .passing])],
                                           createdAt: .distantPast)]),
            ]
            await store.pollAll()
            for entry in store.entries.sorted(by: { $0.thing.updatedAt > $1.thing.updatedAt }).prefix(25) {
                let category = store.categories.first { $0.id == entry.categoryID }?.name ?? ""
                print(String(format: "%-7@ %@ %@  %@  [%@]", category, shortAgo(entry.thing.updatedAt), entry.id,
                             String(entry.thing.title.prefix(50)), entry.facts.map(\.label).joined(separator: " · ")))
            }
            print("things:", store.things.count, "error:", store.inboxError ?? "none")
            print("rate:", store.gh.rateRemaining ?? -1, "graphql:", store.gh.graphqlRemaining ?? -1)
            exit(0)
        }
    }
}

/// `--claude`: what the Router reads of Claude's sessions from the desktop app right now.
@MainActor
enum ClaudeCheck {
    static func run() {
        var start = Date()
        let result = Claude.SessionReader().read()
        let sessionsMS = Int(Date().timeIntervalSince(start) * 1000)
        start = Date()
        let unread = Claude.unreadIDs()
        print("installed:", Claude.isInstalled, "running:", Claude.isRunning, "sessions read in", sessionsMS, "ms, dots in",
              Int(Date().timeIntervalSince(start) * 1000), "ms")
        switch result {
        case .failure(let error): print("sessions:", error)
        case .success(let sessions):
            print("sessions:", sessions.count, "archived:", sessions.filter(\.isArchived).count)
            for s in sessions.filter({ !$0.isArchived }).sorted(by: { $0.lastActivity > $1.lastActivity }).prefix(12) {
                let state = s.running ? "running" : s.summary?.blocked == true ? "blocked" : s.summary == nil ? "-" : "done"
                print(String(format: "%-8@ %-7@ %-5@ turns=%-4d %@ · %@", state, shortAgo(s.lastActivity),
                             unread?.contains(s.id) == true ? "dot" : "", s.completedTurns, s.title, s.folderName))
            }
        }
        print("unread dots:", unread.map { "\($0.count)" } ?? "unreadable")
        if case .success(let sessions) = result {
            let reader = Claude.ActivityReader()
            for s in sessions where s.running {
                print("  working:", s.title, "→", s.cliID.flatMap { reader.activity(for: $0) }.map { "\($0.text) (since \(shortAgo($0.since)))" } ?? "no transcript")
            }
            let folders = Claude.taskFolders()
            let open = Claude.openTaskOutputs()
            let tasks = Claude.TaskReader()
            for s in sessions where !s.running && !s.isArchived {
                guard let cli = s.cliID, let folder = folders[cli] else { continue }
                for t in tasks.tasks(in: folder, transcript: reader.transcript(cli), openOutputs: open) {
                    print("  background:", s.title, "→", t.kind == .agent ? "agent" : "command", t.title,
                          t.activity.map { "(\($0.text))" } ?? "", "since \(shortAgo(t.since))")
                }
            }
        }
        if CommandLine.arguments.contains("--watch") { watch(); return }
        if case .success(let sessions) = result, let unread {
            for s in sessions where unread.contains(s.id) { print("  dot:", s.title, s.isArchived ? "(archived)" : "", shortAgo(s.lastActivity)) }
        }
        exit(0)
    }

    /// `--claude --watch`: the extension live against the real app, nothing saved; prints every change.
    private static var watchers: [FolderWatcher] = []

    private static func watch() {
        let store = Store()
        store.persists = false
        store.agents.enabled = true
        store.agents.enabledAt = Date()
        var last = ""
        func dump(_ reason: String) {
            store.refreshClaude()
            let lines = store.allAgentRows.map { r in
                "\(r.label) \(r.unread ? "UNREAD" : "read  ") \(String(describing: r.group).padding(toLength: 8, withPad: " ", startingAt: 0)) \(r.session.title)"
            }
            let text = lines.joined(separator: "\n")
            guard text != last else { return }
            last = text
            print("--- \(Date().formatted(date: .omitted, time: .standard)) (\(reason))\n" + text)
            fflush(stdout)
        }
        dump("start")
        // Held for the life of the process (the run loop never returns), so the stream keeps delivering.
        watchers.append(FolderWatcher([Claude.sessionsDir, Claude.localStorageDir]) { MainActor.assumeIsolated { dump("files") } })
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in MainActor.assumeIsolated { dump("timer") } }
    }
}
