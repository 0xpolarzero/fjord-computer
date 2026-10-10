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

    /// Opened again after a close, the window has its size back (its content leaves it on close, and coming back must not
    /// size it to the content's minimum: a window too small to see).
    @Test func openingAgainKeepsTheWindowsSize() async {
        let (window, _) = controller()
        var closed = 0
        window.onClose = { closed += 1 }
        window.show(.settings)
        window.window?.setContentSize(NSSize(width: 1100, height: 700))
        let size = window.window?.frame.size
        window.close()
        await waitUntil { closed == 1 }
        window.show(.settings)
        #expect(window.window?.frame.size == size)
        away(window)
        window.close()
        await waitUntil { closed == 2 }
    }

    /// Closed, the window lets go of its content, which stands still out of it, and keeps it for the next open: the same
    /// content comes back, as it was left, without being made again.
    @Test func closingKeepsTheContentOutOfTheWindowForTheNextOpen() async throws {
        let (window, _) = controller()
        var closed = 0
        window.onClose = { closed += 1 }
        window.show(.router)
        away(window)
        let content = try #require(window.window?.contentViewController)
        window.close()
        await waitUntil { closed == 1 }
        #expect(window.window?.contentViewController == nil && content.view.window == nil)
        window.show(.router)
        away(window)
        #expect(window.window?.contentViewController === content)
        window.close()
        await waitUntil { closed == 2 }
    }

    /// The categories page kept from a close has an undo history of what was done before it: a change the Router made while
    /// the window was closed is newer, so ⌘Z after opening again must not take the page back to before it.
    @Test func aRouterChangeWhileClosedIsNotUndoneByTheKeptCategoriesPage() async throws {
        let (window, store) = controller()
        // The page asks GitHub for repos to suggest when it has none.
        store.suggestions = ["octo/repo"]
        var closed = 0
        window.onClose = { closed += 1 }
        window.show(.categories)
        away(window)
        await waitUntil { store.categoryHistory != nil }
        // A step of the page's own, so it has something to undo.
        var renamed = try #require(store.categories.first)
        renamed.name += " (edited)"
        store.categories[0] = renamed
        await waitUntil { store.categoryHistory?.canUndo == true }
        #expect(store.categoryHistory?.canUndo == true)
        window.close()
        await waitUntil { closed == 1 }
        #expect(store.categoryHistory == nil)
        var made = CategoriesView.newDraft(after: store.categories)
        made.name = "From the Router"
        store.categories.append(made)
        store.categoriesChangedByRouter()
        window.show(.categories)
        away(window)
        await waitUntil { store.categoryHistory != nil }
        await waitUntilSteady { store.categoryHistory?.canUndo }
        store.categoryHistory?.undo(store)
        #expect(store.categories.contains { $0.id == made.id })
        window.close()
        await waitUntil { closed == 2 }
    }

    @Test func aPlaceThatIsGoneOpensOnTheFirstCategory() async {
        let (window, store) = controller()
        window.show(.category(UUID()))
        away(window)
        #expect(window.navigator.selection == .category(store.shownCategories[0].id))
        window.close()
        await waitUntil { !window.isOpen }
    }

    @Test func aCardOpensOnTheRouter() async throws {
        let (window, store) = controller()
        window.show(.settings)
        away(window)
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

    /// Check for Updates (the bar's menu) asks the window's own Settings for Updates, which takes the request: from another
    /// place, and again while Settings is open already.
    @Test func checkForUpdatesScrollsTheWindowsSettingsToUpdates() async {
        let (window, _) = controller()
        window.show(.done)
        away(window)
        window.showUpdates()
        #expect(window.isOpen && window.navigator.selection == .settings)
        #expect(window.hub.settingsScroll?.id == SettingsView.updatesID)
        await waitUntil { window.hub.settingsScroll == nil }
        #expect(window.hub.settingsScroll == nil)
        window.showUpdates()
        #expect(window.hub.settingsScroll?.id == SettingsView.updatesID)
        await waitUntil { window.hub.settingsScroll == nil }
        #expect(window.hub.settingsScroll == nil)
        // Closed on Settings and opened again by the menu: the page kept from the close takes it as it comes back.
        var closed = false
        window.onClose = { closed = true }
        window.close()
        await waitUntil { closed }
        window.showUpdates()
        away(window)
        #expect(window.hub.settingsScroll?.id == SettingsView.updatesID)
        await waitUntil { window.hub.settingsScroll == nil }
        #expect(window.hub.settingsScroll == nil)
        window.close()
        await waitUntil { !window.isOpen }
    }
}

@MainActor
@Suite struct BarState {
    @Test func aPeekWaitsForThePointerToSettleThenSwitchesAtOnce() async {
        let hub = HubState()
        hub.enter(.inbox)
        #expect(hub.section == nil)
        await waitUntil { hub.section == .inbox }
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

/// The bar and the window: the bar is away only while the window is open and in front, and the morph is a no-op under test.
@MainActor
@Suite(.hostsWindows) struct BarComesBack {
    @Test func theBarIsAwayOnlyWhileTheOpenWindowIsInFront() {
        var presence = BarPresence()
        #expect(!presence.barAway)
        presence.opened(true)
        #expect(presence.barAway)
        // Another app in front: the bar is back, the window stays open behind.
        presence.front(false)
        #expect(!presence.barAway && presence.windowOpen)
        // The window returns (a click on the bar's item, the Dock icon).
        presence.front(true)
        #expect(presence.barAway)
        presence.opened(false)
        #expect(!presence.barAway)
        // A window that is not open is never in front.
        presence.front(true)
        #expect(!presence.barAway)
    }

    @Test func resigningActiveReportsOutOfSightAndBecomingActiveReportsFront() async {
        _ = NSApplication.shared
        let store = Store()
        store.persists = false
        Demo.populate(store, .router)
        let controller = AppWindowController(store: store, remembers: false, checksClaudeCode: false)
        var reports: [Bool] = []
        controller.onFront = { reports.append($0) }
        controller.show(.settings)
        controller.window?.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        // The window is on screen; whether the app counts as active depends on the runner, so say it.
        controller.reportFront(active: true)
        #expect(reports.last == true || controller.window?.occlusionState.contains(.visible) == false)
        let seen = reports.count
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        await waitUntil { reports.count > seen || reports.last == false }
        #expect(reports.last == false)
        controller.close()
        await waitUntil { !controller.isOpen }
        #expect(!controller.isOpen)
    }

    @Test func theMorphIsSkippedUnderTestSoTheWindowOpensAndClosesAtOnce() async {
        #expect(!AppTransition.enabled)
        _ = NSApplication.shared
        let store = Store()
        store.persists = false
        Demo.populate(store, .router)
        let controller = AppWindowController(store: store, remembers: false, checksClaudeCode: false)
        var asked = 0
        controller.bar = { asked += 1; return BarMorph(frame: NSRect(x: 0, y: 0, width: 50, height: 200)) }
        var closing = 0
        var closed = 0
        controller.onClosing = { closing += 1 }
        controller.onClose = { closed += 1 }
        controller.show(.settings)
        controller.window?.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        #expect(controller.window?.alphaValue == 1 && controller.isOpen)
        controller.close()
        await waitUntil { closed == 1 }
        #expect(closed == 1 && closing == 0 && asked == 0 && !controller.isOpen)
    }

    private final class Ticks {
        var blocks: [@MainActor () -> Void] = []
        var turns: [@MainActor () -> Void] = []
    }

    /// A morph with the frame ticks in the test's hands. Synchronous: nothing else sees the morph switched on.
    private func morphing(_ body: (AppWindowController, Ticks) -> Void) {
        let saved = (AppTransition.enabled, AppTransition.nextFrame, AppTransition.nextTurn)
        let ticks = Ticks()
        AppTransition.enabled = true
        AppTransition.nextFrame = { _, block in ticks.blocks.append(block) }
        AppTransition.nextTurn = { block in ticks.turns.append(block) }
        defer {
            AppTransition.enabled = saved.0
            AppTransition.nextFrame = saved.1
            AppTransition.nextTurn = saved.2
        }
        _ = NSApplication.shared
        let store = Store()
        store.persists = false
        Demo.populate(store, .router)
        let window = AppWindowController(store: store, remembers: false, checksClaudeCode: false)
        window.bar = { BarMorph(frame: NSRect(x: 1400, y: 300, width: 46, height: 300)) }
        body(window, ticks)
        window.run?.end()
        window.close()
    }

    @Test func theRealWindowIsShownBeforeTheOverlayGoes() {
        morphing { controller, ticks in
            controller.show(.settings)
            guard let run = controller.run, let window = controller.window else { return #expect(Bool(false), "no morph") }
            // Waiting at its frame, invisible, while the overlay grows out of the bar.
            #expect(controller.phase == .opening && window.alphaValue == 0 && run.overlay.isVisible)
            run.complete()
            // At the end: the real window is in under the overlay at once, and the overlay stays until two refreshes later.
            #expect(window.alphaValue == 1 && run.overlay.isVisible && !run.ended)
            #expect(ticks.blocks.count == 1)
            ticks.blocks.removeFirst()()
            #expect(window.alphaValue == 1 && run.overlay.isVisible && ticks.blocks.count == 1)
            ticks.blocks.removeFirst()()
            #expect(window.alphaValue == 1 && !run.ended)
        }
    }

    @Test func theMorphMovesBeforeTheWindowIsBuilt() {
        morphing { controller, ticks in
            controller.show(.settings)
            guard let run = controller.run, let window = controller.window else { return #expect(Bool(false), "no morph") }
            // The overlay is on screen at once, on the window's bare surface; the window and its content come a turn later,
            // and it counts as open meanwhile (a toggle closes it).
            #expect(run.overlay.isVisible && run.image == nil && controller.isOpen)
            #expect(!window.isVisible && window.contentViewController == nil)
            #expect(ticks.turns.count == 1)
            ticks.turns.removeFirst()()
            #expect(window.isVisible && window.alphaValue == 0 && window.contentViewController != nil)
            // The picture is there before the real window takes over.
            run.complete()
            #expect(run.image != nil && window.alphaValue == 1 && run.overlay.isVisible)
        }
    }

    /// What a close leaves for the next turn (the content out of the window, the bar told) is called off when the window is
    /// opened again first: the bar must not be told the window closed while it is on its way in.
    @Test func openingAgainBeforeTheCloseIsTidiedKeepsTheWindowOpen() {
        morphing { controller, ticks in
            var closed = 0
            controller.onClose = { closed += 1 }
            controller.show(.settings)
            controller.close()
            controller.run?.complete()
            #expect(controller.phase == .idle && controller.window?.isVisible == false)
            controller.show(.settings)
            #expect(controller.phase == .opening && controller.isOpen)
            // Every turn queued but the new opening's own bringing in: the close's tidying among them.
            let turns = ticks.turns
            ticks.turns = []
            turns.dropLast().forEach { $0() }
            #expect(closed == 0 && controller.isOpen && NSApp.activationPolicy() == .regular)
            #expect(controller.window?.contentViewController != nil)
            turns.last?()
            #expect(closed == 0 && controller.window?.isVisible == true)
        }
    }

    @Test func closingWhileOpeningPicksUpFromWhereTheOverlayIs() {
        morphing { controller, ticks in
            controller.show(.settings)
            guard let run = controller.run, let window = controller.window else { return #expect(Bool(false), "no morph") }
            let before = run.pose
            controller.close()
            // On its way out it counts as closed: a toggle opens it again.
            #expect(controller.phase == .closing && controller.run === run && !controller.isOpen)
            #expect(run.startPose?.rect == before.rect && run.startPose?.radius == before.radius)
            // The real window is out of the way and the overlay carries the close.
            #expect(!window.isVisible && run.overlay.isVisible)
            // Opening again turns it round from there.
            let now = run.pose
            controller.show(.settings)
            #expect(controller.phase == .opening && run.startPose?.rect == now.rect && controller.isOpen)
            #expect(ticks.blocks.isEmpty)
        }
    }
}
