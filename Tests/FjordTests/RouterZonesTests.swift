import Foundation
import Testing
@testable import Fjord

/// The Router's page: Now and History one at a time in a narrow window, the sections of Now folding and kept so.
@MainActor
@Suite struct RouterZonesTests {
    private func demo() -> Store {
        let store = Store()
        Demo.populate(store, .router)
        store.interceptOpen = { _ in }
        return store
    }

    @Test func waitingAndWorkingStartFoldedAndAFoldIsKeptInTheWindowsPreferences() throws {
        let defaults = try #require(UserDefaults(suiteName: "RouterZonesTests-\(UUID().uuidString)"))
        let model = RouterModel(defaults: defaults)
        #expect(model.folded == [.waiting, .working])
        model.setFolded(.working, false)
        model.setFolded(.needs, true)
        #expect(model.folded == [.needs, .waiting])
        #expect(RouterModel(defaults: defaults).folded == [.needs, .waiting])
        // Shots and tests keep nothing.
        #expect(RouterModel().folded == RouterZone.foldedAtFirst)
    }

    @Test func thePaneFollowsWhatYouPickAndStaysWhereYouSendFrom() throws {
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
        // A message stays in Now, where its pill flies to where it went (`RouterFlights`): a reply to a card, and one to the
        // Router, whose answer lands in the history once it is there.
        model.reply(to: open.id, store: store)
        model.draft = "go on"
        model.send(store: store)
        #expect(model.pane == .now)
        model.draft = "what needs me?"
        model.send(store: store)
        #expect(model.pane == .now)
    }

    @Test func soloShowsOnlyTheSoloedStatesAndWinsOverMute() {
        var filter = RouterFilter()
        #expect(filter.isClear && CanvasGroup.allCases.allSatisfy(filter.shows))
        filter.toggleMute(.working)
        #expect(!filter.shows(.working) && filter.shows(.needs) && !filter.isClear)
        filter.toggleSolo(.needs)
        #expect(filter.shows(.needs) && !filter.shows(.notes) && !filter.shows(.working))
        // Several solos show their union; a state both soloed and muted shows, as on a mixer.
        filter.toggleSolo(.working)
        #expect(filter.shows(.needs) && filter.shows(.working) && !filter.shows(.waiting))
        filter.toggleSolo(.working)
        filter.toggleSolo(.needs)
        #expect(!filter.shows(.working) && filter.shows(.needs))
        filter.clear()
        #expect(filter.isClear && filter.shows(.working))
    }

    @Test func revealingAStateUnmutesItAndJoinsTheSolos() {
        var filter = RouterFilter(solo: [.working], mute: [.needs])
        filter.reveal(.needs)
        #expect(filter.shows(.needs) && filter.shows(.working) && filter.mute.isEmpty)
        var muted = RouterFilter(mute: [.notes, .needs])
        muted.reveal(.notes)
        #expect(muted.shows(.notes) && muted.solo.isEmpty && !muted.shows(.needs))
    }

    @Test func theListLeavesOutWhatTheFilterHides() {
        let store = demo()
        Demo.routerTriage(store)
        let model = RouterModel()
        let page = model.zones(store)
        #expect(!page.working.isEmpty && !page.needs.isEmpty)
        model.filter.solo = [.working]
        let shown = model.listZones(store)
        #expect(shown.needs.isEmpty && shown.ready.isEmpty && shown.asks.isEmpty && shown.notes.isEmpty)
        #expect(shown.working == page.working)
        // The same value the canvas reads.
        model.filter = RouterFilter(mute: [.working])
        #expect(model.listZones(store).working.isEmpty && model.listZones(store).needs == page.needs)
        #expect(model.sections(store).needs == page.needs + page.ready)
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
