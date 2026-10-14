import AppKit
import Foundation
import SwiftUI

// The palette's source for Triage: inbox items (archive included), found by title, number or URL, with the actions a row has in
// the inbox; the categories; the Triage runs; and the link between a thing and the session or run that was started for it
// (docs/design/palette/DESIGN.md, Sources). Nothing with Triage off.

/// Made once per palette open, on the main actor, in one pass over the entries: the dictionaries it needs are built before it,
/// and an action holds the store and an id, not the entry, so a few thousand items stay cheap (the entry is read again when the
/// action runs, as it is then).
@MainActor
enum PaletteTriageSource {
    /// How many Triage items the empty palette's "Needs you" lists, after the Router's cards.
    static let needsYouLimit = 5

    static func make(_ context: PaletteContext) -> PaletteSourceOutput {
        let store = context.store
        guard store.triageOn else { return PaletteSourceOutput() }

        var output = PaletteSourceOutput()
        let categories = store.categories
        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sections = Dictionary(store.categorySections.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        let links = Links(store.actionLedger)
        let me = (store.me?.login ?? store.login).lowercased()
        let keys = Keys(store)

        // Inbox items, and which of them need you.
        let entries = store.entries
        output.items.reserveCapacity(entries.count + categories.count + links.runs.count)
        var candidates: [(index: Int, priority: Bool, date: Date)] = []
        for entry in entries {
            let category = byID[entry.categoryID]
            let item = entryItem(entry, category: category, links: links, keys: keys, context: context)
            if entry.isUnread, !entry.isDone, let category, !category.hidden {
                let thing = entry.thing
                let failing = category.isCI && thing.checks == .failing
                let mine = !me.isEmpty && thing.kind == .pr && thing.author?.login.lowercased() == me
                // A CI category only asks for a look when something fails (its badge counts the failing ones).
                if !category.isCI || failing { candidates.append((output.items.count, failing || mine, thing.updatedAt)) }
            }
            output.items.append(item)
        }
        candidates.sort { ($0.priority ? 1 : 0, $0.date) > ($1.priority ? 1 : 0, $1.date) }
        output.needsYou = candidates.prefix(needsYouLimit).map { output.items[$0.index] }

        for category in categories {
            output.items.append(categoryItem(category, section: sections[store.sectionID(of: category) ?? UUID()], context: context))
        }
        for run in links.runs.values {
            output.items.append(runItem(run, number: store.things[run.thingID]?.number, store: store, context: context))
        }
        return output
    }

    // MARK: Inbox items

    /// The shortcuts of the actions an entry shares with the inbox, read once.
    private struct Keys {
        let open: [String]
        let router: [String]
        let read: [String]
        let discard: [String]
        let offersRouter: Bool

        @MainActor init(_ store: Store) {
            open = store.shortcut(.openItem).caps
            router = store.shortcut(.openInRouter).caps
            read = store.shortcut(.toggleRead).caps
            discard = store.shortcut(.discard).caps
            offersRouter = store.offers(.openInRouter)
        }
    }

    /// What was started for each thing: the latest session and the latest Triage run its category actions began, and the
    /// runs themselves. Built from the ledger once.
    private struct Links {
        var session: [String: String] = [:]
        var run: [String: UUID] = [:]
        let runs: [UUID: ComputerRunRecord]

        @MainActor init(_ ledger: ActionLedger) {
            runs = ledger.computerRuns
            var sessionAt: [String: Date] = [:]
            var runAt: [String: Date] = [:]
            for action in ledger.runs.values where action.state != .baselined {
                if let id = action.sessionID, sessionAt[action.thing].map({ action.at > $0 }) ?? true {
                    sessionAt[action.thing] = action.at
                    session[action.thing] = id
                }
                if let id = action.computerRunID, runs[id] != nil, runAt[action.thing].map({ action.at > $0 }) ?? true {
                    runAt[action.thing] = action.at
                    run[action.thing] = id
                }
            }
        }
    }

    private static func entryItem(_ entry: InboxEntry, category: InboxCategory?, links: Links, keys: Keys,
                                  context: PaletteContext) -> PaletteItem {
        let thing = entry.thing
        let store = context.store
        let hidden = category?.hidden ?? false
        let id = entry.id
        let shortRepo = String(thing.repo.split(separator: "/").last ?? "")

        var subtitle: String
        var words = [thing.url.absoluteString, thing.repo, shortRepo]
        if thing.kind == .workflow {
            subtitle = ([thing.repo, thing.workflowName, thing.currentBranch].compactMap { $0 }).joined(separator: " · ")
            words += [thing.workflowName, thing.branch, thing.ciBranch].compactMap { $0 }
            words += ["workflow", "CI", "action", "actions"]
        } else {
            let number = thing.number ?? 0
            subtitle = "\(thing.repo)#\(number)"
            words += ["#\(number)", "\(shortRepo)#\(number)", "\(thing.repo)#\(number)"]
            if let author = thing.author?.login { words += ["@" + author, author] }
            words += thing.kind == .pr ? ["pull request", "PR"] : ["issue"]
        }
        if let title = category?.title { subtitle += " · " + title }
        if entry.isDone { subtitle += " · Archived" }
        switch thing.status {
        case .open: break
        case .draft: words.append("draft")
        case .merged: words.append("merged")
        case .closed: words.append("closed")
        }
        switch thing.checks {
        case .failing?: words += ["failing", "failed"]
        case .passing?: words.append("passing")
        case .pending?: words.append("pending")
        case nil: break
        }
        words += thing.labels

        var actions: [PaletteAction] = []
        let open = PaletteAction(id: "github", title: "Open on GitHub", symbol: "arrow.up.right.square", caps: keys.open) {
            if let entry = fresh(id, store) { store.open(entry) }
        }
        if hidden {
            // Its category isn't shown, so there is no place to show it in: GitHub comes first.
            actions.append(open)
        } else {
            let hub = context.hub
            let go = context.go
            let destination = entry.isDone ? AppDestination.done : .category(entry.categoryID)
            actions.append(PaletteAction(id: "show", title: "Show in Inbox", symbol: category?.symbol ?? "tray") {
                // The selection first: going to the page clears a pick that isn't listed there (AppRootFollow).
                let target = fresh(id, store).map { $0.isDone ? AppDestination.done : .category($0.categoryID) } ?? destination
                hub.selection = "i:" + id
                go(target)
                hub.requestScroll("i:" + id)
            })
            actions.append(open)
        }

        if keys.offersRouter {
            let routerModel = context.routerModel
            let navigator = context.navigator
            actions.append(PaletteAction(id: "router", title: "Open in Router", symbol: EntryMenu.routerSymbol, caps: keys.router) {
                routerModel.open(thing: id, in: navigator)
            })
        }

        if let session = links.session[id], store.claudeSessions[session] != nil {
            actions.append(sessionAction(session, context: context))
        }
        if let run = links.run[id] {
            let go = context.go
            actions.append(PaletteAction(id: "run", title: "Show the Triage run", symbol: "desktopcomputer") { go(.computerRun(run)) })
        }

        if !entry.isDone {
            let unread = entry.isUnread
            actions.append(PaletteAction(id: "read", title: unread ? "Mark as read" : "Mark as unread",
                                         symbol: unread ? "envelope.open" : "envelope.badge", caps: keys.read) {
                guard let entry = fresh(id, store) else { return }
                if unread { store.markSeen(entry) } else { store.markUnread(entry) }
            })
            actions.append(PaletteAction(id: "archive", title: "Archive", symbol: "archivebox", caps: keys.discard, destructive: true) {
                if let entry = fresh(id, store) { store.finish(entry) }
            })
        } else {
            actions.append(PaletteAction(id: "restore", title: "Back to inbox", symbol: "tray.and.arrow.up", caps: keys.discard) {
                if let entry = fresh(id, store) { store.restore(entry) }
            })
        }
        let link = thing.url.absoluteString
        actions.append(PaletteAction(id: "copy", title: "Copy link", symbol: "link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link, forType: .string)
        })

        return PaletteItem(id: "entry:" + id, kind: .entry, title: thing.title, subtitle: subtitle, keywords: words,
                           icon: icon(thing, category: category), dot: entry.isUnread && !entry.isDone ? .attention : nil,
                           date: thing.updatedAt, weight: entry.isDone ? 0.6 : hidden ? 0.7 : 1, actions: actions)
    }

    /// "Open its session": the Router's card for it when the Router is on (its open card if it has one, else its working row),
    /// else the session in the Claude app.
    private static func sessionAction(_ session: String, context: PaletteContext) -> PaletteAction {
        let store = context.store
        let routerModel = context.routerModel
        let go = context.go
        return PaletteAction(id: "session", title: "Open its session", symbol: "bubble.left.and.text.bubble.right") {
            guard store.routerOn else { return store.openAgent(session) }
            if let card = store.router.cards.first(where: { $0.sessionID == session && $0.isOpen }) {
                routerModel.select(card.id, store: store)
                go(.router)
            } else {
                go(.router)
                routerModel.reveal(RouterModel.workingID(session))
            }
        }
    }

    /// A kind's glyph and tint: a PR or issue by its state in its category's colour, a workflow by its checks, as rows draw them.
    private static func icon(_ thing: Thing, category: InboxCategory?) -> PaletteIcon {
        if thing.kind == .workflow {
            let tint: Color = switch thing.checks {
            case .failing?: Theme.red
            case .pending?: Theme.claude
            case .passing?: Theme.green
            case nil: Theme.tertiary
            }
            return .symbol(thing.checks == .passing ? "checkmark.seal.fill" : "xmark.seal.fill", tint: tint)
        }
        let symbol = switch (thing.kind, thing.status) {
        case (.pr, .merged): "arrow.triangle.merge"
        case (.pr, .closed): "xmark.circle"
        case (.pr, _): "arrow.triangle.pull"
        case (_, .closed), (_, .merged): "checkmark.circle"
        default: "smallcircle.filled.circle"
        }
        return .symbol(symbol, tint: category?.color.swatch)
    }

    /// The entry as it is now (its action may run after it was archived or read).
    private static func fresh(_ id: String, _ store: Store) -> InboxEntry? {
        store.entries.first { $0.id == id }
    }

    // MARK: Categories

    private static func categoryItem(_ category: InboxCategory, section: String?, context: PaletteContext) -> PaletteItem {
        let store = context.store
        let go = context.go
        let id = category.id
        var actions: [PaletteAction] = []
        if !category.hidden {
            actions.append(PaletteAction(id: "show", title: "Show", symbol: category.symbol) { go(.category(id)) })
        }
        actions.append(PaletteAction(id: "edit", title: "Edit", symbol: "pencil") { store.editCategory(id, go: go) })
        return PaletteItem(id: "category:" + id.uuidString, kind: .category, title: category.title,
                           subtitle: category.hidden ? "Inbox category · Hidden" : "Inbox category",
                           keywords: [section, "category", "inbox"].compactMap { $0 },
                           icon: .symbol(category.symbol, tint: category.color.swatch), weight: category.hidden ? 0.8 : 1,
                           actions: actions)
    }

    // MARK: Triage runs

    private static func runItem(_ run: ComputerRunRecord, number: Int?, store: Store, context: PaletteContext) -> PaletteItem {
        let go = context.go
        let id = run.id
        var words = [run.repo, run.branch, run.computerName, "Triage run", "computer"]
        if let number { words += ["#\(number)", "\(run.repo)#\(number)"] }
        if let title = store.things[run.thingID]?.title { words.append(title) }
        var actions = [PaletteAction(id: "show", title: "Show", symbol: "desktopcomputer") { go(.computerRun(id)) }]
        if let url = run.pullRequestURL {
            actions.append(PaletteAction(id: "pr", title: "Open the PR", symbol: "arrow.up.right.square") { Link.open(url) })
        }
        let dot: PaletteDot? = run.phase.isEngineOwnedActive ? .running : (run.phase == .failed || run.phase == .unconfirmed ? .attention : nil)
        return PaletteItem(id: "run:" + id.uuidString, kind: .computerRun, title: run.taskTitle,
                           subtitle: "\(run.computerName) · \(run.phase.title)", keywords: words,
                           icon: .symbol("desktopcomputer"), dot: dot, date: run.updatedAt, actions: actions)
    }
}
