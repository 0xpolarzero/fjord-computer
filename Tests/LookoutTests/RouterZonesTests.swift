import Foundation
import Testing
@testable import Lookout

/// The Router's page: Now and History one at a time in a narrow window, the sections of Now folding and kept so.
@MainActor
@Suite struct RouterZonesTests {
    private func demo() -> Store {
        let store = Store()
        Demo.populate(store, .router)
        store.interceptOpen = { _ in }
        return store
    }

    @Test func waitingAndWorkingStartFoldedAndAFoldIsKeptAcrossLaunches() throws {
        let store = demo()
        #expect(store.routerFolded == [.waiting, .working])
        store.setRouterZone(.working, folded: false)
        store.setRouterZone(.needs, folded: true)
        #expect(store.routerFolded == [.needs, .waiting])
        let back = try JSONDecoder().decode(RouterState.self, from: JSONEncoder().encode(store.router))
        #expect(back.foldedZones == ["needs", "waiting"])
        // Nothing changed, nothing is written.
        let before = store.router
        store.setRouterZone(.needs, folded: true)
        #expect(store.router == before)
    }

    @Test func thePaneFollowsWhatYouPickAndTheRouterAnswersInTheHistory() throws {
        let store = demo()
        let model = RouterModel()
        let open = try #require(store.routerZones.needs.first)
        model.pane = .history
        model.select(open.id, store: store)
        #expect(model.pane == .now)
        let addressed = try #require(store.router.cards.first { !$0.isOpen })
        model.select(addressed.id, store: store)
        #expect(model.pane == .history)
        model.jump(to: .working)
        #expect(model.pane == .now && model.zoneRequest?.id == "working")
        // A reply to a card stays in Now; a message to the Router goes to its conversation.
        model.reply(to: open.id, store: store)
        model.draft = "go on"
        model.send(store: store)
        #expect(model.pane == .now)
        model.draft = "what needs me?"
        model.send(store: store)
        #expect(model.pane == .history)
    }

    @Test func eachItemOfNowIsInItsSection() throws {
        let store = demo()
        Demo.routerTriage(store)
        let page = store.routerZones
        let need = try #require(page.needs.first), note = try #require(page.notes.first)
        let wait = try #require(page.waiting.first), row = try #require(page.working.first)
        #expect(page.zone(of: need.id) == .needs && page.zone(of: note.id) == .notes)
        #expect(page.zone(of: RouterModel.workingID(wait.sessionID)) == .waiting)
        #expect(page.zone(of: RouterModel.workingID(row.id)) == .working)
        #expect(page.zone(of: RouterModel.endID) == nil)
        #expect(page.count(.needs) == page.needs.count + page.ready.count + page.asks.count)
    }
}
