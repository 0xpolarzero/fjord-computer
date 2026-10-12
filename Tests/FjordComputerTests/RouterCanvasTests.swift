import AppKit
import Carbon
import Foundation
import SwiftUI
import Testing
@testable import FjordComputer

/// The Router's canvas as you use it: one node open at a time, the keys walking it, Esc folding and clearing, the chips
/// filtering, and scrolls over an open form left to it.
@MainActor
@Suite struct RouterCanvasTests {
    private func demo() -> Store {
        let store = Store()
        Demo.populate(store, .router)
        Demo.routerTriage(store)
        store.interceptOpen = { _ in }
        return store
    }

    private func canvas(_ store: Store) -> RouterModel {
        let model = RouterModel()
        model.layout = .canvas
        return model
    }

    private func key(_ code: Int) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(code))!
    }

    @Test func theKeysWalkTheHistoryThenTheOpenCardsInTheCanvasOrder() throws {
        let store = demo()
        let model = canvas(store)
        let page = model.zones(store)
        let order = RouterCanvasModel.order(model.canvasFolders(store, page: page))
        let open = Set((page.needs + page.ready + page.notes).map(\.id))
        let sections = model.sections(store)
        #expect(sections.needs.map(\.id) == order.filter(open.contains))
        #expect(sections.done.isEmpty)
        #expect(model.cards(store).map(\.id) == sections.earlier.map(\.id) + order.filter(open.contains))
        // The list keeps its own order.
        model.layout = .list
        #expect(model.sections(store).needs.map(\.id) == (page.needs + page.ready).map(\.id))
    }

    @Test func nothingOpensByItselfAndOneNodeIsOpenAtATime() throws {
        let store = demo()
        let model = canvas(store)
        #expect(model.openNeed(store) == nil && model.canvasOpenNode(store) == nil)
        let page = model.zones(store)
        let need = try #require(page.needs.first)
        model.select(need.id, store: store)
        #expect(model.expandedNeed == need.id && model.openNeed(store) == need.id)
        // A ready session's card opens as its row, the card folding.
        let ready = try #require(page.ready.first)
        model.select(ready.id, store: store)
        #expect(model.canvas.openRow == ready.id && model.expandedNeed == nil)
        // A note opens in full, the row folding.
        let note = try #require(page.notes.first)
        model.select(note.id, store: store)
        #expect(model.expandedNeed == note.id && model.canvas.openRow == nil)
        // A note open isn't Needs you's: no plan or form keys act on it.
        #expect(model.openNeed(store) == nil)
        // Its header clicked again folds it; the reply stays.
        model.tap(note.id, store: store)
        #expect(model.expandedNeed == nil && model.replyTo == note.id)
    }

    @Test func escFoldsTheOpenNodeThenClearsTheFilterThenCloses() throws {
        let store = demo()
        let model = canvas(store)
        var closed = false
        let keys = RouterKeys(store: store, model: model) { closed = true }
        let need = try #require(model.zones(store).needs.first { store.pendingForm(for: $0)?.isPlan != true })
        model.select(need.id, store: store)
        model.canvas.filter = [.needs]
        #expect(keys.key(key(kVK_Escape), responder: nil) && model.replyTo == nil && model.expandedNeed == need.id)
        #expect(keys.key(key(kVK_Escape), responder: nil) && model.expandedNeed == nil && model.canvas.filter == [.needs])
        #expect(keys.key(key(kVK_Escape), responder: nil) && model.canvas.filter.isEmpty && !closed)
        #expect(keys.key(key(kVK_Escape), responder: nil) && closed)
    }

    @Test func escWithNothingOpenNeverPutsAPlanInReviseMode() {
        let store = demo()
        let model = canvas(store)
        var closed = false
        let keys = RouterKeys(store: store, model: model) { closed = true }
        // The list shows the first card of Needs you in full; the canvas shows none, so no plan is there to revise.
        #expect(model.expandedPlan(store) == nil)
        #expect(keys.key(key(kVK_Escape), responder: nil) && closed && model.revisingPlan == nil)
    }

    @Test func aChipShowsOnlyItsGroupInPlaceAndASecondClickShowsAllAgain() throws {
        let store = demo()
        let model = canvas(store)
        model.canvas.toggleFilter(.working)
        let folders = model.canvasFolders(store, page: model.zones(store))
        #expect(folders.allSatisfy { $0.shown.allSatisfy { $0.group == .working } })
        // Hidden in place: the groups are still there.
        #expect(folders.contains { $0.groups.contains { $0.hidden } })
        // Only what is drawn is walked.
        #expect(model.sections(store).needs.isEmpty)
        model.canvas.toggleFilter(.working)
        #expect(model.canvas.filter.isEmpty)
    }

    @Test func aWorkingRowOpensThroughTheCanvasAndFoldsTheCardOpen() throws {
        let store = demo()
        let model = canvas(store)
        let need = try #require(model.zones(store).needs.first)
        model.select(need.id, store: store)
        let row = RouterModel.workingID(try #require(model.zones(store).working.first).id)
        model.canvasOpen(row)
        model.canvas.openRow = row
        #expect(model.expandedNeed == nil && model.canvasOpenNode(store) == row)
        #expect(model.foldCanvasNode(store) && model.canvas.openRow == nil && !model.foldCanvasNode(store))
    }

    @Test func aScrollOverAFormTallerThanItsCapIsTheFormsNotTheCanvas() {
        let area = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let root = NSView(frame: area)
        let scroll = NSScrollView(frame: NSRect(x: 100, y: 100, width: 400, height: 300))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 900))
        scroll.documentView = document
        root.addSubview(scroll)
        let inside = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        document.addSubview(inside)
        #expect(CanvasEventView.scrolls(inside, inside: area))
        // All of it shown: the canvas pans.
        document.frame.size.height = 200
        #expect(!CanvasEventView.scrolls(inside, inside: area))
        // Nothing that scrolls under it.
        #expect(!CanvasEventView.scrolls(root, inside: area))
    }

    /// A message sent on the canvas keeps Now in view (it flies to its card there); in the list the history shows at once.
    @Test func aMessageSentOnTheCanvasStaysOnNowAndFliesOnceToItsCard() throws {
        let store = demo()
        let model = canvas(store)
        let card = try #require(model.zones(store).needs.first)
        let canvas = model.canvas
        canvas.depart(store: store, model: model, page: model.zones(store), narrow: false, reduce: true)
        #expect(canvas.settled != nil)
        model.reply(to: card.id, store: store)
        model.draft = "use sqlite"
        model.send(store: store)
        #expect(model.pane == .now)
        // The demo's Router settles it at once: it lands on the card it answered (Reduce Motion: no arc, no pan).
        canvas.nodeRects[card.id] = CGRect(x: 0, y: 0, width: 420, height: 52)
        canvas.depart(store: store, model: model, page: model.zones(store), narrow: false, reduce: true)
        #expect(canvas.landed[card.id]?.text == "use sqlite" && canvas.flights.isEmpty)
        canvas.landed = [:]
        canvas.depart(store: store, model: model, page: model.zones(store), narrow: false, reduce: true)
        #expect(canvas.landed.isEmpty)
        canvas.stopFlights()

        let list = RouterModel()
        list.reply(to: card.id, store: store)
        list.replyTo = nil
        list.draft = "what's running?"
        list.send(store: store)
        #expect(list.pane == .history)
    }
}
