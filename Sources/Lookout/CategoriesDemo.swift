import AppKit
import SwiftUI

// Shots of the category editor (`--playground-shots <dir> categories`): the real views, offscreen, on demo categories and
// groups seeded here. Each is the hub page's width, tall enough to show the whole page.

enum CategoriesShot: String, CaseIterable {
    case page, editor, actions, impossible, groups, autocomplete, single, switched, ci, draft, kinds

    var name: String { "right-categories-\(rawValue)" }

    var height: CGFloat {
        switch self {
        case .page: 760
        case .editor: 780
        case .actions: 1100
        case .impossible: 900
        case .groups: 800
        case .autocomplete: 400
        case .single: 520
        case .switched: 560
        case .ci: 520
        case .draft: 620
        case .kinds: 520
        }
    }
}

@MainActor
enum CategoriesDemo {
    static let width: CGFloat = 480

    static let contributing = InboxGroup(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!, name: "Contributing", kind: .repos,
                                         members: ["superradcompany/microsandbox", "libkrun/libkrun"])
    static let core = InboxGroup(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!, name: "Core team", kind: .people,
                                 members: ["toksdotdev", "appcypher", "stephenberry"])
    static let mine = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
    static let owed = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
    static let reviews = UUID(uuidString: "00000000-0000-0000-0000-0000000000B3")!
    static let single = UUID(uuidString: "00000000-0000-0000-0000-0000000000B4")!
    static let switched = UUID(uuidString: "00000000-0000-0000-0000-0000000000B5")!

    static let sessionAction = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
    static let commentAction = UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!
    static let rerunAction = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!

    /// Actions on a category, and what they did for some of its things (the hub's rows say it). Nothing here is done for real.
    static func seedActions(_ store: Store, categories names: [String: [CategoryAction]]) {
        for i in store.categories.indices {
            if let actions = names[store.categories[i].name] { store.categories[i].actions = ActionList(actions) }
        }
        var ledger = ActionLedger()
        _ = InboxActions.plan(entries: store.entries, categories: store.categories, ledger: &ledger, me: store.me?.login ?? "demo")
        let now = Date()
        func record(_ category: String, _ n: Int, _ action: UUID, _ state: ActionRun.State, _ detail: String, ago: TimeInterval,
                    url: URL? = nil, session: String? = nil) {
            guard let c = store.categories.first(where: { $0.name == category }),
                  let e = store.entries.filter({ $0.categoryID == c.id }).sorted(by: { $0.id < $1.id })[safe: n] else { return }
            ledger.set(ActionRun(category: c.id, thing: e.id, action: action, trigger: "enter", state: state,
                                 at: now.addingTimeInterval(-ago), detail: detail, url: url, sessionID: session))
        }
        record("Contributions", 0, sessionAction, .done, "asked the Router", ago: 130, session: "local_demo")
        record("Contributions", 1, sessionAction, .failed, "the Router is off", ago: 900)
        record("Contributions", 2, sessionAction, .done, "asked the Router", ago: 3 * 3600)
        record("Reviews for you", 0, commentAction, .done, "commented", ago: 600,
               url: URL(string: "https://github.com/ziglang/zig/pull/1#issuecomment-1"))
        record("CI", 0, rerunAction, .done, "re-ran 2 jobs", ago: 300)
        // The second of the Contributions' things is waiting its turn.
        if let c = store.categories.first(where: { $0.name == "Contributions" }),
           let e = store.entries.filter({ $0.categoryID == c.id }).sorted(by: { $0.id < $1.id })[safe: 3] {
            ledger.runs[ActionLedger.key(c.id, e.id, sessionAction, "enter")] = nil
        }
        store.actionLedger = ledger
    }

    static let demoActions: [String: [CategoryAction]] = [
        "Contributions": [CategoryAction(id: sessionAction, kind: .askRouter(prompt: "Address what {url} is waiting on."))],
        "Reviews for you": [CategoryAction(id: commentAction, kind: .comment("Thanks {author}, I'll take a look today."))],
        "CI": [CategoryAction(id: rerunAction, kind: .rerun)],
    ]

    /// Demo categories and groups, over whatever the scenario put there.
    static func seed(_ store: Store) {
        let me = PersonRef.me
        let greptile = PersonRef.user("greptile-apps[bot]")
        store.groups = [contributing, core]
        store.categories = [
            InboxCategory(id: mine, name: "Mine", symbol: "person", color: .blue, rules: [
                Rule(scope: Scope(kinds: [.pr], by: Pick(include: [me]), in: Pick(include: [.group(contributing.id)])), match: .any, conditions: [
                    .lastComment(by: Pick(include: [.maintainers, greptile])),
                    .unresolvedThreads(startedBy: Pick(include: [.maintainers, greptile]), lastReplyBy: Pick(except: [me])),
                    .changesRequested(by: Pick(include: [.maintainers])),
                    .newComment(by: Pick(include: [.maintainers]), since: .myLastReview),
                    .behindBase,
                    .greptileBelow(5),
                ]),
            ]),
            InboxCategory(id: reviews, name: "Review requests", symbol: "eye", color: .violet, rules: [
                Rule(scope: Scope(kinds: [.pr], to: Pick(include: [me]), toRoles: [.reviewRequested], in: Pick(include: [.involved])),
                     match: .all, conditions: [.status([.open]), .checks([.passing, .pending])]),
                Rule(scope: Scope(kinds: [.issue], to: Pick(include: [me]), toRoles: [.assigned]), conditions: []),
            ]),
            InboxCategory(name: "Dependabot", symbol: "shippingbox", color: .gray, rules: [
                Rule(scope: Scope(kinds: [.pr], by: Pick(include: [.bots]), in: Pick(include: [.contributed])), conditions: []),
            ], notifies: false, hidden: true),
        ] + InboxStore.defaultCategories
        store.categories[0].actions = ActionList([
            CategoryAction(id: sessionAction, kind: .askRouter(prompt: "Address what {url} is waiting on.")),
            CategoryAction(id: commentAction, kind: .comment("Thanks {author}, taking another look."), trigger: .eachFact),
        ])
        // Fetched things: the preview has history for both repos.
        let now = Date()
        func thing(_ repo: String, _ n: Int, _ title: String) -> Thing {
            Thing(id: "pr:\(repo)#\(n)", kind: .pr, repo: repo, number: n, title: title,
                  url: URL(string: "https://github.com/\(repo)/pull/\(n)")!,
                  author: Person(login: "0xpolarzero"), createdAt: now.addingTimeInterval(-86400 * 3), updatedAt: now.addingTimeInterval(-3600))
        }
        let maintainer = Person(login: "toksdotdev", association: .member)
        let greptileBot = Person(login: "greptile-apps[bot]", isBot: true)
        var warm = thing("superradcompany/microsandbox", 412, "Warm pool for sandboxes")
        warm.comments = [ThingComment(id: "c1", author: maintainer, at: now.addingTimeInterval(-3600), snippet: "Can we pool by image?")]
        warm.greptileScore = 4
        var mounts = thing("superradcompany/microsandbox", 409, "Fix volume mounts on macOS")
        mounts.threads = [ThingThread(id: "t1", isResolved: false, startedBy: greptileBot, lastReplyBy: greptileBot, lastReplyID: "c9",
                                      lastReplyAt: now.addingTimeInterval(-7200), path: "src/mount.rs", snippet: "Unchecked path join")]
        mounts.greptileScore = 5
        var docs = thing("libkrun/libkrun", 398, "Docs: networking")
        docs.reviews = [ThingReview(id: "r1", author: maintainer, state: .changesRequested, at: now.addingTimeInterval(-5400))]
        for t in [warm, mounts, docs, thing("superradcompany/microsandbox", 401, "Bump deps")] {
            store.things[t.id] = t
        }
    }

    /// A category made to have an impossible chip: it can never match, which the editor says in red.
    static func seedImpossible(_ store: Store) {
        let me = PersonRef.me
        store.categories.insert(InboxCategory(id: owed, name: "Owed reviews", symbol: "text.magnifyingglass", color: .amber, rules: [
            Rule(scope: Scope(kinds: [.pr], by: Pick(include: [me]), to: Pick(include: [me]), toRoles: [.reviewRequested],
                              in: Pick(include: [.group(UUID())])),
                 match: .all, conditions: [
                    .approved(by: Pick(include: [me])),
                    .status([.draft, .merged]),
                    .checks([.failing]),
                    .noActivity(days: 7),
                 ]),
        ]), at: 1)
    }

    static func window(_ shot: CategoriesShot, store: Store) -> NSWindow {
        seed(store)
        var preview = CategoriesPreview()
        let me = PersonRef.me
        switch shot {
        case .page: break
        case .draft:
            // New category, before Create: a draft with nothing typed yet (Create waits for a name).
            preview.draft = CategoriesView.newDraft(after: store.categories)
            preview.editing = .new
        case .editor: preview.editing = .existing(mine)
        case .actions:
            store.categories[0].actions.items.append(CategoryAction(kind: .rerun))
            preview.editing = .existing(mine)
        case .impossible:
            seedImpossible(store)
            preview.editing = .existing(owed)
        case .groups: preview.expandedGroup = contributing.id
        case .autocomplete: break
        case .single:
            store.categories.insert(InboxCategory(id: single, name: "Low Greptile", symbol: "eye", color: .green, rules: [
                Rule(scope: Scope(kinds: [.pr], by: Pick(include: [me])), conditions: [.greptileBelow(4)]),
            ]), at: 0)
            preview.editing = .existing(single)
        case .ci:
            // A Workflows rule with two repos in its required `in`.
            store.categories.insert(InboxCategory(id: switched, name: "Builds", symbol: "hammer", color: .red, rules: [
                Rule(scope: Scope(kinds: [.workflow], in: Pick(include: [.repo("superradcompany/microsandbox"), .repo("libkrun/libkrun")])),
                     conditions: [.workflow([.failing])]),
            ]), at: 0)
            preview.editing = .existing(switched)
        case .kinds:
            // One rule for PRs and issues alike, in an org and the repos you own; an issue fetched there counts in its preview.
            store.ownedRepos = ["0xpolarzero/lookout"]
            var issue = Thing(id: "issue:superradcompany/microsandbox#77", kind: .issue, repo: "superradcompany/microsandbox", number: 77,
                              title: "Sandboxes leak on SIGTERM", url: URL(string: "https://github.com/superradcompany/microsandbox/issues/77")!,
                              author: Person(login: "appcypher"), createdAt: Date().addingTimeInterval(-86400), updatedAt: Date())
            issue.comments = [ThingComment(id: "c7", author: Person(login: "toksdotdev", association: .member), at: Date(), snippet: "Repro?")]
            store.things[issue.id] = issue
            store.categories.insert(InboxCategory(id: switched, name: "My repos", symbol: "folder", color: .blue, rules: [
                Rule(scope: Scope(kinds: [.pr, .issue], in: Pick(include: [.owned, .owner("superradcompany")])),
                     conditions: [.newComment(by: Pick(include: [.maintainers]))], createdAt: .distantPast),
            ]), at: 0)
            preview.editing = .existing(switched)
        case .switched:
            // A PR rule turned into a Workflows one: what could not come along is said under it.
            let before = Rule(scope: Scope(kinds: [.pr], by: Pick(include: [me]), in: Pick(include: [.repo("superradcompany/microsandbox")])),
                              conditions: [.greptileBelow(4), .unresolvedThreads(startedBy: nil, lastReplyBy: nil),
                                           .lastComment(by: Pick(include: [.maintainers]))])
            let result = RuleEditing.switchKinds(before, to: [.workflow])
            store.categories.insert(InboxCategory(id: switched, name: "Builds", symbol: "hammer", color: .red, rules: [result.rule]), at: 0)
            preview.editing = .existing(switched)
            preview.notice = RuleEditing.droppedNotice(result.dropped, for: [.workflow])
        }
        let size = CGSize(width: width, height: shot.height)
        let data = EditorData(store: store)
        // The autocomplete's popover, drawn where popovers can't be: a people slot with two people picked.
        let popover = SlotPopover(pick: Pick<PersonRef>(include: [.user("toksdotdev"), .user("appcypher")]), allowsExcept: true,
                                  title: data.personTitle, symbol: data.personSymbol,
                                  options: { q, p in data.peopleOptions(q, p) }, parse: data.parsePerson,
                                  groupable: 2, groupNoun: "people", onPick: { _, _ in }, onSaveGroup: { _ in },
                                  removal: ("Remove by", {}))
        let root = Group {
            if shot == .autocomplete {
                popover.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(CDS.borderStrong, lineWidth: 1))
                    .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                CategoriesView(store: store, preview: preview)
            }
        }
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(CDS.Surface.s0)
            .environment(\.colorScheme, .dark)
            .tipSpace()
        let hosting = NSHostingView(rootView: root)
        hosting.frame.size = size
        let window = ShotWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        ShotRun.show(window)
        return window
    }
}


private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
