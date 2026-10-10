import AppKit
import Foundation
import Testing
@testable import Lookout

/// The app window as the bar's other mode: it opens on a place, and closing it tells the bar to come back.
@MainActor
@Suite(.hostsWindows) struct AppWindowTests {
    private func controller() -> (AppWindowController, Store) {
        _ = NSApplication.shared
        let store = Store()
        store.persists = false
        Demo.populate(store, .router)
        return (AppWindowController(store: store, remembers: false, checksClaudeCode: false), store)
    }

    /// The window off every screen, and closed again when the test is done.
    private func away(_ controller: AppWindowController) {
        controller.window?.setFrameOrigin(NSPoint(x: -5000, y: -5000))
    }

    @Test func showingOpensTheWindowOnThePlaceAndClosingTellsTheBar() async {
        let (window, _) = controller()
        var closed = 0
        window.onClose = { closed += 1 }
        #expect(!window.isOpen)
        window.show(.settings)
        away(window)
        #expect(window.isOpen && window.navigator.selection == .settings)
        // A regular app while the window is open: a Dock icon and ⌘-Tab.
        #expect(NSApp.activationPolicy() == .regular)
        window.close()
        await waitUntil { closed == 1 }
        #expect(!window.isOpen && closed == 1)
        // The bar only again: no Dock icon.
        #expect(NSApp.activationPolicy() == .accessory)
    }

    @Test func showingWithoutAPlaceOpensWhereItWasLeft() async {
        let (window, _) = controller()
        window.show(.done)
        away(window)
        window.close()
        await waitUntil { !window.isOpen }
        window.show()
        away(window)
        #expect(window.navigator.selection == .done)
        window.close()
        await waitUntil { !window.isOpen }
    }

    @Test func aPlaceThatIsGoneOpensOnTheFirstCategory() async {
        let (window, store) = controller()
        window.show(.category(UUID()))
        away(window)
        #expect(window.navigator.selection == .category(store.shownCategories[0].id))
        window.close()
        await waitUntil { !window.isOpen }
    }

    @Test func theRoutersSearchAndACardOpenOnTheRouter() async throws {
        let (window, store) = controller()
        window.show(.settings)
        away(window)
        window.show(search: true)
        #expect(window.navigator.selection == .router && window.routerModel.searchWanted)
        window.show(.done)
        let card = try #require(store.openRouterCards.first)
        window.show(card: card.id)
        #expect(window.navigator.selection == .router && window.routerModel.selection == card.id)
        window.close()
        await waitUntil { !window.isOpen }
    }

    @Test func anEntryOpensOnItsCategoryPickedAndAskedFor() async throws {
        let (window, store) = controller()
        let entry = try #require(store.entries.first { !$0.isDone })
        window.show(entry: entry)
        away(window)
        #expect(window.navigator.selection == .category(entry.categoryID))
        #expect(window.hub.selection == "i:" + entry.id && window.hub.keyboardSelection?.id == "i:" + entry.id)
        window.close()
        await waitUntil { !window.isOpen }
    }

    @Test func toggleOpensThenCloses() async {
        let (window, _) = controller()
        window.toggle()
        away(window)
        #expect(window.isOpen)
        window.toggle()
        await waitUntil { !window.isOpen }
        #expect(!window.isOpen)
    }
}

@MainActor
@Suite struct BarState {
    @Test func aPeekWaitsForThePointerToSettleThenSwitchesAtOnce() async {
        let hub = HubState()
        hub.enter(.inbox)
        #expect(hub.section == nil)
        await waitUntil(within: 5) { hub.section == .inbox }
        #expect(hub.section == .inbox)
        hub.enter(.router)
        #expect(hub.section == .router)
        hub.cancelDwell()
    }

    @Test func aPeekIsNotShownWhileTheBarIsQuiet() {
        let hub = HubState()
        hub.section = .inbox
        hub.panelFrame = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(hub.openPanelFrame != nil)
        hub.quiet = true
        #expect(hub.openPanelFrame == nil)
    }

    @Test func changingThePeekedTabDropsTheRowPickedInTheOther() {
        let hub = HubState()
        hub.selection = "i:a"
        hub.tab = .done
        #expect(hub.selection == nil)
    }
}
