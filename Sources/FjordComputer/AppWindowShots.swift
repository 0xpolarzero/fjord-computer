import AppKit
import SwiftUI

// Dev entries for the app window: `--window` opens it alone on the demo data; `--window-shots <dir> [substring...]` renders
// its destinations as PNGs, offscreen, the title bar included.

@MainActor
enum AppWindowDev {
    /// `--window`: the window on the demo data (the Router's cards included), the app ending with it.
    static func open(_ store: Store) -> AppWindowController {
        Demo.populate(store, .router)
        let controller = AppWindowController(store: store, remembers: false)
        controller.onClose = { NSApp.terminate(nil) }
        controller.show()
        return controller
    }
}

/// The window of a shot: it may sit anywhere, so it can be off every screen, and it never becomes key or main, so no field
/// in it takes keyboard focus or the keystrokes typed in other apps while a shot runs.
final class ShotWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The shot runs (`--window-shots`, `--playground-shots`) never activate the app.
@MainActor
enum ShotRun {
    /// Before any shot window is made: an accessory app (no Dock icon, no menu bar) that nothing activates.
    static func prepare() {
        NSApp.setActivationPolicy(.accessory)
    }

    /// Shows a shot's window offscreen: ordered front without activating the app or making the window key.
    static func show(_ window: NSWindow) {
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        window.orderFrontRegardless()
    }
}

@MainActor
enum AppWindowShots {
    struct Shot {
        let name: String
        /// Resolved against the demo data when the shot is made.
        let destination: (Store) -> AppDestination
        var sidebarHidden = false
        var size = CGSize(width: 1280, height: 800)
        /// Sets the Router's composer up (a draft with a pill in it).
        var compose: ((RouterModel, Store) -> Void)?
        /// The window's look; nil follows the Mac.
        var appearance: NSAppearance.Name?
    }

    static let catalog: [Shot] = [
        Shot(name: "category") { $0.shownCategories[0].id.asCategory },
        Shot(name: "reviews") { store in store.shownCategories.first { $0.name.contains("Review") }?.id.asCategory ?? .done },
        Shot(name: "ci") { store in store.shownCategories.first(where: \.isCI)?.id.asCategory ?? .done },
        Shot(name: "done") { _ in .done },
        Shot(name: "router") { _ in .router },
        Shot(name: "router-composing", destination: { _ in .router }, compose: { model, store in
            let folder = store.knownFolders.first { !$0.isEmpty } ?? "/Users/me/code/lookout"
            model.pointers = [.project(folder)]
            model.draft = "check the failing tests in \(MentionText.markString) and tell me what you find"
        }),
        // Typing paused: Jev's pick of where the draft goes is a ghost chip over the composer, its card marked on the page.
        Shot(name: "router-predicting", destination: { _ in .router }, compose: { model, store in
            guard let card = store.openRouterCards.first(where: { $0.kind == .question }) ?? store.openRouterCards.first else { return }
            model.draft = "use sqlite for now, and add an index on the user id"
            let target = "answer:\(card.id)"
            model.live.preview(.init(target: target, title: card.title, detail: store.routerDispatcher.describe(target, store: store),
                                     text: model.draft, mark: card.id))
            model.highlighted = card.id
        }),
        Shot(name: "router-history", destination: { _ in .router }, size: CGSize(width: 1280, height: 1000), compose: { model, store in
            store.router.cards = store.router.cards.map { var c = $0; if c.isOpen { c.addressedAt = Date(); c.addressedBy = .you }; return c }
            if let d = store.router.decisions.first(where: { !$0.links.changes.isEmpty }) { model.expanded.insert(d.id.uuidString) }
        }),
        Shot(name: "router-summary-history", destination: { _ in .router }, size: CGSize(width: 1280, height: 1000), compose: { model, store in
            store.router.cards = store.router.cards.map { var c = $0; if c.isOpen { c.addressedAt = Date(); c.addressedBy = .you }; return c }
            if let summary = store.router.summaries.last { model.expanded.insert(RouterPage.Entry.summary(summary).id) }
        }),
        // Four sessions working, each but the last with its summary under it, the last being summarized.
        Shot(name: "router-working-summaries", destination: { _ in .router }, size: CGSize(width: 1280, height: 1000), compose: { model, store in
            for id in ["local_demo-transfer", "local_demo-linux"] { store.claudeSessions[id]?.running = true }
            let rows = store.routerWorkingRows
            for row in rows.dropLast() where store.router.summaries.allSatisfy({ $0.sessionID != row.id }) {
                store.addSummary(RouterSummary(at: Date().addingTimeInterval(-60), text: RouterSummarizer.canned(store.summarySubject(row)),
                                               sessionID: row.id, title: row.session.title))
            }
            model.summarizer.runner = { _ in try await Task.sleep(for: .seconds(3600)); return "" }
            if let last = rows.last { model.summarizer.request(last.id, store: store) }
        }),
        Shot(name: "router-replying-history", destination: { _ in .router }, size: CGSize(width: 1280, height: 1000), compose: { model, store in
            store.router.cards = store.router.cards.map { var c = $0; if c.isOpen { c.addressedAt = Date(); c.addressedBy = .you }; return c }
            if let card = store.routerPage.history.last(where: { if case .card = $0 { true } else { false } }) {
                model.tap(card.id, store: store)
            }
        }),
        // A long Needs you: every open card six times over, so the zones would take the page.
        Shot(name: "router-many-needs", destination: { _ in .router }, compose: { _, store in manyNeeds(store) }),
        // A narrow window: Now and History one at a time, the switch and the sections' chips over them; then History.
        Shot(name: "router-narrow-now", destination: { _ in .router }, size: CGSize(width: 900, height: 1000), compose: { _, store in
            manyNeeds(store)
        }),
        Shot(name: "router-narrow-history", destination: { _ in .router }, size: CGSize(width: 900, height: 1000), compose: { model, store in
            manyNeeds(store)
            model.pane = .history
        }),
        // Every section folded to its line, what it holds said on it.
        Shot(name: "router-folded", destination: { _ in .router }, size: CGSize(width: 1280, height: 1000), compose: { model, store in
            Demo.routerTriage(store)
            for zone in RouterZone.allCases { model.setFolded(zone, true) }
        }),
        // Every section open, Waiting and Working with them.
        Shot(name: "router-all-open", destination: { _ in .router }, size: CGSize(width: 1500, height: 1000), compose: { model, store in
            manyNeeds(store)
            for zone in RouterZone.allCases { model.setFolded(zone, false) }
        }),
        // Jev's triage: an OK asked, a turn asking two questions, chips on the finished ones; and the sessions waiting.
        Shot(name: "router-triage-needs", destination: { _ in .router }, size: CGSize(width: 1280, height: 1400), compose: { model, store in
            Demo.routerTriage(store)
            for zone in RouterZone.allCases { model.setFolded(zone, false) }
            model.expandedNeed = store.router.cards.first { $0.kind == .asks }?.id
        }),
        Shot(name: "router-triage-waiting", destination: { _ in .router }, size: CGSize(width: 1280, height: 1000), compose: { model, store in
            Demo.routerTriage(store)
            for zone in RouterZone.allCases { model.setFolded(zone, false) }
        }),
        // A session going in circles in Needs you, one that builds on another's work ready to continue; then what came while
        // you were away at the top of Needs you.
        Shot(name: "router-jev-circles", destination: { _ in .router }, size: CGSize(width: 1280, height: 1400), compose: { model, store in
            Demo.routerJevAttention(store, away: false)
            for zone in RouterZone.allCases { model.setFolded(zone, false) }
        }),
        Shot(name: "router-jev-away", destination: { _ in .router }, size: CGSize(width: 1280, height: 1400), compose: { model, store in
            Demo.routerJevAttention(store, away: true)
            for zone in RouterZone.allCases { model.setFolded(zone, false) }
        }),
        // Now as a canvas: each project a frame, its sessions grouped and joined to their groups by lines.
        Shot(name: "router-canvas", destination: { _ in .router }, size: canvasSize, compose: { model, _ in model.pickCanvas() },
             appearance: .aqua),
        Shot(name: "router-canvas-dark", destination: { _ in .router }, size: canvasSize, compose: { model, _ in model.pickCanvas() },
             appearance: .darkAqua),
        // Jev's triage on the canvas: an OK asked, a turn asking two questions (one answered), sessions waiting and one ready.
        Shot(name: "router-canvas-triage", destination: { _ in .router }, size: canvasSize, compose: { model, store in
            Demo.routerTriage(store)
            model.pickCanvas()
        }, appearance: .aqua),
        // A card at the canvas's 420: its kind, Jev's chips, the approval's tint and how many questions are left.
        Shot(name: "router-canvas-card420", destination: { _ in .router }, size: canvasSize, compose: { model, store in
            Demo.routerTriage(store)
            if let i = store.router.cards.firstIndex(where: { $0.sessionID == "local_demo-api" && $0.isOpen }),
               let asks = store.router.cards[i].asks {
                store.router.cards[i].left = Array(asks.dropFirst().map(\.question))
                store.router.cards[i].total = asks.count
            }
            model.pickCanvas()
            // microsandbox's frame at full size.
            look(model, at: "microsandbox")
        }, appearance: .darkAqua),
        Shot(name: "router-canvas-narrow", destination: { _ in .router }, size: CGSize(width: 1000, height: 760), compose: { model, store in
            Demo.routerTriage(store)
            model.pickCanvas()
        }, appearance: .aqua),
        // A card opened in place on the canvas: the question's form, the plan, a working session's summaries and tasks, a
        // finished turn worth a look, a finished one's details; the canvas gone to it.
        Shot(name: "router-canvas-open-needs", destination: { _ in .router }, size: canvasSize, compose: { model, store in
            model.pickCanvas()
            if let card = store.router.cards.first(where: { $0.kind == .question && $0.isOpen }) {
                model.select(card.id, store: store)
            }
        }, appearance: .aqua),
        Shot(name: "router-canvas-open-plan", destination: { _ in .router }, size: canvasSize, compose: { model, store in
            model.pickCanvas()
            if let card = store.router.cards.first(where: { $0.kind == .plan && $0.isOpen }) { model.select(card.id, store: store) }
        }, appearance: .darkAqua),
        Shot(name: "router-canvas-open-working", destination: { _ in .router }, size: canvasSize, compose: { model, store in
            model.pickCanvas()
            model.canvas.openRow = RouterModel.workingID("local_demo-ci")
        }, appearance: .aqua),
        Shot(name: "router-canvas-open-notes", destination: { _ in .router }, size: canvasSize, compose: { model, store in
            Demo.routerTriage(store)
            model.pickCanvas()
            if let card = model.zones(store).notes.first { model.select(card.id, store: store) }
        }, appearance: .aqua),
        Shot(name: "router-canvas-open-waiting", destination: { _ in .router }, size: canvasSize, compose: { model, store in
            Demo.routerTriage(store)
            model.pickCanvas()
            if let card = model.zones(store).ready.first { model.select(card.id, store: store) }
        }, appearance: .darkAqua),
        // The chips: only Needs you and Working shown, the other groups gone from their frames in place.
        Shot(name: "router-canvas-filter", destination: { _ in .router }, size: canvasSize, compose: { model, store in
            Demo.routerTriage(store)
            model.pickCanvas()
            model.canvas.filter = [.needs, .working]
        }, appearance: .aqua),
        // The frames of finished sessions only, opened from their fold.
        Shot(name: "router-canvas-done-open", destination: { _ in .router }, size: canvasSize, compose: { model, store in
            model.pickCanvas()
            for folder in model.canvasFolders(store, page: model.zones(store)) where folder.doneOnly {
                model.canvas.folderFolds[folder.key] = false
            }
        }, appearance: .darkAqua),
        // The canvas at full size on one frame, the rest of the ground round it.
        Shot(name: "router-canvas-zoom", destination: { _ in .router }, size: canvasSize, compose: { model, store in
            Demo.routerTriage(store)
            model.pickCanvas()
            look(model, at: "lcu")
        }, appearance: .aqua),
        Shot(name: "router-canvas-zoom-dark", destination: { _ in .router }, size: canvasSize, compose: { model, store in
            Demo.routerTriage(store)
            model.pickCanvas()
            look(model, at: "lcu")
        }, appearance: .darkAqua),
        // The history's panel open over the canvas's right side.
        Shot(name: "router-canvas-history", destination: { _ in .router }, size: canvasSize, compose: { model, _ in
            model.pickCanvas()
            model.show(.history)
        }, appearance: .aqua),
        Shot(name: "router-canvas-history-dark", destination: { _ in .router }, size: canvasSize, compose: { model, _ in
            model.pickCanvas()
            model.show(.history)
        }, appearance: .darkAqua),
        // The frames moved by hand: in a row, staggered, Reset layout among the buttons.
        Shot(name: "router-canvas-arranged", destination: { _ in .router }, size: canvasSize, compose: { model, store in
            arranged(model, store)
        }, appearance: .aqua),
        Shot(name: "router-canvas-arranged-dark", destination: { _ in .router }, size: canvasSize, compose: { model, store in
            arranged(model, store)
        }, appearance: .darkAqua),
        // A search on the canvas: only the frames with a match.
        Shot(name: "router-canvas-search", destination: { _ in .router }, size: canvasSize, compose: { model, _ in
            model.pickCanvas()
            model.search.query = "lcu"
        }, appearance: .aqua),
        // Your messages over the composer: one being sent, with what the Router is doing, and one it asks you about.
        Shot(name: "router-canvas-pending", destination: { _ in .router }, size: canvasSize, compose: { model, _ in
            model.pickCanvas()
        }, appearance: .aqua),
        Shot(name: "router-canvas-pending-dark", destination: { _ in .router }, size: canvasSize, compose: { model, _ in
            model.pickCanvas()
        }, appearance: .darkAqua),
        // The message being sent goes to its session once the canvas is up, held mid-arc; an earlier one landed on a card.
        Shot(name: "router-canvas-flight", destination: { _ in .router }, size: canvasSize, compose: { model, store in
            flight(model, store)
        }, appearance: .aqua),
        Shot(name: "router-canvas-flight-dark", destination: { _ in .router }, size: canvasSize, compose: { model, store in
            flight(model, store)
        }, appearance: .darkAqua),
        Shot(name: "settings") { _ in .settings },
        Shot(name: "categories") { _ in .categories },
        Shot(name: "snippets") { _ in .snippets },
        // Two sections, one folded: its row with the counts added up and its caret turned, its categories gone from the sidebar.
        Shot(name: "categories-sections", destination: { _ in .categories }, compose: { _, store in
            let builds = store.createSection(name: "Builds")
            for c in store.categories where c.isCI { store.moveCategory(c.id, toSection: builds.id) }
            store.toggleCollapsed(builds.id)
        }),
        Shot(name: "category-collapsed", destination: { $0.shownCategories[0].id.asCategory }, sidebarHidden: true),
        Shot(name: "router-collapsed", destination: { _ in .router }, sidebarHidden: true),
        Shot(name: "router-760", destination: { _ in .router }, size: CGSize(width: 760, height: 1000)),
        Shot(name: "router-collapsed-760", destination: { _ in .router }, sidebarHidden: true, size: CGSize(width: 760, height: 1000)),
        Shot(name: "category-narrow", destination: { $0.shownCategories[0].id.asCategory }, size: CGSize(width: 1000, height: 640)),
    ]

    private static let canvasSize = CGSize(width: 1440, height: 900)

    /// The canvas at full size on the frame of the project named `name`, once the frames are drawn.
    private static func look(_ model: RouterModel, at name: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard let key = model.canvas.frameRects.keys.first(where: { URL(fileURLWithPath: $0).lastPathComponent == name }) else { return }
            model.canvas.look(at: key)
        }
    }

    /// Every frame moved by hand, as a drag would leave them: in one staggered row, the frames opened.
    private static func arranged(_ model: RouterModel, _ store: Store) {
        Demo.routerTriage(store)
        model.pickCanvas()
        let folders = model.canvasFolders(store, page: model.zones(store))
        for folder in folders where folder.doneOnly { model.canvas.folderFolds[folder.key] = false }
        model.canvas.positions = Dictionary(uniqueKeysWithValues: folders.enumerated().map { i, folder in
            (folder.key, CGPoint(x: CGFloat(i) * (CanvasMetrics.frameWidth + 96), y: i.isMultiple(of: 2) ? 0 : 160))
        })
    }

    /// The demo's message under way sent to its session a moment after the canvas is drawn, its flight held halfway; and
    /// "You: …" on the plan card, as an earlier message left it.
    private static func flight(_ model: RouterModel, _ store: Store) {
        model.pickCanvas()
        model.canvas.freezeFlight = 0.5
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            if let card = store.router.cards.first(where: { $0.kind == .plan && $0.isOpen }) {
                model.canvas.land("run it on the lab box first", on: card.id)
            }
            guard let i = store.router.decisions.lastIndex(where: { RouterFlights.isMessage($0) && $0.outcome == .pending
                                                                    && !store.routerDispatcher.askBacks.map(\.id).contains($0.id) }) else { return }
            var decisions = store.router.decisions
            let text = decisions[i].triggerText
            decisions[i].add(.sent(to: "Repository ownership transfer setup", text: text, original: nil), session: "local_demo-transfer")
            decisions[i].outcome = .done
            store.router.decisions = decisions
        }
    }

    /// Every open card six times over, so the zones would take the page.
    private static func manyNeeds(_ store: Store) {
        let open = store.router.cards.filter(\.isOpen)
        store.router.cards += (1...5).flatMap { n in open.map { var c = $0; c.id += "#copy\(n)"; return c } }
    }

    /// `--window-shots <dir> [substring...]`.
    static func run(to dir: String) {
        let arguments = CommandLine.arguments
        let start = (arguments.firstIndex(of: "--window-shots") ?? 0) + 2
        let filters = Array(arguments.dropFirst(start).filter { !$0.hasPrefix("--") }).map { $0.lowercased() }
        let shots = catalog.filter { shot in filters.isEmpty || filters.contains { shot.name.contains($0) } }
        guard !shots.isEmpty else {
            print("No shot matches \(filters.joined(separator: ", ")). \(catalog.count) shots, e.g. \(catalog[0].name)")
            exit(1)
        }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        ShotRun.prepare()
        Task {
            for shot in shots {
                let window = open(shot)
                try? await Task.sleep(for: .seconds(2))
                capture(window, to: "\(dir)/window-\(shot.name).png")
                window.close()
            }
            print("\(shots.count) shots in \(dir)")
            exit(0)
        }
    }

    private static func open(_ shot: Shot) -> NSWindow {
        let store = Store()
        Demo.populate(store, .router)
        let navigator = AppNavigator(start: shot.destination(store), defaults: nil)
        let routerModel = RouterModel()
        shot.compose?(routerModel, store)
        let root = AppRootView(store: store, navigator: navigator, routerModel: routerModel, hub: HubState(),
                               checksClaudeCode: false,
                               sidebar: SidebarState(defaults: nil, collapsed: shot.sidebarHidden),
                               // Glass can't be captured: shots draw the opaque chrome, whatever the Mac's settings.
                               chrome: Chrome(mode: .opaque))
        let controller = NSHostingController(rootView: root)
        controller.sizingOptions = []
        let window = ShotWindow(contentRect: NSRect(origin: .zero, size: shot.size),
                                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                backing: .buffered, defer: false)
        AppWindowController.style(window)
        if let look = shot.appearance { window.appearance = NSAppearance(named: look) }
        window.contentViewController = controller
        window.setContentSize(shot.size)
        ShotRun.show(window)
        return window
    }

    /// The content as drawn (the title bar and its toolbar belong to the window server, which a CLI can't ask for the
    /// window without screen-recording permission).
    private static func capture(_ window: NSWindow, to path: String) {
        guard let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

private extension UUID {
    var asCategory: AppDestination { .category(self) }
}
