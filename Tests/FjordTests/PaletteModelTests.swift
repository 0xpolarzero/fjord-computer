import AppKit
import Foundation
import Testing
@testable import Fjord

/// The palette's state: the empty palette's groups, the ranked list and its send row, the selection's rules, the actions
/// page, and running an action. Sources are fixed items, so the matcher is not under test here.
@MainActor
@Suite struct PaletteModelTests {
    /// What an action did, and whether the palette was still open when it did.
    final class Ran {
        var openWhenRun: [Bool] = []
        var titles: [String] = []
    }

    private func item(_ id: String, _ title: String, kind: PaletteItem.Kind = .entry, ran: Ran? = nil,
                      model: @escaping () -> PaletteModel? = { nil }) -> PaletteItem {
        PaletteItem(id: id, kind: kind, title: title, icon: .symbol("circle"), actions: [
            PaletteAction(id: "\(id).open", title: "Open", run: { ran?.openWhenRun.append(model()?.isOpen ?? false); ran?.titles.append("open \(title)") }),
            PaletteAction(id: "\(id).copy", title: "Copy link", run: { ran?.titles.append("copy \(title)") }),
            PaletteAction(id: "\(id).archive", title: "Archive", destructive: true, run: { ran?.titles.append("archive \(title)") }),
        ])
    }

    private func make(_ sources: PaletteSources, usage: PaletteUsage? = nil) -> PaletteModel {
        let store = InboxFixture.store([])
        let model = PaletteModel(store: store, navigator: AppNavigator(fallback: .done, defaults: nil), routerModel: RouterModel(),
                                 hub: HubState(), usage: usage, sources: sources)
        model.later = { $0() }
        return model
    }

    private func send() -> PaletteItem { item("send:router", "Send to the Router", kind: .send) }

    private func ids(_ model: PaletteModel) -> [String] { model.hits.map(\.id) }

    private func usage() -> (PaletteUsage, UserDefaults) {
        let suite = "palette-model-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (PaletteUsage(defaults: defaults), defaults)
    }

    // MARK: The empty palette

    @Test func theEmptyPaletteListsWhatNeedsYouThenRecentsWithoutRepeats() {
        let (usage, _) = usage()
        let a = item("card:a", "Which branch?", kind: .card), b = item("card:b", "Approve the plan", kind: .card)
        let c = item("entry:c", "Fix flaky test"), d = item("entry:d", "Bump the client")
        let model = make(.fixed([a, b, c, d], needsYou: [a, b]), usage: usage)
        usage.record("entry:c", query: "")
        usage.record("card:a", query: "")
        usage.record("entry:gone", query: "")
        model.open()
        #expect(model.sections.map(\.title) == ["Needs you", "Recents"])
        #expect(model.sections[0].hits.map(\.id) == ["card:a", "card:b"])
        // The last pick that is still known, not repeating what already needs you.
        #expect(model.sections[1].hits.map(\.id) == ["entry:c"])
        #expect(model.selection == "card:a")
    }

    @Test func triageItemsInNeedsYouAreCappedAtFiveAfterTheRouterCards() {
        let router = [item("card:1", "Question", kind: .card)]
        let triage = (1...8).map { item("entry:\($0)", "Item \($0)") }
        var sources = PaletteSources.fixed([])
        sources.router = { _ in PaletteSourceOutput(needsYou: router, items: router) }
        sources.triage = { _ in PaletteSourceOutput(needsYou: triage, items: triage) }
        let model = make(sources)
        model.open()
        #expect(model.sections.count == 1 && model.sections[0].title == "Needs you")
        #expect(model.sections[0].hits.map(\.id) == ["card:1", "entry:1", "entry:2", "entry:3", "entry:4", "entry:5"])
    }

    @Test func withNothingToShowItFallsBackToThePages() {
        let pages = [item("page:router", "Router", kind: .page), item("page:settings", "Settings", kind: .page)]
        let model = make(.fixed(pages + [item("entry:1", "A thing")]))
        model.open()
        #expect(model.sections.map(\.title) == ["Go to"])
        #expect(ids(model) == ["page:router", "page:settings"])
    }

    @Test func anItemTwoSourcesMakeIsListedOnce() {
        let shared = item("entry:1", "Shared title")
        var sources = PaletteSources.fixed([shared, item("entry:2", "Shared other")])
        sources.places = { _ in PaletteSourceOutput(needsYou: [shared], items: [shared]) }
        let model = make(sources)
        model.open()
        model.setQuery("shared")
        #expect(ids(model).filter { $0 == "entry:1" }.count == 1)
        #expect(Set(ids(model)) == ["entry:1", "entry:2"])
    }

    // MARK: Typing

    @Test func theSendRowIsLastAndTheOnlyRowWhenNothingMatches() {
        let model = make(.fixed([item("entry:1", "Fix flaky test"), item("entry:2", "Fix the build")], send: send()))
        model.open()
        #expect(model.canSend && model.placeholder == "Search or send")
        model.setQuery("fix")
        #expect(ids(model).last == "send:router" && ids(model).count == 3)
        #expect(model.selection == ids(model).first)
        model.setQuery("zzzqx")
        #expect(ids(model) == ["send:router"] && model.selection == "send:router")
    }

    @Test func withoutARouterThatCanSendThereIsNoSendRowAndNoResultsIsEmpty() {
        let model = make(.fixed([item("entry:1", "Fix flaky test")]))
        model.open()
        #expect(!model.canSend && model.placeholder == "Search")
        model.setQuery("zzzqx")
        #expect(model.hits.isEmpty && model.selection == nil)
    }

    @Test func resultsAreCappedAtFifty() {
        let items = (1...80).map { item("entry:\($0)", "Same title \($0)") }
        let model = make(.fixed(items, send: send()))
        model.open()
        model.setQuery("same")
        // Fifty hits, then the send row.
        #expect(model.hits.count == PaletteModel.limit + 1 && model.hits.last?.id == "send:router")
    }

    // MARK: Selection

    @Test func aNewQuerySelectsTheFirstRowAndADataChangeKeepsTheItem() {
        var items = [item("entry:1", "Fix one"), item("entry:2", "Fix two"), item("entry:3", "Fix three")]
        var sources = PaletteSources.fixed([])
        sources.router = { _ in PaletteSourceOutput(items: items) }
        let model = make(sources)
        model.open()
        model.setQuery("fix")
        model.move(down: true)
        let picked = model.selection
        #expect(picked == ids(model)[1])
        // A row above arrives: the pick stays on the item it was on.
        items.insert(item("entry:0", "Fix zero"), at: 0)
        model.reload()
        #expect(model.selection == picked)
        // The picked item leaves: the first row is selected.
        items.removeAll { $0.id == picked }
        model.reload()
        #expect(model.selection == ids(model).first)
        // A new query starts at the first row, whatever was selected.
        model.move(down: true)
        model.setQuery("fi")
        #expect(model.selection == ids(model).first)
    }

    @Test func theArrowsStayPutAtTheEnds() {
        let model = make(.fixed((1...3).map { item("entry:\($0)", "Fix \($0)") }))
        model.open()
        model.setQuery("fix")
        let rows = ids(model)
        model.move(down: false)
        #expect(model.selection == rows[0])
        model.move(down: true); model.move(down: true); model.move(down: true); model.move(down: true)
        #expect(model.selection == rows[2])
        model.move(down: false)
        #expect(model.selection == rows[1])
    }

    @Test func keyboardMovesAskTheListToScrollButHoverNever() {
        let model = make(.fixed((1...5).map { item("entry:\($0)", "Fix \($0)") }))
        model.open()
        model.setQuery("fix")
        let seq = model.scroll?.seq
        model.move(down: true)
        #expect(model.scroll?.id == ids(model)[1] && model.scroll?.seq != seq)
        let after = model.scroll
        model.pointer(over: ids(model)[3], at: CGPoint(x: 10, y: 10))
        model.pointer(over: ids(model)[3], at: CGPoint(x: 10, y: 40))
        #expect(model.selection == ids(model)[3] && model.scroll == after)
    }

    @Test func thePointerSelectsOnlyAfterMovingMoreThanThreePointsSinceAKey() {
        let model = make(.fixed((1...4).map { item("entry:\($0)", "Fix \($0)") }))
        model.open()
        model.setQuery("fix")
        let rows = ids(model)
        // The first sight of the pointer only notes where it is; a little movement is not a move.
        model.pointer(over: rows[2], at: CGPoint(x: 50, y: 100))
        #expect(model.selection == rows[0])
        model.pointer(over: rows[2], at: CGPoint(x: 52, y: 101))
        #expect(model.selection == rows[0])
        model.pointer(over: rows[2], at: CGPoint(x: 60, y: 101))
        #expect(model.selection == rows[2])
        // A key takes the selection back, and the pointer has to move again.
        model.move(down: false)
        #expect(model.selection == rows[1])
        model.pointer(over: rows[3], at: CGPoint(x: 61, y: 101))
        #expect(model.selection == rows[1])
        model.pointer(over: rows[3], at: CGPoint(x: 80, y: 101))
        model.pointer(over: rows[3], at: CGPoint(x: 90, y: 101))
        #expect(model.selection == rows[3])
        // Rows scrolling under a still pointer is the same spot again: not the pointer.
        model.move(down: false)
        model.pointer(over: rows[0], at: CGPoint(x: 90, y: 101))
        #expect(model.selection == rows[2])
    }

    // MARK: Actions page

    @Test func tabOpensTheActionsPageAndEscOrBackspaceReturnsToTheListAsItWas() {
        let model = make(.fixed([item("entry:1", "Fix one"), item("entry:2", "Fix two")]))
        model.open()
        model.setQuery("fix")
        model.move(down: true)
        let picked = model.selection
        model.showActions()
        #expect(model.page == .actions(picked!) && model.query.isEmpty)
        #expect(model.actionRows.map(\.title) == ["Open", "Copy link", "Archive"])
        #expect(model.selection == "\(picked!).open")
        // Typing filters the actions.
        model.setQuery("arch")
        #expect(model.actionRows.map(\.title) == ["Archive"] && model.selection == "\(picked!).archive")
        // Backspace in a field that still holds text is the field's.
        #expect(!model.backspaceOnEmpty())
        model.setQuery("")
        #expect(model.backspaceOnEmpty())
        #expect(model.page == .list && model.query == "fix" && model.selection == picked)
        // Esc on the actions page goes back; on the list it closes.
        model.showActions()
        model.escape()
        #expect(model.isOpen && model.page == .list)
        model.escape()
        #expect(!model.isOpen)
    }

    @Test func backspaceOnAnEmptyListDoesNothing() {
        let model = make(.fixed([item("page:1", "Router", kind: .page)]))
        model.open()
        #expect(!model.backspaceOnEmpty() && model.isOpen)
    }

    // MARK: Running

    @Test func runningClosesFirstThenRunsAndRecordsThePick() async {
        let (usage, _) = usage()
        let ran = Ran()
        var held: PaletteModel?
        let a = item("entry:1", "Fix one", ran: ran) { held }
        let model = make(.fixed([a, item("entry:2", "Fix two", ran: ran) { held }]), usage: usage)
        held = model
        // The default turn: the action waits for the next run-loop turn.
        model.later = { work in DispatchQueue.main.async { MainActor.assumeIsolated(work) } }
        model.open()
        model.setQuery("fix")
        model.runSelected()
        #expect(!model.isOpen && ran.titles.isEmpty)
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(ran.titles == ["open \(a.title)"] && ran.openWhenRun == [false])
        #expect(usage.recent(1) == ["entry:1"])
    }

    @Test func aPickFromTheActionsPageRunsThatAction() {
        let ran = Ran()
        let model = make(.fixed([item("entry:1", "Fix one", ran: ran)]))
        model.open()
        model.setQuery("fix")
        model.showActions()
        model.move(down: true)
        model.runSelected()
        #expect(!model.isOpen && ran.titles == ["copy Fix one"])
    }

    @Test func aClickPicksTheRowAndRunsItsFirstAction() {
        let ran = Ran()
        let model = make(.fixed([item("entry:1", "Fix one", ran: ran), item("entry:2", "Fix two", ran: ran)]))
        model.open()
        model.setQuery("fix")
        model.pick("entry:2")
        #expect(!model.isOpen && ran.titles == ["open Fix two"])
    }

    @Test func closingClearsWhatWasTypedAndOpensAgainEmpty() {
        let model = make(.fixed([item("page:1", "Router", kind: .page)]))
        model.open()
        model.setQuery("rou")
        model.close()
        #expect(!model.isOpen && model.query.isEmpty && model.sections.isEmpty && model.selection == nil)
        model.open()
        #expect(model.query.isEmpty && model.selection == "page:1")
    }

    // MARK: Window layout and labels

    @Test func theSurfaceSitsAndSizesAsClaudesDoes() {
        let big = PaletteLayout(window: CGSize(width: 1280, height: 800))
        #expect(big.width == 672 && abs(big.top - 130.55) < 0.01)
        let narrow = PaletteLayout(window: CGSize(width: 700, height: 600))
        #expect(narrow.width == 668 && narrow.top >= 61)
        #expect(big.listHeight(content: 2000, footer: true) == 440 && big.listHeight(content: 2000, footer: false) == 481)
        #expect(big.listHeight(content: 100, footer: true) == 100)
    }

    @Test func aRowsDateIsAShortBucket() {
        let now = Date()
        #expect(PaletteTime.label(nil) == nil)
        #expect(PaletteTime.label(now.addingTimeInterval(-60), now: now) == "Just now")
        #expect(PaletteTime.label(now.addingTimeInterval(-1800), now: now) == "Past hour")
        #expect(PaletteTime.label(now.addingTimeInterval(-3 * 86_400), now: now) == "Past week")
        #expect(PaletteTime.label(now.addingTimeInterval(-20 * 86_400), now: now) == "Past month")
        #expect(PaletteTime.label(now.addingTimeInterval(-200 * 86_400), now: now) == "Past year")
        #expect(PaletteTime.label(now.addingTimeInterval(-800 * 86_400), now: now) == nil)
    }
}
